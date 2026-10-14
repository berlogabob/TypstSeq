import 'package:flutter/material.dart';

import '../constants.dart';

class LibraryToolbar extends StatelessWidget {
  const LibraryToolbar({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    this.searchKey,
    this.filtersKey,
    this.trailing = const [],
    this.chips = const [],
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final Key? searchKey;
  final Key? filtersKey;
  final List<Widget> trailing;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    // Phone landscape (< 480 dp tall) has no room for the roomy layout.
    final compact = MediaQuery.sizeOf(context).height < 480;
    final gap = compact ? 0.0 : kSpace8;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: kSpace16, vertical: gap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, _) => TextField(
                    key: searchKey,
                    controller: controller,
                    onChanged: onChanged,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: hintText,
                      prefixIcon: const Icon(Icons.search, size: kIconSmall),
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(
                          Radius.circular(kRadiusMedium),
                        ),
                      ),
                      suffixIcon: value.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              icon: const Icon(Icons.close, size: kIconSmall),
                              onPressed: () {
                                controller.clear();
                                onChanged('');
                              },
                            ),
                    ),
                  ),
                ),
              ),
              ...trailing,
            ],
          ),
          if (chips.isNotEmpty) ...[
            SizedBox(height: gap),
            SingleChildScrollView(
              key: filtersKey,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final chip in chips)
                    Padding(
                      padding: const EdgeInsets.only(right: kSpace8),
                      child: chip,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class LibraryFilterChip extends StatelessWidget {
  const LibraryFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.count,
    this.icon,
  });

  final String label;
  final int? count;
  final IconData? icon;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    avatar: icon == null ? null : Icon(icon, size: kIconSmall),
    label: Text(count == null ? label : '$label · $count'),
    selected: selected,
    onSelected: onSelected,
    materialTapTargetSize: MediaQuery.sizeOf(context).height < 480
        ? MaterialTapTargetSize.shrinkWrap
        : null,
  );
}
