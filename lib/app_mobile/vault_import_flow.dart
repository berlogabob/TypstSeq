part of '../app_mobile.dart';

const _vaultImportAssetLimit = 50 * 1024 * 1024;

enum ImportSourceDecision { importNew, skipUnchanged, importChangedCopy }

ImportSourceDecision decideImportAction({
  required String sourceName,
  required String sha,
  required Map<String, Set<String>> imported,
}) {
  final hashes = imported[sourceName];
  if (hashes == null) return ImportSourceDecision.importNew;
  return hashes.contains(sha)
      ? ImportSourceDecision.skipUnchanged
      : ImportSourceDecision.importChangedCopy;
}

String assignImportOutputPath(
  String relPath,
  Set<String> used,
  bool Function(String) exists,
) {
  var candidate = relPath;
  var suffix = 2;
  while (used.contains(candidate) || exists(candidate)) {
    final stem = relPath.endsWith('.typ')
        ? relPath.substring(0, relPath.length - 4)
        : relPath;
    candidate = '$stem (${suffix++})${relPath.endsWith('.typ') ? '.typ' : ''}';
  }
  used.add(candidate);
  return candidate;
}

String importedNoteBody(String typst) {
  final heading = RegExp(r'(^|\n)= [^\r\n]*(?:\r?\n|$)').firstMatch(typst);
  if (heading == null) return typst;
  return typst.substring(heading.end).replaceFirst(RegExp(r'^(?:\r?\n)+'), '');
}

String detectVaultDialect({
  required bool hasObsidianDir,
  required bool hasLogseqDir,
  required bool hasJournalsDir,
}) {
  final logseq = hasLogseqDir || hasJournalsDir;
  if (hasObsidianDir == logseq) return '';
  return hasObsidianDir ? 'obsidian' : 'logseq';
}

String legacyImportJobId(String dialect, String fingerprint) =>
    'legacy-${sha256.convert(utf8.encode('$dialect\n$fingerprint')).toString().substring(0, 32)}';

String legacyImportNodeId(String jobId, String path, String sha) =>
    _legacyImportId('node', jobId, path, sha);

String legacyImportRevisionId(String jobId, String path, String sha) =>
    _legacyImportId('revision', jobId, path, sha);

({String content, bool appended}) materializeLegacyImportNote({
  required String typst,
  required String? current,
  required String sourceHash,
  required String dialect,
}) {
  final alreadyAppended = current?.contains(sourceHash) ?? false;
  if (alreadyAppended) return (content: current!, appended: false);
  if (current == null) return (content: typst, appended: false);
  return (
    content:
        '$current\n== From ${dialect == 'logseq' ? 'Logseq' : 'Obsidian'}\n\n'
        '${importedNoteBody(typst)}',
    appended: true,
  );
}

int completedImportUnchangedCount({
  required Iterable<String> sourcePaths,
  required Map<String, String?> sourceHashes,
  required Map<String, Set<String>> imported,
}) => sourcePaths.where((path) {
  final hash = sourceHashes[path];
  if (hash == null) return false;
  return decideImportAction(
        sourceName: path.split('/').last,
        sha: hash,
        imported: imported,
      ) ==
      ImportSourceDecision.skipUnchanged;
}).length;

Set<String> legacyImportedAssetPaths(Iterable<String> attributesJson) {
  final assets = <String>{};
  for (final raw in attributesJson) {
    final value = jsonDecode(raw);
    if (value is! Map) continue;
    final paths = value['referenced_assets'];
    if (paths is Iterable) assets.addAll(paths.whereType<String>());
  }
  return assets;
}

({int pages, int journals, int appended, int changedCopies})
legacyImportedCounts(Iterable<String> attributesJson) {
  var pages = 0;
  var journals = 0;
  var appended = 0;
  var changedCopies = 0;
  for (final raw in attributesJson) {
    final value = jsonDecode(raw);
    if (value is! Map) continue;
    if (value['import_is_journal'] == true) {
      journals++;
    } else {
      pages++;
    }
    if (value['import_appended'] == true) appended++;
    if (value['import_changed_copy'] == true) changedCopies++;
  }
  return (
    pages: pages,
    journals: journals,
    appended: appended,
    changedCopies: changedCopies,
  );
}

