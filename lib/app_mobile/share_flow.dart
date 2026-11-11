part of '../app_mobile.dart';

extension _ShareFlow on _HomeScreenState {
  /// Compiles the open note to PDF and hands it to the platform share sheet.
  ///
  /// Shares bytes rather than a path on purpose: on Android the vault lives
  /// behind SAF, so the note has no filesystem path to give anyone, and the
  /// exported PDF should not have to be written into the vault just to leave the
  /// app — reports already do that and land in `outputs/`, where a SAF user
  /// cannot easily reach them.
  ///
  /// Compiles the *preview* source and file map, so what gets shared is exactly
  /// what Preview renders, bibliography and all.
  Future<void> _sharePdf() async {
    final exportVault = vault;
    final exportPath = note;
    if (exportVault == null || exportPath == null) {
      _magicFeedback('Open a note first');
      return;
    }
    if (!workspace.typstPackagesReady) {
      _magicFeedback('Loading packages…');
      return;
    }
    // A dirty buffer would otherwise share the last-saved bytes.
    if (dirty && !await _save(syncAfter: false)) return;
    if (!mounted || vault != exportVault || note != exportPath) return;
    final exportSource = _previewSource();
    final exportRevision = _assetRevision + 1;
    _refreshNoteAssets(exportSource, force: true);
    try {
      await _assetLoadFuture!;
    } catch (error) {
      _magicFeedback('Could not load assets: $error');
      return;
    }
    if (!mounted ||
        vault != exportVault ||
        note != exportPath ||
        _assetRevision != exportRevision ||
        _previewSource() != exportSource) {
      _magicFeedback('Note changed before PDF export');
      return;
    }
    final exportFiles = _typstFiles();
    _magicFeedback('Building PDF…');
    final Uint8List pdf;
    try {
      pdf = await (widget.onCompilePdf ?? compileSourcePdf)(
        source: exportSource,
        files: exportFiles,
        paper: vaultRegistry?.pdfPaper ?? 'a4',
      );
    } catch (error) {
      if (!mounted) return;
      // Same escape hatch the preview offers, since the cause is the same: the
      // note does not compile.
      unawaited(_showTypstHelp(error: error.toString()));
      return;
    }
    if (!mounted ||
        vault != exportVault ||
        note != exportPath ||
        _previewSource() != exportSource) {
      _magicFeedback('Note changed before PDF export');
      return;
    }
    final name = exportPath.split('/').last.replaceFirst(RegExp(r'\.typ$'), '');
    await (widget.onSharePdf ?? _sharePdfBytes)(name, pdf);
  }

  Future<void> _sharePdfBytes(String name, Uint8List pdf) =>
      _shareFileBytes(name, pdf, extension: 'pdf', mimeType: 'application/pdf');

