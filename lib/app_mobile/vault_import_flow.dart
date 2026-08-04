part of '../app_mobile.dart';

const _vaultImportAssetLimit = 50 * 1024 * 1024;

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

class _VaultImportReport {
  int pages = 0;
  int journals = 0;
  int appended = 0;
  int skippedEmpty = 0;
  int assetsCopied = 0;
  int assetsSkipped = 0;
  int assetsMissing = 0;
  int unresolvedWikilinks = 0;
  final details = <String>[];

  int get notes => pages + journals;
}

extension _VaultImportFlow on _HomeScreenState {
  Future<void> _importVault() async {
    if (dirty) await _save(syncAfter: false);
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
    final existingPaths = {
      for (final entry in await opened.storage.list(recursive: true))
        if (!entry.isDirectory) entry.path.replaceAll('\\', '/'),
    };
    if (!mounted || vault != opened) return;

    final progress = ValueNotifier<String>('Converting 0 of ${sources.length}');
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

    for (var index = 0; index < sources.length; index++) {
      final item = sources[index];
      final name = item.path.split('/').last;
      progress.value = 'Converting ${index + 1} of ${sources.length}\n$name';
      try {
        final result = await convertVaultNote(
          dialect: dialect,
          sourceRelPath: item.path,
          markdown: await source.readText(item.path),
        );
        if (result == null) {
          report.skippedEmpty++;
          continue;
        }

        final isJournal = item.journal || result.kind == 'daily';
        if (isJournal &&
            existingPaths.contains(result.relPath) &&
            !used.contains(result.relPath)) {
          final current = await opened.storage.readText(result.relPath);
          await opened.storage.writeText(
            result.relPath,
            '$current\n== From ${dialect == 'logseq' ? 'Logseq' : 'Obsidian'}\n\n'
            '${importedNoteBody(result.typst)}',
          );
          used.add(result.relPath);
          writtenPaths.add(result.relPath);
          report.appended++;
        } else {
          final path = assignImportOutputPath(
            result.relPath,
            used,
            existingPaths.contains,
          );
          await opened.saveNote(path, result.typst);
          writtenPaths.add(path);
        }

        if (isJournal) {
          report.journals++;
        } else {
          report.pages++;
        }
        assets.addAll(result.referencedAssets);
        wikilinks.addAll(result.wikilinkTargets);
        resolvedLinks
          ..add(result.title.toLowerCase())
          ..addAll(result.aliases.map((alias) => alias.toLowerCase()));
        if (result.date case final date?) resolvedLinks.add(date.toLowerCase());
        report.details.addAll(
          result.diagnostics.map((diagnostic) => '${item.path}: $diagnostic'),
        );
      } catch (error) {
        report.details.add('${item.path}: $error');
      }
    }

    progress.value = 'Copying ${assets.length} referenced assets';
    await _copyVaultImportAssets(
      source: source,
      target: opened.storage,
      dialect: dialect,
      assets: assets,
      report: report,
    );

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
    _rebuild(() => status = 'Vault import: ${report.notes} notes');
    await _showVaultImportReport(report);
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
      } catch (error) {
        report.assetsMissing++;
        report.details.add('$sourcePath: $error');
      }
    }
  }

  Future<void> _showVaultImportReport(_VaultImportReport report) =>
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Vault import complete'),
          content: SizedBox(
            width: 560,
            child: ListView(
              shrinkWrap: true,
              children: [
                Text('Pages converted: ${report.pages}'),
                Text('Journals converted: ${report.journals}'),
                Text('Journals appended: ${report.appended}'),
                Text('Files skipped-empty: ${report.skippedEmpty}'),
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
