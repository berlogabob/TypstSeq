/// A page that already exists with a namespace title like "A/B/C".
class NamespacePage {
  final String id;
  final String title;
  final List<String> aliases;

  const NamespacePage(this.id, this.title, this.aliases);
}

/// A single change to apply to make a page or ancestor namespaced.
class NamespaceChange {
  /// Page being changed, or null when the page must be created.
  final String? existingId;

  /// Full path, e.g. "A/B/C".
  final String fullPath;

  /// New title, e.g. "C".
  final String newTitle;

  /// Parent path, e.g. "A/B", or null for a root segment.
  final String? parentPath;

  const NamespaceChange({
    this.existingId,
    required this.fullPath,
    required this.newTitle,
    this.parentPath,
  });
}

/// The result of planning namespaces: changes to apply and titles to skip.
class NamespacePlan {
  final List<NamespaceChange> changes;
  final List<String> skipped;

  const NamespacePlan(this.changes, this.skipped);
}

/// Plans namespace changes for a set of pages.
NamespacePlan planNamespaces(List<NamespacePage> pages) {
  final List<NamespaceChange> changes = <NamespaceChange>[];
  final List<String> skipped = <String>[];
  final Set<String> claimed = <String>{};

  // Pass 1: each namespaced page's own change.
  for (final NamespacePage page in pages) {
    final String title = page.title.trim();
    if (!title.contains('/')) {
      continue;
    }

    final List<String> segments = title
        .split('/')
        .map((s) => s.trim())
        .toList();

    if (_isSkipped(segments)) {
      if (!skipped.contains(page.title)) {
        skipped.add(page.title);
      }
      continue;
    }

    final String fullPath = segments.join('/');
    final String key = fullPath.toLowerCase();
    if (claimed.contains(key)) {
      continue;
    }
    claimed.add(key);

    final String newTitle = segments.last;
    final String? parentPath = segments.length > 1
        ? segments.sublist(0, segments.length - 1).join('/')
        : null;

    changes.add(
      NamespaceChange(
        existingId: page.id,
        fullPath: fullPath,
        newTitle: newTitle,
        parentPath: parentPath,
      ),
    );
  }

  // Pass 2: ensure each ancestor path has exactly one change.
  for (final NamespacePage page in pages) {
    final String title = page.title.trim();
    if (!title.contains('/')) {
      continue;
    }

    final List<String> segments = title
        .split('/')
        .map((s) => s.trim())
        .toList();
    if (_isSkipped(segments)) {
      continue;
    }

    for (int depth = segments.length - 1; depth >= 1; depth--) {
      final List<String> ancestorSegments = segments.sublist(0, depth);
      final String ancestorPath = ancestorSegments.join('/');
      final String key = ancestorPath.toLowerCase();

      if (claimed.contains(key)) {
        continue;
      }

      final String ancestorNewTitle = ancestorSegments.last;
      final String? ancestorParentPath = ancestorSegments.length > 1
          ? ancestorSegments.sublist(0, ancestorSegments.length - 1).join('/')
          : null;

      final String? existingId = _findExistingAncestorId(
        ancestorPath,
        ancestorNewTitle,
        pages.where((p) => !changes.any((c) => c.existingId == p.id)).toList(),
      );

      claimed.add(key);
      changes.add(
        NamespaceChange(
          existingId: existingId,
          fullPath: ancestorPath,
          newTitle: ancestorNewTitle,
          parentPath: ancestorParentPath,
        ),
      );
    }
  }

  changes.sort(_compareByDepthThenAlpha);
  return NamespacePlan(changes, skipped);
}

bool _isSkipped(List<String> segments) {
  for (final String segment in segments) {
    if (segment.isEmpty) {
      return true;
    }
    if (segment.length > 80) {
      return true;
    }
  }
  final String joined = segments.join('/');
  if (joined.contains('://')) {
    return true;
  }
  if (segments.any(
    (segment) =>
        segment.startsWith('www.') ||
        segment.split(RegExp(r'\s+')).length > 4 ||
        RegExp(r'[.!?].+').hasMatch(segment),
  )) {
    return true;
  }
  if (joined.startsWith('r/') || joined.startsWith('u/')) {
    return true;
  }
  final RegExp academicYear = RegExp(r'^\d{4}/\d{4}');
  if (academicYear.hasMatch(joined)) {
    return true;
  }
  return false;
}

String? _findExistingAncestorId(
  String ancestorPath,
  String ancestorNewTitle,
  List<NamespacePage> pages,
) {
  final String key = ancestorPath.toLowerCase();

  // A page whose title equals the ancestor path.
  for (final NamespacePage page in pages) {
    if (page.title.trim().toLowerCase() == key) {
      return page.id;
    }
  }

  // A page whose alias equals the ancestor path.
  for (final NamespacePage page in pages) {
    for (final String alias in page.aliases) {
      if (alias.trim().toLowerCase() == key) {
        return page.id;
      }
    }
  }

  // A page whose title equals the last segment and whose alias equals path.
  for (final NamespacePage page in pages) {
    if (page.title.trim().toLowerCase() != ancestorNewTitle.toLowerCase()) {
      continue;
    }
    for (final String alias in page.aliases) {
      if (alias.trim().toLowerCase() == key) {
        return page.id;
      }
    }
  }

  return null;
}

int _compareByDepthThenAlpha(NamespaceChange a, NamespaceChange b) {
  final int depthA = a.fullPath.split('/').length;
  final int depthB = b.fullPath.split('/').length;
  if (depthA != depthB) {
    return depthA.compareTo(depthB);
  }
  return a.fullPath.toLowerCase().compareTo(b.fullPath.toLowerCase());
}
