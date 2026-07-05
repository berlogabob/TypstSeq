import 'package:yaml/yaml.dart';

class HayagrivaEntry {
  const HayagrivaEntry({
    required this.key,
    required this.type,
    required this.title,
  });

  final String key;
  final String type;
  final String title;
}

List<HayagrivaEntry> parseHayagrivaBibliography(String source) {
  final document = loadYaml(source);
  if (document == null) return const [];
  if (document is! YamlMap) {
    throw const FormatException('Hayagriva bibliography must be a YAML map.');
  }
  final entries = <HayagrivaEntry>[];
  for (final item in document.entries) {
    final key = item.key.toString();
    final value = item.value;
    if (value is! YamlMap) {
      throw FormatException('Bibliography entry $key must be a YAML map.');
    }
    final type = value['type']?.toString().trim() ?? '';
    final title = value['title']?.toString().trim() ?? '';
    if (type.isEmpty || title.isEmpty) {
      throw FormatException('Bibliography entry $key requires type and title.');
    }
    entries.add(HayagrivaEntry(key: key, type: type, title: title));
  }
  entries.sort((a, b) => a.key.compareTo(b.key));
  return entries;
}
