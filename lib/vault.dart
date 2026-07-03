import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'scanner.dart';

class Vault {
  Vault(this.root);

  final Directory root;

  Directory get journal => Directory('${root.path}/journal');
  Directory get pages => Directory('${root.path}/pages');
  Directory get assets => Directory('${root.path}/assets');
  Directory get meta => Directory('${root.path}/.tylog');
  Directory get templates => Directory('${meta.path}/templates');
  File get indexFile => File('${meta.path}/index.json');
  File get searchIndexFile => File('${meta.path}/search-index.json.gz');
  File get helperFile => File('${meta.path}/tylog.typ');
  File get settingsFile => File('${meta.path}/settings.json');

  static Future<Vault> openDefault() async {
    final base = await getApplicationDocumentsDirectory();
    final vault = Vault(defaultVaultDirectory(base));
    await vault.ensureCreated();
    return vault;
  }

  Future<void> ensureCreated() async {
    for (final dir in [root, journal, pages, assets, meta, templates]) {
      if (!await dir.exists()) await dir.create(recursive: true);
    }
    if (!await settingsFile.exists()) {
      await _writeFile(
        settingsFile,
        jsonEncode({'name': 'TyLogVault', 'version': 1}),
      );
    }
    if (!await helperFile.exists()) {
      await _writeFile(helperFile, tylogHelperSource);
    } else {
      final helper = await helperFile.readAsString();
      if (helper == legacyTylogHelperSource ||
          helper.contains('// tylog-helper-version: 2')) {
        await _writeFile(helperFile, tylogHelperSource);
      }
    }
  }

  Future<File> todayNote([DateTime? now]) async {
    final day = _day(now ?? DateTime.now());
    final file = File('${journal.path}/$day.typ');
    if (!await file.exists()) {
      await _writeFile(
        file,
        _noteSource(id: day, title: day, date: day, tag: 'journal'),
      );
    }
    return file;
  }

  Future<File> page(String title, {File? template, DateTime? now}) async {
    final safe = title.trim().replaceAll(RegExp(r'[\\/]'), '-');
    if (safe.isEmpty) throw ArgumentError('Page title is empty');
    final file = File('${pages.path}/$safe.typ');
    if (!await file.exists()) {
      final id = await nextNoteId(title, now: now);
      final source = template == null
          ? _noteSource(id: id, title: title.trim())
          : replaceNoteHeader(
              await template.readAsString(),
              NoteMetadataDraft(id: id, title: title.trim()),
            );
      await _writeFile(file, source);
    }
    return file;
  }

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

  Future<void> saveNote(File file, String text) => _writeFile(file, text);

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
  String? date,
  String? tag,
}) =>
    '''#import "/.tylog/tylog.typ": *

#note(
  id: "$id",
  title: "$title",${date == null ? '' : '\n  date: "$date",'}${tag == null ? '' : '\n  tags: ("$tag",),'}
)

= $title

''';
