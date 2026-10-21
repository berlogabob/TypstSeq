#![windows_subsystem = "windows"]

use std::io;
use std::path::Path;

const FOOTER_LEN: usize = 64;
const MAGIC: &[u8; 8] = b"TYLOGPK1";

fn parse_footer(tail: &[u8]) -> Result<(u64, String), String> {
    if tail.len() < FOOTER_LEN {
        return Err("launcher footer is too short".into());
    }
    if &tail[..8] != MAGIC {
        return Err("launcher footer has the wrong magic".into());
    }

    let payload_len = u64::from_le_bytes(
        tail[8..16]
            .try_into()
            .map_err(|_| "invalid payload length".to_string())?,
    );
    let version_bytes = &tail[16..FOOTER_LEN];
    let version_bytes = &version_bytes[..version_bytes
        .iter()
        .rposition(|&byte| byte != 0)
        .map_or(0, |position| position + 1)];
    let version = std::str::from_utf8(version_bytes)
        .map_err(|_| "launcher version is not valid UTF-8")?
        .to_owned();
    if version.is_empty() {
        return Err("launcher version is empty".into());
    }
    Ok((payload_len, version))
}

fn extract(zip_bytes: &[u8], target: &Path) -> io::Result<()> {
    use std::io::Cursor;
    use zip::ZipArchive;

    std::fs::create_dir_all(target)?;
    let mut archive = ZipArchive::new(Cursor::new(zip_bytes))
        .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error))?;
    for index in 0..archive.len() {
        let mut entry = archive
            .by_index(index)
            .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error))?;
        let path = entry.enclosed_name().ok_or_else(|| {
            io::Error::new(
                io::ErrorKind::InvalidData,
                "zip entry escapes extraction directory",
            )
        })?;
        let path = target.join(path);
        if entry.is_dir() {
            std::fs::create_dir_all(path)?;
        } else {
            if let Some(parent) = path.parent() {
                std::fs::create_dir_all(parent)?;
            }
            let mut output = std::fs::File::create(path)?;
            io::copy(&mut entry, &mut output)?;
        }
    }
    Ok(())
}

#[cfg(windows)]
fn run() -> Result<(), String> {
    use std::fs::File;
    use std::io::{Read, Seek, SeekFrom};
    use std::process::Command;

    let self_path = std::env::current_exe().map_err(|error| error.to_string())?;
    let mut launcher = File::open(&self_path).map_err(|error| error.to_string())?;
    let file_len = launcher
        .metadata()
        .map_err(|error| error.to_string())?
        .len();
    if file_len < FOOTER_LEN as u64 {
        return Err("launcher is shorter than its footer".into());
    }
    launcher
        .seek(SeekFrom::Start(file_len - FOOTER_LEN as u64))
        .map_err(|error| error.to_string())?;
    let mut footer = [0; FOOTER_LEN];
    launcher
        .read_exact(&mut footer)
        .map_err(|error| error.to_string())?;
    let (payload_len, version) = parse_footer(&footer)?;
    let payload_start = file_len
        .checked_sub(FOOTER_LEN as u64)
        .and_then(|length| length.checked_sub(payload_len))
        .ok_or_else(|| "payload length exceeds launcher size".to_string())?;
    let payload_len =
        usize::try_from(payload_len).map_err(|_| "payload is too large".to_string())?;

    let version_path = Path::new(&version);
    if version_path.components().count() != 1
        || !matches!(
            version_path.components().next(),
            Some(std::path::Component::Normal(_))
        )
    {
        return Err("launcher version is not a safe directory name".into());
    }

    let root = std::env::var_os("LOCALAPPDATA")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(std::env::temp_dir)
        .join("TyLog")
        .join("app");
    std::fs::create_dir_all(&root).map_err(|error| error.to_string())?;
    let target = root.join(&version);
    if !target.join(".complete").is_file() {
        let partial = root.join(format!("{version}.partial"));
        let _ = std::fs::remove_dir_all(&partial);
        std::fs::create_dir_all(&partial).map_err(|error| error.to_string())?;
        launcher
            .seek(SeekFrom::Start(payload_start))
            .map_err(|error| error.to_string())?;
        let mut payload = vec![0; payload_len];
        launcher
            .read_exact(&mut payload)
            .map_err(|error| error.to_string())?;
        extract(&payload, &partial).map_err(|error| error.to_string())?;
        File::create(partial.join(".complete")).map_err(|error| error.to_string())?;
        if target.exists() {
            std::fs::remove_dir_all(&target).map_err(|error| error.to_string())?;
        }
        std::fs::rename(partial, &target).map_err(|error| error.to_string())?;
    }

    if let Ok(entries) = std::fs::read_dir(&root) {
        for entry in entries.flatten() {
            if entry.file_type().map(|kind| kind.is_dir()).unwrap_or(false)
                && entry.file_name().to_string_lossy() != version.as_str()
            {
                let _ = std::fs::remove_dir_all(entry.path());
            }
        }
    }

    let executable = target.join("TyLog.exe");
    Command::new(executable)
        .args(std::env::args_os().skip(1))
        .current_dir(&target)
        .env("TYLOG_LAUNCHER", &self_path)
        .spawn()
        .map_err(|error| error.to_string())?;
    Ok(())
}

