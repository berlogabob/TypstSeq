use sha2::{Digest, Sha256};
use std::{
    io::{Read, Seek, SeekFrom, Write},
    path::{Component, Path, PathBuf},
};

const ALPN: &[u8] = b"tylog/folder/1";
const CHUNK: usize = 256 * 1024;
const LIMIT: usize = 16 * 1024 * 1024;
const TRANSFER_TIMEOUT_SECS: u64 = 7200;

type Entry = (String, u64, String);

#[derive(Default)]
struct TransferMetrics {
    connections: std::sync::atomic::AtomicU64,
    requests: std::sync::atomic::AtomicU64,
    initial_changed: std::sync::atomic::AtomicU64,
    resumed: std::sync::atomic::AtomicU64,
}
impl TransferMetrics {
    fn connection(&self) {
        self.connections
            .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    }
    fn changed_files(&self, count: u64) {
        let _ = self.initial_changed.compare_exchange(
            0,
            count + 1,
            std::sync::atomic::Ordering::Relaxed,
            std::sync::atomic::Ordering::Relaxed,
        );
    }
    fn requested(&self, count: u64) {
        self.requests
            .fetch_add(count, std::sync::atomic::Ordering::Relaxed);
    }
    fn resume(&self, offset: u64) {
        self.resumed
            .fetch_add(offset, std::sync::atomic::Ordering::Relaxed);
    }
    fn summary(&self) -> String {
        let connections = self.connections.load(std::sync::atomic::Ordering::Relaxed);
        format!(
            "connections={} retries={} changed_files={} blob_requests={} resumed_bytes={}",
            connections,
            connections.saturating_sub(1),
            self.initial_changed
                .load(std::sync::atomic::Ordering::Relaxed)
                .saturating_sub(1),
            self.requests.load(std::sync::atomic::Ordering::Relaxed),
            self.resumed.load(std::sync::atomic::Ordering::Relaxed)
        )
    }
}
fn hash(path: &Path) -> Result<(u64, String), String> {
    let mut f = std::fs::File::open(path).map_err(|e| e.to_string())?;
    let mut hash = Sha256::new();
    let mut size = 0;
    let mut buf = vec![0; CHUNK];
    loop {
        let n = f.read(&mut buf).map_err(|e| e.to_string())?;
        if n == 0 {
            break;
        }
        size += n as u64;
        hash.update(&buf[..n]);
    }
    Ok((size, format!("{:x}", hash.finalize())))
}
fn safe_path(root: &Path, name: &str) -> Result<PathBuf, String> {
    if name.is_empty()
        || name.contains('\\')
        || name
            .split('/')
            .any(|s| s.is_empty() || s == "." || s == "..")
    {
        return Err("Unsafe path".into());
    }
    let mut path = root.to_path_buf();
    for c in Path::new(name).components() {
        if let Component::Normal(part) = c {
            path.push(part);
        } else {
            return Err("Unsafe path".into());
        }
        match std::fs::symlink_metadata(&path) {
            Ok(m) if m.file_type().is_symlink() => return Err("Symlink in destination".into()),
            Err(e) if e.kind() != std::io::ErrorKind::NotFound => return Err(e.to_string()),
            _ => {}
        }
    }
    Ok(path)
}
fn scan(root: &Path, dir: &Path, entries: &mut Vec<Entry>) -> Result<(), String> {
    for entry in std::fs::read_dir(dir).map_err(|e| e.to_string())? {
        let entry = entry.map_err(|e| e.to_string())?;
        let ty = entry.file_type().map_err(|e| e.to_string())?;
        let path = entry.path();
        if ty.is_dir() {
            scan(root, &path, entries)?;
        } else if ty.is_file() {
            let name = path
                .strip_prefix(root)
                .map_err(|e| e.to_string())?
                .to_str()
                .ok_or("Non UTF-8 path")?
                .replace(std::path::MAIN_SEPARATOR, "/");
            let (size, sha) = hash(&path)?;
            entries.push((name, size, sha));
        } else {
            return Err("Unsupported source entry".into());
        }
    }
    Ok(())
}
fn path_label(ip: bool, relay: bool) -> &'static str {
    if ip {
        "direct-ip"
    } else if relay {
        "relay"
    } else {
        "other"
    }
}

fn log_selected_path(conn: &iroh::endpoint::Connection) -> &'static str {
    let paths = conn.paths();
    paths
        .iter()
        .find(|path| path.is_selected())
        .map(|path| path_label(path.is_ip(), path.is_relay()))
        .unwrap_or("unknown")
}

