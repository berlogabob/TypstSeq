# P05.0 — offline embedding contract and provenance

Status: ACCEPTED; ready for P05.1/P05.2  
Date: 2026-09-15

This checkpoint pins the candidate artifact and the inference contract. It does
not claim that the artifact runs on either target or meets P05 latency, memory,
or retrieval-quality gates.

## Candidate artifact

Source: `intfloat/multilingual-e5-small` on Hugging Face, immutable revision
`ccc66d3bcd826f577e26b9a4072cc5fe3a7ad6a3` (the model tree currently labels
this revision `ccc66d3`; use the full commit in every URL and download).

| File | Size | Verified SHA-256 |
|---|---:|---|
| `onnx/model_O4.onnx` | 235,052,531 bytes | `4654c156f3e4171abc9c716cdb771bf9116455d15ac1aab364aeeede0e3205b0` |
| `onnx/config.json` | 653 bytes | `bbb7c1333fc4b3e27fbc9cd5d2070aabcc1d4dfb99917c3633e772f97545a6b6` |
| `onnx/tokenizer.json` | 17,082,730 bytes | `0b44a9d7b51c3c62626640cda0e2c2f70fdacdc25bbbd68038369d14ebdf4c39` |
| `onnx/sentencepiece.bpe.model` | 5,069,051 bytes | `cfc8146abe2a0488e9e2a0c56de7952f7c11ab059eca145a0a727afce0db2865` |
| `onnx/tokenizer_config.json` | 443 bytes | `a1d6bc8734a6f635dc158508bef000f8e2e5a759c7d92f984b2c86e5ff53425b` |
| `onnx/special_tokens_map.json` | 167 bytes | `d05497f1da52c5e09554c0cd874037a083e1dc1b9cfd48034d1c717f1afc07a7` |

Every digest above was independently calculated from downloaded bytes. The
model digest also matches its upstream Hugging Face LFS OID. `model_O4.onnx`
uses Float16 initializers and ONNX Runtime contributed operators; it has no
x86-specific filename or integer quantization claim. A local SHA-256 manifest
must still match before every benchmark. A024 execution remains a P05.4 gate.

The model card declares MIT licensing, 94 languages, and the files above. The
configuration declares hidden size/dimension 384 and maximum position length
512. The tokenizer configuration declares model max length 512 and
XLM-Roberta tokenization. These are recorded facts, not benchmark results.

## Inference contract

- Inputs are UTF-8 text prefixed exactly with `query: ` for queries and
  `passage: ` for indexed passages, as specified by the model card.
- Use the pinned tokenizer; truncate/pad to at most 512 tokens.
- Mean-pool token embeddings using the attention mask, then L2-normalize.
- Store normalized Float32 vectors of dimension 384.
- Compare with exact cosine first. Do not load the corpus as Dart objects.
- CPU execution is the baseline. Pin ONNX Runtime `1.30.0` for the numerical
  runner and `com.microsoft.onnxruntime:onnxruntime-android:1.30.0` for A024.
  Acceleration is allowed only when measured necessary.

## Reproduction and privacy

Download into a private directory outside the repository, using the immutable
revision URLs:

```bash
MODEL_DIR=/private/p05/multilingual-e5-small-ccc66d3bcd826f577e26b9a4072cc5fe3a7ad6a3
mkdir -p "$MODEL_DIR"
for f in config.json model_O4.onnx sentencepiece.bpe.model special_tokens_map.json tokenizer.json tokenizer_config.json; do
  curl --fail --location --retry 2 --output "$MODEL_DIR/$f" \
    "https://huggingface.co/intfloat/multilingual-e5-small/resolve/ccc66d3bcd826f577e26b9a4072cc5fe3a7ad6a3/onnx/$f"
done
shasum -a 256 "$MODEL_DIR"/* | sort | tee "$MODEL_DIR/SHA256SUMS"
stat -f '%z %N' "$MODEL_DIR"/*
```

Verify the output against this file's pinned values and retain the raw
manifest outside Git. A Mac smoke run with the pinned ONNX Runtime `1.30.0`
loaded the model on `CPUExecutionProvider`; two runs over four synthetic
EN/PT/RU records produced identical finite, unit-normalized `4 x 384`
artifacts. This is compatibility evidence only. Record
`python3 --version`, ONNX Runtime version,
Flutter version, OS/CPU, Android model/build, and the exact app commit. Model
downloads are the only network step; inference and all benchmarks must run in
airplane mode or with network denied. Logs may contain counts, timings,
dimensions, hashes, and error classes only. Never log note text, query text,
file names, source paths, tokens, or credentials.

## Sources

- Model files and revision: <https://huggingface.co/intfloat/multilingual-e5-small/tree/ccc66d3bcd826f577e26b9a4072cc5fe3a7ad6a3/onnx>
- Model card and usage contract: <https://huggingface.co/intfloat/multilingual-e5-small/blob/ccc66d3bcd826f577e26b9a4072cc5fe3a7ad6a3/README.md>
- ONNX Runtime Mobile: <https://onnxruntime.ai/docs/get-started/with-mobile.html>
- ONNX quantization: <https://onnxruntime.ai/docs/performance/model-optimizations/quantization.html>
