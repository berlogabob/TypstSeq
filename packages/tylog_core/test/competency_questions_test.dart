import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

// The TechLAB competency questions in docs/ontology/README.md, answered from
// a scanned fixture vault.
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
  late VaultIndex index;
  late LocalVaultStorage storage;
  setUpAll(() async {
    final root = await Directory.systemTemp.createTemp('tylog-cq-');
    addTearDown(() => root.delete(recursive: true));
    storage = LocalVaultStorage(root);
    final notes = {
      'FabLab': ('lab', ''),
      'Room 1': ('room', 'part_of:: [[FabLab]]'),
      'Bench A': ('place', 'part_of:: [[Room 1]]'),
      'Library': ('place', ''),
      'Laser': ('equipment', 'location:: [[Bench A]]'),
      'Printer': ('equipment', 'location:: [[FabLab]]'),
      'Scanner': ('equipment', 'location:: [[Library]]'),
      'Workshop': (
        'booking',
        'places:: [[Room 1]]\nstarts_at:: 2026-11-23T10:00',
      ),
      'Tour': ('booking', 'places:: [[FabLab]]\nstarts_at:: 2026-11-24T09:00'),
    };
    for (final entry in notes.entries) {
      await storage.writeText(
        'notes/${entry.key.replaceAll(' ', '-')}.typ',
        _note(entry.key, entry.value.$1, entry.value.$2),
      );
    }
    await storage.writeText(
      '$ontologyDir/techlab.json',
      File('../../docs/ontology/techlab.json').readAsStringSync(),
    );
    index = await scanVaultStorage(storage);
  });

  Set<String> ids(Iterable<NoteRef> notes) => {for (final n in notes) n.id};

  test('the domain exports as a blob and as Turtle', () async {
    await storage.writeText(
      '$enrichFeedbackDir/dev.jsonl',
      '{"at":"t","decision":"accept","surface":"fab","entity":"FabLab","note":"d"}\n'
          '{"at":"t","decision":"reject","surface":"lib","entity":"Library","note":"d"}\n',
    );
    final files = await exportDomain(storage, index, 'techlab');
    final instances = const LineSplitter()
        .convert(files['instances.jsonl']!)
        .map((line) => (jsonDecode(line) as Map)['id']);
    // Library is a plain place, a core class: not part of this domain.
    expect(instances, ['FabLab', 'Room 1', 'Tour', 'Workshop']);
    expect(files['decisions.jsonl'], contains('"kind":"lab"'));
    expect(files['decisions.jsonl'], isNot(contains('Library')));
    final ttl = files['techlab.ttl']!;
    expect(
      ttl,
      contains(
        '<urn:tylog:class#lab> rdfs:subClassOf <urn:tylog:class#place> .',
      ),
    );
    expect(
      ttl,
      contains(
        '<urn:tylog:entity#Room%201> <urn:tylog:slot#part_of> '
        '<urn:tylog:entity#FabLab> .',
      ),
    );
    final out = Platform.environment['TYLOG_TTL_OUT'];
    if (out != null) await File(out).writeAsString(ttl);
    expect(() => exportDomain(storage, index, 'nope'), throwsArgumentError);
    final rooms = await exportDomain(
      storage,
      index,
      'techlab',
      onlyClass: 'room',
    );
    expect(
      const LineSplitter().convert(rooms['instances.jsonl']!),
      hasLength(1),
    );
  });

  test('the fixture conforms to the TechLAB ontology', () {
    expect(index.problems.where((p) => p.code.startsWith('ontology')), isEmpty);
  });

  test('CQ1: where is equipment X?', () {
    final laser = index.notes.singleWhere((n) => n.id == 'Laser');
    expect(Ontology.slotValues(laser.properties['location'], entity: true), [
      'Bench A',
    ]);
  });

  test('CQ2: what equipment is in lab L, including its rooms?', () {
    expect(ids(pointingInto(index, 'location', 'FabLab')), {
      'Laser',
      'Printer',
    });
    expect(ids(pointingInto(index, 'location', 'Room 1')), {'Laser'});
  });

  test('CQ3: which bookings use place P on day D?', () {
    final onDay = pointingInto(
      index,
      'places',
      'FabLab',
    ).where((n) => '${n.properties['starts_at']}'.startsWith('2026-11-23'));
    expect(ids(onDay), {'Workshop'});
  });
}
