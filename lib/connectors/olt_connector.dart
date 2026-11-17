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
  List<ExternalEntity> entities() => const [];

  @override
  List<NoteRef> incoming(String day) => oltIncomingOnDay(_cache, decided, day);
}