fn observe_paths(conn: iroh::endpoint::Connection) {
    tokio::spawn(async move {
        let mut previous = "";
        loop {
            let selected = log_selected_path(&conn);
            if selected != previous {
                println!("P2P6_SELECTED_PATH {selected}");
                previous = selected;
            }
            tokio::select! {
                _ = conn.closed() => break,
                _ = tokio::time::sleep(std::time::Duration::from_millis(500)) => {}
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
async fn send_file(
    conn: iroh::endpoint::Connection,
    root: PathBuf,
    entries: std::sync::Arc<Vec<Entry>>,
) -> Result<(), String> {
    let (mut send, mut recv) = conn.accept_bi().await.map_err(|e| e.to_string())?;
    let mut id = [0; 8];
    recv.read_exact(&mut id).await.map_err(|e| e.to_string())?;
    let index = usize::try_from(u64::from_be_bytes(id)).map_err(|e| e.to_string())?;
    let (name, size, expected) = entries.get(index).ok_or("Invalid file index")?;
    let mut offset = [0; 8];
    recv.read_exact(&mut offset)
        .await
        .map_err(|e| e.to_string())?;
    let offset = u64::from_be_bytes(offset);
    if offset > *size {
        return Err("Invalid offset".into());
    }
    let path = safe_path(&root, name)?;
    if hash(&path)? != (*size, expected.clone()) {
        return Err("Source changed".into());
    }
    let mut file = std::fs::File::open(path).map_err(|e| e.to_string())?;
    file.seek(SeekFrom::Start(offset))
        .map_err(|e| e.to_string())?;
    let mut buf = vec![0; CHUNK];
    let mut count = offset;
    loop {
        let n = file.read(&mut buf).map_err(|e| e.to_string())?;
        if n == 0 {
            break;
        }
        count += n as u64;
        if count > *size {
            return Err("Source changed".into());
        }
        send.write_all(&buf[..n]).await.map_err(|e| e.to_string())?;
    }
    if count != *size {
        return Err("Source changed".into());
    }
    send.finish().map_err(|e| e.to_string())?;
    Ok(())
}
pub(super) fn start(path: String) -> Result<String, String> {
    let root = PathBuf::from(path);
    let mut entries = Vec::new();
    scan(&root, &root, &mut entries)?;
    entries.sort();
    let manifest = serde_json::to_vec(&entries).map_err(|e| e.to_string())?;
    if manifest.len() > LIMIT {
        return Err("Manifest too large".into());
    }
    let (tx, rx) = std::sync::mpsc::sync_channel(1);
    std::thread::spawn(move || {
        let rt = match tokio::runtime::Runtime::new() {
            Ok(rt) => rt,
            Err(e) => {
                let _ = tx.send(Err(e.to_string()));
                return;
            }
        };
        rt.block_on(async move {
            let endpoint = match iroh::Endpoint::builder(iroh::endpoint::presets::N0)
                .alpns(vec![ALPN.to_vec()])
                .transport_config(transport())
                .bind()
                .await
            {
                Ok(e) => e,
                Err(e) => {
                    let _ = tx.send(Err(e.to_string()));
                    return;
                }
            };
            let _ =
                tokio::time::timeout(std::time::Duration::from_secs(5), endpoint.online()).await;
            if tx
                .send(
                    serde_json::to_string(&serde_json::json!({"folder": endpoint.addr()}))
                        .map_err(|e| e.to_string()),
                )
                .is_err()
            {
                endpoint.close().await;
                return;
            }
            let _ = tokio::time::timeout(std::time::Duration::from_secs(TRANSFER_TIMEOUT_SECS), async {
                let mut conn = endpoint
                    .accept()
                    .await
                    .ok_or("Closed")?
                    .await
                    .map_err(|e| e.to_string())?;
                loop {
                    let result: Result<(), String> = tokio::select! {
                        result = async {
                        let (mut send, mut recv) =
                            conn.accept_bi().await.map_err(|e| e.to_string())?;
                        let mut hello = [0; 1];
                        recv.read_exact(&mut hello)
                            .await
                            .map_err(|e| e.to_string())?;
                        if hello != [1] {
                            return Err("Invalid protocol".into());
                        }
                        send.write_all(&manifest).await.map_err(|e| e.to_string())?;
                        send.finish().map_err(|e| e.to_string())?;
                        let mut count = [0; 8];
                        recv.read_exact(&mut count)
                            .await
                            .map_err(|e| e.to_string())?;
                        let count = u64::from_be_bytes(count);
                        if count > entries.len() as u64 {
                            return Err("Invalid count".to_string());
                        }
                        let entries = std::sync::Arc::new(entries.clone());
                        let mut tasks = tokio::task::JoinSet::new();
                        for _ in 0..count {
                            if tasks.len() == 4 {
                                tasks
                                    .join_next()
                                    .await
                                    .unwrap()
                                    .map_err(|e| e.to_string())??;
                            }
                            let c = conn.clone();
                            let root = root.clone();
                            let entries = entries.clone();
                            tasks.spawn(async move { send_file(c, root, entries).await });
                        }
                        while let Some(result) = tasks.join_next().await {
                            result.map_err(|e| e.to_string())??;
                        }
                        let mut done = [0];
                        recv.read_exact(&mut done)
                            .await
                            .map_err(|e| e.to_string())?;
                        if done != [1] {
                            return Err("Invalid completion".into());
                        }
                        Ok(())
                        } => result,
                        incoming = endpoint.accept() => {
                            // A killed receiver may leave its connection alive until QUIC times out.
                            let next = incoming.ok_or("Closed")?.await.map_err(|e| e.to_string())?;
                            conn.close(1u32.into(), b"receiver reconnected");
                            conn = next;
                            continue;
                        }
                    };
                    if result.is_ok() {
                        conn.closed().await;
                        break;
                    }
                    conn.close(1u32.into(), b"transfer interrupted");
                    conn = endpoint.accept().await.ok_or("Closed")?.await.map_err(|e| e.to_string())?;
                }
                Ok::<(), String>(())
            })
            .await;
            endpoint.close().await;
        });
    });
    rx.recv().map_err(|e| e.to_string())?
}
async fn receive_one(
    conn: iroh::endpoint::Connection,
    temp: PathBuf,
    root: PathBuf,
    index: usize,
    entry: Entry,
    transferred: std::sync::Arc<std::sync::atomic::AtomicU64>,
    metrics: std::sync::Arc<TransferMetrics>,
) -> Result<u64, String> {
    let (mut send, mut recv) = conn.open_bi().await.map_err(|e| e.to_string())?;
    let temp_file = safe_path(&temp, &index.to_string())?;
    let mut file = std::fs::OpenOptions::new()
        .read(true)
        .append(true)
        .create(true)
        .open(&temp_file)
        .map_err(|e| e.to_string())?;
    let offset = file.metadata().map_err(|e| e.to_string())?.len();
    if offset > entry.1 {
        return Err("Partial file too large".into());
    }
    metrics.resume(offset);
    send.write_all(&(index as u64).to_be_bytes())
        .await
        .map_err(|e| e.to_string())?;
    send.write_all(&offset.to_be_bytes())
        .await
        .map_err(|e| e.to_string())?;
    send.finish().map_err(|e| e.to_string())?;
    let mut remaining = entry.1 - offset;
    let mut buf = vec![0; CHUNK];
    while remaining > 0 {
        let n = remaining.min(CHUNK as u64) as usize;
        let n = recv
            .read(&mut buf[..n])
            .await
            .map_err(|e| e.to_string())?
            .ok_or("Unexpected end of file")?;
        file.write_all(&buf[..n]).map_err(|e| e.to_string())?;
        remaining -= n as u64;
        transferred.fetch_add(n as u64, std::sync::atomic::Ordering::Relaxed);
        #[cfg(test)]
        if remaining <= entry.1 / 2 && remaining > 0 && {
            let mut target = INTERRUPT.lock().unwrap();
            if target.as_ref() == Some(&root) {
                *target = None;
                RESUME_OFFSET.store(entry.1 - remaining, std::sync::atomic::Ordering::SeqCst);
                true
            } else {
                false
            }
        } {
            conn.close(1u32.into(), b"test interruption");
            return Err("Test interruption".into());
        }
    }
    if recv
        .read(&mut buf[..1])
        .await
        .map_err(|e| e.to_string())?
        .is_some()
        || hash(&temp_file)? != (entry.1, entry.2.clone())
    {
        drop(file);
        let _ = std::fs::remove_file(&temp_file);
        return Err("File hash or length mismatch".into());
    }
    file.flush().map_err(|e| e.to_string())?;
    drop(file);
    let target = safe_path(&root, &entry.0)?;
    std::fs::create_dir_all(target.parent().ok_or("Invalid path")?).map_err(|e| e.to_string())?;
    safe_path(&root, &entry.0)?;
    std::fs::rename(temp_file, target).map_err(|e| e.to_string())?;
    Ok(entry.1 - offset)
}
#[cfg(test)]
pub(crate) static INTERRUPT: std::sync::Mutex<Option<PathBuf>> = std::sync::Mutex::new(None);
#[cfg(test)]
pub(crate) static RESUME_OFFSET: std::sync::atomic::AtomicU64 =
    std::sync::atomic::AtomicU64::new(0);
pub(super) fn receive(
    ticket: String,
    path: String,
) -> Result<super::p2p_harness::FileTransfer, String> {
    let value: serde_json::Value = serde_json::from_str(&ticket).map_err(|e| e.to_string())?;
    let addr: iroh::EndpointAddr =
        serde_json::from_value(value["folder"].clone()).map_err(|e| e.to_string())?;
    let root = PathBuf::from(path);
    std::fs::create_dir_all(&root).map_err(|e| e.to_string())?;
    if std::fs::symlink_metadata(&root)
        .map_err(|e| e.to_string())?
        .file_type()
        .is_symlink()
    {
        return Err("Symlink destination".into());
    }
    let rt = tokio::runtime::Runtime::new().map_err(|e| e.to_string())?;
    rt.block_on(async move {
        let start = std::time::Instant::now();
        let endpoint = iroh::Endpoint::builder(iroh::endpoint::presets::N0)
            .transport_config(transport())
            .bind()
            .await
            .map_err(|e| e.to_string())?;
        let result = tokio::time::timeout(std::time::Duration::from_secs(TRANSFER_TIMEOUT_SECS), async {
            let transferred = std::sync::Arc::new(std::sync::atomic::AtomicU64::new(0));
            let metrics = std::sync::Arc::new(TransferMetrics::default());
            loop {
                let conn = endpoint
                    .connect(addr.clone(), ALPN)
                    .await
                    .map_err(|e| e.to_string())?;
                metrics.connection();
                observe_paths(conn.clone());
                let attempt: Result<_, String> = async {
                    let (mut send, mut recv) = conn.open_bi().await.map_err(|e| e.to_string())?;
                    send.write_all(&[1]).await.map_err(|e| e.to_string())?;
                    let manifest = recv.read_to_end(LIMIT).await.map_err(|e| e.to_string())?;
                    let entries: Vec<Entry> =
                        serde_json::from_slice(&manifest).map_err(|e| e.to_string())?;
                    let mut seen = std::collections::HashSet::new();
                    let mut needed = Vec::new();
                    for (i, entry) in entries.into_iter().enumerate() {
                        let dest = safe_path(&root, &entry.0)?;
                        if !seen.insert(entry.0.clone())
                            || entry.2.len() != 64
                            || !entry
                                .2
                                .bytes()
                                .all(|c| c.is_ascii_hexdigit() && !c.is_ascii_uppercase())
                        {
                            return Err("Invalid manifest".into());
                        }
                        if hash(&dest).ok() != Some((entry.1, entry.2.clone())) {
                            needed.push((i, entry));
                        }
                    }
                    let temp_name = format!(".p2p-{:x}", Sha256::digest(&manifest));
                    let temp = safe_path(&root, &temp_name)?;
                    match std::fs::create_dir(&temp) {
                        Ok(()) => (),
                        Err(e)
                            if e.kind() == std::io::ErrorKind::AlreadyExists && temp.is_dir() =>
                        {
                            ()
                        }
                        Err(e) => return Err(e.to_string()),
                    }
                    metrics.changed_files(needed.len() as u64);
                    send.write_all(&(needed.len() as u64).to_be_bytes())
                        .await
                        .map_err(|e| e.to_string())?;
                    metrics.requested(needed.len() as u64);
                    let mut tasks = tokio::task::JoinSet::new();
                    let mut bytes = 0;
                    for (index, entry) in needed {
                        if tasks.len() == 4 {
                            bytes += tasks
                                .join_next()
                                .await
                                .unwrap()
                                .map_err(|e| e.to_string())??;
                        }
                        let c = conn.clone();
                        let t = temp.clone();
                        let r = root.clone();
                        let transferred = transferred.clone();
                        let metrics = metrics.clone();
                        tasks.spawn(async move {
                            receive_one(c, t, r, index, entry, transferred, metrics).await
                        });
                    }
                    while let Some(result) = tasks.join_next().await {
                        bytes += result.map_err(|e| e.to_string())??;
                    }
                    send.write_all(&[1]).await.map_err(|e| e.to_string())?;
                    send.finish().map_err(|e| e.to_string())?;
                    send.stopped().await.map_err(|e| e.to_string())?;
                    std::fs::remove_dir(temp).map_err(|e| e.to_string())?;
                    Ok(bytes)
                }
                .await;
                match attempt {
                    Ok(_bytes) => {
                        println!("P2P6_TRANSFER_METRICS {}", metrics.summary());
                        conn.close(0u32.into(), b"done");
                        break Ok(super::p2p_harness::FileTransfer {
                            bytes: transferred.load(std::sync::atomic::Ordering::Relaxed),
                            elapsed_ms: start.elapsed().as_millis() as u64,
                            sha256: String::new(),
                        });
                    }
                    Err(_e) if conn.close_reason().is_some() => continue,
                    Err(e) => return Err(e),
                }
            }
        })
        .await
        .map_err(|_| "Transfer timed out".to_string());
        endpoint.close().await;
        result?
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn transfer_metrics_count_retries_requests_and_resumed_bytes() {
        let metrics = TransferMetrics::default();
        metrics.connection();
        metrics.changed_files(2);
        metrics.requested(2);
        metrics.resume(100);
        metrics.connection();
        metrics.changed_files(1);
        metrics.requested(1);
        metrics.resume(250);
        assert_eq!(
            metrics.summary(),
            "connections=2 retries=1 changed_files=2 blob_requests=3 resumed_bytes=350"
        );
    }
    #[test]
    fn zero_changed_files_is_preserved_on_retry() {
        let metrics = TransferMetrics::default();
        metrics.changed_files(0);
        metrics.changed_files(3);
        assert!(metrics.summary().contains("changed_files=0"));
    }
    #[test]
    fn new_receiver_can_resume_while_old_connection_is_still_open() {
        let dir = std::env::temp_dir().join(format!("p2p-stale-test-{}", std::process::id()));
        let source = dir.join("source");
        let dest = dir.join("dest");
        std::fs::create_dir_all(&source).unwrap();
        std::fs::write(source.join("note"), b"resume").unwrap();
        let ticket = start(source.to_string_lossy().into_owned()).unwrap();
        let addr: iroh::EndpointAddr = serde_json::from_value(
            serde_json::from_str::<serde_json::Value>(&ticket).unwrap()["folder"].clone(),
        )
        .unwrap();
        let rt = tokio::runtime::Runtime::new().unwrap();
        rt.block_on(async {
            let endpoint = iroh::Endpoint::builder(iroh::endpoint::presets::N0)
                .bind()
                .await
                .unwrap();
            let stale = endpoint.connect(addr, ALPN).await.unwrap();
            tokio::time::timeout(std::time::Duration::from_secs(5), async {
                loop {
                    if log_selected_path(&stale) == "direct-ip" {
                        break;
                    }
                    tokio::time::sleep(std::time::Duration::from_millis(50)).await;
                }
            })
            .await
            .expect("loopback did not select a direct IP path");
            let (mut send, mut recv) = stale.open_bi().await.unwrap();
            send.write_all(&[1]).await.unwrap();
            recv.read_to_end(LIMIT).await.unwrap();
            let (tx, rx) = std::sync::mpsc::channel();
            std::thread::spawn(move || {
                let _ = tx.send(receive(ticket, dest.to_string_lossy().into_owned()));
            });
            let result = tokio::task::spawn_blocking(move || {
                rx.recv_timeout(std::time::Duration::from_secs(15))
            })
            .await
            .unwrap()
            .expect("new receiver stalled behind old connection");
            assert_eq!(result.unwrap().bytes, 6);
            endpoint.close().await;
        });
        std::fs::remove_dir_all(dir).unwrap();
    }
    #[test]
    fn selected_path_labels_are_unambiguous() {
        assert_eq!(path_label(true, false), "direct-ip");
        assert_eq!(path_label(false, true), "relay");
        assert_eq!(path_label(false, false), "other");
    }
    #[test]
    fn rejects_unsafe_paths() {
        let root = std::env::temp_dir();
        for name in [
            "",
            "../escape",
            "/absolute",
            "a/../b",
            "a//b",
            "a\\b",
            "./a",
        ] {
            assert!(safe_path(&root, name).is_err(), "{name}");
        }
    }
}
