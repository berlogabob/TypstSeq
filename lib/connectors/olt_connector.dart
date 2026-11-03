import '../models.dart';
import '../olt/olt_cache.dart';
import 'connector.dart';

/// Adapts the existing device-local OLT cache; its owner controls sync cadence.
class OltConnector implements Connector {
  OltConnector(this.loadCache, {this.decided = const {}});

  final Future<Map<String, List>> Function() loadCache;
  final Set<String> decided;
  Map<String, List> _cache = const {};

  @override
  String get id => 'olt';

  @override
  Future<void> refresh() async => _cache = await loadCache();

  @override
  List<ExternalEntity> entities() {
    final places = _cache['places'] ?? const [];
    final ids = <String, String>{};
    for (final row in places) {
      final code = row['code']?.toString().trim();
      ids['${row['id']}'] =
          'olt:place:${code == null || code.isEmpty ? row['id'] : code}';
    }
    return [
      for (final row in places)
        ExternalEntity(
          id: ids['${row['id']}']!,
          kind: 'place',
          title: '${row['name'] ?? ''}',
          aliases: [
            if (row['code'] != null && '${row['code']}'.trim().isNotEmpty)
              '${row['code']}',
          ],
          partOf: [
            if (ids['${row['parent_id']}'] case final String parent) parent,
          ],
          properties: {
            'source': 'openlabtwin',
            if (row['kind'] != null) 'kind': row['kind'],
            if (row['tier'] != null) 'tier': row['tier'],
          },
        ),
    ];
  }

  @override
  List<NoteRef> incoming(String day) => oltIncomingOnDay(_cache, decided, day);
}
