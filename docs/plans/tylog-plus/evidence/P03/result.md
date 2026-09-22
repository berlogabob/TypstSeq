# P03 — Mac–phone Nextcloud sync

Status: MAC CONNECTION VERIFIED / DEVICE SYNC OPEN

The Mac TyLog documents contain a saved legacy Nextcloud configuration. A
read-only authenticated WebDAV `PROPFIND` against its configured collection
returned HTTP 207. This confirms the saved Mac endpoint and credential can
reach a DAV collection. No remote file contents were downloaded or changed,
and no account values or secrets are recorded here.

The connected A24 is not yet verified against that account. Its production
package keeps settings and credentials in app-private storage/Android Keystore,
which are not accessible through the release package's `run-as` interface.
The earlier production checkpoint found sync disconnected. P03 therefore
remains open until the account is connected on A24 and real bidirectional
behavior is observed.

## Remaining acceptance

- Connect the same Nextcloud account in TyLog on A24 using Settings → Connect
  Nextcloud. Enter the app password on the device; do not put it in Git or chat.
- Verify a small test edit moves Mac → A24 and A24 → Mac through the existing
  sync controls.
- Verify a same-note concurrent edit is preserved as a conflict on both sides.
- Verify an attachment's checksum survives the round trip and a cold app
  restart.

The P03 account check was read-only. No production sync or conflict test has
been run yet.
