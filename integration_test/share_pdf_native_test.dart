import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog/report.dart';
import 'package:tylog/tylog_assets.dart';
import 'package:tylog/vault.dart';

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
      compileSourcePdf(
        source: '#this-function-does-not-exist()',
        files: files,
      ),
      throwsA(anything),
    );
  });
}
