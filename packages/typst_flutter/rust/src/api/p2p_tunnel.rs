//! Peer-to-peer tunnel (iroh): the flutter_rust_bridge surface of
//! `crate::p2p_node`. Without the `p2p` feature it builds as stubs that fail
//! with `PeerErrorKind::NotEnabled`.
//!
//! Each device serves its vault as WebDAV on 127.0.0.1; this node carries
//! TCP connections to and from paired peers byte for byte, and pairs devices.

use crate::frb_generated::StreamSink;
use flutter_rust_bridge::frb;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PeerErrorKind {
    /// Wrong, expired or already used pairing code, or not a code at all.
    PairingRefused,
    /// The other device could not be reached.
    Unreachable,
    Timeout,
    /// `start_node` has not been called.
    NotRunning,
    /// This native build has no `p2p` feature.
    NotEnabled,
    Failed,
}

#[derive(Debug, Clone)]
pub struct PeerError {
    pub kind: PeerErrorKind,
    pub message: String,
}

impl std::fmt::Display for PeerError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{:?}: {}", self.kind, self.message)
    }
}

impl PeerError {
    pub(crate) fn new(kind: PeerErrorKind, message: impl Into<String>) -> Self {
        Self {
            kind,
            message: message.into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PairedPeer {
    pub node_id: String,
    pub name: String,
}

#[cfg(feature = "p2p")]
use crate::p2p_node as node;

#[cfg(not(feature = "p2p"))]
use crate::p2p_stub as node;

/// Starts this app run's node from the persistent 32-byte secret key and
/// returns its node id. Calling it again with the same key only updates the
/// DAV port and device name.
pub async fn start_node(
    secret_key: Vec<u8>,
    local_dav_port: u16,
    device_name: String,
) -> Result<String, PeerError> {
    node::start(secret_key, local_dav_port, device_name).await
}

/// Closes the node, its peer ports and every connection.
pub async fn stop_node() {
    node::stop().await
}

#[frb(sync)]
pub fn node_id() -> Option<String> {
    node::node_id()
}

/// Replaces the allowlist of node ids whose tunnels reach the DAV server.
#[frb(sync)]
pub fn set_paired_peers(ids: Vec<String>) -> Result<(), PeerError> {
    node::set_paired_peers(ids)
}

/// Peers that paired using a code this node showed.
pub fn paired_events(sink: StreamSink<PairedPeer>) -> Result<(), PeerError> {
    node::paired_events(sink)
}

/// A 127.0.0.1 TCP port whose connections are tunnelled to `peer`'s DAV
/// server. The same port while it stays open.
pub async fn open_peer_port(peer: String) -> Result<u16, PeerError> {
    node::open_peer_port(peer).await
}

pub async fn close_peer_port(peer: String) {
    node::close_peer_port(peer).await
}

/// `direct`, `relay` or `offline`; dials the peer if no connection is open.
pub async fn peer_route(peer: String) -> String {
    node::peer_route(peer).await
}

/// A one-time pairing code for this node: 10 minutes, single use.
pub async fn pairing_code() -> Result<String, PeerError> {
    node::pairing_code().await
}

/// Pairs with the node that showed `code` and returns it.
pub async fn pair(code: String) -> Result<PairedPeer, PeerError> {
    node::pair(code).await
}
