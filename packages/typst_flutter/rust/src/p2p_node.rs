//! The iroh node behind `api::p2p_tunnel` (feature `p2p`).
//!
//! One endpoint serves two ALPNs:
//! - `tylog/dav/1`: a dumbpipe-style TCP tunnel. Each bidirectional stream
//!   opens with one `HELLO` byte and is then piped byte for byte to the local
//!   DAV server on 127.0.0.1. Only node ids in the paired allowlist get in.
//!   Outgoing, `open_peer_port` listens on 127.0.0.1 and turns each accepted
//!   TCP connection into a stream on one pooled connection to the peer.
//! - `tylog/pair/1`: proves a one-time code's secret and swaps device names.

use crate::api::p2p_tunnel::{PairedPeer, PeerError, PeerErrorKind};
use crate::frb_generated::StreamSink;
use iroh::endpoint::{Connection, RecvStream, SendStream};
use iroh::{Endpoint, EndpointAddr, EndpointId, SecretKey, TransportAddr};
use serde_json::{Value, json};
use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicU16, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tokio::io::AsyncWriteExt;
use tokio::net::{TcpListener, TcpStream};

pub(crate) const DAV_ALPN: &[u8] = b"tylog/dav/1";
pub(crate) const PAIR_ALPN: &[u8] = b"tylog/pair/1";
const HELLO: u8 = 1;
const MAX_HEADER: usize = 64 * 1024;
const PAIR_TTL: Duration = Duration::from_secs(600);
const CONNECT_TIMEOUT: Duration = Duration::from_secs(30);
const ROUTE_TIMEOUT: Duration = Duration::from_secs(10);
/// Connection close code for a node that is not in the allowlist.
const NOT_PAIRED: u32 = 403;
const CODE_PREFIX: &str = "TYLOG1";
const OP_PAIR: u8 = 7;
const ST_OK: u8 = 0;
const ST_FAILED: u8 = 3;

type Emit<T> = Arc<dyn Fn(T) -> bool + Send + Sync>;
type Slot = Arc<tokio::sync::Mutex<Option<Connection>>>;

fn fail(kind: PeerErrorKind, message: impl std::fmt::Display) -> PeerError {
    PeerError::new(kind, message.to_string())
}

fn parse_id(id: &str) -> Result<EndpointId, PeerError> {
    id.trim()
        .parse()
        .map_err(|e| fail(PeerErrorKind::Failed, format!("Invalid node id: {e}")))
}

/// `direct`, `relay` or `offline`, from the selected path as `p2p_folder`
/// samples it.
fn route_of(conn: &Connection) -> &'static str {
    if conn.close_reason().is_some() {
        return "offline";
    }
    let paths = conn.paths();
    let selected = paths.iter().find(|path| path.is_selected());
    match selected {
        Some(path) if path.is_relay() && !path.is_ip() => "relay",
        Some(_) => "direct",
        None => "offline",
    }
}

/// Logs the selected route whenever it changes, as `p2p_folder` does.
fn observe_route(conn: Connection) {
    tokio::spawn(async move {
        let peer = conn.remote_id().fmt_short().to_string();
        let mut previous = "";
        loop {
            let route = route_of(&conn);
            if route != previous {
                println!("TYLOG_P2P_ROUTE peer={peer} route={route}");
                previous = route;
            }
            tokio::select! {
                _ = conn.closed() => break,
                _ = tokio::time::sleep(Duration::from_millis(500)) => {}
            }
        }
    });
}

fn transport() -> iroh::endpoint::QuicTransportConfig {
    iroh::endpoint::QuicTransportConfig::builder()
        .stream_receive_window((8u32 * 1024 * 1024).into())
        .receive_window((32u32 * 1024 * 1024).into())
        .build()
}

