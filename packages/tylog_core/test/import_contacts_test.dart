import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  late Directory vault;
  late Directory input;
  setUp(() async {
    vault = await Directory.systemTemp.createTemp('contacts-vault-');
    input = await Directory.systemTemp.createTemp('contacts-input-');
  });
  tearDown(() async {
    await vault.delete(recursive: true);
    await input.delete(recursive: true);
  });

  Future<File> fixture(String name, String text) =>
      File('${input.path}/$name').writeAsString(text);

  Future<void> existing(String path, NoteMetadataDraft draft) async {
    final file = File('${vault.path}/$path');
    await file.parent.create(recursive: true);
    await file.writeAsString(replaceNoteHeader('', draft));
  }

  for (final version in ['2.1', '3.0', '4.0']) {
    test('vCard $version: UTF-8, folding, structured name, aliases', () async {
      final file = await fixture('people.vcf', '''BEGIN:VCARD\r
VERSION:$version\r
FN:José \r
 Silva\r
N:Silva;José;;;\r
EMAIL;TYPE=INTERNET:JOSE@example.com\r
EMAIL:other@example.com\r
ORG:Research\\; Design;Lab\r
TEL:+35112345\r
NICKNAME:Zé,Joe\\, Jr.\r
END:VCARD\r
BEGIN:VCARD\r
VERSION:$version\r
N:Smith;Alice;Jane;;\r
END:VCARD\r
BEGIN:VCARD\r
VERSION:$version\r
EMAIL:nameless@example.com\r
END:VCARD\r
''');
      expect(await importContacts(vault, file), (created: 2, skipped: 1));
      expect(await vault.list().toList(), isEmpty);
      expect(await importContacts(vault, file, write: true), (
        created: 2,
        skipped: 1,
      ));
      final source = await File(
        '${vault.path}/notes/José Silva.typ',
      ).readAsString();
      final note = scanNote('notes/José Silva.typ', source);
      final hash = sha256
          .convert(utf8.encode('jose@example.com'))
          .toString()
          .substring(0, 10);
      expect(note.id, 'contact-$hash');
      expect(note.kind, 'person');
      expect(note.tags, ['person']);
      expect(note.aliases, unorderedEquals(['Zé', 'Joe, Jr.']));
      expect(note.aliases, isNot(contains('José')));
      expect(note.date, isNull);
      expect(note.project, isNull);
      expect(note.properties, {
        'email': 'JOSE@example.com',
        'org': 'Research; Design / Lab',
        'source': 'contacts',
      });
      expect(
        source,
        replaceNoteHeader(
          '',
          NoteMetadataDraft(
            id: note.id,
            title: 'José Silva',
            kind: 'person',
            tags: ['person'],
            aliases: ['Zé', 'Joe, Jr.'],
            properties: note.properties,
          ),
        ),
      );
      expect(
        await File('${vault.path}/notes/Alice Jane Smith.typ').exists(),
        isTrue,
      );

      // Moving and renaming the old note defeats the filename/title guards:
      // this assertion must depend on the stable-id dedupe.
      await File('${vault.path}/notes/José Silva.typ').delete();
      await existing(
        'notes/moved.typ',
        NoteMetadataDraft(id: note.id, title: 'Renamed person'),
      );
      expect(await importContacts(vault, file, write: true), (
        created: 0,
        skipped: 3,
      ));
    });
  }

  for (final emailHeader in [
    'E-mail Address',
    'Email Address',
    'E-mail 1 - Value',
  ]) {
    test(
      'CSV $emailHeader: quoted commas, newlines, quotes and Typst text',
      () async {
        final file = await fixture(
          'people.csv',
          '\ufeffFirst Name,Last Name,$emailHeader,Company,Nickname\r\n'
              '"Ada, A.",Lovelace,ada@example.com,"Analytical, ""Engines""\n#lab",Countess\r\n',
        );
        expect(await importContacts(vault, file, write: true), (
          created: 1,
          skipped: 0,
        ));
        final source = await File(
          '${vault.path}/notes/Ada, A. Lovelace.typ',
        ).readAsString();
        final note = scanNote('notes/Ada, A. Lovelace.typ', source);
        expect(note.title, 'Ada, A. Lovelace');
        expect(note.aliases, ['Countess']);
        expect(source, contains('Analytical, \\"Engines\\"\n#lab'));
        expect(note.properties['email'], 'ada@example.com');
        expect(await importContacts(vault, file, write: true), (
          created: 0,
          skipped: 1,
        ));
      },
    );
  }

  for (final alias in [false, true]) {
    test(
      'skips existing ${alias ? 'alias' : 'title'} ignoring case and accents',
      () async {
        await existing(
          'notes/unrelated-filename.typ',
          NoteMetadataDraft(
            id: 'existing',
            title: alias ? 'Someone' : 'JOSÉ SILVA',
            aliases: alias ? ['JOSÉ SILVA'] : [],
          ),
        );
        final file = await fixture(
          'people.csv',
          'First Name,Last Name\nJose,Silva\n',
        );
        expect(await importContacts(vault, file), (created: 0, skipped: 1));
        expect(await importContacts(vault, file, write: true), (
          created: 0,
          skipped: 1,
        ));
        expect(
          await File('${vault.path}/notes/Jose Silva.typ').exists(),
          isFalse,
        );
      },
    );
  }

  test('input duplicates and existing files are never overwritten', () async {
    await existing(
      'notes/A_B.typ',
      const NoteMetadataDraft(id: 'keep', title: 'Different'),
    );
    final before = await File('${vault.path}/notes/A_B.typ').readAsString();
    final file = await fixture(
      'people.csv',
      'Name,Email Address,Nickname\nA/B,a@example.com,\nNew Person,n@example.com,NP\nOther,n@example.com,\nNP,other@example.com,\n',
    );
    expect(await importContacts(vault, file), (created: 1, skipped: 3));
    expect(await importContacts(vault, file, write: true), (
      created: 1,
      skipped: 3,
    ));
    expect(await File('${vault.path}/notes/A_B.typ').readAsString(), before);
  });

  test('vCard 2.1 quoted-printable UTF-8 and soft line breaks', () async {
    final file = await fixture(
      'people.vcf',
      'BEGIN:VCARD\nVERSION:2.1\n'
          'FN;CHARSET=UTF-8;ENCODING=QUOTED-PRINTABLE:Jos=C3=A9=\n Silva\n'
          'END:VCARD\n',
    );
    expect(await importContacts(vault, file, write: true), (
      created: 1,
      skipped: 0,
    ));
    expect(await File('${vault.path}/notes/José Silva.typ').exists(), isTrue);
  });

  test('malformed CSV fails before writing', () async {
    final file = await fixture('people.csv', 'Name\nValid\n"Unclosed');
    await expectLater(
      importContacts(vault, file, write: true),
      throwsFormatException,
    );
    expect(await vault.list().toList(), isEmpty);
  });
}
