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

#[test]
fn folder_incremental_loopback() {
    use crate::api::p2p_harness::{receive_file, start_file};
    use std::io::Write;
    let dir = std::env::temp_dir().join(format!("p2p-folder-test-{}", std::process::id()));
    let source = dir.join("source");
    let dest = dir.join("dest");
    std::fs::create_dir_all(&source).unwrap();
    let data: Vec<u8> = (0..65536)
        .map(|i| ((i * 73 + i / 251) % 256) as u8)
        .collect();
    for i in 0..300 {
        let sub = source.join(format!("group-{}", i / 30));
        std::fs::create_dir_all(&sub).unwrap();
        let mut f = std::fs::File::create(sub.join(format!("{i}.bin"))).unwrap();
        let size = (200 * 1024 * 1024 / 300) + usize::from(i < 200 * 1024 * 1024 % 300);
        for chunk in data
            .iter()
            .copied()
            .cycle()
            .take(size)
            .collect::<Vec<_>>()
            .chunks(65536)
        {
            f.write_all(chunk).unwrap();
        }
    }
    let run = || {
        receive_file(
            start_file(source.to_string_lossy().into_owned()).unwrap(),
            dest.to_string_lossy().into_owned(),
        )
        .unwrap()
    };
    let first = run();
    assert_eq!(first.bytes, 200 * 1024 * 1024);
    for i in 0..300 {
        let p = format!("group-{}/{i}.bin", i / 30);
        assert_eq!(
            std::fs::read(source.join(&p)).unwrap(),
            std::fs::read(dest.join(&p)).unwrap()
        );
    }
    let second = run();
    assert_eq!(second.bytes, 0);
    std::fs::write(source.join("group-0/0.bin"), b"changed").unwrap();
    let third = run();
    assert_eq!(third.bytes, 7);
    assert_eq!(
        std::fs::read(dest.join("group-0/0.bin")).unwrap(),
        b"changed"
    );
    println!(
        "folder loopback: {} bytes in {} ms; {:.2} MB/s; repeat {} bytes",
        first.bytes,
        first.elapsed_ms,
        first.bytes as f64 / 1000.0 / first.elapsed_ms.max(1) as f64,
        second.bytes
    );
    std::fs::remove_dir_all(dir).unwrap();
}
