import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:typst_flutter/typst_flutter.dart';

import 'graph.dart';
import 'models.dart';
import 'nextcloud_sync.dart';
import 'scanner.dart';
import 'vault.dart';

Future<String> appVersion() async =>
    RegExp(r'^version:\s*(.+)$', multiLine: true)
        .firstMatch(await rootBundle.loadString('pubspec.yaml'))
        ?.group(1)
        ?.trim() ??
    'unknown';

class TyLogApp extends StatelessWidget {
  const TyLogApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'TyLog',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3F6F68)),
      inputDecorationTheme: const InputDecorationTheme(
        border: InputBorder.none,
      ),
    ),
    home: const HomeScreen(),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Vault? vault;
  VaultIndex? index;
  File? note;
  final controller = TextEditingController();
  final sourceController = TextEditingController();
  Timer? autosave;
  Timer? cloudAutosave;
  String status = 'Opening vault...';
  bool dirty = false;
  String mode = 'journal';
  String previewSource = '';
  String hiddenSystemPrefix = '';
  NextcloudConfig? cloud;
  bool syncing = false;
  bool leftPanelOpen = true;
  bool rightPanelOpen = true;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    autosave?.cancel();
    cloudAutosave?.cancel();
    sourceController.dispose();
    controller.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    try {
      final cfg = await NextcloudConfig.load();
      final v = await Vault.openDefault();
      var openStatus = 'Vault: ${v.root.path}';
      if (cfg != null && cfg.isReady) {
        setState(() {
          vault = v;
          cloud = cfg;
          syncing = true;
          status = 'Syncing Nextcloud...';
        });
        try {
          openStatus = await NextcloudSync(cfg).sync(v);
        } catch (e) {
          openStatus = 'Sync failed: $e';
        } finally {
          syncing = false;
        }
      }
      final today = await v.todayNote();
      final ix = await v.rebuildIndex();
      _loadSource(await today.readAsString());
      setState(() {
        vault = v;
        note = today;
        index = ix;
        cloud = cfg;
        status = openStatus;
      });
      if (cfg != null && cfg.isReady) _queueCloudSync();
    } catch (e) {
      setState(() => status = 'Open failed: $e');
    }
  }

  Future<void> _save({bool syncAfter = true}) async {
    autosave?.cancel();
    final v = vault;
    final n = note;
    if (v == null || n == null) return;
    try {
      await v.saveNote(n, _currentSource());
      final ix = await v.rebuildIndex();
      setState(() {
        index = ix;
        dirty = false;
        status = 'Saved ${v.relativePath(n)}';
      });
      if (syncAfter) _queueCloudSync();
    } catch (e) {
      setState(() => status = 'Save failed: $e');
    }
  }

  void _queueCloudSync() {
    final cfg = cloud;
    if (cfg == null || !cfg.isReady || syncing) return;
    cloudAutosave?.cancel();
    cloudAutosave = Timer(const Duration(seconds: 2), () {
      if (!syncing && !dirty) unawaited(_syncNow());
    });
  }

  void _queueAutosave() {
    setState(() {
      dirty = true;
      status = 'Autosave pending...';
    });
    autosave?.cancel();
    autosave = Timer(const Duration(milliseconds: 700), _save);
  }

  String _currentSource() => mode == 'source'
      ? sourceController.text
      : '$hiddenSystemPrefix${controller.text}';

  void _loadSource(String source) {
    final clean = _splitCleanSource(source);
    hiddenSystemPrefix = clean.hiddenPrefix;
    controller.text = clean.body;
    sourceController.text = source;
  }

  Future<void> _openNote(File file) async {
    final v = vault;
    if (v == null) return;
    if (dirty) await _save();
    _loadSource(await file.readAsString());
    setState(() {
      note = file;
      dirty = false;
      mode = 'journal';
      status = 'Opened ${v.relativePath(file)}';
    });
  }

  Future<void> _openToday() async {
    final v = vault;
    if (v == null) return;
    await _openNote(await v.todayNote());
  }

  Future<void> _openLink(String title) async {
    final v = vault;
    if (v == null) return;
    final existing = _pathForLink(title);
    if (existing != null) {
      await _openNote(File('${v.root.path}/$existing'));
      return;
    }
    final file = await v.page(title);
    await _openNote(file);
    setState(() => status = 'Created ${v.relativePath(file)}');
  }

  Future<void> _newPage() async {
    final v = vault;
    if (v == null) return;
    final title = await _askPageTitle();
    if (title == null || title.trim().isEmpty) return;
    if (dirty) await _save();
    final file = await v.page(title);
    final ix = await v.rebuildIndex();
    await _openNote(file);
    setState(() {
      index = ix;
      status = 'Created ${v.relativePath(file)}';
    });
  }

  Future<String?> _askPageTitle() {
    final title = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New page'),
        content: TextField(
          controller: title,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Title'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, title.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  String? _pathForLink(String title) {
    final ix = index;
    return ix == null ? null : resolveLinkPath(ix, title);
  }

  Future<void> _rebuildIndex() async {
    final v = vault;
    if (v == null) return;
    final ix = await v.rebuildIndex();
    setState(() {
      index = ix;
      status = 'Index rebuilt';
    });
  }

  Future<void> _syncNow() async {
    final v = vault;
    final cfg = cloud;
    if (v == null) return;
    if (cfg == null || !cfg.isReady) {
      await _showSyncSettings();
      return;
    }
    cloudAutosave?.cancel();
    if (dirty) await _save(syncAfter: false);
    setState(() {
      syncing = true;
      status = 'Syncing Nextcloud...';
    });
    try {
      final result = await NextcloudSync(cfg).sync(v);
      if (note != null && await note!.exists()) {
        _loadSource(await note!.readAsString());
      }
      final ix = await v.rebuildIndex();
      setState(() {
        index = ix;
        status = result;
      });
    } catch (e) {
      setState(() => status = 'Sync failed: $e');
    } finally {
      setState(() => syncing = false);
    }
  }

  Future<void> _showSyncSettings() async {
    final cfg = cloud;
    final url = TextEditingController(text: cfg?.serverUrl ?? '');
    final user = TextEditingController(text: cfg?.username ?? '');
    final pass = TextEditingController(text: cfg?.password ?? '');
    final saved = await showDialog<NextcloudConfig>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nextcloud'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: url,
              decoration: const InputDecoration(labelText: 'Server URL'),
            ),
            TextField(
              controller: user,
              decoration: const InputDecoration(labelText: 'Login'),
            ),
            TextField(
              controller: pass,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              NextcloudConfig(
                serverUrl: url.text,
                username: user.text,
                password: pass.text,
              ),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == null) return;
    await saved.save();
    setState(() {
      cloud = saved;
      status = 'Nextcloud saved';
    });
    unawaited(_syncNow());
  }

  void _showSettings() {
    final v = vault;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => _SettingsSheet(
        vaultPath: v?.root.path ?? 'Opening vault...',
        cloud: cloud,
        syncing: syncing,
        onNextcloud: () {
          Navigator.pop(context);
          unawaited(_showSyncSettings());
        },
      ),
    );
  }

  void _showQuickActions() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.today),
              title: const Text('Today'),
              onTap: () {
                Navigator.pop(context);
                _openToday();
              },
            ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('New page'),
              onTap: () {
                Navigator.pop(context);
                _newPage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(context);
                _showSettings();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPath(String path) async {
    final v = vault;
    if (v == null) return;
    await _openNote(File('${v.root.path}/$path'));
  }

  void _showPreview() {
    setState(() {
      previewSource = _currentSource();
      mode = 'preview';
    });
  }

  void _showJournal() {
    if (mode == 'source') _loadSource(sourceController.text);
    setState(() => mode = 'journal');
  }

  void _showSource() {
    sourceController.text = _currentSource();
    setState(() => mode = 'source');
  }

  @override
  Widget build(BuildContext context) {
    final v = vault;
    final current = v == null || note == null ? null : v.relativePath(note!);
    final currentTitle = _currentTitle(current);
    final backlinks = current == null
        ? const <String>[]
        : index?.backlinksByTarget[current] ?? const <String>[];
    final outgoing = current == null
        ? const <String>[]
        : index?.notesByPath[current]?.outgoingLinks ?? const <String>[];
    final graph = index == null ? null : buildNoteGraph(index!);
    final pagesPanel = _PagesPanel(
      status: status,
      current: current,
      index: index,
      onOpenToday: _openToday,
      onNewPage: _newPage,
      onRebuildIndex: _rebuildIndex,
      onSync: syncing ? null : _syncNow,
      onSettings: _showSettings,
      onOpenNote: (item) =>
          v == null ? null : _openNote(File('${v.root.path}/${item.path}')),
    );
    final linksPanel = _LinksPanel(
      current: current,
      outgoing: outgoing,
      backlinks: backlinks,
      index: index,
      pathForLink: _pathForLink,
      onOpenLink: _openLink,
      onOpenPath: _openPath,
    );
    final workArea = _WorkSurface(
      title: currentTitle,
      subtitle: current ?? 'daily journal',
      child: switch (mode) {
        'graph' => GraphView(
          graph: graph ?? const NoteGraph(nodes: [], edges: []),
          currentPath: current,
          onOpenPath: _openPath,
        ),
        'preview' => TypstDocumentViewer(
          source: previewSource.isEmpty ? _currentSource() : previewSource,
          files: FileSource.bytes({
            '.tylog/tylog.typ': Uint8List.fromList(
              utf8.encode(tylogHelperSource),
            ),
            '/.tylog/tylog.typ': Uint8List.fromList(
              utf8.encode(tylogHelperSource),
            ),
          }),
          loadingBuilder: (_) =>
              const Center(child: CircularProgressIndicator()),
          errorBuilder: (_, error) => Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText('Typst error:\n$error'),
          ),
        ),
        'source' => _Editor(
          controller: sourceController,
          onChanged: _queueAutosave,
          monospace: true,
        ),
        _ => _Editor(controller: controller, onChanged: _queueAutosave),
      },
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 800;
        return Scaffold(
          drawer: compact ? Drawer(child: SafeArea(child: pagesPanel)) : null,
          endDrawer: compact
              ? Drawer(child: SafeArea(child: linksPanel))
              : null,
          appBar: AppBar(
            centerTitle: false,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dirty ? 'TyLog *' : 'TyLog'),
                Text(
                  currentTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
            actions: [
              if (!compact) ...[
                IconButton(
                  onPressed: () =>
                      setState(() => leftPanelOpen = !leftPanelOpen),
                  icon: const Icon(Icons.view_sidebar),
                  tooltip: 'Pages',
                ),
                IconButton(
                  onPressed: () =>
                      setState(() => rightPanelOpen = !rightPanelOpen),
                  icon: const Icon(Icons.notes),
                  tooltip: 'Backlinks',
                ),
                _ModeButton(
                  mode: mode,
                  value: 'journal',
                  icon: Icons.edit_note,
                  tooltip: 'Journal',
                  onPressed: _showJournal,
                ),
                _ModeButton(
                  mode: mode,
                  value: 'source',
                  icon: Icons.code,
                  tooltip: 'Source',
                  onPressed: _showSource,
                ),
                _ModeButton(
                  mode: mode,
                  value: 'preview',
                  icon: Icons.preview,
                  tooltip: 'Preview',
                  onPressed: _showPreview,
                ),
                _ModeButton(
                  mode: mode,
                  value: 'graph',
                  icon: Icons.account_tree,
                  tooltip: 'Graph',
                  onPressed: () => setState(() => mode = 'graph'),
                ),
                IconButton(
                  onPressed: syncing ? null : _syncNow,
                  icon: const Icon(Icons.sync),
                  tooltip: 'Sync',
                ),
              ],
              if (compact)
                IconButton(
                  onPressed: _showSource,
                  icon: const Icon(Icons.code),
                  tooltip: 'Source',
                ),
              if (compact)
                Builder(
                  builder: (context) => IconButton(
                    onPressed: () => Scaffold.of(context).openEndDrawer(),
                    icon: const Icon(Icons.link),
                    tooltip: 'Backlinks',
                  ),
                ),
            ],
          ),
          body: compact
              ? workArea
              : Row(
                  children: [
                    if (leftPanelOpen) SizedBox(width: 280, child: pagesPanel),
                    Expanded(child: workArea),
                    if (rightPanelOpen) SizedBox(width: 300, child: linksPanel),
                  ],
                ),
          bottomNavigationBar: compact
              ? NavigationBar(
                  selectedIndex: _modeIndex(mode),
                  onDestinationSelected: (value) {
                    if (value == 1) {
                      _showPreview();
                    } else if (value == 0) {
                      _showJournal();
                    } else {
                      setState(() => mode = 'graph');
                    }
                  },
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.today),
                      label: 'Journal',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.preview),
                      label: 'Preview',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.account_tree),
                      label: 'Graph',
                    ),
                  ],
                )
              : null,
          floatingActionButton: FloatingActionButton(
            onPressed: _showQuickActions,
            tooltip: 'Quick actions',
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }

  String _currentTitle(String? current) => current == null
      ? 'Today'
      : index?.notesByPath[current]?.title ??
            current.split('/').last.replaceFirst('.typ', '');

  int _modeIndex(String value) => switch (value) {
    'preview' => 1,
    'graph' => 2,
    _ => 0,
  };
}