/// Copies both directions until each side has finished. If either side
/// fails, both are torn down, so a dead peer never leaves a TCP client hanging.
async fn pipe(mut send: SendStream, mut recv: RecvStream, tcp: TcpStream) {
    let _ = tcp.set_nodelay(true);
    let (mut tcp_read, mut tcp_write) = tcp.into_split();
    let result = tokio::try_join!(
        async {
            tokio::io::copy(&mut recv, &mut tcp_write).await?;
            tcp_write.shutdown().await
        },
        async {
            tokio::io::copy(&mut tcp_read, &mut send).await?;
            send.finish().map_err(std::io::Error::other)
        },
    );
    if result.is_ok() {
        let _ = tokio::time::timeout(Duration::from_secs(10), send.stopped()).await;
    } else {
        let _ = send.reset(0u32.into());
        let _ = recv.stop(0u32.into());
    }
}

async fn write_frame(send: &mut SendStream, tag: u8, header: &Value) -> Result<(), String> {
    let header = serde_json::to_vec(header).map_err(|e| e.to_string())?;
    let mut frame = Vec::with_capacity(header.len() + 5);
    frame.push(tag);
    frame.extend_from_slice(&(header.len() as u32).to_be_bytes());
    frame.extend_from_slice(&header);
    send.write_all(&frame).await.map_err(|e| e.to_string())
}

async fn read_frame(recv: &mut RecvStream) -> Result<(u8, Value), String> {
    let mut head = [0u8; 5];
    recv.read_exact(&mut head)
        .await
        .map_err(|e| e.to_string())?;
    let len = u32::from_be_bytes([head[1], head[2], head[3], head[4]]) as usize;
    if len > MAX_HEADER {
        return Err("Header too large".into());
    }
    let mut header = vec![0; len];
    recv.read_exact(&mut header)
        .await
        .map_err(|e| e.to_string())?;
    let header = serde_json::from_slice(&header).map_err(|e| e.to_string())?;
    Ok((head[0], header))
}

