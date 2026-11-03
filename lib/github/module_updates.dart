import 'package:pub_semver/pub_semver.dart';
import 'package:tylog_core/tylog_core.dart';

import '../module_pack_io.dart';
import 'github_client.dart';

Version _moduleVersion(String value) {
  var text = value.startsWith('v') ? value.substring(1) : value;
  if (RegExp(r'^\d+$').hasMatch(text)) text = '$text.0.0';
  return Version.parse(text);
}

int compareModuleVersions(String a, String b) =>
    _moduleVersion(a).compareTo(_moduleVersion(b));

Future<ModulePack?> checkModuleUpdate(
  GitHubClient client,
  InstalledModule module,
) async {
  if (module.github == null) return null;
  final release = await client.latestRelease(module.github!);
  if (compareModuleVersions(release.tag, module.version) <= 0) return null;
  final assets = release.assets.where((a) => a.name.endsWith('.tylogpack'));
  if (assets.isEmpty) return null;
  final pack = readModulePackBytes(
    await client.downloadAsset(assets.first.url),
  );
  if (pack.id != module.id ||
      compareModuleVersions(pack.version, module.version) <= 0) {
    return null;
  }
  return pack;
}

Future<ModulePack> downloadGitHubModule(
  GitHubClient client,
  String repo,
) async {
  if (!RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(repo)) {
    throw const FormatException('Enter owner/repo');
  }
  final release = await client.latestRelease(repo);
  final assets = release.assets.where((a) => a.name.endsWith('.tylogpack'));
  if (assets.isEmpty) {
    throw const FormatException('No .tylogpack release asset');
  }
  return readModulePackBytes(await client.downloadAsset(assets.first.url));
}

Future<ModulePack> downloadGitHubModuleUpdate(
  GitHubClient client,
  InstalledModule module,
) async {
  final pack = await downloadGitHubModule(client, module.github!);
  if (pack.id != module.id ||
      compareModuleVersions(pack.version, module.version) <= 0) {
    throw const FormatException(
      'Downloaded module is not a newer version of the installed module',
    );
  }
  return pack;
}
