import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog/models.dart';
import 'package:tylog/report.dart';
import 'package:tylog/tylog_assets.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/vault_storage.dart';

class CountingLocalStorage extends LocalVaultStorage {
  CountingLocalStorage(super.root);

  final reads = <String, int>{};

  @override
  Future<Uint8List> readBytes(String path) async {
    reads[path] = (reads[path] ?? 0) + 1;
    return super.readBytes(path);
  }
}

/// Covers the compile half of "Share as PDF" against real native Typst.
///
/// The share sheet itself is platform UI and cannot be driven from a test, so
/// what is worth pinning is the part that can silently produce garbage: that a
/// note compiles to actual PDF bytes, with the same virtual filesystem the
/// preview uses (helper, packages, bibliography), rather than to an empty buffer
/// or a Typst error nobody surfaces.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a note compiles to shareable PDF bytes', (_) async {
    final root = await Directory.systemTemp.createTemp('tylog_share_pdf_');
    addTearDown(() => root.delete(recursive: true));
    final vault = Vault(root);
    await vault.ensureCreated();

    const source = '''#import "/_system/tylog.typ" as tylog
#show: tylog.note.with(id: "shared", title: "Shared Note", kind: "note")
= A heading

Body text that must end up in the PDF.
''';
    await vault.saveNote('notes/Shared.typ', source);

    final files = <String, Uint8List>{};
    for (final asset in (await TylogAssets.load()).managedVaultFiles.entries) {
      final bytes = await vault.storage.readBytes(asset.key);
      files[asset.key] = bytes;
      // Typst resolves both root-relative and absolute forms, as _typstFiles does.
      files['/${asset.key}'] = bytes;
    }

    final pdf = await compileSourcePdf(source: source, files: files);

    expect(pdf, isNotEmpty);
    expect(
      utf8.decode(pdf.take(4).toList()),
      '%PDF',
      reason: 'not a PDF — the compile silently produced something else',
    );
    // A one-page note is a few KB; a near-empty buffer would mean the source
    // never made it into the document.
    expect(pdf.length, greaterThan(1000));
  });

  testWidgets('a report export returns the same bytes it wrote', (_) async {
    final root = await Directory.systemTemp.createTemp('tylog_share_report_');
    addTearDown(() => root.delete(recursive: true));
    final vault = Vault(root);
    await vault.ensureCreated();

    const source = '''#import "/_system/tylog.typ" as tylog
= Test Report

Report body that must end up in the PDF.
''';
    await vault.storage.writeBytes(
      'outputs/Test Report.typ',
      Uint8List.fromList(utf8.encode(source)),
    );

    final export = await exportReportPdfStorage(
      vault.storage,
      'outputs/Test Report.typ',
    );

    expect(export.path, 'outputs/Test Report.pdf');
    expect(utf8.decode(export.bytes.take(4).toList()), '%PDF');
    expect(export.bytes.length, greaterThan(1000));
    // The share sheet gets the returned bytes, outputs/ keeps the written file —
    // they must be the same document.
    expect(await vault.storage.readBytes(export.path), export.bytes);
  });

  testWidgets('report export loads only compiler-requested dependencies', (
    _,
  ) async {
    final root = await Directory.systemTemp.createTemp(
      'tylog_report_requests_',
    );
    addTearDown(() => root.delete(recursive: true));
    final vault = Vault(root);
    await vault.ensureCreated();
    final storage = CountingLocalStorage(root);
    storage.reads.clear();

    await storage.writeText(
      'notes/root.typ',
      '''#import "../shared/static.typ": static
#let dynamic_path = "../shared/dynamic.typ"
#import dynamic_path: dynamic
#import "@preview/tylog:0.1.0": identity
#image("../assets/needed.png")
#read("../data/value.txt")
#cite(<smith>)
#static()
#dynamic()
#identity([package])
''',
    );
    await storage.writeText(
      'shared/static.typ',
      '#import "transitive.typ": transitive\n#let static() = transitive()\n',
    );
    await storage.writeText(
      'shared/transitive.typ',
      '#let transitive() = [transitive]\n',
    );
    await storage.writeText(
      'shared/dynamic.typ',
      '#let dynamic() = [dynamic]\n',
    );
    await storage.writeText('data/value.txt', 'data\n');
    await storage.writeText(
      '_system/bibliography.yml',
      'smith:\n  type: Article\n  title: Test\n  author: Smith, Sam\n  date: 2026\n',
    );
    await storage.writeBytes(
      'assets/needed.png',
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
        'YAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
      ),
    );
    await storage.writeText('notes/unselected.typ', 'unselected');
    await storage.writeBytes('assets/unrelated.bin', Uint8List(1024));
    await storage.writeText('outputs/unrelated.pdf', 'old output');

    const index = VaultIndex(
      notesByPath: {
        'notes/root.typ': NoteRef(
          id: 'root',
          path: 'notes/root.typ',
          title: 'Root',
          citations: ['smith'],
          outgoingLinks: [],
        ),
      },
      backlinksByTarget: {},
    );
    final report = await writeReportStorage(
      storage,
      'Requested dependencies',
      index,
      const ReportFilter(),
    );
    final baselineBytes = (await storage.list(recursive: true))
        .where(
          (entry) =>
              !entry.isDirectory &&
              !entry.path.endsWith('.tmp') &&
              !entry.path.startsWith('_index/') &&
              !entry.path.startsWith('_system/index/') &&
              !entry.path.startsWith('.tylog/'),
        )
        .fold<int>(0, (sum, entry) => sum + (entry.size ?? 0));
    storage.reads.clear();

    final export = await exportReportPdfStorage(storage, report);
    expect(utf8.decode(export.bytes.take(4).toList()), '%PDF');
    expect(export.attempts, greaterThan(1));
    expect(export.loadedBytes, greaterThan(0));
    expect(export.loadedBytes, lessThan(baselineBytes));
    expect(
      export.loadedPaths,
      containsAll(<String>[
        '_system/export.typ',
        '_system/theme.typ',
        '_system/bibliography.yml',
        '_system/packages/tylog/0.1.0/lib.typ',
        'notes/root.typ',
        'shared/static.typ',
        'shared/transitive.typ',
        'shared/dynamic.typ',
        'assets/needed.png',
        'data/value.txt',
      ]),
    );
    expect(storage.reads['notes/unselected.typ'], isNull);
    expect(storage.reads['assets/unrelated.bin'], isNull);
    expect(storage.reads['outputs/unrelated.pdf'], isNull);
  });

  testWidgets('missing dynamic report dependency fails without vault fallback', (
    _,
  ) async {
    final root = await Directory.systemTemp.createTemp('tylog_report_missing_');
    addTearDown(() => root.delete(recursive: true));
    final vault = Vault(root);
    await vault.ensureCreated();
    final storage = CountingLocalStorage(root);
    await storage.writeText(
      'notes/root.typ',
      '#let path = "../shared/missing.typ"\n#import path: missing\n#missing()\n',
    );
    await storage.writeText('notes/unselected.typ', 'unselected');
    await storage.writeBytes('assets/unrelated.bin', Uint8List(1024));
    const index = VaultIndex(
      notesByPath: {
        'notes/root.typ': NoteRef(
          id: 'root',
          path: 'notes/root.typ',
          title: 'Root',
          outgoingLinks: [],
        ),
      },
      backlinksByTarget: {},
    );
    final report = await writeReportStorage(
      storage,
      'Missing dependency',
      index,
      const ReportFilter(),
    );
    storage.reads.clear();

    await expectLater(
      exportReportPdfStorage(storage, report),
      throwsA(isA<ReportPreparationException>()),
    );
    expect(storage.reads['notes/unselected.typ'], isNull);
    expect(storage.reads['assets/unrelated.bin'], isNull);
  });

  testWidgets('a note that does not compile fails loudly', (_) async {
    final root = await Directory.systemTemp.createTemp('tylog_share_bad_');
    addTearDown(() => root.delete(recursive: true));
    final vault = Vault(root);
    await vault.ensureCreated();

    final files = <String, Uint8List>{};
    for (final asset in (await TylogAssets.load()).managedVaultFiles.entries) {
      final bytes = await vault.storage.readBytes(asset.key);
      files[asset.key] = bytes;
      files['/${asset.key}'] = bytes;
    }

    // The share path routes a throw into the Typst help sheet; if this ever
    // stopped throwing it would share a blank or stale PDF instead.
    await expectLater(
      compileSourcePdf(source: '#this-function-does-not-exist()', files: files),
      throwsA(anything),
    );
  });
}
