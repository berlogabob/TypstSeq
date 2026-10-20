import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _storage = FlutterSecureStorage();

Future<String?> readApiKey(String connectionId) =>
    _storage.read(key: 'ai-key:$connectionId');

Future<void> writeApiKey(String connectionId, String? key) async {
  final value = key?.trim();
  if (value == null || value.isEmpty) {
    await _storage.delete(key: 'ai-key:$connectionId');
  } else {
    await _storage.write(key: 'ai-key:$connectionId', value: value);
  }
}