fn text(header: &Value, key: &str) -> Option<String> {
    header.get(key).and_then(Value::as_str).map(str::to_owned)
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn unhex(text: &str) -> Option<Vec<u8>> {
    if !text.len().is_multiple_of(2) {
        return None;
    }
    (0..text.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(text.get(i..i + 2)?, 16).ok())
        .collect()
}

const B32: &[u8; 32] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

fn base32(bytes: &[u8]) -> String {
    let mut out = String::new();
    let (mut acc, mut bits) = (0u32, 0);
    for &b in bytes {
        acc = (acc << 8) | b as u32;
        bits += 8;
        while bits >= 5 {
            bits -= 5;
            out.push(B32[((acc >> bits) & 31) as usize] as char);
        }
        acc &= (1 << bits) - 1;
    }
    if bits > 0 {
        out.push(B32[((acc << (5 - bits)) & 31) as usize] as char);
    }
    out
}

fn unbase32(text: &str) -> Option<Vec<u8>> {
    let mut out = Vec::new();
    let (mut acc, mut bits) = (0u32, 0);
    for c in text.bytes() {
        let v = B32.iter().position(|&x| x == c.to_ascii_uppercase())? as u32;
        acc = (acc << 5) | v;
        bits += 5;
        if bits >= 8 {
            bits -= 8;
            out.push((acc >> bits) as u8);
        }
        acc &= (1 << bits) - 1;
    }
    Some(out)
}

/// `TYLOG1` + base32 of `[1][id 32][secret 16][n][addr]*`, where an addr is
/// `4 ip port`, `6 ip port` or `r len url`. Base32 keeps QR codes compact.
pub(crate) fn encode_code(addr: &EndpointAddr, secret: &[u8; 16]) -> String {
    let mut out = vec![1u8];
    out.extend_from_slice(addr.id.as_bytes());
    out.extend_from_slice(secret);
    let mut addrs = Vec::new();
    for a in &addr.addrs {
        match a {
            TransportAddr::Ip(std::net::SocketAddr::V4(s)) => {
                let mut e = vec![4];
                e.extend_from_slice(&s.ip().octets());
                e.extend_from_slice(&s.port().to_be_bytes());
                addrs.push(e);
            }
            TransportAddr::Ip(std::net::SocketAddr::V6(s)) => {
                let mut e = vec![6];
                e.extend_from_slice(&s.ip().octets());
                e.extend_from_slice(&s.port().to_be_bytes());
                addrs.push(e);
            }
            TransportAddr::Relay(url) => {
                let url = url.to_string();
                if url.len() < 256 {
                    let mut e = vec![b'r', url.len() as u8];
                    e.extend_from_slice(url.as_bytes());
                    addrs.push(e);
                }
            }
            #[allow(unreachable_patterns)]
            _ => {}
        }
    }
    addrs.truncate(16);
    out.push(addrs.len() as u8);
    for e in addrs {
        out.extend(e);
    }
    format!("{CODE_PREFIX}{}", base32(&out))
}

pub(crate) fn decode_code(code: &str) -> Result<(EndpointAddr, [u8; 16]), PeerError> {
    let bad = || fail(PeerErrorKind::PairingRefused, "Not a TyLog pairing code");
    let code: String = code.chars().filter(|c| !c.is_whitespace()).collect();
    let body = code
        .get(..CODE_PREFIX.len())
        .filter(|p| p.eq_ignore_ascii_case(CODE_PREFIX))
        .and_then(|_| code.get(CODE_PREFIX.len()..))
        .ok_or_else(bad)?;
    let raw = unbase32(body).ok_or_else(bad)?;
    if raw.len() < 50 || raw[0] != 1 {
        return Err(bad());
    }
    let id_bytes: &[u8; 32] = raw[1..33].try_into().map_err(|_| bad())?;
    let id = iroh::PublicKey::from_bytes(id_bytes).map_err(|_| bad())?;
    let secret: [u8; 16] = raw[33..49].try_into().map_err(|_| bad())?;
    let mut addr = EndpointAddr::new(id);
    let mut rest = &raw[50..];
    for _ in 0..raw[49] {
        let (&tag, tail) = rest.split_first().ok_or_else(bad)?;
        rest = tail;
        match tag {
            4 if rest.len() >= 6 => {
                let ip: [u8; 4] = rest[..4].try_into().unwrap();
                let port = u16::from_be_bytes([rest[4], rest[5]]);
                addr = addr.with_ip_addr((ip, port).into());
                rest = &rest[6..];
            }
            6 if rest.len() >= 18 => {
                let ip: [u8; 16] = rest[..16].try_into().unwrap();
                let port = u16::from_be_bytes([rest[16], rest[17]]);
                addr = addr.with_ip_addr((std::net::Ipv6Addr::from(ip), port).into());
                rest = &rest[18..];
            }
            b'r' if !rest.is_empty() && rest.len() > rest[0] as usize => {
                let len = rest[0] as usize;
                let url = std::str::from_utf8(&rest[1..=len]).map_err(|_| bad())?;
                addr = addr.with_relay_url(url.parse().map_err(|_| bad())?);
                rest = &rest[len + 1..];
            }
            _ => return Err(bad()),
        }
    }
    Ok((addr, secret))
}

fn same_secret(a: &[u8; 16], b: &[u8; 16]) -> bool {
    a.iter().zip(b).fold(0u8, |acc, (x, y)| acc | (x ^ y)) == 0
}

struct PendingPair {
    secret: [u8; 16],
    expires: Instant,
    used: bool,
}

#[derive(Clone, Copy)]
pub(crate) struct Config {
    /// N0 relays and DNS plus mDNS, and wait for the relay before showing a
    /// pairing code. Off in tests, which stay on loopback.
    pub production: bool,
}

struct Shared {
    dav_port: AtomicU16,
    name: Mutex<String>,
    paired: Mutex<HashSet<EndpointId>>,
    pending: Mutex<Vec<PendingPair>>,
    pairs: Mutex<Option<Emit<PairedPeer>>>,
    conns: Mutex<HashMap<EndpointId, Slot>>,
    addrs: Mutex<HashMap<EndpointId, EndpointAddr>>,
    ports: Mutex<HashMap<EndpointId, (u16, tokio::task::JoinHandle<()>)>>,
}

impl Shared {
    fn is_paired(&self, id: &EndpointId) -> bool {
        self.paired.lock().unwrap().contains(id)
    }

    /// Remembers where an incoming peer came from, so we can dial it back
    /// before discovery has published it.
    fn learn_addr(&self, conn: &Connection) {
        let ips: Vec<TransportAddr> = conn
            .paths()
            .iter()
            .map(|p| p.remote_addr().clone())
            .filter(|a| matches!(a, TransportAddr::Ip(_)))
            .collect();
        if !ips.is_empty() {
            let id = conn.remote_id();
            let mut addrs = self.addrs.lock().unwrap();
            let addr = addrs.remove(&id).unwrap_or_else(|| EndpointAddr::new(id));
            addrs.insert(id, addr.with_addrs(ips));
        }
    }
}

pub(crate) struct Node {
    endpoint: Endpoint,
    shared: Arc<Shared>,
    config: Config,
}

impl Node {
    pub(crate) async fn bind(
        key: SecretKey,
        config: Config,
        dav_port: u16,
        name: String,
    ) -> Result<Node, PeerError> {
        let builder = if config.production {
            Endpoint::builder(iroh::endpoint::presets::N0)
                .address_lookup(iroh_mdns_address_lookup::MdnsAddressLookup::builder())
        } else {
            Endpoint::builder(iroh::endpoint::presets::Minimal)
                .relay_mode(iroh::RelayMode::Disabled)
        };
        let endpoint = builder
            .secret_key(key)
            .alpns(vec![DAV_ALPN.to_vec(), PAIR_ALPN.to_vec()])
            .transport_config(transport())
            .bind()
            .await
            .map_err(|e| fail(PeerErrorKind::Failed, e))?;
        let shared = Arc::new(Shared {
            dav_port: AtomicU16::new(dav_port),
            name: Mutex::new(name),
            paired: Default::default(),
            pending: Default::default(),
            pairs: Default::default(),
            conns: Default::default(),
            addrs: Default::default(),
            ports: Default::default(),
        });
        let (ep, sh) = (endpoint.clone(), shared.clone());
        tokio::spawn(async move {
            while let Some(incoming) = ep.accept().await {
                let sh = sh.clone();
                tokio::spawn(async move {
                    let Ok(conn) = incoming.await else { return };
                    let peer = conn.remote_id();
                    if conn.alpn() == DAV_ALPN {
                        if !sh.is_paired(&peer) {
                            conn.close(NOT_PAIRED.into(), b"not paired");
                            return;
                        }
                        sh.learn_addr(&conn);
                        serve_dav(sh, conn, peer).await;
                    } else if conn.alpn() == PAIR_ALPN {
                        let _ = serve_pair(sh, conn, peer).await;
                    } else {
                        conn.close(1u32.into(), b"unknown protocol");
                    }
                });
            }
        });
        Ok(Node {
            endpoint,
            shared,
            config,
        })
    }

    pub(crate) fn id(&self) -> String {
        self.endpoint.id().to_string()
    }

    pub(crate) fn configure(&self, dav_port: u16, name: String) {
        self.shared.dav_port.store(dav_port, Ordering::Relaxed);
        *self.shared.name.lock().unwrap() = name;
    }

    pub(crate) async fn close(&self) {
        let ports: Vec<_> = self.shared.ports.lock().unwrap().drain().collect();
        for (_, (_, task)) in ports {
            task.abort();
        }
        self.endpoint.close().await;
    }

    pub(crate) fn set_paired_peers(&self, ids: Vec<String>) -> Result<(), PeerError> {
        let ids = ids
            .iter()
            .map(|id| parse_id(id))
            .collect::<Result<HashSet<_>, _>>()?;
        *self.shared.paired.lock().unwrap() = ids;
        Ok(())
    }

    pub(crate) fn set_pairs(&self, emit: Emit<PairedPeer>) {
        *self.shared.pairs.lock().unwrap() = Some(emit);
    }

    fn slot(&self, id: EndpointId) -> Slot {
        self.shared
            .conns
            .lock()
            .unwrap()
            .entry(id)
            .or_default()
            .clone()
    }

    /// The pooled tunnel connection to `id`, dialled if missing, closed or
    /// `fresh` is asked for.
    async fn connection(&self, id: EndpointId, fresh: bool) -> Result<Connection, PeerError> {
        let slot = self.slot(id);
        let mut guard = slot.lock().await;
        if let Some(conn) = guard.as_ref()
            && conn.close_reason().is_none()
            && !fresh
        {
            return Ok(conn.clone());
        }
        let addr = self.shared.addrs.lock().unwrap().get(&id).cloned();
        let addr = addr.unwrap_or_else(|| EndpointAddr::new(id));
        let conn = tokio::time::timeout(CONNECT_TIMEOUT, self.endpoint.connect(addr, DAV_ALPN))
            .await
            .map_err(|_| fail(PeerErrorKind::Timeout, "Peer did not answer"))?
            .map_err(|e| fail(PeerErrorKind::Unreachable, e))?;
        observe_route(conn.clone());
        *guard = Some(conn.clone());
        Ok(conn)
    }

    /// Opens a tunnel stream to `id`, redialling once if the pooled
    /// connection turns out to be dead.
    async fn open_stream(&self, id: EndpointId) -> Result<(SendStream, RecvStream), PeerError> {
        let mut last = String::new();
        for fresh in [false, true] {
            let conn = self.connection(id, fresh).await?;
            match conn.open_bi().await {
                Ok((mut send, recv)) => match send.write_all(&[HELLO]).await {
                    Ok(()) => return Ok((send, recv)),
                    Err(e) => last = e.to_string(),
                },
                Err(e) => last = e.to_string(),
            }
        }
        Err(fail(PeerErrorKind::Unreachable, last))
    }

    pub(crate) async fn open_peer_port(self: &Arc<Self>, peer: &str) -> Result<u16, PeerError> {
        let id = parse_id(peer)?;
        if let Some((port, task)) = self.shared.ports.lock().unwrap().get(&id)
            && !task.is_finished()
        {
            return Ok(*port);
        }
        let listener = TcpListener::bind(("127.0.0.1", 0))
            .await
            .map_err(|e| fail(PeerErrorKind::Failed, e))?;
        let port = listener
            .local_addr()
            .map_err(|e| fail(PeerErrorKind::Failed, e))?
            .port();
        let node = self.clone();
        let task = tokio::spawn(async move {
            while let Ok((tcp, _)) = listener.accept().await {
                let node = node.clone();
                tokio::spawn(async move {
                    // Dropping `tcp` on failure shows the client a reset.
                    if let Ok((send, recv)) = node.open_stream(id).await {
                        pipe(send, recv, tcp).await;
                    }
                });
            }
        });
        let old = self.shared.ports.lock().unwrap().insert(id, (port, task));
        if let Some((_, old)) = old {
            old.abort();
        }
        Ok(port)
    }

    pub(crate) fn close_peer_port(&self, peer: &str) {
        let Ok(id) = parse_id(peer) else { return };
        let removed = self.shared.ports.lock().unwrap().remove(&id);
        if let Some((_, task)) = removed {
            task.abort();
        }
    }

    pub(crate) async fn peer_route(&self, peer: &str) -> &'static str {
        let Ok(id) = parse_id(peer) else {
            return "offline";
        };
        let live = self.slot(id).lock().await.clone();
        let live = live.filter(|c| c.close_reason().is_none());
        if let Some(conn) = live {
            return route_of(&conn);
        }
        let Ok(Ok(conn)) = tokio::time::timeout(ROUTE_TIMEOUT, self.connection(id, false)).await
        else {
            return "offline";
        };
        // A peer that has not paired us closes right after the handshake.
        tokio::select! {
            _ = conn.closed() => "offline",
            _ = tokio::time::sleep(Duration::from_millis(300)) => route_of(&conn),
        }
    }

    /// This node's address, once it has direct addresses (and, in
    /// production, a relay) or after a few seconds.
    pub(crate) async fn addr(&self) -> EndpointAddr {
        let ready = async {
            if self.config.production {
                self.endpoint.online().await;
            }
            while self.endpoint.addr().ip_addrs().next().is_none() {
                tokio::time::sleep(Duration::from_millis(20)).await;
            }
        };
        let _ = tokio::time::timeout(Duration::from_secs(3), ready).await;
        self.endpoint.addr()
    }

    pub(crate) async fn pairing_code(&self) -> Result<String, PeerError> {
        let addr = self.addr().await;
        let mut secret = [0u8; 16];
        getrandom::fill(&mut secret).map_err(|e| fail(PeerErrorKind::Failed, e))?;
        let mut pending = self.shared.pending.lock().unwrap();
        let now = Instant::now();
        pending.retain(|p| !p.used && p.expires > now);
        pending.push(PendingPair {
            secret,
            expires: now + PAIR_TTL,
            used: false,
        });
        Ok(encode_code(&addr, &secret))
    }

    pub(crate) async fn pair(&self, code: &str) -> Result<PairedPeer, PeerError> {
        let (addr, secret) = decode_code(code)?;
        let id = addr.id;
        if id == self.endpoint.id() {
            return Err(fail(
                PeerErrorKind::PairingRefused,
                "This is this device's own code",
            ));
        }
        let conn = tokio::time::timeout(
            CONNECT_TIMEOUT,
            self.endpoint.connect(addr.clone(), PAIR_ALPN),
        )
        .await
        .map_err(|_| fail(PeerErrorKind::Timeout, "Device did not answer"))?
        .map_err(|e| fail(PeerErrorKind::Unreachable, e))?;
        let my_name = self.shared.name.lock().unwrap().clone();
        let result = async {
            let (mut send, mut recv) = conn.open_bi().await.map_err(|e| e.to_string())?;
            let request = json!({"secret": hex(&secret), "name": my_name});
            write_frame(&mut send, OP_PAIR, &request).await?;
            send.finish().map_err(|e| e.to_string())?;
            read_frame(&mut recv).await
        }
        .await;
        conn.close(0u32.into(), b"paired");
        let (status, header) = result.map_err(|e| fail(PeerErrorKind::Unreachable, e))?;
        if status != ST_OK {
            let message = text(&header, "message").unwrap_or_default();
            return Err(fail(PeerErrorKind::PairingRefused, message));
        }
        self.shared.paired.lock().unwrap().insert(id);
        self.shared.addrs.lock().unwrap().insert(id, addr);
        Ok(PairedPeer {
            node_id: id.to_string(),
            name: text(&header, "name").unwrap_or_default(),
        })
    }
}

