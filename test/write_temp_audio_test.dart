import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:tylog/widgets/audio_sheets.dart';

class _MissingCache extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _MissingCache(this.path);
  final String path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

void main() {
  test('writeTempAudio creates a cache dir that was cleared', () async {
    final root = Directory.systemTemp.createTempSync('tylog-cache');
    addTearDown(() => root.deleteSync(recursive: true));
    PathProviderPlatform.instance = _MissingCache(
      '${root.path}/org.tylog.tylog',
    );

    final file = await writeTempAudio(Uint8List.fromList([1, 2, 3]), 'opus');

    expect(file.readAsBytesSync(), [1, 2, 3]);
  });
}
