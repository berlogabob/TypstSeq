import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/vault_storage.dart';

void main() {
  test('uses USERPROFILE when HOME is unavailable', () {
    expect(userHome({'USERPROFILE': r'C:\Users\tylog'}), r'C:\Users\tylog');
  });

  test('prefers HOME when both variables are available', () {
    expect(
      userHome({'HOME': '/Users/tylog', 'USERPROFILE': r'C:\Users\other'}),
      '/Users/tylog',
    );
  });
}
