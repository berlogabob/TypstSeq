#[derive(Debug, Clone)]
pub struct ScratchTransfer {
    pub text: String,
    pub bytes: u64,
    pub elapsed_ms: u64,
}

#[cfg(feature = "p2p-harness")]
const ALPN: &[u8] = b"tylog/scratch/1";

// Checked by tool/assert_source_built.sh so a harness build cannot be shipped
// accidentally as one of the normal prebuilt libraries.
#[cfg(feature = "p2p-harness")]
#[unsafe(no_mangle)]
pub static TYLOG_P2P_HARNESS_BUILD_MARKER: &[u8] = b"TYLOG_P2P_HARNESS_BUILD_MARKER";

/// Serves only the supplied scratch text, once, for at most five minutes.
#[cfg(feature = "p2p-harness")]
fn start_impl(text: String) -> Result<String, String> {
    if text.len() > 1024 * 1024 {
        return Err("Scratch text exceeds 1 MiB".into());
    }
    let (tx, rx) = std::sync::mpsc::sync_channel(1);
    std::thread::spawn(move || {
        let runtime = match tokio::runtime::Runtime::new() {
            Ok(r) => r,
            Err(e) => {
                let _ = tx.send(Err(e.to_string()));
                return;
            }
        };
        runtime.block_on(async move {
            let endpoint = match iroh::Endpoint::builder(iroh::endpoint::presets::N0)
                .alpns(vec![ALPN.to_vec()])
                .bind()
                .await
            {
                Ok(endpoint) => endpoint,
                Err(e) => {
                    let _ = tx.send(Err(e.to_string()));
                    return;
                }
            };
            // Wait briefly for relay discovery, while retaining direct addresses offline.
            let _ =
                tokio::time::timeout(std::time::Duration::from_secs(5), endpoint.online()).await;
            let ticket = serde_json::to_string(&endpoint.addr()).map_err(|e| e.to_string());
            if tx.send(ticket).is_err() {
                endpoint.close().await;
                return;
            }
            let _ = tokio::time::timeout(std::time::Duration::from_secs(300), async {
                let incoming = endpoint
                    .accept()
                    .await
                    .ok_or("endpoint closed".to_string())?;
                let conn = incoming.await.map_err(|e| e.to_string())?;
                let (mut send, _) = conn.accept_bi().await.map_err(|e| e.to_string())?;
                send.write_all(text.as_bytes())
                    .await
                    .map_err(|e| e.to_string())?;
                send.finish().map_err(|e| e.to_string())?;
                conn.closed().await;
                Ok::<(), String>(())
            })
            .await;
            endpoint.close().await;
        });
    });
    rx.recv().map_err(|e| e.to_string())?
}

#[cfg(feature = "p2p-harness")]
fn receive_impl(ticket: String) -> Result<ScratchTransfer, String> {
    let addr: iroh::EndpointAddr =
        serde_json::from_str(&ticket).map_err(|e| format!("Invalid ticket: {e}"))?;
    let runtime = tokio::runtime::Runtime::new().map_err(|e| e.to_string())?;
    runtime.block_on(async move {
        tokio::time::timeout(std::time::Duration::from_secs(60), async {
            let start = std::time::Instant::now();
            let endpoint = iroh::Endpoint::bind(iroh::endpoint::presets::N0)
                .await
                .map_err(|e| e.to_string())?;
            let conn = endpoint
                .connect(addr, ALPN)
                .await
                .map_err(|e| e.to_string())?;
            let (mut send, mut recv) = conn.open_bi().await.map_err(|e| e.to_string())?;
            send.finish().map_err(|e| e.to_string())?;
            let data = recv
                .read_to_end(1024 * 1024)
                .await
                .map_err(|e| e.to_string())?;
            let bytes = data.len() as u64;
            let text = String::from_utf8(data).map_err(|e| e.to_string())?;
            let elapsed_ms = start.elapsed().as_millis() as u64;
            conn.close(0u32.into(), b"done");
            endpoint.close().await;
            Ok(ScratchTransfer {
                text,
                bytes,
                elapsed_ms,
            })
        })
        .await
        .map_err(|_| "Transfer timed out".to_string())?
    })
}

#[cfg(not(feature = "p2p-harness"))]
fn start_impl(_: String) -> Result<String, String> {
    Err("P2P harness not enabled in native build".into())
}
#[cfg(not(feature = "p2p-harness"))]
fn receive_impl(_: String) -> Result<ScratchTransfer, String> {
    Err("P2P harness not enabled in native build".into())
}

pub fn start_scratch(text: String) -> Result<String, String> {
    start_impl(text)
}
pub fn receive_scratch(ticket: String) -> Result<ScratchTransfer, String> {
    receive_impl(ticket)
}