class _CleanSource {
  const _CleanSource(this.hiddenPrefix, this.body);

  final String hiddenPrefix;
  final String body;
}

_CleanSource _splitCleanSource(String source) {
  final lines = source.split('\n');
  var index = 0;
  while (index < lines.length) {
    final trimmed = lines[index].trimLeft();
    if (trimmed.isEmpty) {
      index++;
      continue;
    }
    if (!_isSystemLine(trimmed)) break;

    var depth =
        '('.allMatches(lines[index]).length -
        ')'.allMatches(lines[index]).length;
    index++;
    while (depth > 0 && index < lines.length) {
      depth +=
          '('.allMatches(lines[index]).length -
          ')'.allMatches(lines[index]).length;
      index++;
    }
  }
  while (index < lines.length && lines[index].trim().isEmpty) {
    index++;
  }
  final prefix = index == 0 ? '' : '${lines.take(index).join('\n')}\n';
  return _CleanSource(prefix, lines.skip(index).join('\n'));
}

bool _isSystemLine(String line) =>
    RegExp(r'^#(import|include|show|set|let|note)\b').hasMatch(line);

class _PagesPanel extends StatelessWidget {
  const _PagesPanel({
    required this.status,
    required this.current,
    required this.index,
    required this.onOpenToday,
    required this.onNewPage,
    required this.onRebuildIndex,
    required this.onSync,
    required this.onSettings,
    required this.onOpenNote,
  });

