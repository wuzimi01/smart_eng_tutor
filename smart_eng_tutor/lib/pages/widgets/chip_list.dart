import 'package:flutter/material.dart';

/// 候选词横排列表（纯展示组件）
class ChipList extends StatelessWidget {
  final List<String> chips;
  final String? selectedWord;
  final ValueChanged<String> onSelect;

  const ChipList({
    super.key,
    required this.chips,
    required this.selectedWord,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final word = chips[index];
          final selected = word == selectedWord;
          return InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => onSelect(word),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.blue
                    : Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: Text(
                word,
                style: TextStyle(
                  fontSize: 16,
                  color: selected ? Colors.white : Colors.blue,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
