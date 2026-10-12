part of '../scanner.dart';

const _keep = Object();

/// Omit nullable fields to keep them; pass null to write Typst `none`, or a string to set them.
String setTaskFields(
  String source,
  String id, {
  String? status,
  String? priority,
  Object? scheduled = _keep,
  Object? due = _keep,
  Object? recurrence = _keep,
}) {
  final call = _locateTaskCall(source, id);
  var replacement = call.source;
  for (final entry in {
    'status': status ?? _keep,
    'priority': priority ?? _keep,
    'scheduled': scheduled,
    'due': due,
    'recurrence': recurrence,
  }.entries) {
    if (identical(entry.value, _keep)) continue;
    final value = entry.value == null
        ? 'none'
        : typstString(entry.value as String);
    final field = _locateTopLevelField(replacement, entry.key);
    replacement = field == null
        ? _appendCallField(
            replacement,
            entry.key,
            value,
            allowed: writableTaskFields,
          )
        : replacement.replaceRange(
            field.start,
            field.end,
            '${entry.key}: $value',
          );
  }
  return source.replaceRange(call.start, call.end, replacement);
}

/// Records repeat completions and starts/stops the task clock on status transitions.
String applyTaskStatus(String source, String id, String next, DateTime now) {
  final call = _locateTaskCall(source, id);
  final timestamp = now.toIso8601String();
  if (next == 'doing') {
    for (final other in locateTypstCalls(source, names: const {'tylog.task'})) {
      final otherId = taskField(other.source, 'id');
      if (otherId == null ||
          otherId == id ||
          ClockEntry.latestRunning(parseClockedField(other.source)) == null) {
        continue;
      }
      source = replaceTaskStatus(
        stopTaskClock(source, otherId, timestamp),
        otherId,
        'todo',
      );
    }
    source = replaceTaskStatus(source, id, next);
    return taskField(call.source, 'status') == 'doing' &&
            ClockEntry.latestRunning(parseClockedField(call.source)) != null
        ? source
        : startTaskClock(source, id, timestamp);
  }
  source = stopTaskClock(source, id, timestamp);
  final recurrence = taskField(call.source, 'recurrence');
  if (next == 'done' && recurrence != null && recurrence.isNotEmpty) {
    return completeTaskOccurrence(
      replaceTaskStatus(source, id, 'todo'),
      id,
      timestamp,
    );
  }
  return replaceTaskStatus(source, id, next);
}

String replaceTaskStatus(String source, String id, String status) =>
    setTaskFields(source, id, status: status);

String completeTaskOccurrence(String source, String id, String timestamp) {
  final call = _locateTaskCall(source, id);
  final field = _locateTopLevelField(call.source, 'completed');
  final replacement = field == null
      ? _appendCallField(
          call.source,
          'completed',
          '("$timestamp",)',
          allowed: writableTaskFields,
        )
      : call.source.replaceRange(
          field.start,
          field.end,
          'completed: (${call.source.substring(field.valueStart + 1, field.valueEnd - 1)}"$timestamp",)',
        );
  return source.replaceRange(call.start, call.end, replacement);
}

/// Field names TyLog may write into a `#tylog.task(...)` call.
///
/// Bound to `typst/tylog/lib.typ` by `package_contract_test.dart`: every name
/// here must be a parameter the shipped package actually declares. That test
/// exists because this is the failure that cost 167 notes — the app started
/// writing `clocked:` as a named argument the package had never declared, so
/// every note carrying one stopped compiling. Nothing caught it, because the
/// fallback parser reads a broken call back as a perfectly good task.
///
/// Adding a field here without adding it to the package fails the test. Adding
/// it to neither means the writer cannot emit it at all.
const writableTaskFields = {
  'status',
  'priority',
  'scheduled',
  'due',
  'recurrence',
  'completed',
  'text',
  'properties',
};

/// Field names TyLog may write into a `tylog.note.with(...)` header.
/// Same contract as [writableTaskFields].
const writableNoteFields = {
  'id',
  'title',
  'kind',
  'date',
  'tags',
  'aliases',
  'project',
  'properties',
};

