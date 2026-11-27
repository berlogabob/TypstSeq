//! In-process nodes on loopback; a TCP echo server stands in for the DAV
//! server.

use super::*;
use tokio::io::AsyncReadExt;

/// A 127.0.0.1 echo server; returns its port.
async fn echo_server() -> u16 {
    let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
    let port = listener.local_addr().unwrap().port();
    tokio::spawn(async move {
        while let Ok((tcp, _)) = listener.accept().await {
            tokio::spawn(async move {
                let (mut r, mut w) = tcp.into_split();
                let _ = tokio::io::copy(&mut r, &mut w).await;
                let _ = w.shutdown().await;
            });
        }
    });
    port
}

struct Peer {
    node: Arc<Node>,
    paired: Arc<Mutex<Vec<PairedPeer>>>,
}

async fn peer(name: &str) -> Peer {
    let port = echo_server().await;
    let key = SecretKey::generate();
    let node = Node::bind(key, Config { production: false }, port, name.into())
        .await
        .unwrap();
    let paired: Arc<Mutex<Vec<PairedPeer>>> = Default::default();
    let events = paired.clone();
    node.set_pairs(Arc::new(move |p| {
        events.lock().unwrap().push(p);
        true
    }));
    Peer {
        node: Arc::new(node),
        paired,
    }
}

/// Lets `a` dial `b` without discovery, and returns `b`'s id.
async fn introduce(a: &Peer, b: &Peer) -> String {
    let addr = b.node.addr().await;
    assert!(addr.ip_addrs().next().is_some(), "no direct address");
    a.node.shared.addrs.lock().unwrap().insert(addr.id, addr);
    b.node.id()
}

/// Sends `data` through `port` and returns what came back before EOF.
async fn round_trip(port: u16, data: &[u8]) -> Vec<u8> {
    let tcp = TcpStream::connect(("127.0.0.1", port)).await.unwrap();
    let (mut r, mut w) = tcp.into_split();
    let data = data.to_vec();
    let writer = tokio::spawn(async move {
        let _ = w.write_all(&data).await;
        let _ = w.shutdown().await;
    });
    let mut back = Vec::new();
    let _ = r.read_to_end(&mut back).await;
    let _ = writer.await;
    back
}

fn run<F: std::future::Future<Output = ()>>(f: F) {
    runtime().block_on(async {
        tokio::time::timeout(Duration::from_secs(60), f)
            .await
            .expect("test timed out")
    });
}

#[test]
fn bytes_round_trip_through_the_tunnel() {
    run(async {
        let (a, b) = (peer("Ay").await, peer("Bee").await);
        let id = introduce(&a, &b).await;
        b.node.set_paired_peers(vec![a.node.id()]).unwrap();
        let port = a.node.open_peer_port(&id).await.unwrap();
        assert_eq!(a.node.open_peer_port(&id).await.unwrap(), port);

        let big: Vec<u8> = (0..3_000_000u32).map(|i| (i * 31 % 251) as u8).collect();
        let (one, two) = tokio::join!(round_trip(port, &big), round_trip(port, b"hello"));
        assert!(one == big, "large echo differs ({} bytes back)", one.len());
        assert_eq!(two, b"hello");
        assert_eq!(a.node.peer_route(&id).await, "direct");

        a.node.close_peer_port(&id);
        tokio::time::sleep(Duration::from_millis(50)).await;
        assert!(TcpStream::connect(("127.0.0.1", port)).await.is_err());
    });
}

#[test]
fn unpaired_node_is_refused() {
    run(async {
        let (a, b) = (peer("Ay").await, peer("Bee").await);
        let id = introduce(&a, &b).await;
        let port = a.node.open_peer_port(&id).await.unwrap();
        assert!(round_trip(port, b"secret").await.is_empty());
        assert_eq!(a.node.peer_route(&id).await, "offline");

        b.node.set_paired_peers(vec![a.node.id()]).unwrap();
        assert_eq!(round_trip(port, b"now").await, b"now");

        // Unpairing cuts off the live connection at its next stream.
        b.node.set_paired_peers(vec![]).unwrap();
        assert!(round_trip(port, b"again").await.is_empty());
    });
}

#[test]
fn pairing_needs_the_right_fresh_unused_secret() {
    run(async {
        let (a, b, c) = (peer("Ay").await, peer("Bee").await, peer("Sea").await);
        let code = b.node.pairing_code().await.unwrap();

        let (addr, mut secret) = decode_code(&code).unwrap();
        secret[0] ^= 1;
        let err = c.node.pair(&encode_code(&addr, &secret)).await.unwrap_err();
        assert_eq!(err.kind, PeerErrorKind::PairingRefused, "{err}");
        assert!(err.message.contains("Wrong"), "{err}");

        let peer = a.node.pair(&code).await.unwrap();
        assert_eq!(
            peer,
            PairedPeer {
                node_id: b.node.id(),
                name: "Bee".into()
            }
        );
        let events = b.paired.lock().unwrap().clone();
        assert_eq!(
            events,
            vec![PairedPeer {
                node_id: a.node.id(),
                name: "Ay".into()
            }]
        );
        // Both sides now let the other through, and B can dial A back.
        let port = a.node.open_peer_port(&b.node.id()).await.unwrap();
        assert_eq!(round_trip(port, b"a to b").await, b"a to b");
        let port = b.node.open_peer_port(&a.node.id()).await.unwrap();
        assert_eq!(round_trip(port, b"b to a").await, b"b to a");

        let err = c.node.pair(&code).await.unwrap_err();
        assert_eq!(err.kind, PeerErrorKind::PairingRefused, "{err}");
        assert!(err.message.contains("already used"), "{err}");

        let code = b.node.pairing_code().await.unwrap();
        for p in b.node.shared.pending.lock().unwrap().iter_mut() {
            p.expires = Instant::now() - Duration::from_secs(1);
        }
        let err = c.node.pair(&code).await.unwrap_err();
        assert_eq!(err.kind, PeerErrorKind::PairingRefused, "{err}");
        assert!(err.message.contains("expired"), "{err}");

        assert!(!b.node.shared.is_paired(&c.node.endpoint.id()));
        assert_eq!(b.paired.lock().unwrap().len(), 1);
        let err = c.node.pair("TYLOG1NOTACODE").await.unwrap_err();
        assert_eq!(err.kind, PeerErrorKind::PairingRefused, "{err}");
    });
}

#[test]
fn pairing_code_round_trips() {
    let addr = EndpointAddr::new(SecretKey::generate().public())
        .with_ip_addr("192.168.1.7:4321".parse().unwrap())
        .with_ip_addr("[fe80::1]:9".parse().unwrap())
        .with_relay_url("https://euw1-1.relay.n0.iroh.link./".parse().unwrap());
    let code = encode_code(&addr, &[7; 16]);
    assert!(code.starts_with("TYLOG1"));
    assert!(code[6..].bytes().all(|c| B32.contains(&c)), "{code}");
    let (back, secret) = decode_code(&code.to_lowercase()).unwrap();
    assert_eq!((back, secret), (addr, [7; 16]));
    assert!(decode_code("TYLOG1AAAA").is_err());
    assert!(decode_code("hello").is_err());
}
