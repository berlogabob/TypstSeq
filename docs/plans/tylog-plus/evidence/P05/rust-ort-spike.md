# P05.4a1 result — isolated Rust ONNX Runtime spike

Accepted 2026-09-15 without adding dependencies to the product crate.

The standalone pinned Rust spike loads the verified `multilingual-e5-small` Float16 ONNX model and tokenizer offline, applies E5 prefixes and 512-token truncation, supplies all three model inputs, mean-pools, and returns a finite normalized 384-dimensional Float32 vector. Model paths, input text, and vectors are not logged.

Validation: strict Clippy, the pooling/normalization unit test, and an offline Mac smoke pass. The smoke reported norm `1.000000` and about 3 ms inference after model/session setup. Android cross-build and numerical agreement remain P05.4a2 gates.
