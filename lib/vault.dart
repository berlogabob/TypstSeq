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
  File get indexFile => File('${meta.path}/index.json');
  File get helperFile => File('${meta.path}/tylog.typ');
  File get settingsFile => File('${meta.path}/settings.json');

  static Future<Vault> openDefault() async {
    final base = await getApplicationDocumentsDirectory();
    final vault = Vault(defaultVaultDirectory(base));
    await vault.ensureCreated();
    return vault;
  }

  Future<void> ensureCreated() async {
    for (final dir in [root, journal, pages, assets, meta]) {
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

  Future<File> page(String title) async {
    final safe = title.trim().replaceAll(RegExp(r'[\\/]'), '-');
    if (safe.isEmpty) throw ArgumentError('Page title is empty');
    final file = File('${pages.path}/$safe.typ');
    if (!await file.exists()) {
      await _writeFile(file, _noteSource(id: safe, title: safe));
    }
    return file;
  }

  Future<VaultIndex> rebuildIndex() async {
    final index = await scanVault(root);
    await _writeFile(
      const JsonEncoder.withIndent('  ').convert(index.toJson()),
      indexFile,
    );
    return index;
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

const tylogHelperSource = '''#let note(
  id: none,
  title: none,
  date: none,
  tags: (),
  aliases: (),
  links: (),
  files: (),
) = none

#let wikilink(target, display: none) = {
  if display == none { target } else { display }
}

#let tag(name) = [#name]
''';
