import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:typst_flutter/typst_flutter.dart' as p2p;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('P2P transfer running; see logs')),
      ),
    ),
  );
  Socket? socket;
  try {
    if (Platform.isAndroid &&
        await const MethodChannel(
              'org.tylog.tylog/share',
            ).invokeMethod<bool>('isProfileTest') !=
            true) {
      throw StateError('Requires isolated .profiletest package');
    }
    await p2p.initP2pHarness();
    socket = await Socket.connect('127.0.0.1', 47993);
    final lines = StreamIterator(
      socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter()),
    );
    const sender = String.fromEnvironment('P2P_SENDER', defaultValue: 'mac');
    if (sender != 'mac' && sender != 'android') {
      throw StateError('P2P_SENDER must be mac or android');
    }
    final role = Platform.isAndroid ? 'android' : 'mac';
    socket.writeln(role);
    if (role != sender) {
      if (!await lines.moveNext()) throw StateError('Missing ticket');
      final dir = Directory(
        '${(await getApplicationSupportDirectory()).path}/p2p6-received',
      );
      final result = await p2p.receiveP2pFile(lines.current, dir.path);
      // ignore: avoid_print
      print(
        'P2P6_SUCCESS bytes=${result.bytes} elapsed_ms=${result.elapsedMs} destination=${dir.path}',
      );
      socket.writeln('received ${result.bytes} ${result.elapsedMs}');
    } else {
      const path = String.fromEnvironment('P2P_SOURCE');
      if (path.isEmpty) throw StateError('Missing snapshot path');
      final ticket = await p2p.startP2pFile(path);
      socket.writeln(ticket);
      if (!await lines.moveNext() || lines.current != 'received') {
        throw StateError('Receiver failed');
      }
      // ignore: avoid_print
      print('P2P6_SENDER_COMPLETE');
    }
  } catch (e, stack) {
    // ignore: avoid_print
    print('P2P6_ERROR $e\n$stack');
    socket?.writeln('error $e');
    await socket?.flush();
  } finally {
    socket?.destroy();
  }
}
