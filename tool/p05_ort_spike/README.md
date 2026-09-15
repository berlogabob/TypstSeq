# P05.4a1 ORT feasibility spike

Keep model and tokenizer files outside the repository. Build and test offline
after dependencies are cached:

```bash
cargo test --manifest-path tool/p05_ort_spike/Cargo.toml --offline
cargo run --manifest-path tool/p05_ort_spike/Cargo.toml --offline -- \
  /private/p05/model_O4.onnx /private/p05/tokenizer.json query 'smoke text'
```

The command prints only dimension, norm, finite status, and elapsed time.
Input paths and text are never printed. A build or model-load failure is a
blocker for this Rust path; do not substitute another framework in this spike.

The pinned candidate is `intfloat/multilingual-e5-small` revision
`ccc66d3bcd826f577e26b9a4072cc5fe3a7ad6a3`, using `onnx/model_O4.onnx` and
the matching `onnx/tokenizer.json`. The offline Mac smoke produced
`dimension=384 norm=1.000000 finite=true elapsed_ms=2.730208`.