  Future<void> _shareFileBytes(
    String name,
    Uint8List bytes, {
    required String extension,
    required String mimeType,
  }) async {
    final safeName = name.replaceAll(RegExp(r'[\\/\r\n]'), '-');
    final filename = '$safeName.$extension';
    // iPad and macOS anchor the share popover to a rect; without one they throw
    // or place it arbitrarily.
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            bytes,
            mimeType: mimeType,
            name: filename,
            length: bytes.length,
          ),
        ],
        fileNameOverrides: [filename],
        subject: name,
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  Future<void> _shareGraphSvg(NoteGraph graph) async {
    final positions = forceLayoutPositions(graph, const Size(1000, 1000));
    final svg = graphToSvg(
      nodes: [
        for (final node in graph.nodes)
          if (positions[node.path] case final point?)
            SvgGraphNode(
              id: node.path,
              label: node.title,
              x: point.dx,
              y: point.dy,
            ),
      ],
      edges: [
        for (final edge in graph.edges)
          SvgGraphEdge(from: edge.from, to: edge.to),
      ],
    );
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            Uint8List.fromList(utf8.encode(svg)),
            mimeType: 'image/svg+xml',
            name: 'tylog-graph.svg',
          ),
        ],
        fileNameOverrides: const ['tylog-graph.svg'],
        subject: 'TyLog graph',
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  Future<String?> _chooseCitation() async {
    final v = vault;
    if (v == null) return null;
    final hasYml = await v.storage.exists(Vault.bibliographyPath);
    final hasZotero = await v.storage.exists(Vault.zoteroBibPath);
    if (!hasYml && !hasZotero) {
      _magicFeedback('No bibliography entries');
      return null;
    }
    final entries = <HayagrivaEntry>[];
    if (hasYml) {
      final bib = await v.storage.readText(Vault.bibliographyPath);
      bibliographySource = bib;
      entries.addAll(parseHayagrivaBibliography(bib));
    }
    if (hasZotero) {
      final bib = await v.storage.readText(Vault.zoteroBibPath);
      zoteroBibSource = bib;
      entries.addAll(parseBibtexBibliography(bib));
    }
    if (!mounted) return null;
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: false,
      isScrollControlled: true,
      builder: (context) {
        var query = '';
        return AppSheet.body(
          title: 'Citations',
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              final q = query.trim().toLowerCase();
              final filtered = q.isEmpty
                  ? entries
                  : entries
                        .where(
                          (entry) =>
                              entry.title.toLowerCase().contains(q) ||
                              entry.key.toLowerCase().contains(q) ||
                              (entry.author ?? '').toLowerCase().contains(q),
                        )
                        .toList();
              return Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        kSpace16,
                        0,
                        kSpace16,
                        kSpace8,
                      ),
                      child: TextField(
                        key: const Key('citation-search'),
                        autofocus: entries.length > 8,
                        onChanged: (value) =>
                            setSheetState(() => query = value),
                        decoration: const InputDecoration(
                          isDense: true,
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search citations',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          if (filtered.isEmpty)
                            const ListTile(
                              title: Text('No bibliography entries'),
                            ),
                          for (final entry in filtered)
                            ListTile(
                              leading: const Icon(Icons.format_quote),
                              title: Text(entry.title),
                              subtitle: Text(
                                '${entry.key} · '
                                '${entry.author ?? entry.type}'
                                '${entry.year == null ? '' : ' ${entry.year}'}'
                                '${entry.source == 'zotero' ? ' · Zotero' : ''}',
                              ),
                              onTap: () => Navigator.pop(context, entry.key),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _insertAttachment() async {
    if (vault == null) return;
    final picked = await FilePicker.pickFiles();
    final sourcePath = picked?.files.single.path;
    if (sourcePath == null) return;
    await _attachFile(File(sourcePath));
  }

  Future<String?> _attachFile(File source) async {
    final v = vault;
    if (v == null) return null;
    final base = source.path.split(Platform.pathSeparator).last;
    var target = 'assets/$base';
    var suffix = 2;
    while (_pendingAttach.containsKey(target) ||
        await v.storage.existsNow(target)) {
      final dot = base.lastIndexOf('.');
      final stem = dot < 0 ? base : base.substring(0, dot);
      final extension = dot < 0 ? '' : base.substring(dot);
      target = 'assets/$stem-${suffix++}$extension';
    }
    const imageExtensions = {'.png', '.jpg', '.jpeg', '.gif', '.svg', '.webp'};
    final lower = target.toLowerCase();
    final image = imageExtensions.any(lower.endsWith);
    // Chip first, copy after: the SAF write can queue behind the index for
    // minutes, and the user must see the attachment land at once.
    _pendingAttach[target] = source;
    _applyMagic(
      MagicRequest(
        action: MagicAction.attachment,
        value: '/$target',
        kind: image
            ? 'image'
            : isAudioPath(lower)
            ? 'audio'
            : 'file',
      ),
    );
    _trackSave(base, target, importPlatformFile(v.storage, target, source));
    return target;
  }

  Future<void> _createReport() async {
    final v = vault;
    final ix = index;
    if (v == null || ix == null) return;
    final title = await _askText('Report title');
    if (title == null || title.isEmpty) return;
    final project = await _chooseNote(
      kind: 'project',
      heading: 'Project filter (optional)',
    );
    if (!mounted) return;
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
      helpText: 'Date range (optional)',
    );
    final report = await writeReportStorage(
      v.storage,
      title,
      ix,
      includeZotero: await v.storage.exists(Vault.zoteroBibPath),
      ReportFilter(
        project: project?.id,
        from: range == null ? null : isoDay(range.start),
        to: range == null ? null : isoDay(range.end),
      ),
    );
    final export = await exportReportPdfStorage(
      v.storage,
      report,
      paper: vaultRegistry?.pdfPaper ?? 'a4',
    );
    if (mounted) {
      _magicFeedback('Created report and PDF');
      _queueCloudSync();
      // The PDF is already in outputs/; the share sheet is the natural
      // completion of "create a report", and dismissing it costs nothing.
      final name = export.path.split('/').last.replaceFirst('.pdf', '');
      await _sharePdfBytes(name, export.bytes);
    }
  }

  Future<void> _showMagicMenu() async {
    try {
      final action = await showModalBottomSheet<MagicAction>(
        context: context,
        showDragHandle: false,
        isScrollControlled: true,
        builder: (context) {
          final columns = MediaQuery.sizeOf(context).width < 500 ? 3 : 4;
          return AppSheet.body(
            title: 'Add to note',
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.8,
              child: CustomScrollView(
                slivers: [
                  for (final group in kMagicActionGroups.entries) ...[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        kSpace16,
                        kSpace16,
                        kSpace16,
                        kSpace8,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          group.key,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ),
                    SliverGrid.count(
                      crossAxisCount: columns,
                      children: group.value.map((action) {
                        final display = kMagicActionDisplay[action]!;
                        return InkWell(
                          onTap: () => Navigator.pop(context, action),
                          child: Semantics(
                            button: true,
                            label: display.$2,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (action == MagicAction.heading)
                                  Text(
                                    'H1',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  )
                                else
                                  Icon(display.$1),
                                const SizedBox(height: 6),
                                Text(display.$2, textAlign: TextAlign.center),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      );
      if (action != null) {
        try {
          await _runMagic(action);
        } catch (error) {
          _magicFeedback('Magic failed: $error');
        }
      }
    } finally {
      if (mounted && (mode == 'source' || mode == 'split')) {
        sourceEditorKey.currentState?.requestFocus();
      }
    }
  }
}