async fn serve_pair(sh: Arc<Shared>, conn: Connection, peer: EndpointId) -> Result<(), String> {
    let (mut send, mut recv) = tokio::time::timeout(Duration::from_secs(30), conn.accept_bi())
        .await
        .map_err(|_| "timeout".to_string())?
        .map_err(|e| e.to_string())?;
    let (op, header) = read_frame(&mut recv).await?;
    let secret: Option<[u8; 16]> = text(&header, "secret")
        .and_then(|s| unhex(&s))
        .and_then(|s| s.try_into().ok());
    let verdict = match secret.filter(|_| op == OP_PAIR) {
        None => Err("Invalid pairing request"),
        Some(secret) => {
            let mut pending = sh.pending.lock().unwrap();
            match pending.iter_mut().find(|p| same_secret(&p.secret, &secret)) {
                None => Err("Wrong pairing code"),
                Some(p) if p.used => Err("Pairing code was already used"),
                Some(p) if p.expires <= Instant::now() => Err("Pairing code expired"),
                Some(p) => {
                    p.used = true;
                    Ok(())
                }
            }
        }
    };
    match verdict {
        Ok(()) => {
            sh.paired.lock().unwrap().insert(peer);
            sh.learn_addr(&conn);
            let my_name = sh.name.lock().unwrap().clone();
            write_frame(&mut send, ST_OK, &json!({"name": my_name})).await?;
            let emit = sh.pairs.lock().unwrap().clone();
            if let Some(emit) = emit {
                emit(PairedPeer {
                    node_id: peer.to_string(),
                    name: text(&header, "name").unwrap_or_default(),
                });
            }
        }
        Err(message) => write_frame(&mut send, ST_FAILED, &json!({"message": message})).await?,
    }
    send.finish().map_err(|e| e.to_string())?;
    let _ = tokio::time::timeout(Duration::from_secs(10), conn.closed()).await;
    Ok(())
}

