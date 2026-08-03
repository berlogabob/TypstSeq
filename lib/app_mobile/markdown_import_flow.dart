part of '../app_mobile.dart';

enum _MarkdownImportOutcome { imported, replaced, kept, unchanged, failed }

class _MarkdownImportReportItem {
  const _MarkdownImportReportItem({
    required this.name,
    required this.outcome,
    this.detail,
  });

  final String name;
  final _MarkdownImportOutcome outcome;
  final String? detail;
}

class _PreparedMarkdownArticle {
  const _PreparedMarkdownArticle(this.name, this.draft);

  final String name;
  final MarkdownArticleDraft draft;
}

enum _MarkdownDuplicateChoice { keepExisting, useImported, merged }

class _MarkdownDuplicateDecision {
  const _MarkdownDuplicateDecision(this.choice, [this.source]);

  final _MarkdownDuplicateChoice choice;
  final String? source;
}

extension _MarkdownImportFlow on _HomeScreenState {
  Future<void> _importMarkdownArticles() async {
    final opened = vault;
    if (opened == null) return;
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['md', 'markdown'],
    );
    if (picked == null || picked.files.isEmpty) return;
    if (dirty) await _save(syncAfter: false);
    if (!mounted || vault != opened) return;

    final progress = ValueNotifier<String>(
      'Preparing 0 of ${picked.files.length}',
    );
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Importing Markdown articles'),
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
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final prepared = <_PreparedMarkdownArticle>[];
    final report = <_MarkdownImportReportItem>[];
    for (var index = 0; index < picked.files.length; index++) {
      final file = picked.files[index];
      progress.value =
          'Preparing ${index + 1} of ${picked.files.length}\n${file.name}';
      try {
        final lower = file.name.toLowerCase();
        if (!lower.endsWith('.md') && !lower.endsWith('.markdown')) {
          throw const FormatException(
            'Only .md and .markdown files are supported',
          );
        }
        prepared.add(
          _PreparedMarkdownArticle(
            file.name,
            await buildMarkdownArticleDraft(
              bytes: await file.readAsBytes(),
              sourceName: file.name,
            ),
          ),
        );
      } catch (error) {
        report.add(
          _MarkdownImportReportItem(
            name: file.name,
            outcome: _MarkdownImportOutcome.failed,
            detail: error.toString(),
          ),
        );
      }
    }
    if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    progress.dispose();
    if (!mounted) return;

    final articles = (index?.notes ?? const <NoteRef>[])
        .where((note) => note.kind == 'article')
        .toList();
    var wroteFiles = false;
    final writtenPaths = <String>{};
    for (final item in prepared) {
      final draft = item.draft;
      try {
        final duplicate = classifyMarkdownDuplicate(draft, articles);
        // Fetch remote images into the vault (except for unchanged articles,
        // which are not rewritten) so #image(...) references resolve.
        final assets = duplicate.kind == MarkdownDuplicateKind.unchanged
            ? (
                typst: draft.typstSource,
                diagnostics: const <MarkdownArticleDiagnostic>[],
              )
            : await downloadArticleImages(
                typst: draft.typstSource,
                articleId: draft.id,
                storage: opened.storage,
              );
        final typstSource = assets.typst;
        final warningCount = draft.diagnostics.length + assets.diagnostics.length;
        final warningDetail = warningCount == 0
            ? null
            : '$warningCount conversion warning${warningCount == 1 ? '' : 's'}';
        switch (duplicate.kind) {
          case MarkdownDuplicateKind.newArticle:
            final path = await nextMarkdownArticlePath(
              opened.storage,
              draft.title,
            );
            await opened.saveNote(path, typstSource);
            articles.add(_noteForImportedArticle(path, draft));
            wroteFiles = true;
            writtenPaths.add(path);
            report.add(
              _MarkdownImportReportItem(
                name: item.name,
                outcome: _MarkdownImportOutcome.imported,
                detail: warningDetail ?? path,
              ),
            );
            break;
          case MarkdownDuplicateKind.unchanged:
            report.add(
              _MarkdownImportReportItem(
                name: item.name,
                outcome: _MarkdownImportOutcome.unchanged,
                detail: duplicate.existing?.path,
              ),
            );
            break;
          case MarkdownDuplicateKind.changed:
            final existing = duplicate.existing!;
            final existingSource = await opened.readText(existing.path);
            final decision = await _resolveMarkdownDuplicate(
              existing: existingSource,
              incoming: typstSource,
              title: draft.title,
            );
            if (decision.choice == _MarkdownDuplicateChoice.keepExisting) {
              report.add(
                _MarkdownImportReportItem(
                  name: item.name,
                  outcome: _MarkdownImportOutcome.kept,
                  detail: existing.path,
                ),
              );
              continue;
            }
            final source = decision.choice == _MarkdownDuplicateChoice.merged
                ? decision.source!
                : typstSource;
            await opened.saveNote(existing.path, source);
            final position = articles.indexOf(existing);
            if (position >= 0) {
              articles[position] = _noteForImportedArticle(
                existing.path,
                draft,
              );
            }
            wroteFiles = true;
            report.add(
              _MarkdownImportReportItem(
                name: item.name,
                outcome: _MarkdownImportOutcome.replaced,
                detail: decision.choice == _MarkdownDuplicateChoice.merged
                    ? 'Manual merge · ${existing.path}'
                    : warningDetail ?? existing.path,
              ),
            );
            break;
        }
      } catch (error) {
        report.add(
          _MarkdownImportReportItem(
            name: item.name,
            outcome: _MarkdownImportOutcome.failed,
            detail: error.toString(),
          ),
        );
      }
    }

