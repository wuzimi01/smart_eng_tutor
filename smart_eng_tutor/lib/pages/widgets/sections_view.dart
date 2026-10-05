import 'package:flutter/material.dart';
import '../../dictionary/section.dart';
import '../../settings/display_settings.dart';

/// 通用词典结果渲染：按设置过滤，按类型排版；未知类型忽略。
class SectionsView extends StatelessWidget {
  final int dictId;
  final List<ResultSection> sections;

  const SectionsView({super.key, required this.dictId, required this.sections});

  @override
  Widget build(BuildContext context) {
    final s = DisplaySettings.shared;
    final visible =
        sections.where((sec) => s.isVisible(dictId, sec.type)).toList();

    if (visible.isEmpty) {
      return const Text('（无显示内容）',
          style: TextStyle(color: Colors.grey));
    }

    // sortHint 小的靠前（徽章 -10 在释义 0 前）
    int hint(ResultSection s) => s.sortHint ?? 0;
    visible.sort((a, b) => hint(a).compareTo(hint(b)));

    // 徽章与其他 section 分开
    final tags = visible.where((sec) => sec.type == SectionType.tag).toList();
    final others =
        visible.where((sec) => sec.type != SectionType.tag).toList();

    if (others.isEmpty) {
      // 只有徽章：直接竖列
      return Wrap(
        direction: Axis.vertical,
        spacing: 4,
        runSpacing: 6,
        alignment: WrapAlignment.center,
        children: [
          for (final sec in tags)
            for (final code in (sec.data as TagData).codes)
              ExamBadge(code: code),
        ],
      );
    }

    // 左侧：释义等内容
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final sec in others) ...[
          if (sec.type == SectionType.translation)
            _TranslationView(sec.data as TranslationData),
          const SizedBox(height: 12),
        ],
      ],
    );

    // 无徽章：只返回内容
    if (tags.isEmpty) return content;

    // 有徽章：旧版布局 —— 左内容 + 右徽章竖列（纵贯）
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: content),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 64),
          child: Wrap(
            direction: Axis.vertical,
            spacing: 4,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              for (final sec in tags)
                for (final code in (sec.data as TagData).codes)
                  ExamBadge(code: code),
            ],
          ),
        ),
      ],
    );
  }
}

/// 考纲徽章：小圆角矩形，不同考纲不同颜色（原版照搬）
class ExamBadge extends StatelessWidget {
  final String code;
  const ExamBadge({super.key, required this.code});

  static const Map<String, String> _names = {
    'zk': '中考', 'gk': '高考', 'cet4': '四级', 'cet6': '六级',
    'ky': '考研', 'ielts': '雅思', 'toefl': '托福', 'gre': 'GRE',
  };
  static const Map<String, Color> _colors = {
    'zk': Colors.teal,
    'gk': Colors.indigo,
    'cet4': Colors.blue,
    'cet6': Colors.blueAccent,
    'ky': Colors.deepPurple,
    'ielts': Colors.green,
    'toefl': Colors.orange,
    'gre': Colors.red,
  };

  @override
  Widget build(BuildContext context) {
    final name = _names[code] ?? code;
    final color = _colors[code] ?? Colors.blueGrey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color, width: 1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        name,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}


class _TranslationView extends StatelessWidget {
  final TranslationData data;
  const _TranslationView(this.data);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in data.lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(line,
                style: const TextStyle(fontSize: 18, height: 1.6)),
          ),
      ],
    );
  }
}
