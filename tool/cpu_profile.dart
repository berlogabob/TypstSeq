// ignore_for_file: depend_on_referenced_packages

// Samples the CPU of the main isolate of a profile-mode app for N seconds and
// prints the hottest functions by self time (what the UI thread was doing).
// usage: dart run tool/cpu_profile.dart <vm-service-ws-or-http-url> [seconds=30]
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

Future<void> main(List<String> args) async {
  var url = args.first.replaceFirst('http', 'ws');
  if (!url.endsWith('/ws')) url = '${url.endsWith('/') ? url : '$url/'}ws';
  final seconds = args.length > 1 ? int.parse(args[1]) : 30;
  final service = await vmServiceConnectUri(url);
  final vm = await service.getVM();
  final isolate = vm.isolates!.firstWhere((i) => i.name == 'main');
  await service.clearCpuSamples(isolate.id!);
  stdout.writeln('sampling main isolate for ${seconds}s ...');
  await Future<void>.delayed(Duration(seconds: seconds));
  final samples = await service.getCpuSamples(isolate.id!, 0, 1 << 62);
  final self = <int, int>{};
  final inclusive = <int, int>{};
  for (final s in samples.samples!) {
    final stack = s.stack!;
    if (stack.isEmpty) continue;
    self[stack.first] = (self[stack.first] ?? 0) + 1;
    for (final f in stack.toSet()) {
      inclusive[f] = (inclusive[f] ?? 0) + 1;
    }
  }
  String name(int i) {
    final f = samples.functions![i];
    final fn = f.function;
    final owner = fn is FuncRef ? fn.owner : null;
    final cls = owner is ClassRef ? '${owner.name}.' : '';
    final lib = (f.resolvedUrl ?? '').split('/').last;
    return '$cls${fn is FuncRef ? fn.name : fn} ($lib)';
  }
  final total = samples.samples!.length;
  stdout.writeln('total samples: $total (period ${samples.samplePeriod}us)');
  stdout.writeln('--- self time');
  for (final e in (self.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(22)) {
    stdout.writeln('${(100 * e.value / total).toStringAsFixed(1).padLeft(5)}%  ${name(e.key)}');
  }
  stdout.writeln('--- inclusive (callers)');
  for (final e in (inclusive.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).where((e) { final n = name(e.key); return !n.contains("binding.dart") && !n.contains("future_impl") && !n.contains("schedule_microtask") && !n.contains("hooks.dart") && !n.contains("framework.dart") && !n.contains("timer_impl") && !n.contains("isolate_patch") && !n.contains("eventhandler") && !n.contains("[NativeFunction"); }).take(40)) {
    stdout.writeln('${(100 * e.value / total).toStringAsFixed(1).padLeft(5)}%  ${name(e.key)}');
  }
  await service.dispose();
}
