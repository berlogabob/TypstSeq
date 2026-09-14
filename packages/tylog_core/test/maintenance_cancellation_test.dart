import 'dart:io';

import 'package:test/test.dart';
import 'package:tylog_core/maintenance.dart';
import 'package:tylog_core/storage.dart';
import 'package:tylog_core/scanner.dart';
import 'package:tylog_core/search_index.dart';
import 'package:tylog_core/vault.dart';

class CancellingStorage extends LocalVaultStorage {
  CancellingStorage(super.root, this.onRead, {this.afterWrite});
  final void Function(String path) onRead;
  final void Function(String path)? afterWrite;

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    await super.writeBytes(path, bytes);
    afterWrite?.call(path);
  }

  @override
  Future<List<VaultStorageEntry>> list({String path = '', bool recursive = false}) async {
    final result = await super.list(path: path, recursive: recursive);
    onRead(path);
    return result;
  }

  @override
  Future<String> readText(String path) async {
    final result = await super.readText(path);
    onRead(path);
    return result;
  }
}

void main() {
  test('cancelling after index stops later stages and next run succeeds', () async {
    final root = await Directory.systemTemp.createTemp('tylog_cancel_stage_');
    addTearDown(() => root.delete(recursive: true));
    final storage = LocalVaultStorage(root);
    await storage.writeText('notes/a.typ', '= A\n\nBody\n');
    final maintenance = VaultMaintenance(storage);
    var cancelled = false;
    final events = <VaultMaintenanceEvent>[];
    Object? error;
    await maintenance.run(
      validate: true,
      buildSearch: true,
      sweep: false,
      isCancelled: () => cancelled,
    ).forEach((event) {
      events.add(event);
      if (event is MaintenanceIndexed) cancelled = true;
    }).catchError((Object caught, StackTrace _) {
      error = caught;
    });
    expect(error, isA<IndexBuildCancelled>());
    expect(events.whereType<MaintenanceValidated>(), isEmpty);
    expect(events.whereType<MaintenanceSearchBuilt>(), isEmpty);

    cancelled = false;
    final retry = await maintenance.run(sweep: false).toList();
    expect(retry.whereType<MaintenanceIndexed>(), hasLength(1));
    expect(retry.whereType<MaintenanceSearchBuilt>(), hasLength(1));
  });

  test('cancels during validation without publishing search output', () async {
    final root = await Directory.systemTemp.createTemp('tylog_cancel_mid_');
    addTearDown(() => root.delete(recursive: true));
    var armed = false;
    var cancelled = false;
    final storage = CancellingStorage(root, (_) {
      if (armed) cancelled = true;
    });
    await storage.writeText('notes/a.typ', '= A\n\nBody\n');
    final maintenance = VaultMaintenance(storage);
    final first = <VaultMaintenanceEvent>[];
    Object? error;
    await maintenance.run(isCancelled: () => cancelled, sweep: false).forEach((event) {
      first.add(event);
      if (event is MaintenanceIndexed) armed = true;
    }).catchError((caught) => error = caught);
    expect(error, isA<IndexBuildCancelled>());
    expect(first.whereType<MaintenanceSearchBuilt>(), isEmpty);
    cancelled = false;
    armed = false;
    final retry = await maintenance.run(sweep: false).toList();
    expect(retry.whereType<MaintenanceSearchBuilt>(), hasLength(1));
  });

  test('cancels after the final search read batch', () async {
    final root = await Directory.systemTemp.createTemp('tylog_cancel_search_');
    addTearDown(() => root.delete(recursive: true));
    var armed = false;
    var cancelled = false;
    final storage = CancellingStorage(root, (path) {
      if (armed && path == 'notes/a.typ') cancelled = true;
    });
    await storage.writeText('notes/a.typ', '= A\n\nBody\n');
    final index = await VaultMaintenance(storage).buildIndex();
    armed = true;
    await expectLater(
      PkmsSearchIndex.buildStorage(
        storage,
        index,
        isCancelled: () => cancelled,
      ),
      throwsA(isA<IndexBuildCancelled>()),
    );
    armed = false;
    expect(await PkmsSearchIndex.buildStorage(storage, index), isA<PkmsSearchIndex>());
  });

  test('cancels after search write before publication or sweep', () async {
    final root = await Directory.systemTemp.createTemp('tylog_cancel_write_');
    addTearDown(() => root.delete(recursive: true));
    var cancelled = false;
    final storage = CancellingStorage(
      root,
      (_) {},
      afterWrite: (path) {
        if (path == TylogVaultPaths.searchIndex) cancelled = true;
      },
    );
    await storage.writeText('notes/a.typ', '= A\n\nBody\n');
    final events = <VaultMaintenanceEvent>[];
    Object? error;
    await VaultMaintenance(storage)
        .run(sweep: true, isCancelled: () => cancelled)
        .forEach(events.add)
        .catchError((caught) => error = caught);
    expect(error, isA<IndexBuildCancelled>());
    expect(events.whereType<MaintenanceSearchBuilt>(), isEmpty);
    expect(events.whereType<MaintenanceSwept>(), isEmpty);
  });
}