/// Pipes each stream from a paired peer to the local DAV server. The
/// allowlist is checked again per stream, so unpairing cuts a live peer off.
async fn serve_dav(sh: Arc<Shared>, conn: Connection, peer: EndpointId) {
    while let Ok((mut send, mut recv)) = conn.accept_bi().await {
        if !sh.is_paired(&peer) {
            conn.close(NOT_PAIRED.into(), b"not paired");
            break;
        }
        let port = sh.dav_port.load(Ordering::Relaxed);
        tokio::spawn(async move {
            let mut hello = [0u8; 1];
            if recv.read_exact(&mut hello).await.is_err() || hello[0] != HELLO {
                return;
            }
            match TcpStream::connect(("127.0.0.1", port)).await {
                Ok(tcp) => pipe(send, recv, tcp).await,
                Err(_) => {
                    let _ = send.reset(0u32.into());
                }
            }
        });
    }
}

// ---- the app's single node, for the flutter_rust_bridge API ----

fn runtime() -> &'static tokio::runtime::Runtime {
    static RUNTIME: std::sync::OnceLock<tokio::runtime::Runtime> = std::sync::OnceLock::new();
    RUNTIME.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .thread_name("tylog-p2p")
            .enable_all()
            .build()
            .expect("p2p runtime")
    })
}