  final String status;
  final String? current;
  final VaultIndex? index;
  final VoidCallback onOpenToday;
  final VoidCallback onNewPage;
  final VoidCallback onRebuildIndex;
  final VoidCallback? onSync;
  final VoidCallback onSettings;
  final ValueChanged<NoteRef> onOpenNote;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainer,
    child: ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('Journal', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(status, maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onOpenToday,
          icon: const Icon(Icons.today),
          label: const Text('Today'),
        ),
        FilledButton.tonalIcon(
          onPressed: onNewPage,
          icon: const Icon(Icons.add),
          label: const Text('New page'),
        ),
        TextButton.icon(
          onPressed: onSync,
          icon: const Icon(Icons.sync),
          label: const Text('Sync'),
        ),
        TextButton.icon(
          onPressed: onRebuildIndex,
          icon: const Icon(Icons.refresh),
          label: const Text('Rebuild index'),
        ),
        ListTile(
          leading: const Icon(Icons.settings),
          title: const Text('Settings'),
          onTap: onSettings,
        ),
        const Divider(height: 28),
        Text('Pages', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        for (final item in index?.notes ?? const <NoteRef>[])
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: Icon(
              item.path.startsWith('journal/') ? Icons.today : Icons.notes,
            ),
            title: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              item.path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            selected: item.path == current,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onTap: () => onOpenNote(item),
          ),
      ],
    ),
  );
}