/// Inserts `name: value` just before a Typst call's closing paren — used for
/// both `#tylog.task(...)` fields and `tylog.note.with(...)` header fields.
///
/// The separator depends on how the call was written: the multi-line form ends
/// `,\n)` and needs none, while a single-line `#tylog.task(id: "x", text: "y")`
/// ends on a value and needs `, `. Getting this wrong produces
/// `priority: "normal"  clocked: (...)`, which is not valid Typst and silently
/// makes the whole task unreadable.
String _appendCallField(
  String callSource,
  String name,
  String value, {
  required Set<String> allowed,
}) {
  // A field the package does not declare is a hard Typst error, and the
  // fallback parser will happily read the broken call back as valid.
  assert(
    allowed.contains(name),
    'TyLog may not write "$name" — see writableTaskFields/writableNoteFields',
  );
  final close = callSource.lastIndexOf(')');
  if (close < 0) return callSource;
  var before = close - 1;
  while (before >= 0 && _isSpace(callSource.codeUnitAt(before))) {
    before--;
  }
  if (before < 0) return callSource;
  final previous = callSource[before];
  final multiline = callSource.substring(before + 1, close).contains('\n');
  if (previous == ',') {
    return callSource.replaceRange(
      before + 1,
      close,
      multiline ? '\n  $name: $value,\n' : ' $name: $value,',
    );
  }
  if (previous == '(') {
    return callSource.replaceRange(before + 1, close, '$name: $value,');
  }
  return callSource.replaceRange(before + 1, close, ', $name: $value,');
}

bool _isSpace(int code) => code == 32 || code == 9 || code == 10 || code == 13;

/// Appends `"key": value` to a Typst dictionary literal, supplying the comma
/// the previous entry may not have.
///
/// `("status": "read")` has no trailing comma, so a blind splice before the
/// closing paren yields `("status": "read""clocked": …)` — the same
/// missing-separator defect that made 406 task calls unreadable, one level
/// down.
String _appendDictEntry(String dict, String key, String rawValue) {
  final entry = '${typstString(key)}: $rawValue,';
  if (dict.trim() == '(:)' || dict.trim() == '()') return '($entry)';
  final close = dict.lastIndexOf(')');
  if (close < 0) return dict;
  var before = close - 1;
  while (before >= 0 && _space(dict.codeUnitAt(before))) {
    before--;
  }
  if (before < 0) return dict;
  final separator = dict[before] == ',' || dict[before] == '(' ? '' : ', ';
  return dict.replaceRange(before + 1, close, '$separator$entry');
}

/// Sets [id]'s tracked sessions, stored as `properties("clocked")`.
///
/// Duplicate `(start, end)` pairs collapse — the imported data holds 171 exact
/// repeats — and order is preserved otherwise.
String setTaskClocked(String source, String id, List<ClockEntry> entries) {
  final seen = <String>{};
  final unique = <ClockEntry>[];
  for (final entry in entries) {
    if (seen.add('${entry.start}|${entry.end}')) unique.add(entry);
  }
  final rendered = unique
      .map(
        (entry) =>
            '("${entry.start}", ${entry.end == null ? 'none' : '"${entry.end}"'})',
      )
      .join(', ');
  final call = _locateTaskCall(source, id);
  return source.replaceRange(
    call.start,
    call.end,
    // Also drops a legacy top-level `clocked:` argument, so a note written
    // before the data moved into properties migrates the first time it is
    // touched — and stops failing to compile on packages that never had that
    // argument.
    _removeTaskField(
      _setTaskProperty(
        call.source,
        'clocked',
        unique.isEmpty ? null : '($rendered,)',
      ),
      'clocked',
    ),
  );
}

/// Removes a top-level named argument from a task call, tidying the comma.
String _removeTaskField(String callSource, String name) {
  final field = _locateTopLevelField(callSource, name);
  if (field == null) return callSource;
  var end = field.end;
  while (end < callSource.length && _space(callSource.codeUnitAt(end))) {
    end++;
  }
  if (end < callSource.length && callSource[end] == ',') end++;
  var start = field.start;
  // If nothing follows, take the comma that preceded it instead.
  if (end >= callSource.length || callSource.substring(end).trim() == ')') {
    while (start > 0 && _space(callSource.codeUnitAt(start - 1))) {
      start--;
    }
    if (start > 0 && callSource[start - 1] == ',') start--;
  }
  return callSource.replaceRange(start, end, '');
}