static NODE: Mutex<Option<Arc<Node>>> = Mutex::new(None);
static LIFECYCLE: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

fn current() -> Result<Arc<Node>, PeerError> {
    NODE.lock()
        .unwrap()
        .clone()
        .ok_or_else(|| fail(PeerErrorKind::NotRunning, "P2P node is not running"))
}

/// Runs `f` on the node's runtime, whatever executor awaits the result.
async fn on_runtime<T: Send + 'static>(
    f: impl std::future::Future<Output = T> + Send + 'static,
) -> Result<T, PeerError> {
    runtime()
        .spawn(f)
        .await
        .map_err(|e| fail(PeerErrorKind::Failed, e))
}

pub async fn start(secret_key: Vec<u8>, dav_port: u16, name: String) -> Result<String, PeerError> {
    let key: [u8; 32] = secret_key
        .try_into()
        .map_err(|_| fail(PeerErrorKind::Failed, "Secret key must be 32 bytes"))?;
    let _guard = LIFECYCLE.lock().await;
    let old = NODE.lock().unwrap().take();
    if let Some(old) = old {
        if old.endpoint.secret_key().to_bytes() == key {
            old.configure(dav_port, name);
            let id = old.id();
            *NODE.lock().unwrap() = Some(old);
            return Ok(id);
        }
        on_runtime(async move { old.close().await }).await?;
    }
    let key = SecretKey::from_bytes(&key);
    let config = Config { production: true };
    let node = on_runtime(Node::bind(key, config, dav_port, name)).await??;
    let id = node.id();
    *NODE.lock().unwrap() = Some(Arc::new(node));
    Ok(id)
}

