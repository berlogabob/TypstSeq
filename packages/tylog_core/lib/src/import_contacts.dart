import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'enrich.dart';
import 'scanner.dart';
import 'storage.dart';

/// Imports person notes without changing existing files. Dry runs reserve the
/// same identities and filenames as writes, including duplicates in the input.
Future<({int created, int skipped})> importContacts(
  Directory vault,
  File file, {
  bool write = false,
}) async {
  final source = (await file.readAsString()).replaceFirst('\ufeff', '');
  final contacts = switch (file.path.split('.').last.toLowerCase()) {
    'vcf' => _vcardContacts(source),
    'csv' => _csvContacts(source),
    _ => throw const FormatException('Expected a .vcf or .csv contacts file'),
  };
  if (!await vault.exists()) throw StateError('Vault directory does not exist');
  final storage = LocalVaultStorage(vault);
  final ids = <String>{};
  final names = <String>{};
  final paths = <String>{};
  for (final entry in await storage.list(recursive: true)) {
    paths.add(entry.path);
    if (entry.isDirectory ||
        !entry.path.endsWith('.typ') ||
        entry.path.startsWith('_system/') ||
        entry.path.startsWith('.tylog/')) {
      continue;
    }
    final note = scanNote(entry.path, await storage.readText(entry.path));
    ids.add(note.id);
    names.addAll([note.title, ...note.aliases].map(enrichKey));
  }
  var created = 0;
  var skipped = 0;
  for (final contact in contacts) {
    final title = contact.title.trim();
    final id =
        'contact-${sha256.convert(utf8.encode((contact.email.isEmpty ? title : contact.email).toLowerCase())).toString().substring(0, 10)}';
    final aliases = contact.aliases.where((s) => s.isNotEmpty).toSet().toList();
    final keys = [title, ...aliases].map(enrichKey).toSet();
    final stem = title
        .replaceAll(RegExp(r'[\x00-\x1f<>:"/\\|?*]'), '_')
        .replaceFirst(RegExp(r'[. ]+$'), '');
    // Leave room for the extension within common 255-byte filename limits.
    var filename = stem;
    while (utf8.encode(filename).length > 240) {
      filename = String.fromCharCodes(
        filename.runes.take(filename.runes.length - 1),
      );
    }
    final path = 'notes/${filename.isEmpty ? id : filename}.typ';
    if (title.isEmpty ||
        ids.contains(id) ||
        keys.any(names.contains) ||
        paths.contains(path)) {
      skipped++;
      continue;
    }
    if (write) {
      final target = File('${vault.path}/$path');
      await target.parent.create(recursive: true);
      try {
        await target.create(exclusive: true);
      } on PathExistsException {
        skipped++;
        continue;
      }
      final marker = await storage.markIndexDirty(path);
      await target.writeAsString(
        replaceNoteHeader(
          '',
          NoteMetadataDraft(
            id: id,
            title: title,
            kind: 'person',
            tags: const ['person'],
            aliases: aliases,
            properties: {
              if (contact.email.isNotEmpty) 'email': contact.email,
              if (contact.org.isNotEmpty) 'org': contact.org,
              'source': 'contacts',
            },
          ),
        ),
      );
      await storage.commitIndexWrite(marker, path);
    }
    ids.add(id);
    names.addAll(keys);
    paths.add(path);
    created++;
  }
  return (created: created, skipped: skipped);
}

class _Contact {
  const _Contact(this.title, this.email, this.org, this.aliases);
  final String title;
  final String email;
  final String org;
  final List<String> aliases;
}

