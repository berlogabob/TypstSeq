import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:typst_flutter/typst_flutter.dart';

import 'graph.dart';
import 'models.dart';
import 'scanner.dart';
import 'vault.dart';

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
  String status = 'Opening vault...';
  bool dirty = false;
  String mode = 'editor';
  String previewSource = '';
  bool leftPanelOpen = true;
  bool rightPanelOpen = true;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    try {
      final v = await Vault.openDefault();
      final today = await v.todayNote();
      final ix = await v.rebuildIndex();
      controller.text = await today.readAsString();
      setState(() {
        vault = v;
        note = today;
        index = ix;
        status = 'Vault: ${v.root.path}';
      });
    } catch (e) {
      setState(() => status = 'Open failed: $e');
    }
  }

  Future<void> _save() async {
    final v = vault;
    final n = note;
    if (v == null || n == null) return;
    try {
      await v.saveNote(n, controller.text);
      final ix = await v.rebuildIndex();
      setState(() {
        index = ix;
        dirty = false;
        status = 'Saved ${v.relativePath(n)}';
      });
    } catch (e) {
      setState(() => status = 'Save failed: $e');
    }
  }

  Future<void> _openNote(File file) async {
    final v = vault;
    if (v == null) return;
    controller.text = await file.readAsString();
    setState(() {
      note = file;
      dirty = false;
      mode = 'editor';
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

  Future<void> _openPath(String path) async {
    final v = vault;
    if (v == null) return;
    await _openNote(File('${v.root.path}/$path'));
  }

  void _showPreview() {
    setState(() {
      previewSource = controller.text;
      mode = 'preview';
    });
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
      onSave: _save,
      onOpenToday: _openToday,
      onRebuildIndex: _rebuildIndex,
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
          source: previewSource.isEmpty ? controller.text : previewSource,
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
        _ => _Editor(
          controller: controller,
          onChanged: () => setState(() => dirty = true),
        ),
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
                  value: 'editor',
                  icon: Icons.edit_note,
                  tooltip: 'Editor',
                  onPressed: () => setState(() => mode = 'editor'),
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
              ],
              IconButton(
                onPressed: _save,
                icon: const Icon(Icons.save),
                tooltip: 'Save',
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
                    } else {
                      setState(() => mode = value == 2 ? 'graph' : 'editor');
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
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _openToday,
            icon: const Icon(Icons.today),
            label: const Text('Today'),
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

class _PagesPanel extends StatelessWidget {
  const _PagesPanel({
    required this.status,
    required this.current,
    required this.index,
    required this.onSave,
    required this.onOpenToday,
    required this.onRebuildIndex,
    required this.onOpenNote,
  });

  final String status;
  final String? current;
  final VaultIndex? index;
  final VoidCallback onSave;
  final VoidCallback onOpenToday;
  final VoidCallback onRebuildIndex;
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
        OutlinedButton.icon(
          onPressed: onSave,
          icon: const Icon(Icons.save),
          label: const Text('Save'),
        ),
        TextButton.icon(
          onPressed: onRebuildIndex,
          icon: const Icon(Icons.refresh),
          label: const Text('Rebuild index'),
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
  const _Editor({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    expands: true,
    maxLines: null,
    minLines: null,
    textAlignVertical: TextAlignVertical.top,
    style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.45),
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
