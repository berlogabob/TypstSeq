part of '../app_mobile.dart';

extension _SettingsFlow on _HomeScreenState {
  /// Leaves Settings entirely (home and any group page) before an action
  /// that opens something else; one pop only closed the top page.
  void _closeSettings(BuildContext context) => Navigator.of(context).popUntil(
    (route) => !(route.settings.name?.startsWith(kSettingsRoute) ?? false),
  );

  Future<List<PkmsSearchResult>> _searchNotes(
    VaultIndex fallbackIndex,
    String query, {
    String? tag,
    String? status,
  }) async {
    final externalResults = <PkmsSearchResult>[
      if (tag == null && status == null)
        for (final item in workspace.externalEntities)
          if (query.trim().isEmpty ||
              [item.title, item.id, ...item.aliases].any(
                (text) =>
                    text.toLowerCase().contains(query.trim().toLowerCase()),
              ))
            PkmsSearchResult(
              id: item.id,
              path: item.id,
              title: item.title,
              kind: item.kind,
              tags: const [],
              score: 0,
            ),
    ];
    final activeEntry = workspace.entry;
    if (activeEntry != null) {
      try {
        final db = await _databaseForVault(activeEntry);
        if (db != null && await db.nodeProjectionComplete()) {
          final ids = await db.searchNodeIds(query);
          final byId = {for (final note in fallbackIndex.notes) note.id: note};
          final pathsById = await db.nodePathsForIds(ids);
          return [
            ...externalResults,
            ...mergeKeywordResults([
              for (var i = 0; i < ids.length; i++)
                if ((byId[ids[i]] ??
                        fallbackIndex.notesByPath[pathsById[ids[i]]])
                    case final NoteRef note)
                  if ((tag == null || note.tags.contains(tag)) &&
                      (status == null || note.properties['status'] == status))
                    PkmsSearchResult(
                      id: note.id,
                      path: note.path,
                      title: note.title,
                      kind: note.kind,
                      tags: note.tags,
                      score: ids.length - i,
                    ),
            ], await workspace.searchNotes(query, tag: tag, status: status)),
          ];
        }
      } catch (_) {
        // The derived index is optional; preserve the existing search path.
      }
    }
    return [
      ...externalResults,
      ...await workspace.searchNotes(query, tag: tag, status: status),
    ];
  }

