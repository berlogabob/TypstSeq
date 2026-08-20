# Minimal age-encrypted backup design

## Decision

Keep the TyLog vault plaintext and unchanged so Typst, editors, and sync tools continue to work. Add **no encryption to the vault format**. The first useful version is an external, desktop/operator workflow that:

1. quiesces every vault writer;
2. streams one uncompressed `tar` archive of the whole vault into the official `age` CLI;
3. publishes one binary `*.tar.age` artifact outside the vault; and
4. restores only into a new vault directory, never over the active vault.

`age` accepts one input file or stdin, and its own example archives a directory with `tar` before encryption ([age(1)](https://filippo.io/age/age.1), [official README](https://github.com/FiloSottile/age#readme)). This requires no Flutter dependency and preserves TyLog's ordinary-file contract ([TyLog ecosystem](tylog-ecosystem.md)). Android Storage Access Framework integration is deliberately deferred because the current external tool cannot safely assume a filesystem path.

## Threat model

**Protects:** confidentiality and authenticated integrity of a completed backup copied to an untrusted cloud account, removable disk, or stolen storage device. The age v1 payload is streaming ChaCha20-Poly1305 and the header is MACed; modified or truncated streams fail authentication ([age v1 specification](https://age-encryption.org/v1)).

**Does not protect:**

- the unlocked plaintext working vault or plaintext after restore;
- a compromised host while it reads the vault, invokes `age`, or has the identity available;
- deletion, rollback to an old valid backup, traffic analysis, or denial of service;
- loss or compromise of the identity;
- provenance: a recipient is a public value, so anyone who knows it can create a different valid age file for that recipient. Decryption proves ciphertext integrity, not who created the archive ([age(1), recipients and identities](https://filippo.io/age/age.1)).

Use at least two independently stored backup artifacts for availability; that policy is outside this encryption layer.

## Why archive before encryption

A vault is a directory while `age` encrypts one byte stream. Archiving first creates one recoverable object and puts internal paths, filenames, empty directories, and archive metadata inside the ciphertext. Piping `tar` directly to `age` avoids a plaintext archive on disk. Compression, if ever added, must also happen before encryption, but the initial `.tar.age` format stays uncompressed: it is simpler, streamable, and avoids a decompression stage and compression-bomb risk.

Archive paths are relative to the vault root. Include all vault content, including hidden files and rebuildable indexes, except the local transient `.tylog/vault.lock` and known temporary export files. Never place the destination or temporary output inside the vault, which would risk recursive self-inclusion. Most importantly, **an age identity must never exist in the vault, the archive, or any synced folder**.

## Key management

- Generate one dedicated native age identity on a separate recovery device with `age-keygen`; transfer only its public recipient to the vault/backup host. Keep the private `AGE-SECRET-KEY-…` identity and a second protected offline copy away from the vault and every sync target, then perform a recovery drill. `age-keygen` will not overwrite an existing output file, and `age-keygen -y` derives the public recipient ([age-keygen(1)](https://filippo.io/age/age-keygen.1)).
- The public recipient may be stored in app/external-tool configuration outside the vault. Export must require an already configured recipient; never silently generate a new key during backup.
- Initial interoperability baseline: one dedicated native X25519 recipient (`age1…`). This is the smallest v1 profile and deliberately does **not** claim protection against future quantum computers. If harvest-now/decrypt-later is in scope, set official `age` 1.3.0+ as a hard compatibility floor and use `age-keygen -pq`; current age recommends its hybrid ML-KEM-768 + X25519 keys for most applications ([age(1)](https://filippo.io/age/age.1), [official README](https://github.com/FiloSottile/age#post-quantum-keys)). Do not mix classic and post-quantum recipients: the official CLI rejects that because a classic recipient would defeat the post-quantum property.
- Do not default to SSH recipients. The official documentation warns that SSH mode embeds a public-key tag that makes files linkable to a key, and SSH authentication keys are often not retained as long-term decryption keys ([official README](https://github.com/FiloSottile/age#ssh-keys)).
- Do not default to a passphrase. Passphrase mode is valid and uses a fresh scrypt salt per file ([age v1 specification](https://age-encryption.org/v1#the-scrypt-recipient-type)), but it replaces identity custody with passphrase recovery and interactive secret handling. If offered later, never put the passphrase in arguments, logs, config, or environment variables.
- One recipient is enough initially. Additional recipients are independent decryption authorities—use them only for an explicit recovery policy ([official README](https://github.com/FiloSottile/age#multiple-recipients)).

## Export flow

1. **Preflight:** resolve the vault and an output path outside it; refuse an existing final filename; confirm the configured recipient; verify free space and that the vault marker/generation is supported.
2. **Quiesce:** require TyLog, its background sync, Typst, and external editors to be closed. Per-file atomic writes do not make a multi-file archive a point-in-time snapshot. The existing `VaultLock` coordinates sync/reindex only and is not by itself a backup barrier.
3. **Stream:** start the archive producer and official `age` as separate processes without a shell; connect archive stdout to age stdin and age stdout to a uniquely named sibling temporary file. Dart's `Process.start` takes an executable and argument list and defaults to `runInShell: false` ([Dart `Process.start`](https://api.dart.dev/dart-io/Process/start.html)). Never interpolate vault paths into a shell command.
4. **Check every participant:** close stdin correctly and require success from both the archive producer and `age`. `age` exits zero only after successful full-input encryption, but it cannot know that `tar` stopped early; checking only the last pipeline process can publish a valid encryption of an incomplete archive ([age(1), exit status](https://filippo.io/age/age.1)).
5. **Publish:** flush the ciphertext, close it, confirm it is non-empty, then rename the sibling temporary file to the final name. This matches the repository's existing write-temp/flush/rename convention. Keep staging and final paths on the same filesystem: Dart documents that `File.rename` may not cross filesystems, and it removes an existing destination, which is why preflight must refuse overwrite ([Dart `File.rename`](https://api.dart.dev/dart-io/File/rename.html), [`RandomAccessFile.flush`](https://api.dart.dev/dart-io/RandomAccessFile/flush.html)).
6. **Failure:** on cancellation or any read/write/process/flush/rename error, delete only the temporary ciphertext and report failure. Never publish or replace the final artifact.

This gives an atomic **publication boundary**, not a filesystem snapshot. Source consistency comes from quiescing writers.

## Restore flow

1. Treat the backup as untrusted input. Create an empty staging directory beside a new, non-existing final vault path; never target the active vault.
2. Decrypt to a temporary tar or a safe streaming extractor. Require `age` exit zero before accepting any result. The CLI may emit authenticated partial plaintext before a later error, so any nonzero exit discards all staged output ([age(1), exit status](https://filippo.io/age/age.1)).
3. Before creating files, reject absolute paths, `..`, backslashes, duplicate/case-colliding names, symlinks, hard links, devices, and entries outside reasonable count/size limits. The TyLog format already requires safe vault-relative paths ([TyLog Format v1](../spec/tylog-format-v1.md)). Do not extract with a general-purpose command directly into a live directory.
4. Drop transient `.tylog/vault.lock`; validate the vault marker/generation and run the existing vault validation/doctor path. Rebuild indexes rather than trusting them as authoritative.
5. Flush and close staged files, then rename the completed staging directory to the new final name on the same filesystem. Only after that succeeds may TyLog register/select it. Keep the old vault untouched until the user has opened and checked the restored one.
6. Wrong identity, truncation, tampering, unsafe archive entry, unsupported generation, no space, or any process failure leaves the active vault unchanged and deletes staging.

## Interoperability and recovery checks

- Pin and record the supported official `age` major/minor floor and recipient profile; keep binary age output (no ASCII armor unless a 7-bit transport requires it).
- Before relying on the feature, make a small backup, decrypt it with the intended recovery identity on a separate recovery environment, validate/list the tar, and byte-compare representative files. Repeat after changing age version, recipient type, or archive implementation.
- A replacement age implementation must pass the official format [test vectors](https://age-encryption.org/testkit) and round-trip artifacts with the official CLI. Stable age files are documented as decryptable by later stable releases ([age(1), backwards compatibility](https://filippo.io/age/age.1)).
- `age-inspect` can identify version, recipient types, and payload size without decrypting; use it only as a structural diagnostic, not as proof that the backup can be decrypted ([official README](https://github.com/FiloSottile/age#inspecting-encrypted-files)). A periodic full restore drill is the proof.

## Metadata leakage

Encryption does not hide the artifact's filename, directory, owner/permissions, timestamps, creation/upload timing, or the storage account holding it. The age header exposes the format version plus recipient stanza count/types, and ciphertext length reveals approximate plaintext size: the CLI documents roughly 200 bytes per recipient plus 16 bytes per 64 KiB of plaintext ([age(1)](https://filippo.io/age/age.1)); `age-inspect` reports recipient types and payload size. Native X25519 ciphertext is not linkable to its recipient without the identity, while SSH recipient tags are linkable ([age(1)](https://filippo.io/age/age.1), [age v1 recipient-stanza rules](https://age-encryption.org/v1#recipient-stanza)).

Use a neutral filename if the vault name or backup schedule is sensitive. Internal vault names and paths remain inside the encrypted tar.

## Do not build initially

- custom Dart cryptography, an age file parser, or a new age dependency;
- transparent/in-place vault encryption or changes to TyLog format generation 5;
- in-app Android/SAF restore, overwrite restore, or restore into an open vault;
- cloud-provider APIs, scheduling, retention, incremental/deduplicated backups, compression, chunking, or resumable upload;
- automatic key generation, escrow, rotation/re-encryption, key sync, plugin/hardware-token UI, or multi-recipient management;
- signing/provenance infrastructure or a custom manifest.

Add one of these only after the external `.tar.age` workflow and real recovery drills expose a concrete need. Security boundaries, path validation, no-overwrite publication, and failure cleanup are not optional simplifications.
