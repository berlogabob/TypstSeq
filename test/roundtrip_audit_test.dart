@Tags(['audit'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/rich_editor.dart';

/// Editing+parsing systemic audit harness (report-only; always passes).
/// Run: `flutter test test/roundtrip_audit_test.dart --tags audit -r expanded`.

String _esc(String s) => s.replaceAll('\n', '↵');

String _firstDiff(String a, String b) {
  final n = a.length < b.length ? a.length : b.length;
  var i = 0;
  while (i < n && a[i] == b[i]) {
    i++;
  }
  return 'len ${a.length}->${b.length} @$i: '
      'exp="${_esc(a.substring((i - 8).clamp(0, i), (i + 8).clamp(0, a.length)))}" '
      'got="${_esc(b.substring((i - 8).clamp(0, i), (i + 8).clamp(0, b.length)))}"';
}

/// Block start offsets in visibleText, mirroring TyLogDocument._ranges
/// (blocks spaced by exactly two newlines).
List<({int start, int end, TyLogBlockStyle style})> _ranges(TyLogDocument d) {
  final out = <({int start, int end, TyLogBlockStyle style})>[];
  var cursor = 0;
  for (final b in d.blocks) {
    final end = cursor + b.visibleText.length;
    out.add((start: cursor, end: end, style: b.style));
    cursor = end + 2;
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final synthetic = <String, String>{
    'para-before-block(+72)': '- a\n- b\n\ntqwe\n\nDo we?\n\\- x',
    'para-after-list(+74)': '- list 01\n- list 02\n\nt\n\n',
    'trailing-blank': 'hello\n\n',
    'double-blanks': 'a\n\n\n\nb',
    'leading-dash-para': r'\- not a list',
    'raw-dash-list': '- one\n- two\n\nafter',
    'numbered-list': '+ one\n+ two',
    'adjacent-lists': '- a\n\n- b',
    'heading-then-para': '= Title\n\nbody',
    'task-then-para': '#tylog.task(id: "t1", text: "Ship it")\n\nbody',
    'equation-then-para': r'$x^2$' '\n\nbody',
    'inline-mix': '#strong[b] #emph[i] #strike[s]\n\nplain',
    'para-para': 'alpha\n\nbeta',
    'three-paras': 'one\n\ntwo\n\nthree',
  };

  final identityFail = <String>[]; // Invariant 1
  // Invariant 2: revert -> bucket by "op @ boundary : prevStyle>curStyle"
  final editByPattern = <String, int>{};
  final editExample = <String, String>{};
  var editTried = 0;
  var editRevert = 0;

  void checkIdentity(String label, String source) {
    try {
      final d = TyLogDocument.parse(source);
      final round =
          TyLogDocument.parse(d.toSource(validate: false)).visibleText;
      if (round != d.visibleText) {
        identityFail.add('$label :: ${_firstDiff(d.visibleText, round)}');
      }
    } catch (e) {
      identityFail.add('$label :: THREW $e');
    }
  }

  // Realistic user ops, per block: Enter at block END, Backspace at block
  // START, type-x at block END, type-x at block START-of-text.
  void checkEdits(String label, String source) {
    final errors = <Object>[];
    TyLogEditingController make() => TyLogEditingController(
          source: source,
          onSourceChanged: (_) {},
          onError: errors.add,
          onProtectedTap: (_) {},
        );
    final probe = make();
    final ranges = _ranges(probe.document);
    final len = probe.text.length;
    probe.dispose();

    void run(String op, int at, String label2) {
      if (at < 0 || at > len) return;
      editTried++;
      errors.clear();
      final c = make();
      try {
        final t = c.text;
        c.selection = TextSelection.collapsed(offset: at);
        switch (op) {
          case 'enter':
            c.value = TextEditingValue(
              text: t.replaceRange(at, at, '\n'),
              selection: TextSelection.collapsed(offset: at + 1),
            );
          case 'backspace':
            if (at == 0) return;
            c.value = TextEditingValue(
              text: t.replaceRange(at - 1, at, ''),
              selection: TextSelection.collapsed(offset: at - 1),
            );
          case 'type':
            c.value = TextEditingValue(
              text: t.replaceRange(at, at, 'x'),
              selection: TextSelection.collapsed(offset: at + 1),
            );
        }
        if (errors.isNotEmpty) {
          editRevert++;
          // Is the edit adjacent to a protected node (￼ = U+FFFC)?
          final adj = (at > 0 && t[at - 1] == '￼') ||
              (at < t.length && t[at] == '￼');
          final err = '${errors.first}'.contains('protected')
              ? 'crossed-protected'
              : 'validate-fail';
          final bucket = '${op.padRight(9)} | '
              '${adj ? 'PROTECTED-adjacent' : 'plain-boundary  '} | $err';
          editByPattern.update(bucket, (v) => v + 1, ifAbsent: () => 1);
          editExample.putIfAbsent(bucket, () {
            final lo = (at - 20).clamp(0, t.length);
            return '$label2  ctx="${_esc(t.substring(lo, (at + 8).clamp(0, t.length)))}"';
          });
        }
      } catch (_) {
      } finally {
        c.dispose();
      }
    }

    for (var i = 0; i < ranges.length; i++) {
      final r = ranges[i];
      final prev = i > 0 ? ranges[i - 1].style.name : '∅';
      final cur = r.style.name;
      // Enter at end of this block (before the next block boundary).
      run('enter', r.end, 'enter @block-end : $cur>${i + 1 < ranges.length ? ranges[i + 1].style.name : '∅'}');
      // Backspace at the start of this block (deletes the separator above).
      if (i > 0) run('backspace', r.start, 'backspace @block-start : $prev>$cur');
      // Type at end / start of this block.
      run('type', r.end, 'type @block-end : $cur');
      run('type', r.start, 'type @block-start : $cur');
    }
  }

  test('AUDIT: serialize/parse identity + edit safety', () {
    synthetic.forEach((label, src) {
      checkIdentity('syn:$label', src);
      checkEdits('syn:$label', src);
    });

    // Real-vault sweep is opt-in (slow + machine-specific): run with
    // `AUDIT_VAULT=1 flutter test test/roundtrip_audit_test.dart --tags audit`.
    final vault =
        Directory('${Platform.environment['HOME']}/Nextcloud/TyLogVault');
    var vaultFiles = 0;
    var editSample = 0;
    if (Platform.environment['AUDIT_VAULT'] == '1' && vault.existsSync()) {
      final files = vault
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) =>
              f.path.endsWith('.typ') && !f.path.contains('/_system/'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final f in files) {
        final src = f.readAsStringSync();
        final id = f.path.replaceAll('${vault.path}/', '');
        checkIdentity('vault:$id', src);
        vaultFiles++;
        if (vaultFiles % 25 == 0) {
          checkEdits('vault:$id', src);
          editSample++;
        }
      }
    }

    final patterns = editByPattern.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // ignore: avoid_print
    print('\n================ AUDIT REPORT ================');
    // ignore: avoid_print
    print('vault notes: $vaultFiles (identity) / $editSample (edit-driven)');
    // ignore: avoid_print
    print('INVARIANT 1 serialize/parse identity failures: ${identityFail.length}');
    for (final f in identityFail.take(15)) {
      // ignore: avoid_print
      print('   ! $f');
    }
    // ignore: avoid_print
    print('\nINVARIANT 2 edit-safety: $editRevert reverts / $editTried edits '
        '(${(100 * editRevert / editTried).toStringAsFixed(1)}%) across '
        '${patterns.length} distinct patterns:');
    for (final e in patterns) {
      // ignore: avoid_print
      print('   [${e.value.toString().padLeft(4)}]  ${e.key}');
      // ignore: avoid_print
      print('          e.g. "${editExample[e.key]}"');
    }
    // ignore: avoid_print
    print('============== END AUDIT REPORT ==============\n');

    // Regression gate (opt-in): after the Option-1 accept-and-resync fix the
    // boundary-edit revert rate must stay near zero. Run with
    // `AUDIT_ASSERT=1 flutter test test/roundtrip_audit_test.dart --tags audit`
    // (add AUDIT_VAULT=1 for the full corpus). Identity must always be perfect.
    expect(identityFail, isEmpty, reason: 'serialize/parse must be identity');
    if (Platform.environment['AUDIT_ASSERT'] == '1') {
      final rate = editTried == 0 ? 0.0 : editRevert / editTried;
      expect(rate, lessThan(0.01),
          reason: 'boundary-edit revert rate regressed to '
              '${(100 * rate).toStringAsFixed(1)}%');
    }
  });
}
