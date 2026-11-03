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
    final items = {
      for (final row in _cache['items'] ?? const []) '${row['id']}': row,
    };
    final assetPlaces = <String, List<String>>{};
    for (final row in _cache['asset_place'] ?? const []) {
      final place = ids['${row['place_id']}'];
      if (place != null) {
        assetPlaces.putIfAbsent('${row['asset_id']}', () => []).add(place);
      }
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
            'stock': [
              for (final stock in _cache['stock'] ?? const [])
                if ('${stock['place_id']}' == '${row['id']}')
                  {
                    'name': items['${stock['item_id']}']?['name'] ?? '',
                    'qty': stock['qty'],
                    'unit': items['${stock['item_id']}']?['unit'],
                  },
            ],
          },
        ),
      for (final row in _cache['assets'] ?? const [])
        if (row['tag'] != null && '${row['tag']}'.isNotEmpty)
          ExternalEntity(
            id: 'olt:asset:${row['tag']}',
            kind: 'asset',
            title: '${row['tag']}',
            aliases: [
              if (row['serial'] != null) '${row['serial']}',
              if (items['${row['item_id']}']?['name'] != null)
                '${items['${row['item_id']}']['name']}',
            ],
            partOf: assetPlaces['${row['id']}'] ?? const [],
            properties: {
              'source': 'openlabtwin',
              'item': items['${row['item_id']}']?['name'],
              'condition': row['condition'],
              'seen': row['seen_at'],
              'serial': row['serial'],
            },
          ),
    ];
  }

  @override
  List<NoteRef> incoming(String day) => oltIncomingOnDay(_cache, decided, day);
}
