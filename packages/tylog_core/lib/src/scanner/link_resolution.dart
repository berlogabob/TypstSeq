part of '../scanner.dart';

enum LinkResolutionStatus { resolved, unresolved, ambiguous }

class LinkResolution {
  const LinkResolution({
    required this.target,
    required this.status,
    this.path,
    this.candidates = const [],
  });

  final String target;
  final LinkResolutionStatus status;
  final String? path;
  final List<String> candidates;
}

class LinkResolver {
  LinkResolver(Iterable<NoteRef> notes) {
    for (final note in notes) {
      _add(_ids, note.id, note.path);
      _add(_titles, note.title, note.path);
      _add(
        _stems,
        note.path.split('/').last.replaceFirst(_typExtension, ''),
        note.path,
      );
      for (final alias in note.aliases) {
        _add(_aliases, alias, note.path);
      }
    }
  }

  final _ids = <String, Set<String>>{};
  final _aliases = <String, Set<String>>{};
  final _titles = <String, Set<String>>{};
  final _stems = <String, Set<String>>{};

  LinkResolution resolve(String target) {
    for (final map in [_ids, _aliases, _titles, _stems]) {
      final candidates = map[target];
      if (candidates != null) return _resolveCandidates(target, candidates);
    }
    return LinkResolution(
      target: target,
      status: LinkResolutionStatus.unresolved,
    );
  }
}

String? resolveLinkPath(VaultIndex index, String target) {
  final resolved = LinkResolver(index.notes).resolve(target);
  return resolved.status == LinkResolutionStatus.resolved
      ? resolved.path
      : null;
}

LinkResolution resolveLink(VaultIndex index, String target) =>
    LinkResolver(index.notes).resolve(target);

/// Other vault notes [note] plausibly relates to, found by matching its
/// own tags/citations/string properties against the same exact-match
/// id/alias/title/stem maps [LinkResolver] already uses to resolve
/// `#tylog.ref-note(...)` targets. No fuzzy matching.
///
/// Pass [resolver] to reuse one across many notes — building it is O(vault), so
/// calling this in a loop without it is quadratic. [suggestLinkTargetsForNotes]
/// does that for you and is what batch callers should use.
List<String> suggestLinkTargets(
  NoteRef note,
  VaultIndex index, {
  LinkResolver? shared,
}) {
  final resolver = shared ?? LinkResolver(index.notes);
  final candidates = <String>{
    ...note.tags,
    ...note.citations,
    for (final value in note.properties.values)
      if (value is String)
        value
      else if (value is List)
        ...value.whereType<String>(),
  };
  final targets = <String>{};
  for (final candidate in candidates) {
    final resolved = resolver.resolve(candidate);
    if (resolved.status == LinkResolutionStatus.resolved &&
        resolved.path != note.path) {
      targets.add(resolved.path!);
    }
  }
  return targets.toList()..sort();
}

/// [suggestLinkTargets] for many notes, sharing one [LinkResolver].
///
/// Batch callers must use this rather than looping: the resolver is O(vault) to
/// build, so a per-note loop is quadratic — Relink vault over ~1700 articles was
/// tens of seconds of frozen UI before this existed. Returns note path → targets.
Map<String, List<String>> suggestLinkTargetsForNotes(
  Iterable<NoteRef> notes,
  VaultIndex index,
) {
  final shared = LinkResolver(index.notes);
  return {
    for (final note in notes)
      note.path: suggestLinkTargets(note, index, shared: shared),
  };
}

void _add(Map<String, Set<String>> map, String key, String path) {
  if (key.isNotEmpty) map.putIfAbsent(key, () => {}).add(path);
}

LinkResolution _resolveCandidates(String target, Set<String> candidates) {
  final sorted = candidates.toList()..sort();
  if (sorted.length == 1) {
    return LinkResolution(
      target: target,
      status: LinkResolutionStatus.resolved,
      path: sorted.first,
      candidates: sorted,
    );
  }
  return LinkResolution(
    target: target,
    status: LinkResolutionStatus.ambiguous,
    candidates: sorted,
  );
}

