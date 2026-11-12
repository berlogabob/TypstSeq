import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tylog_core/values.dart';

import '../models.dart';
import 'constants.dart';

/// Adds a sender without replacing the existing body or its daily reference.
String addShareSender(String source, NoteRef person) {
  final line =
      'From: #tylog.ref-note(${jsonEncode(person.id)})[${escapeMarkup(person.title)}]';
  final from = RegExp(r'^From:.*$', multiLine: true).firstMatch(source);
  if (from != null) {
    return source.replaceRange(from.end, from.end, '\n$line');
  }
  final comments = source.indexOf('== Comments');
  if (comments >= 0) {
    return source.replaceRange(comments, comments, '$line\n\n');
  }
  return '$source\n$line\n';
}

Future<File> _recentFile() async => File(
  '${(await getApplicationSupportDirectory()).path}/share-from-recent.json',
);

Future<List<String>> readShareRecents() async {
  try {
    final data = jsonDecode(await (await _recentFile()).readAsString());
    return (data as List).whereType<String>().take(5).toList();
  } catch (_) {
    return [];
  }
}

Future<void> rememberSharePerson(String id, List<String> recent) async {
  final file = await _recentFile();
  await file.parent.create(recursive: true);
  await file.writeAsString(
    jsonEncode([id, ...recent.where((e) => e != id)].take(5).toList()),
  );
}

class ShareFromSheet extends StatefulWidget {
  const ShareFromSheet({super.key, required this.notes, required this.recent});
  final List<NoteRef> notes;
  final List<String> recent;

  @override
  State<ShareFromSheet> createState() => _ShareFromSheetState();
}

class _ShareFromSheetState extends State<ShareFromSheet> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final candidates = widget.notes
        .where((n) => n.kind == 'person' || n.kind == 'note')
        .toList();
    final visible = query.trim().isEmpty
        ? [
            for (final id in widget.recent)
              ...candidates.where((n) => n.id == id).take(1),
          ]
        : candidates
              .where(
                (n) =>
                    n.title.toLowerCase().contains(
                      query.trim().toLowerCase(),
                    ) ||
                    n.aliases.any(
                      (a) =>
                          a.toLowerCase().contains(query.trim().toLowerCase()),
                    ),
              )
              .toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: kSpace16,
          right: kSpace16,
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: 340,
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('From whom?', style: TextStyle(fontSize: 20)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Skip'),
                  ),
                ],
              ),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Search people or pages',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => query = value),
              ),
              Expanded(
                child: ListView(
                  children: [
                    if (visible.isEmpty)
                      ListTile(
                        title: Text(
                          query.trim().isEmpty
                              ? 'Search for a person or page'
                              : 'No matching people or pages',
                        ),
                      ),
                    for (final note in visible)
                      ListTile(
                        title: Text(note.title),
                        onTap: () => Navigator.pop(context, note),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
