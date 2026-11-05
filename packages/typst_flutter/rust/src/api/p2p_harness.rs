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

#[derive(Debug, Clone)]
pub struct FileTransfer {
    pub bytes: u64,
    pub elapsed_ms: u64,
    pub sha256: String,
}

#[cfg(feature = "p2p-harness")]
const FILE_ALPN: &[u8] = b"tylog/file/1";
#[cfg(feature = "p2p-harness")]
const MAX_FILE: u64 = 50 * 1024 * 1024;
#[cfg(feature = "p2p-harness")]
const CHUNK: usize = 256 * 1024;

/// Serve a file or folder once. Folder tickets allow up to two hours.
#[cfg(feature = "p2p-harness")]
pub fn start_file(path: String) -> Result<String, String> {
    use sha2::{Digest, Sha256};
    use std::io::Read;
    if std::path::Path::new(&path).is_dir() {
        return super::p2p_folder::start(path);
    }
    let mut file = std::fs::File::open(path).map_err(|e| e.to_string())?;
    let size = file.metadata().map_err(|e| e.to_string())?.len();
    if size > MAX_FILE {
        return Err("File exceeds 50 MiB".into());
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
                .alpns(vec![FILE_ALPN.to_vec()])
                .bind()
                .await
            {
                Ok(endpoint) => endpoint,
                Err(e) => {
                    let _ = tx.send(Err(e.to_string()));
                    return;
                }
            };
            let _ =
                tokio::time::timeout(std::time::Duration::from_secs(5), endpoint.online()).await;
            if tx
                .send(serde_json::to_string(&endpoint.addr()).map_err(|e| e.to_string()))
                .is_err()
            {
                endpoint.close().await;
                return;
            }
            let _ = tokio::time::timeout(std::time::Duration::from_secs(300), async {
                let conn = endpoint
                    .accept()
                    .await
                    .ok_or("endpoint closed".to_string())?
                    .await
                    .map_err(|e| e.to_string())?;
                let (mut send, _) = conn.accept_bi().await.map_err(|e| e.to_string())?;
                send.write_all(&size.to_be_bytes())
                    .await
                    .map_err(|e| e.to_string())?;
                let mut hash = Sha256::new();
                let mut remaining = size;
                let mut buf = [0u8; CHUNK];
                while remaining > 0 {
                    let n = file
                        .read(&mut buf[..remaining.min(CHUNK as u64) as usize])
                        .map_err(|e| e.to_string())?;
                    if n == 0 {
                        return Err("Source file shortened".to_string());
                    }
                    hash.update(&buf[..n]);
                    send.write_all(&buf[..n]).await.map_err(|e| e.to_string())?;
                    remaining -= n as u64;
                }
                if file.read(&mut buf[..1]).map_err(|e| e.to_string())? != 0 {
                    return Err("Source file grew".to_string());
                }
                send.write_all(&hash.finalize())
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

/// Receive a verified file into a new path, or update a folder incrementally.
#[cfg(feature = "p2p-harness")]
pub fn receive_file(ticket: String, path: String) -> Result<FileTransfer, String> {
    use sha2::{Digest, Sha256};
    use std::io::Write;
    if serde_json::from_str::<serde_json::Value>(&ticket)
        .ok()
        .and_then(|v| v.get("folder").cloned())
        .is_some()
    {
        return super::p2p_folder::receive(ticket, path);
    }
    let addr: iroh::EndpointAddr =
        serde_json::from_str(&ticket).map_err(|e| format!("Invalid ticket: {e}"))?;
    let runtime = tokio::runtime::Runtime::new().map_err(|e| e.to_string())?;
    runtime.block_on(async move {
        let start = std::time::Instant::now();
        let endpoint = iroh::Endpoint::bind(iroh::endpoint::presets::N0)
            .await
            .map_err(|e| e.to_string())?;
        let result = tokio::time::timeout(std::time::Duration::from_secs(300), async {
            let conn = endpoint
                .connect(addr, FILE_ALPN)
                .await
                .map_err(|e| e.to_string())?;
            let (mut send, mut recv) = conn.open_bi().await.map_err(|e| e.to_string())?;
            send.finish().map_err(|e| e.to_string())?;
            let mut length = [0u8; 8];
            recv.read_exact(&mut length)
                .await
                .map_err(|e| e.to_string())?;
            let size = u64::from_be_bytes(length);
            if size > MAX_FILE {
                return Err("File exceeds 50 MiB".to_string());
            }
            let opened = std::fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&path)
                .map_err(|e| e.to_string())?;
            struct RemoveOnDrop(String, bool);
            impl Drop for RemoveOnDrop {
                fn drop(&mut self) {
                    if self.1 {
                        let _ = std::fs::remove_file(&self.0);
                    }
                }
            }
            let mut cleanup = RemoveOnDrop(path.clone(), true);
            let mut file = opened;
            let received = async {
                let mut remaining = size;
                let mut hash = Sha256::new();
                let mut buf = [0u8; CHUNK];
                while remaining > 0 {
                    let n = remaining.min(CHUNK as u64) as usize;
                    recv.read_exact(&mut buf[..n])
                        .await
                        .map_err(|e| e.to_string())?;
                    file.write_all(&buf[..n]).map_err(|e| e.to_string())?;
                    hash.update(&buf[..n]);
                    remaining -= n as u64;
                }
                let mut expected = [0u8; 32];
                recv.read_exact(&mut expected)
                    .await
                    .map_err(|e| e.to_string())?;
                if recv
                    .read(&mut buf[..1])
                    .await
                    .map_err(|e| e.to_string())?
                    .is_some()
                {
                    return Err("Unexpected trailing data".to_string());
                }
                let actual = hash.finalize();
                if actual[..] != expected {
                    return Err("File hash mismatch".to_string());
                }
                file.flush().map_err(|e| e.to_string())?;
                Ok(FileTransfer {
                    bytes: size,
                    elapsed_ms: start.elapsed().as_millis() as u64,
                    sha256: format!("{actual:x}"),
                })
            }
            .await;
            drop(file);
            if received.is_ok() {
                cleanup.1 = false;
            }
            conn.close(0u32.into(), b"done");
            received
        })
        .await
        .map_err(|_| "Transfer timed out".to_string());
        endpoint.close().await;
        result?
    })
}

#[cfg(not(feature = "p2p-harness"))]
pub fn start_file(path: String) -> Result<String, String> {
    let _ = path;
    Err("P2P harness not enabled in native build".into())
}
#[cfg(not(feature = "p2p-harness"))]
pub fn receive_file(ticket: String, path: String) -> Result<FileTransfer, String> {
    let _ = (ticket, path);
    Err("P2P harness not enabled in native build".into())
}
