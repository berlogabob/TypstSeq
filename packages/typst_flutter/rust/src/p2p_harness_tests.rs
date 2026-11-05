use crate::api::p2p_harness::{receive_scratch, start_scratch};

#[test]
fn scratch_note_round_trips_over_iroh() {
    let ticket = start_scratch("hello from scratch".to_owned()).unwrap();
    let result = receive_scratch(ticket).unwrap();
    assert_eq!(result.text, "hello from scratch");
    assert_eq!(result.bytes, 18);
    println!(
        "loopback: {} bytes in {} ms",
        result.bytes, result.elapsed_ms
    );
}

#[test]
fn rejects_invalid_ticket_and_oversized_scratch() {
    assert!(receive_scratch("not a ticket".into()).is_err());
    assert!(start_scratch("x".repeat(1024 * 1024 + 1)).is_err());
}

#[test]
fn file_round_trips_over_iroh() {
    use crate::api::p2p_harness::{receive_file, start_file};
    use sha2::{Digest, Sha256};
    use std::io::{Read, Write};
    let dir = std::env::temp_dir().join(format!("p2p-file-test-{}", std::process::id()));
    std::fs::create_dir(&dir).unwrap();
    let source = dir.join("source");
    let destination = dir.join("received");
    let mut file = std::fs::File::create(&source).unwrap();
    let chunk: Vec<u8> = (0..65536)
        .map(|i| ((i * 73 + i / 251) % 256) as u8)
        .collect();
    let mut hash = Sha256::new();
    for _ in 0..320 {
        file.write_all(&chunk).unwrap();
        hash.update(&chunk);
    }
    drop(file);
    let expected = format!("{:x}", hash.finalize());
    let ticket = start_file(source.to_string_lossy().into_owned()).unwrap();
    let result = receive_file(ticket, destination.to_string_lossy().into_owned()).unwrap();
    let mut actual = Sha256::new();
    let mut file = std::fs::File::open(destination).unwrap();
    let mut buf = [0; 65536];
    loop {
        let n = file.read(&mut buf).unwrap();
        if n == 0 {
            break;
        }
        actual.update(&buf[..n]);
    }
    assert_eq!(result.bytes, 20 * 1024 * 1024);
    assert_eq!(result.sha256, expected);
    assert_eq!(format!("{:x}", actual.finalize()), expected);
    println!(
        "file loopback: {} bytes in {} ms; {:.2} MB/s",
        result.bytes,
        result.elapsed_ms,
        result.bytes as f64 / 1000.0 / result.elapsed_ms.max(1) as f64
    );
    std::fs::remove_dir_all(dir).unwrap();
}
