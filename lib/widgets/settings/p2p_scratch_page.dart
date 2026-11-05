import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class P2pScratchPage extends StatefulWidget {
  const P2pScratchPage({
    super.key,
    required this.start,
    required this.receive,
    this.startSnapshot,
    this.receiveSnapshot,
  });
  final Future<String> Function()? startSnapshot;
  final Future<String> Function(String)? receiveSnapshot;
  final Future<String> Function(String) start;
  final Future<String> Function(String) receive;
  @override
  State<P2pScratchPage> createState() => _P2pScratchPageState();
}

class _P2pScratchPageState extends State<P2pScratchPage> {
  final text = TextEditingController();
  final ticket = TextEditingController();
  String result = '';
  bool busy = false;

  @override
  void dispose() {
    text.dispose();
    ticket.dispose();
    super.dispose();
  }

  Future<void> run(Future<String> Function() action) async {
    setState(() {
      busy = true;
      result = '';
    });
    try {
      final value = await action();
      if (mounted) setState(() => result = value);
    } catch (error) {
      if (mounted) setState(() => result = 'Error: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('P2P scratch experiment')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Tickets grant access to scratch text or a generated synthetic folder for five minutes. Do not paste private data.',
        ),
        TextField(
          key: const ValueKey('scratch-text'),
          controller: text,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Scratch text to share'),
        ),
        ElevatedButton(
          onPressed: busy ? null : () => run(() => widget.start(text.text)),
          child: const Text('Create ticket'),
        ),
        if (widget.startSnapshot != null)
          ElevatedButton(
            onPressed: busy ? null : () => run(widget.startSnapshot!),
            child: const Text('Create synthetic folder ticket'),
          ),
        TextField(
          key: const ValueKey('scratch-ticket'),
          controller: ticket,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Peer ticket'),
        ),
        ElevatedButton(
          onPressed: busy ? null : () => run(() => widget.receive(ticket.text)),
          child: const Text('Receive'),
        ),
        if (widget.receiveSnapshot != null)
          ElevatedButton(
            onPressed: busy
                ? null
                : () => run(() => widget.receiveSnapshot!(ticket.text)),
            child: const Text('Receive synthetic folder'),
          ),
        if (busy) const CircularProgressIndicator(),
        if (result.isNotEmpty) SelectableText(result),
        if (result.isNotEmpty)
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: result)),
            child: const Text('Copy result'),
          ),
      ],
    ),
  );
}
