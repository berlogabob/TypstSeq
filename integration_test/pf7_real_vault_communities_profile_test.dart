import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog/workspace_controller.dart';
import 'package:tylog_core/tylog_core.dart' show CommunityMap;
import 'package:tylog/vault.dart';
import 'package:tylog/vault_registry.dart';
import 'package:tylog/vault_storage.dart';
import 'package:tylog/voronoi_view.dart';

// On P30, run with:
// flutter drive --no-pub --no-dds --profile -PtylogProfileSuffix=.profiletest \
//   -d XPH0219904001750 --driver=test_driver/integration_test.dart \
//   --target=integration_test/pf7_real_vault_communities_profile_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'PF7 real-vault community view cold and repeated opens',
    (tester) async {
      final registry = await VaultRegistry.load();
      final entry = registry.entries.isEmpty
          ? await () async {
              final selection = await AndroidTreeVaultStorage.pick();
              expect(
                selection,
                isNotNull,
                reason: 'select the exact real-vault SAF folder in the picker',
              );
              final selected = await registry.addTree(selection!);
              await registry.select(selected);
              return selected;
            }()
          : registry.active;
      expect(
        entry.storageKind,
        'android-tree',
        reason:
            'select the exact real-vault SAF folder in this .profiletest app',
      );
      final storage = entry.storage as AndroidTreeVaultStorage;
      expect(
        await storage.hasAccess(),
        isTrue,
        reason:
            'grant this .profiletest app access to the exact real-vault folder',
      );

      // Read the existing app-owned index only. This harness does not rebuild,
      // sync, or write anything into the user's vault.
      final vault = Vault.withStorage(storage);
      final index = await vault.loadIndex();
      expect(index, isNotNull, reason: 'the real vault has no saved index yet');
      expect(index!.notesByPath, isNotEmpty);

      final frames = <FrameTiming>[];
      void collectFrames(List<FrameTiming> values) => frames.addAll(values);
      SchedulerBinding.instance.addTimingsCallback(collectFrames);
      addTearDown(
        () => SchedulerBinding.instance.removeTimingsCallback(collectFrames),
      );

      Widget view(CommunityMap? communities, int revision) => MaterialApp(
        home: Scaffold(
          body: VoronoiView(
            index: index,
            communities: communities,
            indexRevision: revision,
            onOpenPath: (_) {},
          ),
        ),
      );

      Future<void> waitForLayout() async {
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        while (find.byKey(const Key('voronoi-fit')).evaluate().isEmpty &&
            DateTime.now().isBefore(deadline)) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        expect(find.byKey(const Key('voronoi-fit')), findsOneWidget);
      }

      List<int> frameUs(int start) =>
          frames
              .skip(start)
              .map((timing) => timing.totalSpan.inMicroseconds)
              .toList()
            ..sort();

      final coldDerive = Stopwatch()..start();
      final communities = await compute(computeCommunitiesIsolate, index);
      coldDerive.stop();

      final coldFrameStart = frames.length;
      final coldOpen = Stopwatch()..start();
      await tester.pumpWidget(view(communities, 1));
      await waitForLayout();
      coldOpen.stop();
      await tester.pump(const Duration(milliseconds: 100));
      final coldFrames = frameUs(coldFrameStart);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      final repeatFrameStart = frames.length;
      final repeatOpen = Stopwatch()..start();
      await tester.pumpWidget(view(communities, 1));
      await waitForLayout();
      repeatOpen.stop();
      await tester.pump(const Duration(milliseconds: 100));
      final repeatFrames = frameUs(repeatFrameStart);

      String frameSummary(List<int> values) {
        int percentile(double p) =>
            values.isEmpty ? 0 : values[((values.length - 1) * p).round()];
        return 'frames=${values.length} p95Us=${percentile(.95)} '
            'p99Us=${percentile(.99)} maxUs=${values.isEmpty ? 0 : values.last}';
      }

      // ignore: avoid_print
      print(
        'PF7_REAL_VAULT notes=${index.notesByPath.length} '
        'communities=${communities.clusterOrder.length} '
        'coldDeriveMs=${coldDerive.elapsedMilliseconds} '
        'coldOpenMs=${coldOpen.elapsedMilliseconds} '
        '${frameSummary(coldFrames)} '
        'repeatOpenMs=${repeatOpen.elapsedMilliseconds} '
        '${frameSummary(repeatFrames)}',
      );
    },
    skip: !Platform.isAndroid,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