    if (wroteFiles) {
      await workspace.refreshIndex(updateStatus: false, always: true);
      await _autoLinkImportedArticles(writtenPaths);
      _queueCloudSync();
    }
    if (!mounted) return;
    final successful = report
        .where((item) => item.outcome != _MarkdownImportOutcome.failed)
        .length;
    _rebuild(() {
      status =
          'Markdown import: $successful succeeded, '
          '${report.length - successful} failed';
    });
    await _showMarkdownImportReport(report);
  }

  NoteRef _noteForImportedArticle(String path, MarkdownArticleDraft draft) =>
      NoteRef(
        id: draft.id,
        path: path,
        title: draft.title,
        kind: 'article',
        date: draft.date,
        tags: draft.tags,
        aliases: draft.aliases,
        outgoingLinks: const [],
        properties: draft.properties,
        metadataSource: 'typst-query',
      );

  Future<int> _appendRelatedSection(
    String path,
    List<String> targetPaths,
  ) async {
    final source = await vault!.readText(path);
    final stripped = stripAutoRelated(source);
    final lines = [
      for (final targetPath in targetPaths)
        if (index!.notesByPath[targetPath] case final target?)
          // Bulleted so the block renders as a list, and so article-pipeline
          // (which writes the same marked block from its LLM suggestions)
          // produces byte-identical markup.
          '- #tylog.ref-note(${typstString(target.id)})[${typstContent(target.title)}]',
    ];
    if (lines.isNotEmpty) {
      await vault!.saveNote(
        path,
        '$stripped\n\n$_autoRelatedMarker\n== Related\n${lines.join('\n')}\n',
      );
      return 1;
    }
    if (stripped != source) await vault!.saveNote(path, stripped);
    return 0;
  }

  /// Appends a clearly-labeled links section to freshly imported articles
  /// whose tags/citations/properties match existing vault notes. Only
  /// touches notes just written by this import — never edits pre-existing
  /// files silently.
  Future<void> _autoLinkImportedArticles(Set<String> paths) async {
    final opened = vault;
    final currentIndex = index;
    if (opened == null || currentIndex == null || paths.isEmpty) return;
    var appended = false;
    // One resolver for the batch: suggestLinkTargets builds a whole-vault
    // LinkResolver per call, so calling it per imported article was quadratic.
    final suggestions = suggestLinkTargetsForNotes(
      [for (final path in paths) currentIndex.notesByPath[path]].nonNulls,
      currentIndex,
    );
    for (final entry in suggestions.entries) {
      appended =
          await _appendRelatedSection(entry.key, entry.value) > 0 || appended;
    }
    if (appended) {
      await workspace.refreshIndex(updateStatus: false, always: true);
    }
  }

  Future<void> _relinkVault() async {
    if (vault == null || index == null) return;
    final idx = index!;
    final communities = computeCommunities(idx);
    final articles = relinkCandidates(idx.notes);
    final skipped =
        idx.notes.where((n) => n.kind == 'article').length - articles.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Relink vault'),
        content: Text(
          'Rescan ${articles.length} articles and refresh their suggested links?'
          '${skipped > 0 ? '\n\n$skipped already linked by a language model are left unchanged.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Relink'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    try {
      // One resolver for every article, not one per article — the per-article
      // form was quadratic and cost tens of seconds of frozen UI on a large
      // vault (see suggestLinkTargetsForNotes).
      final suggestions = suggestLinkTargetsForNotes(articles, idx);
      for (final note in articles) {
        final sourceCluster = communities.noteToCluster[note.path];
        final targets = (suggestions[note.path] ?? const <String>[]).where((
          targetPath,
        ) {
          final targetCluster = communities.noteToCluster[targetPath];
          return sourceCluster == null ||
              targetCluster == null ||
              sourceCluster == targetCluster;
        }).toList();
        await _appendRelatedSection(note.path, targets);
      }
    } finally {
      if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
    await workspace.refreshIndex(always: true);
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text('Relinked ${articles.length} articles')),
    );
  }

  Future<_MarkdownDuplicateDecision> _resolveMarkdownDuplicate({
    required String existing,
    required String incoming,
    required String title,
  }) async {
    final merged = TextEditingController(text: incoming);
    final result = await showDialog<_MarkdownDuplicateDecision>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        insetPadding: const EdgeInsets.all(16),
        title: Text('Article changed: $title'),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 1000,
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final panes = [
                      _markdownSourcePane('Existing Typst', existing),
                      _markdownSourcePane('Incoming Typst', incoming),
                    ];
                    return constraints.maxWidth >= 700
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: panes[0]),
                              const SizedBox(width: 12),
                              Expanded(child: panes[1]),
                            ],
                          )
                        : ListView(
                            children: [
                              SizedBox(height: 180, child: panes[0]),
                              const SizedBox(height: 12),
                              SizedBox(height: 180, child: panes[1]),
                            ],
                          );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: () => merged.text = existing,
                    child: const Text('Edit existing'),
                  ),
                  TextButton(
                    onPressed: () => merged.text = incoming,
                    child: const Text('Edit imported'),
                  ),
                ],
              ),
              SizedBox(
                height: 180,
                child: TextField(
                  key: const ValueKey('markdown-manual-merge'),
                  controller: merged,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Manual merged Typst source',
                    alignLabelWithHint: true,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              const _MarkdownDuplicateDecision(
                _MarkdownDuplicateChoice.keepExisting,
              ),
            ),
            child: const Text('Keep existing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              const _MarkdownDuplicateDecision(
                _MarkdownDuplicateChoice.useImported,
              ),
            ),
            child: const Text('Use imported'),
          ),
          FilledButton(
            onPressed: () {
              if (merged.text.trim().isEmpty) {
                showSnack(context, 'Merged Typst cannot be empty');
                return;
              }
              Navigator.pop(
                context,
                _MarkdownDuplicateDecision(
                  _MarkdownDuplicateChoice.merged,
                  merged.text,
                ),
              );
            },
            child: const Text('Save manual merge'),
          ),
        ],
      ),
    );
    merged.dispose();
    return result ??
        const _MarkdownDuplicateDecision(_MarkdownDuplicateChoice.keepExisting);
  }

  Widget _markdownSourcePane(String title, String source) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(8),
            child: SelectableText(
              source,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> _showMarkdownImportReport(
    List<_MarkdownImportReportItem> report,
  ) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Markdown import complete'),
      content: SizedBox(
        width: 560,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final item in report)
              ListTile(
                dense: true,
                leading: Icon(switch (item.outcome) {
                  _MarkdownImportOutcome.imported => Icons.file_download_done,
                  _MarkdownImportOutcome.replaced => Icons.swap_horiz,
                  _MarkdownImportOutcome.kept => Icons.inventory_2_outlined,
                  _MarkdownImportOutcome.unchanged =>
                    Icons.check_circle_outline,
                  _MarkdownImportOutcome.failed => Icons.error_outline,
                }),
                title: Text(item.name),
                subtitle: Text(
                  '${item.outcome.name}${item.detail == null ? '' : ' · ${item.detail}'}',
                ),
              ),
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