  void _showSettings() {
    final initialStorageHealth = vault == null ? false : storageHealthy;
    final storageHealth = initialStorageHealth == null
        ? workspace.probeStorage()
        : Future.value(initialStorageHealth);
    final registry = vaultRegistry;
    final activeLocation = vaultEntryLocation(_activeRegistryEntry);
    final openError = status.startsWith('Open failed:');
    final vaultPath = openError
        ? [activeLocation, status].whereType<String>().join('\n')
        : activeLocation ?? status;

    Navigator.of(context)
        .push<void>(
          MaterialPageRoute(
            settings: const RouteSettings(name: kSettingsRoute),
            builder: (context) => FutureBuilder<bool>(
              future: storageHealth,
              initialData: initialStorageHealth,
              builder: (context, snapshot) {
                final healthy = snapshot.data;
                final syncStatusSubtitle = healthy == null
                    ? 'Checking folder access…'
                    : syncStatusTitle(
                        syncStatusKind(
                          vaultOpen: vault != null,
                          storageHealthy: healthy,
                          cloudConfigured: cloud?.isReady ?? false,
                          desktopManaged:
                              _localVaultDirectory != null &&
                              isNextcloudManagedVault(_localVaultDirectory!),
                          syncing: syncing,
                          error: syncError,
                          conflicts: syncConflicts.length,
                          result: lastSync,
                        ),
                        conflicts: syncConflicts.length,
                      );
                return SettingsSheet(
                  workspace: workspace,
                  onOpenPath: (path) => unawaited(_openPath(path)),
                  onOpenProcessing: () => unawaited(_showProcessing()),
                  storage: vault?.storage,
                  calendarSettings: workspace.calendarSettings,
                  onConfigureCalendars: workspace.configureCalendars,
                  vaultPath: vaultPath,
                  cloud: cloud,
                  syncing: syncing,
                  syncStatusSubtitle: syncStatusSubtitle,
                  vaultCount: registry?.entries.length ?? 0,
                  readAi: vault == null
                      ? null
                      : () => readAiSettings(vault!.storage),
                  writeAi: vault == null
                      ? null
                      : (settings) async {
                          await writeAiSettings(vault!.storage, settings);
                          unawaited(_syncNow());
                        },
                  readWorkers: vault == null
                      ? null
                      : () => readWorkers(vault!.storage),
                  audioPolicyRead: vault == null
                      ? null
                      : () => readAudioPolicy(vault!.storage),
                  audioPolicyWrite: vault == null
                      ? null
                      : (policy) async {
                          await writeAudioPolicy(vault!.storage, policy);
                          unawaited(_syncNow());
                        },
                  onProcessAudio: vault == null
                      ? null
                      : () async {
                          final currentVault = vault!;
                          await requestProcessNow(currentVault.storage);
                          _processingJobWritten(currentVault, processNowPath);
                          unawaited(_syncNow());
                        },
                  screenshotsMode: registry?.screenshotsMode ?? 'off',
                  screenshotsTime: registry?.screenshotsTime ?? '03:00',
                  readScreenshotsStatus: () async => vault!.storage.readText(
                    '_system/screenshots/status.json',
                  ),
                  onConfigureScreenshots: (mode, time) async {
                    // The wanted mode syncs in ai.json, so any device can set it;
                    // the Mac applies it to its LaunchAgents.
                    final storage = vault!.storage;
                    final ai = await readAiSettings(storage);
                    await writeAiSettings(
                      storage,
                      ai.copyWith(
                        screenshots: ai.screenshots.copyWith(
                          mode: mode,
                          time: time,
                        ),
                      ),
                    );
                    if (Platform.isMacOS) {
                      await configureScreenshotsOcr(
                        vaultPath,
                        mode,
                        time,
                        scriptsDir: registry?.screenshotsFolder,
                      );
                      await registry?.setScreenshotsOcr(mode, time);
                    } else {
                      unawaited(_syncNow());
                    }
                  },
                  readScreenshotsWanted: () async {
                    final task = (await readAiSettings(
                      vault!.storage,
                    )).screenshots;
                    final mode = task.mode;
                    return mode == null ? null : (mode, task.time ?? '03:00');
                  },
                  screenshotsFolder: Platform.isMacOS
                      ? registry?.screenshotsFolder
                      : null,
                  onScreenshotsFolderChanged: !Platform.isMacOS
                      ? null
                      : (folder) async {
                          await registry?.setScreenshotsFolder(folder);
                          // Reinstall the agents so they run from the new folder.
                          await configureScreenshotsOcr(
                            vaultPath,
                            registry?.screenshotsMode ?? 'off',
                            registry?.screenshotsTime ?? '03:00',
                            scriptsDir: folder,
                          );
                          if (mounted) _rebuild(() {});
                        },
                  onProcessScreenshots: () async {
                    if (Platform.isMacOS) {
                      await runScreenshotsBackfill(
                        vaultPath,
                        scriptsDir: registry?.screenshotsFolder,
                      );
                    } else {
                      await requestScreenshotsRun(vault!.storage);
                      unawaited(_syncNow());
                    }
                  },
                  pdfPaper: registry?.pdfPaper ?? 'a4',
                  onPdfPaperChanged: (paper) {
                    unawaited(registry?.setPdfPaper(paper) ?? Future.value());
                  },
                  themeMode: widget.themeMode,
                  onThemeModeChanged: (mode) {
                    widget.onThemeModeChanged?.call(mode);
                    unawaited(
                      registry?.setThemeMode(themeModeName(mode)) ??
                          Future.value(),
                    );
                  },
                  onManageVaults: () => Navigator.pop(context, true),
                  onNextcloud: () {
                    _closeSettings(context);
                    unawaited(_showSyncDashboard());
                  },
                  onEnableReminders: () async {
                    await taskScheduler.requestPermission();
                    await taskScheduler.reconcile(index?.tasks ?? const []);
                    if (context.mounted) {
                      showSnack(context, 'Task reminders enabled');
                    }
                  },
                  onMigrateEntityTypes: () async {
                    _closeSettings(context);
                    await _migrateEntityTypes();
                  },
                  onMigrateNamespaces: () async {
                    _closeSettings(context);
                    await _migrateNamespaces();
                  },
                  onStripImportNoise: () async {
                    _closeSettings(context);
                    await _stripImportNoise();
                  },
                  onImportVault: () async {
                    _closeSettings(context);
                    await _importVault();
                  },
                  onUpdateModule: (module) async {
                    _closeSettings(context);
                    await _updateModule(module);
                  },
                  onInstallModule: () async {
                    _closeSettings(context);
                    await _showModules();
                  },
                  onProblems: () {
                    _closeSettings(context);
                    unawaited(
                      _showKnowledge(initialView: KnowledgeView.problems),
                    );
                  },
                  onRebuildIndex: () {
                    _closeSettings(context);
                    unawaited(_rebuildIndex(force: true));
                  },
                  onRelinkVault: () {
                    _closeSettings(context);
                    unawaited(_relinkVault());
                  },
                  onSemanticSearch: () {
                    _closeSettings(context);
                    unawaited(_showSemanticSearch());
                  },
                  onTypstHelp: () {
                    _closeSettings(context);
                    unawaited(_showTypstHelp());
                  },
                  onCheckForUpdates:
                      Platform.isMacOS || updater.windowsSelfUpdatable()
                      ? () {
                          _closeSettings(context);
                          unawaited(_checkForUpdates(silent: false));
                        }
                      : null,
                );
              },
            ),
          ),
        )
        .then((_) {
          if (mounted) _rebuild(() {});
        });
  }

