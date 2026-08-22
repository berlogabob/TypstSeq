import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'models.dart';
import 'scanner.dart';
import 'storage.dart';

/// Encodes a [VaultIndex] for its on-disk cache at [TylogVaultPaths.index].
///
/// Gzip-wrapped compact JSON: the plain encoding measured 6.7 MB on a real
/// vault and is written on every rebuild and decoded on every open; the same
/// corpus compresses roughly 4:1 (the search index's measured ratio). The
/// path keeps its `.json` name — `_index/` is local and disposable, and
/// [decodeVaultIndexBytes] still reads the old plain format.
Uint8List encodeVaultIndexBytes(VaultIndex index) => Uint8List.fromList(
  gzip.encode(utf8.encode(jsonEncode(index.toJson()))),
);

/// Decodes bytes written by [encodeVaultIndexBytes], accepting both the
/// gzip format (magic `1f 8b`) and the plain JSON written by older builds.
VaultIndex decodeVaultIndexBytes(List<int> bytes) {
  final isGzip = bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b;
  final json = utf8.decode(isGzip ? gzip.decode(bytes) : bytes);
  return VaultIndex.fromJson(
    (jsonDecode(json) as Map).cast<String, Object?>(),
  );
}

abstract final class TylogVaultPaths {
  static const index = '_index/index.json';
  static const searchIndex = '_index/search-index.json.gz';
  static const helper = '_system/tylog.typ';
  static const theme = '_system/theme.typ';
  static const export = '_system/export.typ';
  static const bibliography = '_system/bibliography.yml';
  static const zoteroBib = '_system/zotero.bib';
  static const settings = '.tylog/settings.json';

  /// Per-device index donors: `<indexDonors>/<deviceId>.json`.
  ///
  /// `_index/` stays local and disposable — its mtime+size fingerprints mean
  /// nothing on another device. A donor is the portable half: the same
  /// [NoteRef] list, keyed by content hash, published so a peer can skip
  /// re-querying Typst for notes this device already inspected. It lives under
  /// `_system/` because that prefix already syncs, and one file per device
  /// means two devices can never write the same path — no conflicts.
  static const indexDonors = '_system/index';

  /// `{"schema": 1, "synonyms": {"ии": "ai", "llms": "llm"}}` — variant tags
  /// folded onto a canonical one when the index is built. Under `_system/` so
  /// it syncs to every device on its own.
  static const tagSynonyms = '_system/tag-synonyms.json';

  static const directories = [
    'daily',
    'notes',
    'projects',
    'articles',
    'assets',
    'outputs',
    '_system',
    '_index',
    '.tylog',
    '.tylog/conflicts',
    '_system/templates',
  ];
}

enum VaultStorageKind { empty, validVault, nonVault, incompatibleVault }

class VaultStorageInspection {
  const VaultStorageInspection(this.kind, {this.entryCount = 0});

  final VaultStorageKind kind;
  final int entryCount;
}

Future<VaultStorageInspection> inspectVaultStorage(VaultStorage storage) async {
  final entries = (await storage.list())
      .where((entry) => entry.path.split('/').last != '.DS_Store')
      .toList();
  if (!await storage.exists(TylogVaultPaths.settings)) {
    return VaultStorageInspection(
      entries.isEmpty ? VaultStorageKind.empty : VaultStorageKind.nonVault,
      entryCount: entries.length,
    );
  }
  try {
    final settings = jsonDecode(
      await storage.readText(TylogVaultPaths.settings),
    );
    if (settings is Map && settings['version'] == 5) {
      return VaultStorageInspection(
        VaultStorageKind.validVault,
        entryCount: entries.length,
      );
    }
  } catch (_) {}
  return VaultStorageInspection(
    VaultStorageKind.incompatibleVault,
    entryCount: entries.length,
  );
}

