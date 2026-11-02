import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/audio/audio_note_actions.dart';
import 'package:tylog/audio/audio_note_doc.dart';
import 'package:tylog/models.dart';
import 'package:tylog/scanner.dart';
import 'package:tylog/task_scheduler.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/workspace_controller.dart';

const _audio = NoteRef(
  id: 'recording',
  title: 'Rehearsal #1 [live]',
  path: 'notes/recording.typ',
  kind: 'audio',
  outgoingLinks: [],
);

const _source = '''
== Summary en
- 00:00 English summary
== Summary pt
- 00:00 Resumo
== Scenes en
- 00:05 Scene one
== References en
- 01:10 Reference one
== Transcript
- 00:05 Olá
- 01:10 Mundo
== Translation en
- 00:05 Hello
- 01:11 World
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('side-by-side Markdown has selected sections and all timed lines', () {
    final lines = audioTextLines(
      parseTranscript(_source),
      parallel: parseTranslation(_source, 'en'),
    );
    expect(
      audioExportContent(
        title: 'Rehearsal',
        source: _source,
        language: 'en',
        lines: lines,
        format: AudioExportFormat.markdown,
      ),
      '# Rehearsal\n\n## Summary\n\n- 00:00 English summary\n'
      '\n## Scenes\n\n- 00:05 Scene one\n'
      '\n## References\n\n- 01:10 Reference one\n'
      '\n## Text\n\n- 00:05 Olá\n- 00:05 Hello\n'
      '- 01:10 Mundo\n- 01:11 World\n',
    );
  });

  test(
    'open as page creates once, preserves edits, and reopens after restart',
    () async {
      final root = await Directory.systemTemp.createTemp('audio_text_page_');
      addTearDown(() => root.delete(recursive: true));
      final workspace = _TextPageWorkspace()..vault = Vault(root);
      addTearDown(workspace.dispose);
      final lines = [
        ...audioTextLines(parseTranslation(_source, 'en')),
        r'01:15 #hello [x] @ref `raw` <label> // text \ end',
      ];
      final path = await createAudioTextPage(workspace, _audio, 'en', lines);
      final created = await workspace.readNote(path);
      final note = scanNote(path, created);
      expect(note.kind, 'text');
      expect(note.title, '${_audio.title} (EN)');
      expect(note.outgoingLinks, contains(_audio.id));
      expect(created, contains('- 00:05 Hello\n- 01:11 World'));
      final edited = '$created\nUser edits\n';
      await workspace.mutateNote(path, (_) => edited);
      expect(
        await createAudioTextPage(workspace, _audio, 'en', ['changed']),
        path,
      );
      expect(await workspace.readNote(path), edited);
      final reopened = _TextPageWorkspace()..vault = Vault(root);
      addTearDown(reopened.dispose);
      expect(
        await createAudioTextPage(reopened, _audio, 'en', ['changed']),
        path,
      );
      expect(await workspace.readNote(path), edited);
      expect(
        await root
            .list(recursive: true)
            .where((e) => e.path.endsWith('.typ'))
            .length,
        1,
      );

      // Same CLI compilation pattern as audio_note_doc_test.dart.
      if ((await Process.run('typst', ['--version'])).exitCode != 0) return;
      await Directory('${root.path}/_system').create();
      await File('typst/tylog/lib.typ').copy('${root.path}/_system/tylog.typ');
      final result = await Process.run('typst', [
        'compile',
        '--root',
        root.path,
        '${root.path}/$path',
        '${root.path}/page.pdf',
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
    },
  );

  test('PDF-equivalent Typst escapes transcript markup and compiles', () async {
    final source = audioExportContent(
      title: _audio.title,
      source: _source,
      language: 'en',
      lines: const [
        r'00:05 #hello [x] @ref `raw` <label> // text \ end',
        r'00:06 (?) $math$',
      ],
      format: AudioExportFormat.pdf,
    );
    if ((await Process.run('typst', ['--version'])).exitCode != 0) return;
    final root = await Directory.systemTemp.createTemp('audio_export_');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/export.typ').writeAsString(source);
    final result = await Process.run('typst', [
      'compile',
      '${root.path}/export.typ',
      '${root.path}/export.pdf',
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
  });
}

// Keep the real creation and persistence APIs without starting the indexer.
class _TextPageWorkspace extends WorkspaceController {
  _TextPageWorkspace() : super(taskScheduler: TaskScheduler());

  @override
  Future<void> refreshIndex({
    bool updateStatus = true,
    bool always = false,
  }) async {}
}
