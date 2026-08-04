import 'package:typst_flutter/src/rust/api/vault_import.dart' as api;
import 'package:typst_flutter/src/rust/frb_generated.dart';

/// Converts one Logseq/Obsidian source note into a TyLog Typst note using the
/// bundled native bridge. Returns null for empty notes (nothing to import).
Future<api.VaultNoteResult?> convertVaultNote({
  required String dialect,
  required String sourceRelPath,
  required String markdown,
}) async {
  try {
    await RustLib.init();
    // A compiler or earlier import may already have initialised the bridge.
    // ignore: avoid_catching_errors
  } on StateError catch (error) {
    if (!error.message.contains('twice')) rethrow;
  }
  return api.convertVaultNote(
    dialect: dialect,
    sourceRelPath: sourceRelPath,
    markdown: markdown,
  );
}
