import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:tylog_core/models.dart';
import 'package:tylog_core/scanner.dart';
import 'package:tylog_core/storage.dart';
import 'package:tylog_core/vault.dart';

import 'flutter_typst_inspector.dart';
import 'tylog_assets.dart';

export 'package:tylog_core/vault.dart'
    show VaultStorageInspection, VaultStorageKind, inspectVaultStorage;

class Vault {
  Vault(Directory root) : storage = LocalVaultStorage(root);
  Vault.withStorage(this.storage);

  final VaultStorage storage;

  static const indexPath = TylogVaultPaths.index;
  static const searchIndexPath = TylogVaultPaths.searchIndex;
  static const helperPath = TylogVaultPaths.helper;
  static const themePath = TylogVaultPaths.theme;
  static const exportPath = TylogVaultPaths.export;
  static const bibliographyPath = TylogVaultPaths.bibliography;
  static const zoteroBibPath = TylogVaultPaths.zoteroBib;
  static const settingsPath = TylogVaultPaths.settings;

  static Future<Vault> openDefault() async {
    final base = await getApplicationDocumentsDirectory();
    final vault = Vault(defaultVaultDirectory(base));
    await vault.ensureCreated();
    return vault;
  }

  Future<void> ensureCreated({bool createIfMissing = true}) async {
    final bundled = await TylogAssets.load();
    await initializeVaultStorage(
      storage,
      managedFiles: bundled.managedVaultFiles,
      currentHelper: bundled.text('typst/vault/tylog.typ'),
      legacyHelper: bundled.text('typst/vault/legacy-v5-tylog.typ'),
      createIfMissing: createIfMissing,
    );
  }

  Future<String> todayNote([DateTime? now]) async {
    final instant = now ?? DateTime.now();
    final day = _day(instant);
    final month =
        'daily/${instant.year.toString().padLeft(4, '0')}/${instant.month.toString().padLeft(2, '0')}';
    await storage.createDirectory(month);
    final path = '$month/$day.typ';
    if (!await storage.exists(path)) {
      await storage.writeText(
        path,
        _noteSource(
          id: day,
          title: day,
          kind: 'daily',
          date: day,
          tags: const ['journal'],
        ),
      );
    }
    return path;
  }

  /// Opens (creating if missing) the journal file for an arbitrary day.
  Future<String> dailyNote(DateTime day) => todayNote(day);

  Future<String> page(
    String title, {
    String kind = 'note',
    String? template,
    DateTime? now,
  }) async {
    final safe = title.trim().replaceAll(RegExp(r'[\\/]'), '-');
    if (safe.isEmpty) throw ArgumentError('Page title is empty');
    final directory = switch (kind) {
      'project' => 'projects',
      'article' => 'articles',
      _ => 'notes',
    };
    final path = '$directory/$safe.typ';
    if (!await storage.exists(path)) {
      final id = await nextNoteId(title, now: now);
      final source = template == null
          ? _noteSource(id: id, title: title.trim(), kind: kind)
          : replaceNoteHeader(
              await storage.readText(template),
              NoteMetadataDraft(id: id, title: title.trim(), kind: kind),
            );
      await storage.writeText(path, source);
    }
    return path;
  }

  Future<String> project(String title, {DateTime? now}) =>
      page(title, kind: 'project', now: now);

  Future<String> article(String title, {DateTime? now}) =>
      page(title, kind: 'article', now: now);