String vaultImportReportTitle(bool complete) =>
    complete ? 'Vault import complete' : 'Vault import paused';

class _VaultImportReport {
  int pages = 0;
  int journals = 0;
  int appended = 0;
  int skippedEmpty = 0;
  int unchanged = 0;
  int changedCopies = 0;
  int assetsCopied = 0;
  int assetsSkipped = 0;
  int assetsMissing = 0;
  int unresolvedWikilinks = 0;
  final details = <String>[];

  int get notes => pages + journals;
}

String _legacyImportId(String kind, String jobId, String path, String sha) =>
    '$kind-${sha256.convert(utf8.encode('$jobId\n$path\n$sha')).toString().substring(0, 32)}';

extension _VaultImportFlow on _HomeScreenState {
  Future<void> _importVault() async {
    if (dirty && !await _save(syncAfter: false)) return;
    final opened = vault;
    if (!mounted || opened == null) return;

    final source = await _pickVaultImportSource();
    if (source == null || !mounted || vault != opened) return;

    var dialect = detectVaultDialect(
      hasObsidianDir: await source.exists('.obsidian'),
      hasLogseqDir: await source.exists('logseq'),
      hasJournalsDir: await source.exists('journals'),
    );
    if (dialect.isEmpty) {
      dialect = await _chooseVaultDialect() ?? '';
    }
    if (dialect.isEmpty || !mounted || vault != opened) return;

    final sources = await _vaultImportSources(source, dialect);
    final importDialect = dialect == 'logseq'
        ? LegacyImportDialect.logseq
        : LegacyImportDialect.obsidian;
    final manifest = await buildLegacyImportManifest(source, importDialect);
    final activeEntry = _activeRegistryEntry;
    if (activeEntry == null) return;
    final db = await _databaseForVault(activeEntry);
    if (db == null) return;
    final jobId = legacyImportJobId(dialect, manifest.fingerprint);
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.createOrResumeImportJob(
      ImportJobData(
        id: jobId,
        sourceKind: dialect,
        sourceFingerprint: manifest.fingerprint,
        status: 'running',
        totalCount: manifest.entries.length,
        completedCount: 0,
        createdAtMs: now,
        updatedAtMs: now,
        errorJson: '{}',
      ),
      [
        for (final entry in manifest.entries)
          ImportItemData(
            jobId: jobId,
            sourcePath: entry.path,
            sourceSha256: null,
            state: 'pending',
            targetNodeId: null,
            targetPath: null,
            errorJson: '{}',
            updatedAtMs: now,
          ),
      ],
    );
    final storedItems = await (db.select(
      db.importItems,
    )..where((item) => item.jobId.equals(jobId))).get();
    final checkpointedPaths = <String, String>{
      for (final item in storedItems)
        if (item.targetPath != null) item.sourcePath: item.targetPath!,
    };
    final existingPaths = {
      for (final entry in await opened.storage.list(recursive: true))
        if (!entry.isDirectory) entry.path.replaceAll('\\', '/'),
    };
    final imported = <String, Set<String>>{};
    for (final note in index?.notes ?? const <NoteRef>[]) {
      final sourceName = note.properties['import_source_name'];
      if (sourceName is! String) continue;
      final hashes = imported.putIfAbsent(sourceName, () => <String>{});
      final sourceHash = note.properties['import_sha256'];
      if (sourceHash is String) hashes.add(sourceHash);
    }
    if (!mounted || vault != opened) return;

    final progress = ValueNotifier<String>('Converting 0 of ${sources.length}');
    var cancelled = false;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Importing vault'),
          content: ValueListenableBuilder<String>(
            valueListenable: progress,
            builder: (context, message, _) => SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LinearProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(message),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: cancelled
                  ? null
                  : () {
                      cancelled = true;
                      progress.value = 'Cancelling…';
                    },
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final report = _VaultImportReport();
    final used = <String>{};
    final assets = <String>{};
    final wikilinks = <String>{};
    final resolvedLinks = <String>{};
    final writtenPaths = <String>{};
    var convertedNotes = 0;
    final metadata =
        <
          String,
          ({bool appendExisting, String sourceName, String sourceHash})
        >{};
    final runner = LegacyImportRunner(
      database: db,
      storage: source,
      manifest: manifest,
      shouldCancel: () => cancelled,
      converter: (entry, markdown, sourceHash) async {
        if (entry.kind == LegacyImportEntryKind.asset ||
            entry.kind == LegacyImportEntryKind.unsupported) {
          return null;
        }
        final name = entry.path.split('/').last;
        progress.value =
            'Converting ${++convertedNotes} of ${sources.length}\n$name';
        final decision = decideImportAction(
          sourceName: name,
          sha: sourceHash,
          imported: imported,
        );
        if (decision == ImportSourceDecision.skipUnchanged) {
          report.unchanged++;
          return null;
        }
        final result = await convertVaultNote(
          dialect: dialect,
          sourceRelPath: entry.path,
          markdown: markdown,
        );
        if (result == null) {
          return null;
        }
        final typst = migrateEntityTypeToKind(
          replaceNoteProperty(result.typst, 'import_sha256', sourceHash),
        );
        final isJournal =
            entry.kind == LegacyImportEntryKind.journal ||
            result.kind == 'daily';
        final path =
            checkpointedPaths[entry.path] ??
            (isJournal &&
                    existingPaths.contains(result.relPath) &&
                    !used.contains(result.relPath)
                ? result.relPath
                : assignImportOutputPath(
                    result.relPath,
                    used,
                    existingPaths.contains,
                  ));
        used.add(path);
        final current = isJournal && existingPaths.contains(path)
            ? await opened.storage.readText(path)
            : null;
        final materialized = materializeLegacyImportNote(
          typst: typst,
          current: current,
          sourceHash: sourceHash,
          dialect: dialect,
        );
        final content = materialized.content;
        metadata[entry.path] = (
          appendExisting: isJournal && current != null,
          sourceName: name,
          sourceHash: sourceHash,
        );
        final nodeId = legacyImportNodeId(jobId, entry.path, sourceHash);
        final revisionId = legacyImportRevisionId(
          jobId,
          entry.path,
          sourceHash,
        );
        return (
          node: NodeData(
            id: nodeId,
            type: result.kind,
            title: result.title,
            content: content,
            attributesJson: jsonEncode({
              'import_source_path': entry.path,
              'import_source_name': name,
              'import_sha256': sourceHash,
              'import_is_journal': isJournal,
              'import_appended': materialized.appended,
              'import_changed_copy':
                  decision == ImportSourceDecision.importChangedCopy,
              'referenced_assets': result.referencedAssets,
              'wikilink_targets': result.wikilinkTargets,
              'resolved_links': [result.title, ...result.aliases, ?result.date],
              'diagnostics': result.diagnostics,
            }),
            createdAtMs: now,
            updatedAtMs: now,
          ),
          revision: RevisionData(
            id: revisionId,
            entityKind: 'node',
            entityId: nodeId,
            payloadJson: jsonEncode({
              'source': entry.path,
              'sha256': sourceHash,
            }),
            createdAtMs: now,
          ),
          targetPath: path,
        );
      },
      materializer: (item, node, targetPath) async {
        final info = metadata[item.sourcePath];
        if (info?.appendExisting ?? false) {
          if (!await workspace.mutateNote(targetPath, (_) => node.content)) {
            throw StateError('vault materialization failed');
          }
        } else {
          await opened.saveNote(targetPath, node.content);
        }
        if (info != null) {
          imported
              .putIfAbsent(info.sourceName, () => <String>{})
              .add(info.sourceHash);
        }
        writtenPaths.add(targetPath);
      },
    );
    var interrupted = false;
    try {
      var more = true;
      while (more && !cancelled) {
        more = await runner.runBatch(jobId);
      }
    } catch (_) {
      interrupted = true;
      report.details.add(
        'Import interrupted; pending items can resume. See the import job for details.',
      );
    }
    if (cancelled) {
      report.details.add('Import cancelled; pending items can resume.');
    }
    final finalItems = (await db.select(db.importItems).get())
        .where((item) => item.jobId == jobId)
        .toList();
    final notePaths = manifest.entries
        .where(
          (entry) =>
              entry.kind == LegacyImportEntryKind.page ||
              entry.kind == LegacyImportEntryKind.journal,
        )
        .map((entry) => entry.path)
        .toSet();
    final skippedNotes = finalItems.where(
      (item) => item.state == 'skipped' && notePaths.contains(item.sourcePath),
    );
    report.unchanged = completedImportUnchangedCount(
      sourcePaths: skippedNotes.map((item) => item.sourcePath),
      sourceHashes: {
        for (final item in finalItems) item.sourcePath: item.sourceSha256,
      },
      imported: imported,
    );
    report.skippedEmpty = skippedNotes.length - report.unchanged;
    for (final item in finalItems.where((item) => item.state == 'failed')) {
      report.details.add('${item.sourcePath}: legacy import failed');
    }
    final complete = finalItems.every(
      (item) => item.state != 'pending' && item.state != 'failed',
    );
    final writtenItemIds = finalItems
        .where((item) => item.state == 'written' && item.targetNodeId != null)
        .map((item) => item.targetNodeId!)
        .toSet();
    final importedNodes = (await db.select(db.nodes).get()).where(
      (node) => writtenItemIds.contains(node.id),
    );
    assets.addAll(
      legacyImportedAssetPaths(
        importedNodes.map((node) => node.attributesJson),
      ),
    );
    final importedCounts = legacyImportedCounts(
      importedNodes.map((node) => node.attributesJson),
    );
    report
      ..pages = importedCounts.pages
      ..journals = importedCounts.journals
      ..appended = importedCounts.appended
      ..changedCopies = importedCounts.changedCopies;
    for (final node in importedNodes) {
      final attributes =
          jsonDecode(node.attributesJson) as Map<String, dynamic>;
      wikilinks.addAll(
        (attributes['wikilink_targets'] as Iterable? ?? const [])
            .whereType<String>(),
      );
      resolvedLinks.addAll(
        (attributes['resolved_links'] as Iterable? ?? const [])
            .whereType<String>()
            .map((value) => value.toLowerCase()),
      );
      report.details.addAll(
        (attributes['diagnostics'] as Iterable? ?? const [])
            .whereType<String>()
            .map((value) => '${attributes['import_source_path']}: $value'),
      );
    }

    if (!interrupted && !cancelled) {
      progress.value = 'Copying ${assets.length} referenced assets';
      await _copyVaultImportAssets(
        source: source,
        target: opened.storage,
        dialect: dialect,
        assets: assets,
        report: report,
      );
    }

    for (final path in {...existingPaths, ...writtenPaths}) {
      if (!path.toLowerCase().endsWith('.typ')) continue;
      resolvedLinks.add(
        path
            .split('/')
            .last
            .substring(0, path.split('/').last.length - 4)
            .toLowerCase(),
      );
    }
    final unresolved = <String, String>{};
    for (final target in wikilinks) {
      unresolved.putIfAbsent(target.toLowerCase(), () => target);
    }
    unresolved.removeWhere((key, _) => resolvedLinks.contains(key));
    report.unresolvedWikilinks = unresolved.length;
    report.details.addAll(
      unresolved.values.map((target) => 'Unresolved wikilink: $target'),
    );

    if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    progress.dispose();
    if (!mounted || vault != opened) return;

    await workspace.refreshIndex(updateStatus: false, always: true);
    if (!mounted || vault != opened) return;
    _queueCloudSync();
    _rebuild(
      () => status = complete
          ? 'Vault import: ${report.notes} notes'
          : 'Vault import paused: ${report.notes} notes',
    );
    await _showVaultImportReport(report, complete: complete);
  }

  Future<VaultStorage?> _pickVaultImportSource() async {
    if (!Platform.isAndroid) {
      final path = await FilePicker.getDirectoryPath(
        dialogTitle: 'Choose Logseq or Obsidian vault',
      );
      return path == null ? null : LocalVaultStorage(Directory(path));
    }

    final allowed = await showConfirmDialog(
      context,
      title: 'Allow source vault access',
      message:
          'TyLog needs access to one folder to read and convert your notes. '
          'Android will open its folder picker. Choose your Logseq or Obsidian '
          'vault, then tap “Use this folder”. TyLog cannot access other folders.',
      confirmLabel: 'Choose folder',
      barrierDismissible: false,
    );
    if (!allowed || !mounted) return null;
    final selection = await AndroidTreeVaultStorage.pick();
    return selection == null
        ? null
        : AndroidTreeVaultStorage(uri: selection.uri, name: selection.name);
  }

  Future<String?> _chooseVaultDialect() => showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('What kind of vault is this?'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, 'logseq'),
          child: const Text('Logseq'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, 'obsidian'),
          child: const Text('Obsidian'),
        ),
      ],
    ),
  );

  Future<List<({String path, bool journal})>> _vaultImportSources(
    VaultStorage storage,
    String dialect,
  ) async {
    final files = <({String path, bool journal})>[];
    if (dialect == 'logseq') {
      for (final directory in const ['pages', 'journals']) {
        for (final entry in await storage.list(path: directory)) {
          final path = entry.path.replaceAll('\\', '/');
          if (!entry.isDirectory && path.toLowerCase().endsWith('.md')) {
            files.add((path: path, journal: directory == 'journals'));
          }
        }
      }
    } else {
      for (final entry in await storage.list(recursive: true)) {
        final path = entry.path.replaceAll('\\', '/');
        if (!entry.isDirectory &&
            path.toLowerCase().endsWith('.md') &&
            !path.split('/').any((part) => part.startsWith('.'))) {
          files.add((path: path, journal: false));
        }
      }
    }
    files.sort((left, right) => left.path.compareTo(right.path));
    return files;
  }

  Future<void> _copyVaultImportAssets({
    required VaultStorage source,
    required VaultStorage target,
    required String dialect,
    required Set<String> assets,
    required _VaultImportReport report,
  }) async {
    for (final asset in assets.toList()..sort()) {
      final sourcePath = asset.replaceAll('\\', '/');
      final destination = dialect == 'logseq'
          ? sourcePath.startsWith('assets/')
                ? 'assets/logseq/${sourcePath.substring(7)}'
                : ''
          : 'assets/obsidian/${sourcePath.split('/').last}';
      try {
        if (destination.isEmpty) {
          throw const FormatException('invalid asset path');
        }
        validateVaultPath(sourcePath);
        validateVaultPath(destination);
        if (await target.exists(destination)) {
          report.assetsSkipped++;
          continue;
        }
        final info = await source.stat(sourcePath);
        if (info == null || info.isDirectory) {
          report.assetsMissing++;
          report.details.add('$sourcePath: asset not found');
          continue;
        }
        if ((info.size ?? 0) > _vaultImportAssetLimit) {
          report.assetsSkipped++;
          report.details.add('$sourcePath: asset exceeds 50 MB; skipped');
          continue;
        }
        await target.writeBytes(
          destination,
          await source.readBytes(sourcePath),
        );
        report.assetsCopied++;
      } catch (_) {
        report.assetsMissing++;
        report.details.add('$sourcePath: asset copy failed');
      }
    }
  }

  Future<void> _showVaultImportReport(
    _VaultImportReport report, {
    required bool complete,
  }) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(vaultImportReportTitle(complete)),
      content: SizedBox(
        width: 560,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text('Pages converted: ${report.pages}'),
            Text('Journals converted: ${report.journals}'),
            Text('Journals appended: ${report.appended}'),
            Text('Files skipped-empty: ${report.skippedEmpty}'),
            Text('Unchanged (skipped): ${report.unchanged}'),
            Text('Changed (imported as copy): ${report.changedCopies}'),
            Text('Assets copied: ${report.assetsCopied}'),
            Text('Assets skipped: ${report.assetsSkipped}'),
            Text('Assets missing: ${report.assetsMissing}'),
            Text('Unresolved wikilinks: ${report.unresolvedWikilinks}'),
            if (report.details.isNotEmpty) ...[
              const Divider(),
              for (final detail in report.details.take(50))
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.info_outline),
                  title: Text(detail),
                ),
            ],
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}