  Future<void> _showTypstHelp({String? error}) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(error == null ? 'Typst help' : 'Explain Typst error'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (error != null) ...[
                  SelectableText(error),
                  if (deterministicTypstFix(error, _currentSource())
                      case final fix?)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: kSpace8),
                      child: Text(fix),
                    ),
                ],
                Wrap(
                  spacing: kSpace8,
                  children: [
                    for (final entry in const {
                      'Heading': '= Heading',
                      'Note link': '#tylog.ref-note("note-id")[Title]',
                      'Tag': '#tylog.tag("topic")',
                      'Date': '#tylog.date-ref("2026-07-05")[5 July]',
                      'Task': 'Task',
                    }.entries)
                      ActionChip(
                        label: Text(entry.key),
                        onPressed: () async {
                          final opened = vault;
                          if (opened == null) return;
                          final snippet = entry.key == 'Task'
                              ? taskSnippet(
                                  id: await opened.nextTaskId(
                                    'Task',
                                    reserved: _reservedTaskIds,
                                  ),
                                  text: 'Task',
                                )
                              : entry.value;
                          if (!context.mounted || !identical(vault, opened)) {
                            return;
                          }
                          if (entry.key == 'Task') {
                            _reservedTaskIds.add(taskField(snippet, 'id')!);
                          }
                          Navigator.pop(context);
                          _insertTypstSnippet(snippet);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _openAttachment(String path) async {
    final v = vault;
    if (v == null || !isSafeVaultPath(path)) return;
    try {
      await _attachTasks[path];
      if (path.toLowerCase().endsWith('.pdf')) {
        final entry = workspace.entry;
        final bytes = await v.storage.readBytes(path);
        final db = entry == null ? null : await _databaseForVault(entry);
        if (!mounted || vault != v) return;
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) =>
                PdfReaderScreen(bytes: bytes, path: path, database: db),
          ),
        );
      } else if (isAudioPath(path)) {
        await _openAudioAsset(path);
      } else {
        await openPlatformFile(
          v.storage,
          path,
          localRoot: _localVaultDirectory,
        );
      }
    } catch (error) {
      if (mounted) showSnack(context, 'Could not open file: $error');
    }
  }

  Future<void> _openCitation(ChunkCitation citation) async {
    final v = vault;
    if (citation.sourceKind == 'note') {
      return;
    }
    if (v == null ||
        citation.sourceKind != 'pdf' ||
        !isSafeVaultPath(citation.sourceLocator) ||
        !citation.sourceLocator.toLowerCase().endsWith('.pdf')) {
      return;
    }
    try {
      final bytes = await v.storage.readBytes(citation.sourceLocator);
      final entry = workspace.entry;
      final db = entry == null ? null : await _databaseForVault(entry);
      if (!mounted || vault != v || db == null) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => PdfReaderScreen(
            bytes: bytes,
            path: citation.sourceLocator,
            database: db,
            initialSourceVersionId: citation.sourceVersionId,
            initialStartOffset: citation.startOffset,
            initialEndOffset: citation.endOffset,
          ),
        ),
      );
    } catch (error) {
      if (mounted) showSnack(context, 'Could not open citation: $error');
    }
  }

  Future<String?> _resolveCitationPath(
    ChunkCitation citation,
    VaultIndex ix,
  ) async {
    final entry = workspace.entry;
    final db = entry == null ? null : await _databaseForVault(entry);
    final pathsById = db == null
        ? const <String, String>{}
        : await db.nodePathsForIds([citation.sourceId]);
    final locatorsById = db == null
        ? const <String, String>{}
        : await db.sourceLocatorsForIds([citation.sourceId]);
    return resolveCitationPath(
      sourceId: citation.sourceId,
      sourceLocator: citation.sourceLocator,
      sourceTitle: citation.sourceTitle,
      pathsById: pathsById,
      locatorsById: locatorsById,
      titlesByPath: {for (final note in ix.notes) note.path: note.title},
    );
  }

  Future<void> _openSearchNote(
    String path,
    int previousDestination, {
    required String query,
    required int offset,
  }) async {
    final selection = ++_destinationGeneration;
    Navigator.of(context).pop();
    _rebuild(() => primaryDestination = previousDestination);
    await workspace.materializeEvent(path);
    if (!mounted || selection != _destinationGeneration) return;
    if (await _openNote(
          path,
          rememberView: false,
          searchQuery: query,
          searchOffset: offset,
        ) &&
        mounted) {
      _rememberView(knowledge: KnowledgeView.search);
      _rebuild(() {});
    }
  }
}
