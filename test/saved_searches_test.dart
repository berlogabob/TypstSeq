import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/saved_searches.dart';
import 'package:tylog/vault_storage.dart';

void main() {
  test('SavedSearch JSON round-trip with all fields', () {
    final search = SavedSearch(
      name: 'My Search',
      query: 'flutter',
      tag: 'dart',
      status: 'todo',
    );
    final json = search.toJson();
    final restored = SavedSearch.fromJson(json);

    expect(restored.name, equals('My Search'));
    expect(restored.query, equals('flutter'));
    expect(restored.tag, equals('dart'));
    expect(restored.status, equals('todo'));
  });

  test('SavedSearch JSON round-trip with null fields', () {
    final search = SavedSearch(
      name: 'Simple',
      query: 'test',
    );
    final json = search.toJson();
    final restored = SavedSearch.fromJson(json);

    expect(restored.name, equals('Simple'));
    expect(restored.query, equals('test'));
    expect(restored.tag, isNull);
    expect(restored.status, isNull);
  });

  test('SavedSearch fromJson defensively handles odd types', () {
    final json = {
      'name': 'Test',
      'query': 'search',
      'tag': 123, // Wrong type
      'status': true, // Wrong type
    };
    final search = SavedSearch.fromJson(json);

    expect(search.name, equals('Test'));
    expect(search.query, equals('search'));
    expect(search.tag, isNull);
    expect(search.status, isNull);
  });

  test('SavedSearchStore load missing file returns empty list', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_saved_searches_');
    addTearDown(() => dir.delete(recursive: true));

    final store = SavedSearchStore(LocalVaultStorage(dir));
    final searches = await store.load();

    expect(searches, isEmpty);
  });

  test('SavedSearchStore save and load round-trip', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_saved_searches_');
    addTearDown(() => dir.delete(recursive: true));

    final searches = [
      SavedSearch(
        name: 'Tagged Notes',
        query: 'flutter',
        tag: 'dart',
      ),
      SavedSearch(
        name: 'Tasks',
        query: '',
        status: 'todo',
      ),
    ];

    final store = SavedSearchStore(LocalVaultStorage(dir));
    await store.save(searches);
    final loaded = await store.load();

    expect(loaded.length, equals(2));
    expect(loaded[0].name, equals('Tagged Notes'));
    expect(loaded[0].query, equals('flutter'));
    expect(loaded[0].tag, equals('dart'));
    expect(loaded[1].name, equals('Tasks'));
    expect(loaded[1].status, equals('todo'));
  });

  test('SavedSearchStore corrupt file returns empty list', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_saved_searches_');
    addTearDown(() => dir.delete(recursive: true));
    await Directory('${dir.path}/_system').create();

    await File('${dir.path}/_system/saved-searches.json')
        .writeAsString('{ invalid json');

    final store = SavedSearchStore(LocalVaultStorage(dir));
    final searches = await store.load();

    expect(searches, isEmpty);
  });
}
