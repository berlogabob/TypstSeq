import 'package:flutter/material.dart';
import '../constants.dart';
/// One Settings page: a title bar with back arrow and a scrolling list.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: ListView(
      padding: const EdgeInsets.symmetric(vertical: kSpace8),
      children: children,
    ),
  );
}
