import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/app_mobile.dart';

void main() {
  test(
    'only phones stop the poll in the background; a closed Mac window keeps publishing',
    () {
      expect(stopsPollingInBackground(TargetPlatform.android), isTrue);
      expect(stopsPollingInBackground(TargetPlatform.iOS), isTrue);
      expect(stopsPollingInBackground(TargetPlatform.macOS), isFalse);
      expect(stopsPollingInBackground(TargetPlatform.windows), isFalse);
      expect(stopsPollingInBackground(TargetPlatform.linux), isFalse);
    },
  );
}