/// Sets (or removes, when [rawValue] is null) `properties[key]` on a task
/// call, leaving every other argument byte-identical.
///
/// Time tracking lives here rather than in a named argument because a dict
/// tolerates keys an older Typst package has never seen, while an unknown
/// named argument is a hard compile error — and the package syncs between
/// devices that may be on different builds.
String _setTaskProperty(String callSource, String key, String? rawValue) {
  final field = _locateTopLevelField(callSource, 'properties');
  if (field == null) {
    if (rawValue == null) return callSource;
    return _appendCallField(
      callSource,
      'properties',
      '(${typstString(key)}: $rawValue,)',
      allowed: writableTaskFields,
    );
  }
  final dict = callSource.substring(field.valueStart, field.valueEnd);
  final entry = _locateDictEntry(dict, key);
  final String next;
  if (entry != null) {
    next = rawValue == null
        ? _stripDictEntry(dict, entry)
        : dict.replaceRange(
            entry.start,
            entry.end,
            '${typstString(key)}: $rawValue',
          );
  } else if (rawValue == null) {
    return callSource;
  } else {
    next = _appendDictEntry(dict, key, rawValue);
  }
  return callSource.replaceRange(field.valueStart, field.valueEnd, next);
}

/// Removes one entry from a dictionary literal, collapsing the comma it left.
String _stripDictEntry(String dict, _DictEntry entry) {
  final without = dict.replaceRange(entry.start, entry.end, '');
  final cleaned = without
      .replaceAll(RegExp(r',\s*,'), ',')
      .replaceAll(RegExp(r'\(\s*,'), '(');
  return cleaned.trim() == '()' ? '(:)' : cleaned;
}

/// Reads a task's sessions from the current source, including unsaved edits.
List<ClockEntry> taskClocked(String source, String id) =>
    parseClockedField(_locateTaskCall(source, id).source);

/// Opens a new tracked session on [id].
///
/// Closes the session currently running on this task first, so a task can
/// never accumulate two open clocks — Logseq's willingness to do exactly that
/// is how 107 of this vault's sessions ended with no end at all. Older strays
/// are left open for the flagging path rather than back-dated.
///
/// Stopping a clock running on a *different* task is the caller's job; see the
/// one-running-clock rule in the app layer.
String startTaskClock(String source, String id, String startIso) {
  final closed = stopTaskClock(source, id, startIso);
  final call = _locateTaskCall(closed, id);
  return setTaskClocked(closed, id, [
    ...parseClockedField(call.source),
    ClockEntry(start: startIso),
  ]);
}

/// Closes the session running on [id]. A no-op when nothing is running.
///
/// Only the most recent open session closes. Four tasks in the real vault
/// carry two, and closing both to one timestamp invented a second session of
/// identical length and double-counted the time.
String stopTaskClock(String source, String id, String endIso) {
  final call = _locateTaskCall(source, id);
  final entries = parseClockedField(call.source);
  final running = ClockEntry.latestRunning(entries);
  final index = running == null ? -1 : entries.lastIndexOf(running);
  if (index < 0) return source;
  final next = [...entries];
  next[index] = ClockEntry(start: next[index].start, end: endIso);
  return setTaskClocked(source, id, next);
}

String replaceTaskText(String source, String id, String text) {
  final call = _locateTaskCall(source, id);
  final quoted = '"${text.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
  final field = _locateTopLevelField(call.source, 'text');
  final replacement = field == null
      ? _appendCallField(
          call.source,
          'text',
          quoted,
          allowed: writableTaskFields,
        )
      : call.source.replaceRange(field.start, field.end, 'text: $quoted');
  return source.replaceRange(call.start, call.end, replacement);
}

/// Structurally reads the top-level string field [name] from a single call's
/// source (e.g. `#tylog.task(...)`). Returns the unescaped string value, or
/// null when the field is absent or its value isn't a double-quoted string
/// literal (e.g. `due: none`).
String? taskField(String callSource, String name) {
  final field = _locateTopLevelField(callSource, name);
  if (field == null) return null;
  final value = callSource.substring(field.valueStart, field.valueEnd);
  final quoted = RegExp(r'^"((?:\\.|[^"\\])*)"$').firstMatch(value);
  if (quoted == null) return null;
  return quoted
      .group(1)!
      .replaceAllMapped(RegExp(r'\\(.)'), (m) => m.group(1)!);
}

