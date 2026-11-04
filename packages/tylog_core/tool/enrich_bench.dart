// Read-only: time resolving every mentions file in a vault.
import 'dart:convert';
import 'dart:io';
import 'package:tylog_core/tylog_core.dart';
import 'package:tylog_core/storage.dart';

Future<void> main(List<String> args) async {
  final storage = LocalVaultStorage(Directory(args[0]));
  final index = (await loadVaultIndex(storage))!;
  final sw = Stopwatch()..start();
  final memory = EnrichMemory.build(index, await loadEnrichFeedback(storage));
  final built = sw.elapsedMilliseconds;
  var n = 0;
  for (final f in Directory('${args[0]}/$enrichMentionsDir').listSync(recursive: true).whereType<File>()) {
    final m = EnrichMentions.tryParse(jsonDecode(f.readAsStringSync()));
    final note = m == null ? null : index.notesByPath['${m.note}'] ?? index.notesByPath['${m.note}.typ'];
    if (m == null || note == null) continue;
    n += resolveMentions(m, note, memory).length;
  }
  print('entities=${memory.entities.length} memoryMs=$built decisions=$n totalMs=${sw.elapsedMilliseconds}');
}