Future<void> initializeVaultStorage(
  VaultStorage storage, {
  required Map<String, List<int>> managedFiles,
  required String currentHelper,
  required String legacyHelper,
  bool createIfMissing = true,
}) async {
  final inspection = await inspectVaultStorage(storage);
  final hasSettings = inspection.kind == VaultStorageKind.validVault;
  if (!hasSettings) {
    if (inspection.kind == VaultStorageKind.incompatibleVault) {
      throw StateError('This vault marker is malformed or unsupported.');
    }
    if (inspection.kind == VaultStorageKind.nonVault) {
      throw StateError(
        'This folder contains other files. Choose an empty folder or a TyLog v5 vault.',
      );
    }
    if (!createIfMissing) {
      throw StateError(
        'TyLog vault marker is missing. Reselect the existing vault folder.',
      );
    }
  }
  if (!hasSettings) {
    for (final path in TylogVaultPaths.directories) {
      await storage.createDirectory(path);
    }
    await storage.writeText(
      TylogVaultPaths.settings,
      jsonEncode({'name': 'TyLogVault', 'version': 5}),
    );
  }

  if (!await storage.exists(TylogVaultPaths.helper)) {
    await storage.writeBytes(
      TylogVaultPaths.helper,
      managedFiles[TylogVaultPaths.helper]!,
    );
  } else {
    final kind = classifyTylogHelper(
      await storage.readText(TylogVaultPaths.helper),
      current: currentHelper,
      legacy: legacyHelper,
    );
    if (kind == TylogHelperKind.legacy || kind == TylogHelperKind.outdated) {
      await storage.writeBytes(
        TylogVaultPaths.helper,
        managedFiles[TylogVaultPaths.helper]!,
      );
    }
  }
  for (final path in [TylogVaultPaths.theme, TylogVaultPaths.export]) {
    if (!await storage.exists(path)) {
      await storage.writeBytes(path, managedFiles[path]!);
    }
  }
  for (final entry in managedFiles.entries) {
    if (!entry.key.startsWith('_system/packages/')) continue;
    if (!await storage.exists(entry.key) ||
        !_sameBytes(await storage.readBytes(entry.key), entry.value)) {
      await storage.writeBytes(entry.key, entry.value);
    }
  }
  await _pruneStalePackageVersions(storage, managedFiles);
  if (!await storage.exists(TylogVaultPaths.bibliography)) {
    await storage.writeText(TylogVaultPaths.bibliography, '{}\n');
  }
  await writeSyncExcludes(storage);
}

/// Keeps the device-local caches out of a desktop sync client's upload.
///
/// A vault commonly lives *inside* `~/Nextcloud`, and the client uploads
/// whatever it finds there — on a real vault ~27 MB of cache, and because the
/// search index tokenises whole note bodies it carries note text with it,
/// including values from `pswrd:` lines. The client reads `.sync-exclude.lst`
/// from a synced directory, so one file settles it.
///
/// Lives here rather than in the app because the CLI is the context most likely
/// to be pointed at a desktop vault inside a synced folder, and it never called
/// the app's copy — the hardening existed in exactly the place that needed it
/// least.
///
/// Written for every vault, not just detected-managed ones: a vault can be
/// moved into a synced folder later, and a stray exclude file in a folder no
/// client watches is inert. It does not remove what has already been uploaded —
/// that is a deliberate deletion, not something to do behind the user's back.
Future<void> writeSyncExcludes(VaultStorage storage) async {
  const path = '.sync-exclude.lst';
  const contents = '''
# Written by TyLog. Device-local caches — rebuildable, and large.
# The search index contains note text, so this also keeps note contents out of
# a desktop client's upload.
_index
.tylog
''';
  try {
    if (await storage.exists(path)) return;
    await storage.writeText(path, contents);
  } catch (_) {
    // A read-only or restricted vault still opens; this is a hardening step,
    // not a precondition.
  }
}

/// Delete files under `_system/packages/tylog/<version>/` for versions the
/// managed set no longer ships. Without this every package upgrade leaves
/// its predecessor in the vault forever. Uses only non-recursive listing
/// (this runs on the vault-open fast path, where a recursive scan is the
/// expensive operation) and file-level deletes, so the same code works on
/// SAF-backed storage where directory semantics differ; an empty directory
/// left behind is harmless.
Future<void> _pruneStalePackageVersions(
  VaultStorage storage,
  Map<String, List<int>> managedFiles,
) async {
  const root = '_system/packages/tylog';
  final currentVersions = managedFiles.keys
      .where((k) => k.startsWith('$root/'))
      .map((k) => k.substring(root.length + 1).split('/').first)
      .toSet();
  if (currentVersions.isEmpty) return;
  final List<VaultStorageEntry> versionDirs;
  try {
    versionDirs = await storage.list(path: root);
  } on Object {
    return; // nothing vendored yet
  }
  for (final dir in versionDirs) {
    if (!dir.isDirectory) continue;
    final version = dir.path.split('/').last;
    if (!currentVersions.contains(version)) {
      await _deleteFilesShallowly(storage, dir.path);
    }
  }
}

Future<void> _deleteFilesShallowly(VaultStorage storage, String path) async {
  for (final entry in await storage.list(path: path)) {
    if (entry.isDirectory) {
      await _deleteFilesShallowly(storage, entry.path);
    } else {
      await storage.delete(entry.path);
    }
  }
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}