List<_Contact> _vcardContacts(String source) {
  final contacts = <_Contact>[];
  var fields = <String, List<String>>{};
  final lines = <String>[];
  for (final line in const LineSplitter().convert(source)) {
    if (lines.isNotEmpty &&
        lines.last.toUpperCase().contains('ENCODING=QUOTED-PRINTABLE') &&
        lines.last.endsWith('=')) {
      lines[lines.length - 1] =
          lines.last.substring(0, lines.last.length - 1) + line;
    } else if (lines.isNotEmpty &&
        (line.startsWith(' ') || line.startsWith('\t'))) {
      lines[lines.length - 1] += line.substring(1);
    } else {
      lines.add(line);
    }
  }
  for (final line in lines) {
    final colon = line.indexOf(':');
    if (colon < 0) continue;
    final key = line
        .substring(0, colon)
        .split(';')
        .first
        .split('.')
        .last
        .toUpperCase();
    var value = line.substring(colon + 1);
    if (line
        .substring(0, colon)
        .toUpperCase()
        .contains('ENCODING=QUOTED-PRINTABLE')) {
      final bytes = <int>[];
      final encoded = utf8.encode(value);
      for (var j = 0; j < encoded.length; j++) {
        final hex = encoded[j] == 61 && j + 2 < encoded.length
            ? int.tryParse(
                String.fromCharCodes(encoded.sublist(j + 1, j + 3)),
                radix: 16,
              )
            : null;
        if (hex != null) {
          bytes.add(hex);
          j += 2;
        } else {
          bytes.add(encoded[j]);
        }
      }
      value = utf8.decode(bytes);
    }
    if (key == 'BEGIN' && value.toUpperCase() == 'VCARD') fields = {};
    if (key == 'END' && value.toUpperCase() == 'VCARD') {
      String first(String key) => fields[key]?.first ?? '';
      final n = _vcardParts(first('N'), ';');
      final title = _vcardText(first('FN')).trim();
      contacts.add(
        _Contact(
          title.isNotEmpty
              ? title
              : [
                  if (n.length > 3) n[3],
                  if (n.length > 1) n[1],
                  if (n.length > 2) n[2],
                  if (n.isNotEmpty) n[0],
                  if (n.length > 4) n[4],
                ].map(_vcardText).where((s) => s.isNotEmpty).join(' '),
          _vcardText(first('EMAIL')).trim(),
          _vcardParts(
            first('ORG'),
            ';',
          ).map(_vcardText).where((s) => s.isNotEmpty).join(' / '),
          _vcardParts(
            first('NICKNAME'),
            ',',
          ).map(_vcardText).map((s) => s.trim()).toList(),
        ),
      );
      fields = {};
    } else {
      (fields[key] ??= []).add(value);
    }
  }
  return contacts;
}

List<String> _vcardParts(String value, String separator) {
  final parts = <String>[];
  var start = 0;
  for (var i = 0; i < value.length; i++) {
    if (value[i] == '\\') {
      i++;
    } else if (value[i] == separator) {
      parts.add(value.substring(start, i));
      start = i + 1;
    }
  }
  return [...parts, value.substring(start)];
}

String _vcardText(String value) => value.replaceAllMapped(
  RegExp(r'\\(.)'),
  (m) => m[1]!.toLowerCase() == 'n' ? '\n' : m[1]!,
);

List<_Contact> _csvContacts(String source) {
  final rows = <List<String>>[];
  var row = <String>[];
  var field = StringBuffer();
  var quoted = false;
  for (var i = 0; i < source.length; i++) {
    final ch = source[i];
    if (ch == '"') {
      if (quoted && i + 1 < source.length && source[i + 1] == '"') {
        field.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (!quoted && (ch == ',' || ch == '\n' || ch == '\r')) {
      row.add(field.toString());
      field = StringBuffer();
      if (ch != ',') {
        rows.add(row);
        row = [];
        if (ch == '\r' && i + 1 < source.length && source[i + 1] == '\n') i++;
      }
    } else {
      field.write(ch);
    }
  }
  if (quoted) throw const FormatException('Unclosed quoted CSV field');
  if (row.isNotEmpty || field.isNotEmpty) rows.add([...row, field.toString()]);
  if (rows.isEmpty) return [];
  final headers = rows.first.map((s) => s.trim().toLowerCase()).toList();
  return rows.skip(1).where((row) => row.any((s) => s.trim().isNotEmpty)).map((
    row,
  ) {
    String get(List<String> names) {
      for (final name in names) {
        final i = headers.indexOf(name);
        if (i >= 0 && i < row.length && row[i].trim().isNotEmpty) {
          return row[i].trim();
        }
      }
      return '';
    }

    final full = get(['display name', 'full name', 'name']);
    return _Contact(
      full.isNotEmpty
          ? full
          : [
              get(['first name', 'given name']),
              get(['middle name', 'additional name']),
              get(['last name', 'family name']),
            ].where((s) => s.isNotEmpty).join(' '),
      get([
        'e-mail address',
        'email address',
        'e-mail 1 - value',
        'email 1 - value',
      ]),
      get(['company', 'organization 1 - name', 'organization name']),
      [
        get(['nickname']),
      ],
    );
  }).toList();
}
