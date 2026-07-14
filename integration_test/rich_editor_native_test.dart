import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog/controlled_editor.dart';
import 'package:tylog/rich_editor.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android taps every Magic action and keeps IME input alive', (
    tester,
  ) async {
    final key = GlobalKey<_NativeMagicHarnessState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: _NativeMagicHarness(key: key)),
      ),
    );
    await tester.pumpAndSettle();

    for (final action in MagicAction.values) {
      final harness = key.currentState!;
      harness.reset();
      await tester.pump();

      final field = find.byKey(const Key('rich-journal-editor'));
      await tester.tap(field);
      harness.controller.selection = TextSelection.collapsed(
        offset: harness.controller.text.length,
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Insert'));
      await tester.pumpAndSettle();

      final choice = find.byKey(Key('native-magic-${action.name}'));
      await tester.scrollUntilVisible(
        choice,
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.ensureVisible(choice);
      await tester.pumpAndSettle();
      await tester.tap(choice);
      await tester.pumpAndSettle();

      final textField = tester.widget<TextField>(field);
      expect(textField.focusNode!.hasFocus, isTrue, reason: action.name);
      final sentinel = '|тест-${action.name}|';
      _typeComposing(tester, harness.controller, sentinel);
      await tester.pump();
      tester.testTextInput.updateEditingValue(
        harness.controller.value.copyWith(composing: TextRange.empty),
      );
      await tester.pump();

      expect(harness.controller.text, contains(sentinel));
      expect(
        harness.errors,
        isEmpty,
        reason:
            '${action.name}\n${harness.source}\n${harness.controller.value}',
      );
      expect(
        TyLogDocument.parse(harness.source).toSource(),
        harness.source,
        reason: action.name,
      );
      expect(harness.source, contains(_sourceMarker(action)));
    }
  });
}

const _initialSource =
    '''#show: tylog.note.with(id: "test", title: "Test", kind: "note")
seed
''';

class _NativeMagicHarness extends StatefulWidget {
  const _NativeMagicHarness({super.key});

  @override
  State<_NativeMagicHarness> createState() => _NativeMagicHarnessState();
}

class _NativeMagicHarnessState extends State<_NativeMagicHarness> {
  final errors = <Object>[];
  late String source = _initialSource;
  late final controller = TyLogEditingController(
    source: source,
    onSourceChanged: (value) => source = value,
    onError: errors.add,
    onProtectedTap: (_) {},
  );

  void reset() {
    errors.clear();
    source = _initialSource;
    controller.loadSource(source);
  }

  Future<void> _showMagicMenu() async {
    final request = await showModalBottomSheet<MagicRequest>(
      context: context,
      builder: (context) => ListView(
        children: [
          for (final action in MagicAction.values)
            ListTile(
              key: Key('native-magic-${action.name}'),
              title: Text(action == MagicAction.heading ? 'H1' : action.name),
              onTap: () => Navigator.pop(context, _requestFor(action)),
            ),
        ],
      ),
    );
    if (request != null && request.action != MagicAction.report) {
      controller.applyMagic(request);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      TyLogRichEditor(controller: controller, onInsert: _showMagicMenu);
}

MagicRequest _requestFor(MagicAction action) => switch (action) {
  MagicAction.noteLink => const MagicRequest(
    action: MagicAction.noteLink,
    id: 'native-note',
    value: 'Native note',
  ),
  MagicAction.mention => const MagicRequest(
    action: MagicAction.mention,
    id: 'native-person',
    value: 'Ada',
  ),
  MagicAction.tag => const MagicRequest(
    action: MagicAction.tag,
    value: 'android',
  ),
  MagicAction.task => const MagicRequest(
    action: MagicAction.task,
    id: 'native-task',
    value: 'Native task',
    due: '2026-07-14',
  ),
  MagicAction.date => const MagicRequest(
    action: MagicAction.date,
    value: '2026-07-14',
  ),
  MagicAction.project => const MagicRequest(
    action: MagicAction.project,
    id: 'native-project',
    value: 'Native project',
  ),
  MagicAction.citation => const MagicRequest(
    action: MagicAction.citation,
    value: 'smith2026',
  ),
  MagicAction.attachment => const MagicRequest(
    action: MagicAction.attachment,
    value: 'assets/native.png',
    kind: 'image',
  ),
  MagicAction.heading => const MagicRequest(action: MagicAction.heading),
  MagicAction.bold => const MagicRequest(action: MagicAction.bold),
  MagicAction.italic => const MagicRequest(action: MagicAction.italic),
  MagicAction.table => const MagicRequest(
    action: MagicAction.table,
    rows: 2,
    columns: 3,
  ),
  MagicAction.equation => const MagicRequest(
    action: MagicAction.equation,
    value: 'x + 1',
  ),
  MagicAction.report => const MagicRequest(action: MagicAction.report),
};

void _typeComposing(
  WidgetTester tester,
  TyLogEditingController controller,
  String text,
) {
  final selection = controller.selection;
  final start = selection.isValid ? selection.start : controller.text.length;
  final end = selection.isValid ? selection.end : controller.text.length;
  final next = controller.text.replaceRange(start, end, text);
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + text.length),
      composing: TextRange(start: start, end: start + text.length),
    ),
  );
}

String _sourceMarker(MagicAction action) => switch (action) {
  MagicAction.noteLink || MagicAction.project => '#tylog.ref-note(',
  MagicAction.mention => r'\@Ada',
  MagicAction.tag => '#tylog.tag(',
  MagicAction.task => '#tylog.task(',
  MagicAction.date => '#tylog.date-ref(',
  MagicAction.citation => '@smith2026',
  MagicAction.attachment => '#tylog.attachment(',
  MagicAction.heading => '= |тест-heading|',
  MagicAction.bold => '#strong[',
  MagicAction.italic => '#emph[',
  MagicAction.table => '#table(columns: 3',
  MagicAction.equation => r'$x + 1$',
  MagicAction.report => '|тест-report|',
};
