import 'package:flutter/material.dart';
import '../../dictionary/section.dart';
import '../../settings/display_settings.dart';
import 'sections_view.dart';

/// 词条内容统一视图：首页释义区、词库词条详情页共用同一 UI。
///
/// [word]      当前词条（大标题）
/// [sections]  词典查询结果
/// [chips]     词根候选（详情页传 null/空则不显示）
/// [selected]  当前选中的候选
/// [onChipTap] 点候选回调（首页传切换逻辑；详情页不传则 chips 只读）
class WordContentView extends StatelessWidget {
  final String word;
  final List<ResultSection> sections;
  final List<String>? chips;
  final String? selected;
  final ValueChanged<String>? onChipTap;

  const WordContentView({
    super.key,
    required this.word,
    required this.sections,
    this.chips,
    this.selected,
    this.onChipTap,
  });

  @override
  Widget build(BuildContext context) {
    // sections 里每个 section 自带 dictId，取第一个用于设置过滤
    final dictId = sections.isNotEmpty ? sections.first.dictId : 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 词头
        Text(word,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),

        // 词根候选 chips（有才显示）
        if (chips != null && chips!.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in chips!)
                ChoiceChip(
                  label: Text(c),
                  selected: c == selected,
                  onSelected: onChipTap != null ? (_) => onChipTap!(c) : null,
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],

        // 徽章 + 释义（受设置开关控制，监听即时刷新）
        AnimatedBuilder(
          animation: DisplaySettings.shared,
          builder: (_, _) =>
              SectionsView(dictId: dictId, sections: sections),
        ),
      ],
    );
  }
}
