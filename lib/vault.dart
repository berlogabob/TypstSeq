import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'scanner.dart';

class Vault {
  Vault(this.root);

  final Directory root;

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

  static Future<Vault> openDefault() async {
    final base = await getApplicationDocumentsDirectory();
    final vault = Vault(defaultVaultDirectory(base));
    await vault.ensureCreated();
    return vault;
  }

  Future<void> ensureCreated() async {
    if (!await settingsFile.exists() && await _hasLegacyContent()) {
      throw StateError(
        'This is not a TyLog v5 vault. Choose an empty folder; automatic migration is intentionally unsupported.',
      );
    }
    for (final dir in [
      root,
      daily,
      notes,
      projects,
      articles,
      assets,
      outputs,
      system,
      cache,
      meta,
      templates,
    ]) {
      if (!await dir.exists()) await dir.create(recursive: true);
    }
    if (!await settingsFile.exists()) {
      await _writeFile(
        settingsFile,
        jsonEncode({'name': 'TyLogVault', 'version': 5}),
      );
    } else {
      final settings = jsonDecode(await settingsFile.readAsString()) as Map;
      if (settings['version'] != 5) {
        throw StateError(
          'This vault uses schema ${settings['version']}; TyLog requires a new v5 vault.',
        );
      }
    }
    if (!await helperFile.exists()) {
      await _writeFile(helperFile, tylogHelperSource);
    }
    if (!await themeFile.exists()) {
      await _writeFile(themeFile, tylogThemeSource);
    }
    if (!await exportFile.exists()) {
      await _writeFile(exportFile, tylogExportSource);
    }
    if (!await bibliographyFile.exists()) {
      await _writeFile(bibliographyFile, '{}\n');
    }
  }

  Future<File> todayNote([DateTime? now]) async {
    final instant = now ?? DateTime.now();
    final day = _day(instant);
    final month = Directory(
      '${daily.path}/${instant.year.toString().padLeft(4, '0')}/${instant.month.toString().padLeft(2, '0')}',
    );
    if (!await month.exists()) await month.create(recursive: true);
    final file = File('${month.path}/$day.typ');
    if (!await file.exists()) {
      await _writeFile(
        file,
        _noteSource(
          id: day,
          title: day,
          kind: 'daily',
          date: day,
          tags: const ['journal'],
        ),
      );
    }
    return file;
  }

  Future<File> page(
    String title, {
    String kind = 'note',
    File? template,
    DateTime? now,
  }) async {
    final safe = title.trim().replaceAll(RegExp(r'[\\/]'), '-');
    if (safe.isEmpty) throw ArgumentError('Page title is empty');
    final directory = switch (kind) {
      'project' => projects,
      'article' => articles,
      _ => notes,
    };
    final file = File('${directory.path}/$safe.typ');
    if (!await file.exists()) {
      final id = await nextNoteId(title, now: now);
      final source = template == null
          ? _noteSource(id: id, title: title.trim(), kind: kind)
          : replaceNoteHeader(
              await template.readAsString(),
              NoteMetadataDraft(id: id, title: title.trim(), kind: kind),
            );
      await _writeFile(file, source);
    }
    return file;
  }

  Future<File> project(String title, {DateTime? now}) =>
      page(title, kind: 'project', now: now);

  Future<File> article(String title, {DateTime? now}) =>
      page(title, kind: 'article', now: now);

  Future<VaultIndex> rebuildIndex({
    bool force = false,
    void Function(int complete, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final previous = await loadIndex();
    final index = await scanVault(
      root,
      previous: previous,
      force: force,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
    await _writeFile(
      const JsonEncoder.withIndent('  ').convert(index.toJson()),
      indexFile,
    );
    return index;
  }

  Future<VaultIndex?> loadIndex() async {
    if (!await indexFile.exists()) return null;
    try {
      return VaultIndex.fromJson(
        (jsonDecode(await indexFile.readAsString()) as Map)
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

  Future<void> saveNote(File file, String text) async {
    if (file.path.endsWith('.typ') && text.trim().isEmpty) {
      throw ArgumentError('A TyLog note cannot be empty');
    }
    await _writeFile(file, text);
  }

  Future<bool> _hasLegacyContent() async {
    if (!await root.exists()) return false;
    await for (final entry in root.list()) {
      final name = entry.path.split(Platform.pathSeparator).last;
      if (name == '.DS_Store') continue;
      if (name == '.tylog' && entry is Directory) {
        if (!await entry.list().isEmpty) return true;
        continue;
      }
      return true;
    }
    return false;
  }

  String relativePath(File file) {
    final rootPath = root.absolute.path.endsWith(Platform.pathSeparator)
        ? root.absolute.path
        : '${root.absolute.path}${Platform.pathSeparator}';
    return file.absolute.path
        .substring(rootPath.length)
        .replaceAll(Platform.pathSeparator, '/');
  }
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

Future<void> _writeFile(Object a, Object b) async {
  final file = a is File ? a : b as File;
  final text = a is String ? a : b as String;
  await file.parent.create(recursive: true);
  final tmp = File('${file.path}.tmp');
  await tmp.writeAsString(text, flush: true);
  if (await file.exists()) await file.delete();
  await tmp.rename(file.path);
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
