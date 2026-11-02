import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/database/tylog_database.dart';

NodeData _shot(String content) => NodeData(
  id: 'shot-7f61352333c11c52',
  type: 'screenshot',
  title: 'Screenshot',
  content: content,
  attributesJson: '{"contentHash":"${content.hashCode}"}',
  createdAtMs: 1,
  updatedAtMs: 1,
);

void main() {
  test('projection refreshes a projected note whose file changed', () async {
    final db = TyLogDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    // First projection: the screenshot's Text section is still empty.
    await db.projectNodes([
      _shot('== Description\nA concert\n== Text\n'),
    ]);
    // The OCR producer later writes the Text section into the same file.
    await db.projectNodes([
      _shot('== Description\nA concert\n== Text\nMONSANTOS'),
    ]);
    expect(
      await db.searchNodeIds('MONSANTOS'),
      contains('shot-7f61352333c11c52'),
    );
  });
}
