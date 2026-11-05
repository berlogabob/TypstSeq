import 'package:tylog/vault_registry.dart';

Future<void> registerReceivedVault(VaultRegistry registry, String path) async {
  const id = 'p2p6-received';
  final existing = registry.entries.indexWhere((entry) => entry.id == id);
  final entry = VaultEntry(
    id: id,
    name: 'P2P received copy',
    path: path,
    storageKind: 'app-local',
  );
  if (existing < 0) {
    registry.entries.add(entry);
  } else {
    registry.entries[existing] = entry;
  }
  registry.activeId = id;
  registry.onboardingComplete = true;
  await registry.save();
}
