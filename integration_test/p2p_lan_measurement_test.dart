import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:typst_flutter/typst_flutter.dart' as p2p;
import 'package:tylog/widgets/settings/p2p_snapshot.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('generated scratch folder crosses both directions', (
    tester,
  ) async {
    await tester.runAsync(() async {
      if (Platform.isAndroid) {
        expect(
          await const MethodChannel(
            'org.tylog.tylog/share',
          ).invokeMethod<bool>('isProfileTest'),
          isTrue,
        );
      }
      await p2p.initP2pHarness();
      const host = String.fromEnvironment('P2P_CONTROL_HOST');
      final socket = await Socket.connect(host, 47993);
      final lines = StreamIterator(
        socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter()),
      );
      socket.writeln(Platform.isAndroid ? 'android' : 'mac');
      final root = await Directory.systemTemp.createTemp('p2p-lan-test-');
      try {
        final snapshot = await createRepresentativeScratchSnapshot(root);
        Future<void> send() async {
          socket.writeln(await p2p.startP2pScratch(snapshot));
          expect(await lines.moveNext(), isTrue);
          expect(lines.current, 'received');
        }

        Future<void> receive() async {
          expect(await lines.moveNext(), isTrue);
          final transfer = await p2p.receiveP2pScratch(lines.current);
          expect(transfer.text, snapshot);
          final restored = await restoreScratchSnapshot(transfer.text, root);
          expect(await Directory('${restored.path}/notes').list().length, 200);
          // ignore: avoid_print
          print(
            'P2P_MEASUREMENT ${Platform.operatingSystem} '
            '${transfer.bytes} bytes ${transfer.elapsedMs} ms',
          );
          socket.writeln('received');
        }

        if (Platform.isAndroid) {
          await receive();
          await send();
        } else {
          await send();
          await receive();
        }
      } finally {
        socket.destroy();
        await root.delete(recursive: true);
      }
    });
  }, timeout: const Timeout(Duration(minutes: 10)));
}
