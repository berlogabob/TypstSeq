# P09b result — deterministic legacy manifest

Accepted 2026-09-15.

- Every non-directory source entry is classified as page, journal, asset, or unsupported.
- Logseq and Obsidian rules match the existing importer; hidden paths remain explicitly unsupported.
- Unsafe and duplicate relative paths stop planning.
- Dialect, normalized path, kind, size, and modification time produce a deterministic SHA-256 fingerprint without reading or logging content.

Validation: 4 focused Flutter tests pass.
