import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'scanner.dart';
import 'tylog_assets.dart';
import 'vault_storage.dart';

class Vault {
  Vault(Directory root) : storage = LocalVaultStorage(root);
  Vault.withStorage(this.storage);

  final VaultStorage storage;

  Directory get root => (storage as LocalVaultStorage).root;
  Directory? get localRoot => storage is LocalVaultStorage ? root : null;
  Directory get daily => Directory('${root.path}/daily');
  Directory get notes => Directory('${root.path}/notes');
  Directory get projects => Directory('${root.path}/projects');
  Directory get articles => Directory('${root.path}/articles');
  Directory get assets => Directory('${root.path}/assets');
  Directory get outputs => Directory('${root.path}/outputs');
  Directory get system => Directory('${root.path}/_system');
  Directory get cache => Directory('${root.path}/_index');
  Directory get meta => Directory('${root.path}/.tylog');
  Directory get templates => Directory('${system.path}/templates');
  File get indexFile => File('${cache.path}/index.json');
  File get searchIndexFile => File('${cache.path}/search-index.json.gz');
  File get helperFile => File('${system.path}/tylog.typ');
  File get themeFile => File('${system.path}/theme.typ');
  File get exportFile => File('${system.path}/export.typ');
  File get bibliographyFile => File('${system.path}/bibliography.yml');
  File get settingsFile => File('${meta.path}/settings.json');

  static const indexPath = '_index/index.json';
  static const searchIndexPath = '_index/search-index.json.gz';
  static const helperPath = '_system/tylog.typ';
  static const themePath = '_system/theme.typ';
  static const exportPath = '_system/export.typ';
  static const bibliographyPath = '_system/bibliography.yml';
  static const settingsPath = '.tylog/settings.json';

  static Future<Vault> openDefault() async {
    final base = await getApplicationDocumentsDirectory();
    final vault = Vault(defaultVaultDirectory(base));
    await vault.ensureCreated();
    return vault;
  }

  Future<void> ensureCreated({bool createIfMissing = true}) async {
    final hasSettings = await storage.exists(settingsPath);
    if (!hasSettings) {
      if (await _hasLegacyContent()) {
        throw StateError(
          'This is not a TyLog v5 vault. Choose an empty folder; automatic migration is intentionally unsupported.',
        );
      }
      if (!createIfMissing) {
        throw StateError(
          'TyLog vault marker is missing. Reselect the existing vault folder.',
        );
      }
    }
    for (final path in [
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
    ]) {
      await storage.createDirectory(path);
    }
    if (!hasSettings) {
      await storage.writeText(
        settingsPath,
        jsonEncode({'name': 'TyLogVault', 'version': 5}),
      );
    } else {
      final settings = jsonDecode(await storage.readText(settingsPath)) as Map;
      if (settings['version'] != 5) {
        throw StateError(
          'This vault uses schema ${settings['version']}; TyLog requires a new v5 vault.',
        );
      }
    }
    final bundled = await TylogAssets.load();
    final managed = bundled.managedVaultFiles;
    if (!await storage.exists(helperPath)) {
      await storage.writeBytes(helperPath, managed[helperPath]!);
    } else if (await classifyTylogHelper(await storage.readText(helperPath)) ==
        TylogHelperKind.legacy) {
      await storage.writeBytes(helperPath, managed[helperPath]!);
    }
    for (final path in [themePath, exportPath]) {
      if (!await storage.exists(path)) {
        await storage.writeBytes(path, managed[path]!);
      }
    }
    for (final entry in managed.entries) {
      if (!entry.key.startsWith('_system/packages/')) continue;
      if (!await storage.exists(entry.key) ||
          !_sameBytes(await storage.readBytes(entry.key), entry.value)) {
        await storage.writeBytes(entry.key, entry.value);
      }
    }
    if (!await storage.exists(bibliographyPath)) {
      await storage.writeText(bibliographyPath, '{}\n');
    }
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
    bool force = false,
    void Function(int complete, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final previous = await loadIndex();
    final index = await scanVaultStorage(
      storage,
      previous: previous,
      force: force,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
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

  Future<void> saveNote(String path, String text) async {
    if (path.endsWith('.typ') && text.trim().isEmpty) {
      throw ArgumentError('A TyLog note cannot be empty');
    }
    await storage.writeText(path, text);
  }

  Future<bool> _hasLegacyContent() async {
    for (final entry in await storage.list()) {
      final name = entry.path.split('/').last;
      if (name == '.DS_Store') continue;
      if (name == '.tylog' && entry.isDirectory) {
        if ((await storage.list(path: '.tylog')).isNotEmpty) return true;
        continue;
      }
      return true;
    }
    return false;
  }

  String relativePath(Object value) {
    if (value is String && !value.startsWith(storage.location)) {
      return value.replaceAll('\\', '/');
    }
    final path = value is File ? value.absolute.path : value.toString();
    if (storage is! LocalVaultStorage) return path.replaceAll('\\', '/');
    final rootPath = root.absolute.path.endsWith(Platform.pathSeparator)
        ? root.absolute.path
        : '${root.absolute.path}${Platform.pathSeparator}';
    return path
        .substring(rootPath.length)
        .replaceAll(Platform.pathSeparator, '/');
  }

  Future<String> readText(String path) => storage.readText(path);
  Future<List<int>> readBytes(String path) => storage.readBytes(path);
  Future<bool> exists(String path) => storage.exists(path);
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
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

String _typstList(List<String> values) => values.isEmpty
    ? '()'
    : '(${values.map((value) => '"${value.replaceAll('"', r'\"')}"').join(', ')},)';
