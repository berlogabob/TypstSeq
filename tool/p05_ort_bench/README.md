# P05 indexing gap bench

Use existing pinned O4 assets inside the repo. This tool does not fetch models.
`MODEL` and `TOKENIZER` below are paths to those files; `.` is the repo root.

```bash
cargo run --offline --release --manifest-path tool/p05_ort_bench/Cargo.toml -- MODEL TOKENIZER .
# Generate 200 passages with exactly N encoded tokens (prefix/specials included).
cargo run --offline --release --manifest-path tool/p05_ort_bench/Cargo.toml -- MODEL TOKENIZER . --tokens 256
# Match the app's dynamic input width instead of the historical bench's 512.
cargo run --offline --release --manifest-path tool/p05_ort_bench/Cargo.toml -- MODEL TOKENIZER . --tokens 256 --dynamic
# Execute the actual production Rust function, including its cached model lock.
CARGO_PROFILE_RELEASE_OPT_LEVEL=z cargo run --offline --release --manifest-path tool/p05_ort_bench/Cargo.toml -- MODEL TOKENIZER . --tokens 256 --app
```

Repeat the sweep at 128 and 512 tokens. Synthetic repeated words control token
length; they do not reproduce a vault's language or tokenizer workload. Use
`--texts-json FILE` instead of `--tokens` for a repo-local JSON array of chunk
strings. `--tokenize-only` needs only the tokenizer; the model argument can be
`unused`. No vault is opened or changed by the tool.

All modes report raw and truncated token min/p50/p95/max/mean and truncation
count over the **whole corpus**, replacing the old first-16 warmup mean. On
Apple-silicon Mac they also assert exact stock/lean token-ID and attention-mask
parity and time both tokenizers. The stock tokenizer timing is warm: length
reporting has already encoded those texts. Loading is excluded from warm
throughput; `--app` reports cold loading separately and checks repeat-vector
bit equality. It includes Rust inference, tokenization and pooling, but excludes
the Flutter bridge, UI and database. Existing P05 native vector-golden tests
remain necessary for model parity.

## Source comparison (2026-10-03)

Production: `packages/typst_flutter/rust/src/api/embedding.rs` and
`lean_tokenizer.rs`; reference: `src/main.rs` (`session`, `inputs`, `run`, `pool`).

| Operation | App | Historical bench/default mode |
|---|---|---|
| ORT dependency | `2.0.0-rc.13`, `ndarray`, `download-binaries` | Same version/features |
| Session builder | Defaults, then `commit_from_file` | Same in `default-b1`; extra Level3/perf-thread variants |
| Thread counts | ORT defaults; no explicit 1-thread setting | ORT defaults; perf variant overrides intra threads |
| Lifetime | One global cached session/tokenizer; reload only when paths differ | One session per variant; one tokenizer per process |
| Lock | Global mutex covers tokenization, inference and pooling | No mutex |
| Tokenizer | Lean Unigram flat-map prefix search, no stock Unigram cache | Stock Unigram trie/cache |
| Prefix/truncation | `passage: `, 512 including special tokens | Same |
| Input width | Encoded length, no padding | Always 512; `--dynamic` now uses group's maximum encoded length |
| Inference batch | 1; Dart's 16-item page calls embed sequentially | 1 or 16 |
| Inputs/output | i64 IDs/mask/zero types; copied f32 hidden tensor | Same |
| Pooling | Masked sum; norm of mean; final `sum / (count * norm)` | Masked sum, then mean, then `/ norm` |
| Rust optimization | Release `opt-level = "z"`, thin LTO, 1 codegen unit | Cargo release defaults (`opt-level = 3`) |

Both poolers implement normalized masked mean, but their final division order
differs in floating-point rounding. The production pooler is unchanged.
`--app` compiles the production source directly, including its tokenizer, rather
than approximating it with the reference pooler. Use the `z` override above to
isolate the production optimization level; this does not duplicate every app
linker/profile setting.

The chunker (`lib/retrieval/chunking.dart`) targets 800 **UTF-16 code units**,
with 120 overlap; both note and PDF callers use those defaults. It gives no
token distribution. The original bench slices 800 Unicode scalar values and
extends recycled passages with a variant suffix. Neither corpus establishes
the actual vault's token lengths.

The macOS pod links a prebuilt archive; `tool/setup_typst_native.sh` builds it
with `cargo build --release` even when Flutter runs in debug mode. Identical
ORT dependency declarations do not prove that previously installed binaries
or session defaults at runtime were identical. No production performance fix
is justified without running the same inputs through these paths.

## Checks

```bash
cargo test --offline --manifest-path tool/p05_ort_bench/Cargo.toml
TYLOG_TOKENIZER_JSON=TOKENIZER cargo test --offline --manifest-path tool/p05_ort_bench/Cargo.toml matches_reference_tokenizer -- --nocapture
```

The tests cover generated token budgets, percentile reporting, padding/masks,
and lean/stock parity on a small synthetic Unigram vocabulary. The optional
real-vocabulary parity test skips when `TYLOG_TOKENIZER_JSON` is unset.
