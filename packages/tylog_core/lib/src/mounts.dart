import 'dart:convert';

const mountsSettingsPath = '_system/settings/mounts.json';
const mountPrefix = 'ext/';
final _mountId = RegExp(r'^[a-z0-9][a-z0-9-]{0,40}$');

class MountSource {
  MountSource({
    required this.kind,
    this.path,
    this.repo,
    this.ref,
    this.subdir,
    Map<String, dynamic> extra = const {},
  }) : extra = Map.of(extra);

  final String kind;
  final String? path, repo, ref, subdir;
  final Map<String, dynamic> extra;

  factory MountSource.fromJson(Map<String, dynamic> json) => MountSource(
    kind: json['kind'] as String,
    path: json['path'] as String?,
    repo: json['repo'] as String?,
    ref: json['ref'] as String?,
    subdir: json['subdir'] as String?,
    extra: Map.of(json)
      ..removeWhere(
        (key, _) => {'kind', 'path', 'repo', 'ref', 'subdir'}.contains(key),
      ),
  );

  Map<String, dynamic> toJson() => {
    ...extra,
    'kind': kind,
    if (path != null) 'path': path,
    if (repo != null) 'repo': repo,
    if (ref != null) 'ref': ref,
    if (subdir != null) 'subdir': subdir,
  };
}

class Mount {
  Mount({
    required this.id,
    required this.name,
    required this.source,
    required this.push,
    Map<String, dynamic> extra = const {},
  }) : extra = Map.of(extra) {
    if (!_mountId.hasMatch(id)) throw FormatException('Invalid mount id: $id');
  }

  final String id, name;
  final MountSource source;
  final bool push;
  final Map<String, dynamic> extra;

  factory Mount.fromJson(Map<String, dynamic> json) => Mount(
    id: json['id'] as String,
    name: json['name'] as String,
    source: MountSource.fromJson(json['source'] as Map<String, dynamic>),
    push: json['push'] as bool,
    extra: Map.of(json)
      ..removeWhere((key, _) => {'id', 'name', 'source', 'push'}.contains(key)),
  );

  Map<String, dynamic> toJson() => {
    ...extra,
    'id': id,
    'name': name,
    'source': source.toJson(),
    'push': push,
  };
}

List<Mount> parseMounts(String json) => (jsonDecode(json) as List)
    .map((item) => Mount.fromJson(item as Map<String, dynamic>))
    .toList();
String encodeMounts(List<Mount> mounts) =>
    jsonEncode(mounts.map((mount) => mount.toJson()).toList());
