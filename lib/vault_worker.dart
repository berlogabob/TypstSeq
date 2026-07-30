import 'dart:async';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:tylog_core/graph.dart';

import 'models.dart';
import 'pkms_registry.dart';
import 'scanner.dart';
import 'search_index.dart';
import 'task_scheduler.dart';
import 'vault.dart';
import 'vault_registry.dart';

/// The vault worker: everything expensive about indexing, on its own isolate.
///
/// Before this existed the scan loop, `sha256`, the per-note flutter_rust_bridge
/// serialisation, a ~2 MB `jsonEncode`, the search-index gzip and community
/// detection all ran on the root isolate, so a rebuild rendered no frames — see
/// the `% 32` yield in `tylog_core`'s scanner, which was the only thing letting
/// the UI breathe at all. Now the root isolate only sends commands and receives
/// finished data.
///
/// One command at a time, by design: [VaultWorkerClient.run] awaits a terminal
/// event before the next command goes out, which is what lets the worker keep a
/// single Typst engine and skip request-id plumbing entirely.
///
/// Native Typst genuinely works here — `RustLib.init()` is per-isolate over a
/// process-wide FRB handler, pinned by
/// `integration_test/vault_worker_native_test.dart`.

// ── Boot ─────────────────────────────────────────────────────────────────────

class VaultWorkerBoot {
  const VaultWorkerBoot({
    required this.entry,
    required this.commands,
    required this.events,
    this.deviceId,
    this.rootIsolateToken,
  });

  /// Plain data, and [VaultEntry.storage] rebuilds the backend from it — so the
  /// worker needs no storage descriptor of its own.
  final VaultEntry entry;
  final SendPort commands;
  final SendPort events;
  final String? deviceId;

  /// Null off Android. There, it is what lets the worker reach the SAF
  /// `MethodChannel` at all — every vault read goes through it.
  final RootIsolateToken? rootIsolateToken;
}

// ── Commands (UI → worker) ───────────────────────────────────────────────────

sealed class VaultWorkerCommand {
  const VaultWorkerCommand();
}

/// [force] discards the scan cache and re-compiles every note.
class RebuildIndexCommand extends VaultWorkerCommand {
  const RebuildIndexCommand({required this.stale, this.force = false});

  final bool force;

  /// The root isolate's pending [Vault.staleNotes] — the worker's own `Vault`
  /// never saw those saves.
  final Set<String> stale;
}

class CancelWorkCommand extends VaultWorkerCommand {
  const CancelWorkCommand();
}

class ShutdownCommand extends VaultWorkerCommand {
  const ShutdownCommand();
}

// ── Events (worker → UI) ─────────────────────────────────────────────────────

sealed class VaultWorkerEvent {
  const VaultWorkerEvent();
}

class IndexProgressEvent extends VaultWorkerEvent {
  const IndexProgressEvent(this.complete, this.total);

  final int complete;
  final int total;
}

/// The scan's own result. Sent before the slower passes below so the UI can
/// render notes while validation and the search index are still building — on
/// SAF vaults that build reads many files and must never gate Journal/Library.
class IndexBuiltEvent extends VaultWorkerEvent {
  const IndexBuiltEvent(this.index);

  final VaultIndex index;
}

class CommunitiesBuiltEvent extends VaultWorkerEvent {
  const CommunitiesBuiltEvent(this.communities);

  final CommunityMap communities;
}

class PkmsBuiltEvent extends VaultWorkerEvent {
  const PkmsBuiltEvent(this.report, this.search);

  final PkmsValidationReport report;
  final PkmsSearchIndex search;
}

class WorkDoneEvent extends VaultWorkerEvent {
  const WorkDoneEvent();
}

class WorkFailedEvent extends VaultWorkerEvent {
  const WorkFailedEvent(this.message, {this.cancelled = false});

  final String message;
  final bool cancelled;
}

// ── Worker isolate ───────────────────────────────────────────────────────────

@pragma('vm:entry-point')
Future<void> vaultWorkerMain(VaultWorkerBoot boot) async {
  final token = boot.rootIsolateToken;
  if (token != null) {
    // Must precede any platform-channel use, i.e. any SAF read.
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  }
  final worker = _VaultWorker(boot);
  await worker.serve();
}

class _VaultWorker {
  _VaultWorker(this._boot) : _vault = Vault.withStorage(_boot.entry.storage);

  final VaultWorkerBoot _boot;
  final Vault _vault;
  final ReceivePort _commands = ReceivePort();
  final Completer<void> _stopped = Completer<void>();

  /// Kept across commands: `FlutterTypstInspector.create()` allocates a native
  /// engine, and re-creating one per incremental refresh would undo the point.
  FlutterTypstInspector? _inspector;
  bool _cancelled = false;
  bool _busy = false;

  Future<void> serve() async {
    _boot.commands.send(_commands.sendPort);
    // Sync listener on purpose: a Cancel arriving mid-scan has to be observed
    // *while* the scan runs, and it only can be if handling it never awaits.
    // The scanner's per-32-note yield is what gives this listener its turn.
    _commands.listen((message) {
      switch (message) {
        case CancelWorkCommand():
          _cancelled = true;
        case ShutdownCommand():
          _cancelled = true;
          if (!_stopped.isCompleted) _stopped.complete();
        case final RebuildIndexCommand command:
          if (_busy) {
            _send(const WorkFailedEvent('worker busy'));
            return;
          }
          unawaited(_rebuild(command));
        default:
          _send(WorkFailedEvent('unknown command: $message'));
      }
    });
    await _stopped.future;
    _commands.close();
    _inspector?.dispose();
  }