class _LinksPanel extends StatelessWidget {
  const _LinksPanel({
    required this.current,
    required this.outgoing,
    required this.backlinks,
    required this.index,
    required this.pathForLink,
    required this.onOpenLink,
    required this.onOpenPath,
  });

  final String? current;
  final List<String> outgoing;
  final List<String> backlinks;
  final VaultIndex? index;
  final String? Function(String title) pathForLink;
  final ValueChanged<String> onOpenLink;
  final ValueChanged<String> onOpenPath;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('Context', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(current ?? '-', maxLines: 2, overflow: TextOverflow.ellipsis),
        const Divider(height: 28),
        _SectionTitle('Outgoing'),
        if (outgoing.isEmpty) const _EmptyHint('No links from this page yet.'),
        for (final link in outgoing)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            title: Text(link),
            trailing: Icon(
              pathForLink(link) == null ? Icons.add : Icons.open_in_new,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onTap: () => onOpenLink(link),
          ),
        const Divider(height: 28),
        _SectionTitle('Backlinks'),
        if (backlinks.isEmpty)
          const _EmptyHint('Mention this page elsewhere and it appears here.'),
        for (final path in backlinks)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: const Icon(Icons.link),
            title: Text(
              index?.notesByPath[path]?.title ?? path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onTap: () => onOpenPath(path),
          ),
      ],
    ),
  );
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet({
    required this.vaultPath,
    required this.cloud,
    required this.syncing,
    required this.onNextcloud,
  });

  final String vaultPath;
  final NextcloudConfig? cloud;
  final bool syncing;
  final VoidCallback onNextcloud;

  @override
  Widget build(BuildContext context) {
    final ready = cloud?.isReady ?? false;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        shrinkWrap: true,
        children: [
          Text('Settings', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          _SettingsTile(
            icon: Icons.folder_open,
            title: 'Local folder',
            subtitle: vaultPath,
          ),
          _SettingsTile(
            icon: Icons.cloud,
            title: 'Nextcloud settings',
            subtitle: ready ? cloud!.serverUrl : 'Local folder only',
            onTap: onNextcloud,
          ),
          _SettingsTile(
            icon: Icons.sync,
            title: 'Sync server status',
            subtitle: syncing
                ? 'Syncing...'
                : (ready ? 'Ready' : 'Not configured'),
          ),
          FutureBuilder<String>(
            future: appVersion(),
            builder: (context, snapshot) => _SettingsTile(
              icon: Icons.info_outline,
              title: 'App version',
              subtitle: snapshot.data ?? '...',
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
        child: Icon(icon),
      ),
      title: Text(title),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    ),
  );
}

class _WorkSurface extends StatelessWidget {
  const _WorkSurface({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surface,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              elevation: 0,
              clipBehavior: Clip.antiAlias,
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              child: child,
            ),
          ),
        ],
      ),
    ),
  );
}

class _Editor extends StatelessWidget {
  const _Editor({
    required this.controller,
    required this.onChanged,
    this.monospace = false,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;
  final bool monospace;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    expands: true,
    maxLines: null,
    minLines: null,
    textAlignVertical: TextAlignVertical.top,
    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
      height: 1.45,
      fontFamily: monospace ? 'monospace' : null,
    ),
    decoration: const InputDecoration(contentPadding: EdgeInsets.all(18)),
    onChanged: (_) => onChanged(),
  );
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.mode,
    required this.value,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final String mode;
  final String value;
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
    isSelected: mode == value,
    onPressed: onPressed,
    icon: Icon(icon),
    tooltip: tooltip,
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.labelLarge);
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(text, style: Theme.of(context).textTheme.bodySmall),
  );
}
