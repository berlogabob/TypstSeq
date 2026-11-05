use crate::api::p2p_harness::{receive_scratch, start_scratch};

#[test]
fn scratch_note_round_trips_over_iroh() {
    let ticket = start_scratch("hello from scratch".to_owned()).unwrap();
    let result = receive_scratch(ticket).unwrap();
    assert_eq!(result.text, "hello from scratch");
    assert_eq!(result.bytes, 18);
    println!("loopback: {} bytes in {} ms", result.bytes, result.elapsed_ms);
}

#[test]
fn rejects_invalid_ticket_and_oversized_scratch() {
    assert!(receive_scratch("not a ticket".into()).is_err());
    assert!(start_scratch("x".repeat(1024 * 1024 + 1)).is_err());
}
