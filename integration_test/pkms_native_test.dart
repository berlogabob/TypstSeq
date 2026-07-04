import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:typst_flutter/typst_flutter.dart';
import 'package:tylog/models.dart';
import 'package:tylog/pkms_publisher.dart';
import 'package:tylog/pkms_registry.dart';
import 'package:tylog/scanner.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native Typst metadata query and PDF export', (_) async {
    final reader = await TypstMetadataReader.create();
    try {
      final metadata = await reader.read('''
#note(id: "root", title: "Root", tags: ("pkms",), links: ("child",))
#wikilink("child")
#tag("pkms")
#filelink("manual")
''');
      expect(metadata.note?['id'], 'root');
      expect(metadata.links, ['child']);
      expect(metadata.tags, ['pkms']);
      expect(metadata.files, ['manual']);
    } finally {
      reader.dispose();
    }

    final compiler = await TypstCompiler.create();
    try {
      final document = await compiler.compile(
        source: '''
#import "/.tylog/tylog.typ": *
#note(id: "root", title: "Root", tags: ("pkms",), links: ("child",), files: ("manual",))
Visible
''',
        files: FileSource.bytes({
          '.tylog/tylog.typ': Uint8List.fromList(
            utf8.encode(tylogHelperSource),
          ),
          '/.tylog/tylog.typ': Uint8List.fromList(
            utf8.encode(tylogHelperSource),
          ),
        }),
      );
      try {
        final baseline = await compiler.compile(source: 'Visible');
        try {
          final actual = await document.renderRaster(pageIndex: 0);
          final expected = await baseline.renderRaster(pageIndex: 0);
          expect(actual.width, expected.width);
          expect(actual.height, expected.height);
          expect(actual.bytes, expected.bytes);
        } finally {
          baseline.dispose();
        }
        final pdf = await document.exportPdf();
        expect(String.fromCharCodes(pdf.take(4)), '%PDF');
      } finally {
        document.dispose();
      }
    } finally {
      compiler.dispose();
    }

    final root = await Directory.systemTemp.createTemp('tylog_export_');
    addTearDown(() => root.delete(recursive: true));
    await Directory('${root.path}/pages').create();
    await File('${root.path}/pages/root.typ').writeAsString('''
#import "/.tylog/tylog.typ": *
#note(id: "root", title: "Root")
= Root
''');
    final output = File('${root.path}/collection.pdf');
    await exportPkmsCollection(
      root: root,
      index: const VaultIndex(
        notesByPath: {
          'pages/root.typ': NoteRef(
            id: 'root',
            path: 'pages/root.typ',
            title: 'Root',
            outgoingLinks: [],
          ),
        },
        backlinksByTarget: {},
      ),
      files: PkmsFileRegistry.empty,
      collection: const PkmsCollectionEntry(
        id: 'book',
        title: 'Book',
        noteIds: ['root'],
      ),
      output: output,
    );
    expect(await output.length(), greaterThan(100));
  });
}
