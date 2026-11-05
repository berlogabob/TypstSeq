import 'rust/api/p2p_harness.dart' as api;
import 'rust/frb_generated.dart';

export 'rust/api/p2p_harness.dart' show ScratchTransfer;

Future<void> initP2pHarness() async {
  try {
    await RustLib.init();
  } on StateError catch (error) {
    if (!error.message.contains('twice')) rethrow;
  }
}

Future<String> startP2pScratch(String text) => api.startScratch(text: text);
Future<api.ScratchTransfer> receiveP2pScratch(String ticket) =>
    api.receiveScratch(ticket: ticket);
