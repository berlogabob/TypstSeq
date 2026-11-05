// Read-only: how the resolver decides recent days' mentions in a vault.
import 'dart:convert';
import 'dart:io';
import 'package:tylog_core/tylog_core.dart';

Future<void> main(List<String> args) async {
  final storage = LocalVaultStorage(Directory(args[0]));
  final index = (await loadVaultIndex(storage))!;
  final memory = EnrichMemory.build(index, await loadEnrichFeedback(storage));
  for (final day in args.skip(1)) {
    final path = 'daily/${day.substring(0, 4)}/${day.substring(5, 7)}/$day.typ';
    final note = index.notesByPath[path];
    final file = File('${args[0]}/${enrichMentionsPath(path)}');
    if (note == null || !file.existsSync()) continue;
    final m = EnrichMentions.tryParse(jsonDecode(file.readAsStringSync()))!;
    for (final d in resolveMentions(m, note, memory)) {
      print(
        '$day ${d.status.name.padRight(7)} ${d.mention.surface} -> ${d.target?.title ?? ''}',
      );
    }
  }
}