  Future<VaultIndex> rebuildIndex({
    TypstInspector? inspector,
    bool force = false,
    void Function(int complete, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final previous = await loadIndex();
    FlutterTypstInspector? ownedInspector;
    if (inspector == null) {
      try {
        ownedInspector = await FlutterTypstInspector.create();
        inspector = ownedInspector;
      } catch (_) {
        // Native Typst is optional in unit tests; core safely falls back.
      }
    }
    final VaultIndex index;
    try {
      index = await scanVaultStorage(
        storage,
        inspector: inspector,
        previous: previous,
        force: force,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
    } finally {
      ownedInspector?.dispose();
    }
    await storage.writeText(
      indexPath,
      const JsonEncoder.withIndent('  ').convert(index.toJson()),
    );
    return index;
  }

  Future<VaultIndex?> loadIndex() async {
    if (!await storage.exists(indexPath)) return null;
    try {
      return VaultIndex.fromJson(
        (jsonDecode(await storage.readText(indexPath)) as Map)
            .cast<String, Object?>(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<String> nextNoteId(String title, {DateTime? now}) async {
    final instant = now ?? DateTime.now();
    final stamp =
        '${instant.year.toString().padLeft(4, '0')}'
        '${instant.month.toString().padLeft(2, '0')}'
        '${instant.day.toString().padLeft(2, '0')}-'
        '${instant.hour.toString().padLeft(2, '0')}'
        '${instant.minute.toString().padLeft(2, '0')}'
        '${instant.second.toString().padLeft(2, '0')}';
    final slug = title
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final base = slug.isEmpty ? stamp : '$stamp-$slug';
    final ids = (await loadIndex())?.notes.map((note) => note.id).toSet() ?? {};
    var id = base;
    var suffix = 2;
    while (ids.contains(id)) {
      id = '$base-${suffix++}';
    }
    return id;
  }

  Future<String> nextTaskId(String text, {DateTime? now}) async {
    final instant = now ?? DateTime.now();
    final stamp =
        '${instant.year.toString().padLeft(4, '0')}'
        '${instant.month.toString().padLeft(2, '0')}'
        '${instant.day.toString().padLeft(2, '0')}-'
        '${instant.hour.toString().padLeft(2, '0')}'
        '${instant.minute.toString().padLeft(2, '0')}'
        '${instant.second.toString().padLeft(2, '0')}';
    final slug = text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final base = slug.isEmpty ? stamp : '$stamp-$slug';
    final ids = (await loadIndex())?.tasks.map((task) => task.id).toSet() ?? {};
    var id = base;
    var suffix = 2;
    while (ids.contains(id)) {
      id = '$base-${suffix++}';
    }
    return id;
  }

  Future<void> saveNote(String path, String text) async {
    if (path.endsWith('.typ') && text.trim().isEmpty) {
      throw ArgumentError('A TyLog note cannot be empty');
    }
    await storage.writeText(path, text);
  }

  Future<String> readText(String path) => storage.readText(path);
  Future<List<int>> readBytes(String path) => storage.readBytes(path);
  Future<bool> exists(String path) => storage.exists(path);
}

Directory defaultVaultDirectory(
  Directory appDocuments, {
  Map<String, String>? environment,
  bool? desktop,
}) {
  final env = environment ?? Platform.environment;
  final configured = env['TYLOG_VAULT_DIR']?.trim();
  if (configured != null && configured.isNotEmpty) return Directory(configured);

  final home = env['HOME'];
  if ((desktop ?? (Platform.isMacOS || Platform.isLinux)) && home != null) {
    final direct = Directory('$home/Nextcloud');
    if (direct.existsSync()) return Directory('${direct.path}/TyLogVault');

    final cloudStorage = Directory('$home/Library/CloudStorage');
    if (cloudStorage.existsSync()) {
      for (final entry in cloudStorage.listSync()) {
        if (entry is Directory &&
            entry.path.split('/').last.toLowerCase().contains('nextcloud')) {
          return Directory('${entry.path}/TyLogVault');
        }
      }
    }
  }

  return Directory('${appDocuments.path}/TyLogVault');
}

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _noteSource({
  required String id,
  required String title,
  String kind = 'note',
  String? date,
  List<String> tags = const [],
}) =>
    '''#import "/_system/tylog.typ" as tylog

#show: tylog.note.with(
  id: "$id",
  title: "$title",
  kind: "$kind",${date == null ? '' : '\n  date: "$date",'}
  tags: ${_typstList(tags)},
)

= $title

''';

bool isPristineStarterNote(String path, String source) {
  final match = RegExp(
    r'^daily/\d{4}/\d{2}/(\d{4}-\d{2}-\d{2})\.typ$',
  ).firstMatch(path);
  final day = match?.group(1);
  return day != null &&
      source ==
          _noteSource(
            id: day,
            title: day,
            kind: 'daily',
            date: day,
            tags: const ['journal'],
          );
}

String _typstList(List<String> values) => values.isEmpty
    ? '()'
    : '(${values.map((value) => '"${value.replaceAll('"', r'\"')}"').join(', ')},)';
