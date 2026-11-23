import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

// A second field of application arrives as a data-only pack: no code knows
// about farms or crops.
String _note(String id, String kind, [String body = '']) =>
    '''
#show: tylog.note.with(
  id: "$id",
  title: "$id",
  kind: "$kind",
)

$body
''';

void main() {
  test('smart agriculture works from its pack alone', () async {
    final root = await Directory.systemTemp.createTemp('tylog-agri-');
    addTearDown(() => root.delete(recursive: true));
    final storage = LocalVaultStorage(root);
    final ontology = File(
      '../../docs/ontology/smartagri.json',
    ).readAsBytesSync();
    final pack = ModulePack.parse({
      'ontology.json': ontology,
      'manifest.json': Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'schema': 1,
            'id': 'smartagri',
            'files': [
              {
                'path': 'ontology.json',
                'sha256': sha256.convert(ontology).toString(),
              },
            ],
          }),
        ),
      ),
    });
    await installModule(storage, pack, DateTime(2026, 1, 1));

    final notes = {
      'Quinta': ('farm', ''),
      'Parcela 1': ('parcel', 'part_of:: [[Quinta]]'),
      'Ana': ('farmer', 'manages:: [[Quinta]]'),
      'Trigo': ('crop', 'located_in:: [[Parcela 1]]\nplant_date:: 2026-03-01'),
      'Milho': ('crop', 'located_in:: [[Ana]]\nplant_date:: spring'),
      'Sonda': ('soil_tensiometer', 'location:: [[Parcela 1]]'),
    };
    for (final entry in notes.entries) {
      await storage.writeText(
        'notes/${entry.key.replaceAll(' ', '-')}.typ',
        _note(entry.key, entry.value.$1, entry.value.$2),
      );
    }
    final index = await scanVaultStorage(storage);

    expect(
      [
        for (final p in index.problems)
          if (p.code == 'ontology') '${p.subject}: ${p.message}',
      ],
      unorderedEquals([
        'notes/Milho.typ: "located_in": "Ana" is a farmer, expected place',
        'notes/Milho.typ: "plant_date": "spring" is not a date (YYYY-MM-DD)',
      ]),
    );
    expect(
      {for (final n in pointingInto(index, 'located_in', 'Quinta')) n.id},
      {'Trigo'},
    );

    final loaded = (await loadOntology(storage)).ontology;
    final memory = EnrichMemory.build(index, const [], loaded);
    String? linked(String surface, String type) => resolveMentions(
      EnrichMentions(
        note: 'x',
        contentSha: 'x',
        mentions: [EnrichMention(surface: surface, type: type, line: 1)],
        keywords: const [],
      ),
      index.notes.first,
      memory,
    ).single.target?.id;
    expect(linked('Trigo', 'topic'), 'Trigo');
    expect(linked('Quinta', 'place'), 'Quinta');
    expect(memory.entities['Sonda']?.kind, 'equipment');

    final files = await exportDomain(storage, index, 'smartagri');
    expect(
      const LineSplitter().convert(files['instances.jsonl']!),
      hasLength(6),
    );
    final out = Platform.environment['TYLOG_TTL_OUT'];
    if (out != null) await File(out).writeAsString(files['smartagri.ttl']!);
  });
}
