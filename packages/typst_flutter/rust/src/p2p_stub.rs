//! `api::p2p_tunnel` without the `p2p` feature: every call fails.

use crate::api::p2p_tunnel::{PairedPeer, PeerError, PeerErrorKind};
use crate::frb_generated::StreamSink;
fn off<T>() -> Result<T, PeerError> {
    Err(PeerError::new(
        PeerErrorKind::NotEnabled,
        "P2P not enabled in native build",
    ))
}
pub async fn start(_: Vec<u8>, _: u16, _: String) -> Result<String, PeerError> {
    off()
}
pub async fn stop() {}
pub fn node_id() -> Option<String> {
    None
}
pub fn set_paired_peers(_: Vec<String>) -> Result<(), PeerError> {
    off()
}
pub fn paired_events(_: StreamSink<PairedPeer>) -> Result<(), PeerError> {
    off()
}
pub async fn open_peer_port(_: String) -> Result<u16, PeerError> {
    off()
}
pub async fn close_peer_port(_: String) {}
pub async fn peer_route(_: String) -> String {
    "offline".into()
}
pub async fn pairing_code() -> Result<String, PeerError> {
    off()
}
pub async fn pair(_: String) -> Result<PairedPeer, PeerError> {
    off()
}
