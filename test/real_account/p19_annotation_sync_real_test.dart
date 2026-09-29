// P19 acceptance: annotation revisions sync through the real Nextcloud
// account between two devices (two vaults + databases on one host), both
// directions, without silent overwrite. Uses a scratch remote folder, never
// the production vault folder. Runs only with NC_URL/NC_USER/NC_PW set.
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/database/revision_publisher.dart';
import 'package:tylog/database/tylog_database.dart';
import 'package:tylog/nextcloud_sync.dart';
import 'package:tylog/pdf/pdf_extraction.dart';
import 'package:tylog/pdf/pdf_reader_store.dart';
import 'package:tylog/vault.dart';

final _env = Platform.environment;
final _configured = ['NC_URL', 'NC_USER', 'NC_PW'].every(
  (key) => (_env[key] ?? '').isNotEmpty,
);

void main() {
  test(
    'annotation revisions converge through the real account',
    () async {
      final folder = 'TyLogP19Scratch-${DateTime.now().millisecondsSinceEpoch}';
      final config = NextcloudConfig(
        serverUrl: _env['NC_URL']!,
        username: _env['NC_USER']!,
        password: _env['NC_PW']!,
        remoteFolder: folder,
      );
      addTearDown(() => _deleteRemote(config, folder));

      Future<(Vault, TyLogDatabase, PdfExtraction)> device() async {
        final dir = await Directory.systemTemp.createTemp('tylog_p19_');
        addTearDown(() => dir.delete(recursive: true));
        final vault = Vault(dir);
        await vault.ensureCreated();
        final db = TyLogDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final pdf = await persistPdfReaderExtraction(
          database: db,
          path: 'papers/p19.pdf',
          bytes: const [37, 80, 68, 70, 45, 49],
          pageTexts: const ['Alpha beta gamma'],
        );
        return (vault, db, pdf);
      }

      // The app's sync pass (workspace_controller): materialize, sync,
      // receive every envelope, acknowledge.
      Future<List<RevisionReceiveResult>> syncPass(
        Vault vault,
        TyLogDatabase db,
      ) async {
        final publisher = RevisionPublisher(db);
        final ids = await publisher.materialize(
          write: vault.storage.writeBytes,
        );
        final result = await NextcloudSync(config).sync(vault);
        expect(result.conflicts, 0);
        final received = <RevisionReceiveResult>[];
        for (final file in await vault.storage.list(
          path: '_system/revisions',
        )) {
          if (file.isDirectory || !file.path.endsWith('.json')) continue;
          final envelope = RevisionPublisher.decodeEnvelope(
            await vault.storage.readBytes(file.path),
          );
          if (envelope.annotation == null) continue;
          received.add(
            await db.receiveAnnotationRevision(
              annotation: envelope.annotation!,
              revision: envelope.revision,
            ),
          );
        }
        if (ids.isNotEmpty) await publisher.acknowledge(ids);
        return received;
      }

      Future<Set<String>> quotes(TyLogDatabase db, PdfExtraction pdf) =>
          db
              .annotationsFor(pdf.sourceVersionId)
              .then((rows) => {for (final row in rows) row.quote});

      final (vaultA, dbA, pdfA) = await device();
      final (vaultB, dbB, pdfB) = await device();

      await savePdfReaderSelection(
        database: dbA,
        extraction: pdfA,
        page: 0,
        localStart: 0,
        localEnd: 5,
      );
      await syncPass(vaultA, dbA);
      final atB = await syncPass(vaultB, dbB);
      expect(atB, contains(RevisionReceiveResult.applied));
      expect(await quotes(dbB, pdfB), {'Alpha'});

      await savePdfReaderSelection(
        database: dbB,
        extraction: pdfB,
        page: 0,
        localStart: 6,
        localEnd: 10,
      );
      await syncPass(vaultB, dbB);
      final atA = await syncPass(vaultA, dbA);
      expect(atA, contains(RevisionReceiveResult.applied));
      expect(await quotes(dbA, pdfA), {'Alpha', 'beta'});

      final again = await syncPass(vaultA, dbA);
      expect(again, everyElement(RevisionReceiveResult.duplicate));
      expect(await dbA.annotationsFor(pdfA.sourceVersionId), hasLength(2));

      // A divergent revision for B's annotation must not overwrite it.
      final beta = (await dbB.annotationsFor(
        pdfB.sourceVersionId,
      )).firstWhere((row) => row.quote == 'beta');
      final revisions = await dbA.select(dbA.revisions).get();
      final betaRevision = revisions.firstWhere(
        (row) => row.payloadJson.contains(beta.id),
      );
      final betaRow = (await dbA.annotationsFor(
        pdfA.sourceVersionId,
      )).firstWhere((row) => row.id == beta.id);
      expect(
        await dbA.receiveAnnotationRevision(
          annotation: betaRow,
          revision: betaRevision.copyWith(id: 'p19-divergent'),
        ),
        RevisionReceiveResult.conflict,
      );
      expect(await quotes(dbA, pdfA), {'Alpha', 'beta'});

      // ignore: avoid_print
      print(
        'P19 real-account: A->B ${atB.length} received, B->A ${atA.length} '
        'received, repeat ${again.length} duplicate, divergent=conflict',
      );
    },
    skip: !_configured,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<void> _deleteRemote(NextcloudConfig config, String folder) async {
  final client = HttpClient();
  try {
    final base = config.serverUrl.replaceAll(RegExp(r'/+$'), '');
    final request = await client.deleteUrl(
      Uri.parse(
        '$base/remote.php/dav/files/${config.username}/$folder',
      ),
    );
    request.headers
      ..set(
        HttpHeaders.authorizationHeader,
        'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}',
      )
      ..set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (TyLog P19 test)');
    await (await request.close()).drain<void>();
  } finally {
    client.close(force: true);
  }
}
