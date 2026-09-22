import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/database/revision_publisher.dart';
import 'package:tylog/database/tylog_database.dart';
import 'package:tylog/pdf/pdf_reader_store.dart';

void main() {
  test('annotation revision round-trips and rejects divergent parent', () async {
    final sender = TyLogDatabase(NativeDatabase.memory());
    final receiver = TyLogDatabase(NativeDatabase.memory());
    addTearDown(sender.close);
    addTearDown(receiver.close);

    final senderPdf = await persistPdfReaderExtraction(
      database: sender,
      path: 'papers/example.pdf',
      bytes: const [37, 80, 68, 70, 45, 49],
      pageTexts: const ['Alpha beta'],
    );
    await savePdfReaderSelection(
      database: sender,
      extraction: senderPdf,
      page: 0,
      localStart: 0,
      localEnd: 5,
    );
    final annotation = (await sender.annotationsFor(
      senderPdf.sourceVersionId,
    )).single;

    // The receiver extracts the same synced PDF before applying its annotation.
    final receiverPdf = await persistPdfReaderExtraction(
      database: receiver,
      path: 'papers/example.pdf',
      bytes: const [37, 80, 68, 70, 45, 49],
      pageTexts: const ['Alpha beta'],
    );
    expect(receiverPdf.sourceVersionId, senderPdf.sourceVersionId);

    late List<int> envelopeBytes;
    final revisionIds = await RevisionPublisher(
      sender,
    ).materialize(write: (_, bytes) async => envelopeBytes = bytes);
    expect(revisionIds, hasLength(1));
    final envelope = RevisionPublisher.decodeEnvelope(envelopeBytes);
    expect(envelope.node, isNull);
    expect(envelope.annotation?.id, annotation.id);
    expect(jsonDecode(envelope.revision.payloadJson), contains('quote'));

    expect(
      await receiver.receiveAnnotationRevision(
        annotation: envelope.annotation!,
        revision: envelope.revision,
      ),
      RevisionReceiveResult.applied,
    );
    expect(
      (await receiver.annotationsFor(receiverPdf.sourceVersionId)).single.quote,
      'Alpha',
    );
    expect(
      await receiver.receiveAnnotationRevision(
        annotation: envelope.annotation!,
        revision: envelope.revision,
      ),
      RevisionReceiveResult.duplicate,
    );

    final divergent = envelope.revision.copyWith(
      id: 'divergent-annotation-revision',
    );
    expect(
      await receiver.receiveAnnotationRevision(
        annotation: envelope.annotation!,
        revision: divergent,
      ),
      RevisionReceiveResult.conflict,
    );
    expect(await receiver.select(receiver.revisions).get(), hasLength(1));
  });
}