  void _send(VaultWorkerEvent event) => _boot.events.send(event);

  Future<void> _rebuild(RebuildIndexCommand command) async {
    _busy = true;
    _cancelled = false;
    try {
      _inspector ??= await _createInspector();
      final index = await _vault.rebuildIndex(
        inspector: _inspector,
        force: command.force,
        deviceId: _boot.deviceId,
        stale: command.stale,
        isCancelled: () => _cancelled,
        // Throttled here rather than on the far side so the ticks the UI would
        // have discarded never cross the port at all.
        onProgress: (complete, total) {
          if (complete % 100 != 0 && complete != total) return;
          _send(IndexProgressEvent(complete, total));
        },
      );
      _send(IndexBuiltEvent(index));

      // Derived state is an optimization; the UI degrades to null on failure.
      try {
        _send(CommunitiesBuiltEvent(computeCommunities(index)));
      } catch (_) {}

      final report = await validatePkmsStorage(_vault.storage, index);
      // Unparseable task recurrence rules — rrule lives in the app layer, not
      // tylog_core — into the same Problems report the UI already shows.
      report.problems.addAll(validateTaskRecurrences(index.tasks));
      final cached = await PkmsSearchIndex.loadStorage(
        _vault.storage,
        Vault.searchIndexPath,
      );
      final search = await PkmsSearchIndex.buildStorage(
        _vault.storage,
        index,
        previous: cached,
      );
      await search.saveStorage(_vault.storage, Vault.searchIndexPath);
      _send(PkmsBuiltEvent(report, search));
      _send(const WorkDoneEvent());
    } on IndexBuildCancelled {
      _send(const WorkFailedEvent('cancelled', cancelled: true));
    } catch (error) {
      _send(WorkFailedEvent('$error'));
    } finally {
      _busy = false;
    }
  }

  Future<FlutterTypstInspector?> _createInspector() async {
    try {
      return await FlutterTypstInspector.create();
    } catch (_) {
      // Native Typst is optional; the scanner falls back to source parsing.
      return null;
    }
  }
}

// ── UI-side handle ───────────────────────────────────────────────────────────

class VaultWorkerClient {
  VaultWorkerClient._(this._isolate, this._commands, this._events, this._errors);

  final Isolate _isolate;
  final SendPort _commands;
  final ReceivePort _events;
  final ReceivePort _errors;

  /// A `ReceivePort` is single-subscription, and every rebuild after the first
  /// would need a second `listen` on it. So it is listened to exactly once, here,
  /// and each [run] subscribes to this instead.
  late final Stream<VaultWorkerEvent> _stream = _relay.stream;
  final StreamController<VaultWorkerEvent> _relay =
      StreamController<VaultWorkerEvent>.broadcast();

  void _startRelay() {
    _events.listen((message) {
      if (message is VaultWorkerEvent && !_relay.isClosed) _relay.add(message);
    });
    // A worker that dies mid-command (a Rust panic aborts the whole process, but
    // a Dart-level crash or a kill does not) would otherwise hang the caller
    // forever. `onExit` also lands here, with a null message.
    _errors.listen((message) {
      if (!_relay.isClosed) {
        _relay.add(WorkFailedEvent('worker stopped: $message'));
      }
    });
  }

  static Future<VaultWorkerClient> spawn({
    required VaultEntry entry,
    String? deviceId,
  }) async {
    final events = ReceivePort('tylog-vault-worker-events');
    final errors = ReceivePort('tylog-vault-worker-errors');
    final handshake = ReceivePort('tylog-vault-worker-handshake');
    final isolate = await Isolate.spawn(
      vaultWorkerMain,
      VaultWorkerBoot(
        entry: entry,
        commands: handshake.sendPort,
        events: events.sendPort,
        deviceId: deviceId,
        rootIsolateToken: RootIsolateToken.instance,
      ),
      onError: errors.sendPort,
      onExit: errors.sendPort,
      debugName: 'tylog-vault-worker',
    );
    final commands = await handshake.first as SendPort;
    handshake.close();
    return VaultWorkerClient._(isolate, commands, events, errors)
      .._startRelay();
  }

  /// Runs one command, yielding its events until a terminal one.
  ///
  /// Single-flight, and enforced rather than assumed: every [run] subscribes to
  /// the same relay, so two overlapping runs would each receive the *other's*
  /// events and both mis-report. Throwing here turns that into an obvious bug at
  /// the call site instead of silent cross-talk.
  Stream<VaultWorkerEvent> run(VaultWorkerCommand command) {
    if (_running) {
      throw StateError('VaultWorkerClient.run is single-flight; a command is '
          'already in flight');
    }
    _running = true;
    // Buffered (non-broadcast) on purpose: the command goes out before the
    // caller has listened, so early events must queue rather than be dropped.
    final out = StreamController<VaultWorkerEvent>();
    late final StreamSubscription<VaultWorkerEvent> events;
    events = _stream.listen((event) {
      out.add(event);
      if (event is WorkDoneEvent || event is WorkFailedEvent) {
        _running = false;
        unawaited(events.cancel());
        unawaited(out.close());
      }
    });
    _commands.send(command);
    return out.stream;
  }

  bool _running = false;

  /// Cooperative — observed at the scanner's per-32-note yield.
  void cancel() => _commands.send(const CancelWorkCommand());

  Future<void> dispose() async {
    _commands.send(const ShutdownCommand());
    // Don't wait on a wedged native compile to notice the shutdown: the engine
    // holds no vault lock we need back, and nobody is reading its events now.
    _isolate.kill(priority: Isolate.beforeNextEvent);
    _events.close();
    _errors.close();
    await _relay.close();
  }
}
