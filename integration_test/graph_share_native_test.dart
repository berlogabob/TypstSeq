import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('graph SVG reaches the native share handoff', (_) async {
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            Uint8List.fromList(
              '<svg xmlns="http://www.w3.org/2000/svg"><title>TyLog graph</title></svg>'
                  .codeUnits,
            ),
            mimeType: 'image/svg+xml',
            name: 'tylog-graph.svg',
          ),
        ],
        fileNameOverrides: const ['tylog-graph.svg'],
        subject: 'TyLog graph',
      ),
    );
    // Empty raw means the chooser was dismissed; it still proves the native
    // intent was launched. `unavailable` means no platform share support.
    expect(result.status, isNot(ShareResultStatus.unavailable));
  });
}