#[cfg(windows)]
fn show_error(message: &str) {
    use windows_sys::Win32::UI::WindowsAndMessaging::{MessageBoxW, MB_ICONERROR, MB_OK};

    let mut text: Vec<u16> = format!("TyLog could not start: {message}")
        .encode_utf16()
        .collect();
    text.push(0);
    let title: Vec<u16> = "TyLog".encode_utf16().chain(std::iter::once(0)).collect();
    unsafe {
        MessageBoxW(
            std::ptr::null_mut(),
            text.as_ptr(),
            title.as_ptr(),
            MB_OK | MB_ICONERROR,
        );
    }
}

#[cfg(windows)]
fn main() {
    if let Err(error) = run() {
        let log_root = std::env::var_os("LOCALAPPDATA")
            .map(std::path::PathBuf::from)
            .unwrap_or_else(std::env::temp_dir);
        let _ = std::fs::create_dir_all(&log_root);
        let _ = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(log_root.join("launcher.log"))
            .and_then(|mut log| {
                use std::io::Write;
                writeln!(log, "{error}")
            });
        show_error(&error);
        std::process::exit(1);
    }
}

#[cfg(not(windows))]
fn main() {}

#[cfg(test)]
mod tests {
    use super::{extract, parse_footer, FOOTER_LEN, MAGIC};
    use std::io::{Cursor, Write};

    #[test]
    fn parses_good_footer() {
        let mut footer = [0; FOOTER_LEN];
        footer[..8].copy_from_slice(MAGIC);
        footer[8..16].copy_from_slice(&123u64.to_le_bytes());
        footer[16..22].copy_from_slice(b"1.2.3\0");
        assert_eq!(parse_footer(&footer).unwrap(), (123, "1.2.3".to_string()));
    }

    #[test]
    fn rejects_wrong_magic() {
        assert!(parse_footer(&[0; FOOTER_LEN]).is_err());
    }

    #[test]
    fn rejects_short_input() {
        assert!(parse_footer(&[0; FOOTER_LEN - 1]).is_err());
    }

    #[test]
    fn extracts_zip_contents() {
        let mut writer = zip::ZipWriter::new(Cursor::new(Vec::new()));
        let options = zip::write::SimpleFileOptions::default();
        writer.start_file("TyLog.exe", options).unwrap();
        writer.write_all(b"exe").unwrap();
        writer.start_file("data/app.so", options).unwrap();
        writer.write_all(b"app").unwrap();
        let zip_bytes = writer.finish().unwrap().into_inner();

        let target = std::env::temp_dir().join(format!(
            "tylog-launcher-test-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        extract(&zip_bytes, &target).unwrap();
        assert_eq!(std::fs::read(target.join("TyLog.exe")).unwrap(), b"exe");
        assert_eq!(std::fs::read(target.join("data/app.so")).unwrap(), b"app");
        std::fs::remove_dir_all(target).unwrap();
    }
}