pub async fn stop() {
    let _guard = LIFECYCLE.lock().await;
    let node = NODE.lock().unwrap().take();
    if let Some(node) = node {
        let _ = on_runtime(async move { node.close().await }).await;
    }
}

pub fn node_id() -> Option<String> {
    current().ok().map(|n| n.id())
}

pub fn set_paired_peers(ids: Vec<String>) -> Result<(), PeerError> {
    current()?.set_paired_peers(ids)
}

pub fn paired_events(sink: StreamSink<PairedPeer>) -> Result<(), PeerError> {
    current()?.set_pairs(Arc::new(move |p| sink.add(p).is_ok()));
    Ok(())
}

pub async fn open_peer_port(peer: String) -> Result<u16, PeerError> {
    let node = current()?;
    on_runtime(async move { node.open_peer_port(&peer).await }).await?
}

pub async fn close_peer_port(peer: String) {
    if let Ok(node) = current() {
        node.close_peer_port(&peer);
    }
}

pub async fn peer_route(peer: String) -> String {
    let Ok(node) = current() else {
        return "offline".into();
    };
    on_runtime(async move { node.peer_route(&peer).await })
        .await
        .unwrap_or("offline")
        .into()
}

pub async fn pairing_code() -> Result<String, PeerError> {
    let node = current()?;
    on_runtime(async move { node.pairing_code().await }).await?
}

pub async fn pair(code: String) -> Result<PairedPeer, PeerError> {
    let node = current()?;
    on_runtime(async move { node.pair(&code).await }).await?
}

#[cfg(test)]
mod tests;