/// Locates the single `tylog.task(...)` call whose `id` field equals [id].
///
/// Throws a [StateError] if no task with that id exists, or if more than
/// one task shares the id (rather than silently mutating a random match).
TypstCall _locateTaskCall(String source, String id) {
  final matches = locateTypstCalls(
    source,
    names: const {'tylog.task'},
  ).where((call) => _field(call.source, 'id') == id).toList();
  if (matches.isEmpty) throw StateError('Task $id not found');
  if (matches.length > 1) {
    throw StateError('Duplicate task id "$id" (${matches.length} matches)');
  }
  return matches.single;
}

/// The `[start, end)` byte range of a `name: value` pair, plus the
/// `[valueStart, valueEnd)` range of just the value, as found at the top
/// level of a single Typst call's argument list (depth 1, i.e. directly
/// inside the call's outer parens, outside any string/comment/raw block and
/// outside any nested `(...)`/`[...]`).
class _TopLevelField {
  const _TopLevelField(this.start, this.end, this.valueStart, this.valueEnd);

  final int start;
  final int end;
  final int valueStart;
  final int valueEnd;
}

/// Structurally locates the top-level `name: value` field inside a single
/// call's source (e.g. `#tylog.task(...)`), reusing the same char-scanning
/// primitives as [locateTypstCalls] so strings, comments, raw blocks, and
/// nested parens/brackets can't be mistaken for a field boundary.
///
/// Returns null if the field isn't present at the top level of the call.
_TopLevelField? _locateTopLevelField(String callSource, String name) {
  final open = callSource.indexOf('(');
  if (open < 0) return null;
  var i = open + 1;
  const outerDepth = 1;
  var depth = outerDepth;
  while (i < callSource.length && depth > 0) {
    if (callSource.startsWith('//', i)) {
      final nl = callSource.indexOf('\n', i);
      i = nl < 0 ? callSource.length : nl;
      continue;
    }
    if (callSource.startsWith('/*', i)) {
      i = _skipBlockComment(callSource, i);
      continue;
    }
    final code = callSource.codeUnitAt(i);
    if (code == 34) {
      i = _skipString(callSource, i);
      continue;
    }
    if (code == 96) {
      i = _skipRaw(callSource, i);
      continue;
    }
    if (code == 40 || code == 91) {
      depth++;
      i++;
      continue;
    }
    if (code == 41 || code == 93) {
      depth--;
      i++;
      continue;
    }
    if (depth == outerDepth && _identifierStart(code)) {
      final identStart = i;
      while (i < callSource.length && _identifier(callSource.codeUnitAt(i))) {
        i++;
      }
      final ident = callSource.substring(identStart, i);
      var j = i;
      while (j < callSource.length && _space(callSource.codeUnitAt(j))) {
        j++;
      }
      if (ident != name ||
          j >= callSource.length ||
          callSource.codeUnitAt(j) != 58) {
        continue;
      }
      var k = j + 1;
      while (k < callSource.length && _space(callSource.codeUnitAt(k))) {
        k++;
      }
      final valueStart = k;
      var valueDepth = outerDepth;
      while (k < callSource.length) {
        if (callSource.startsWith('//', k)) {
          final nl = callSource.indexOf('\n', k);
          k = nl < 0 ? callSource.length : nl;
          continue;
        }
        if (callSource.startsWith('/*', k)) {
          k = _skipBlockComment(callSource, k);
          continue;
        }
        final vcode = callSource.codeUnitAt(k);
        if (vcode == 34) {
          k = _skipString(callSource, k);
          continue;
        }
        if (vcode == 96) {
          k = _skipRaw(callSource, k);
          continue;
        }
        if (vcode == 40 || vcode == 91) {
          valueDepth++;
          k++;
          continue;
        }
        if (vcode == 41 || vcode == 93) {
          if (valueDepth == outerDepth) break;
          valueDepth--;
          k++;
          continue;
        }
        if (vcode == 44 && valueDepth == outerDepth) break;
        k++;
      }
      var valueEnd = k;
      while (valueEnd > valueStart &&
          _space(callSource.codeUnitAt(valueEnd - 1))) {
        valueEnd--;
      }
      return _TopLevelField(identStart, valueEnd, valueStart, valueEnd);
    }
    i++;
  }
  return null;
}

bool _identifierStart(int code) =>
    code >= 65 && code <= 90 || code >= 97 && code <= 122 || code == 95;

