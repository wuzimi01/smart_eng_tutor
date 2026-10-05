import 'package:flutter/material.dart';

/// 词条结果区：左侧（信息栏 + 释义），右侧（考纲徽章竖列，纵贯两区）
class WordInfoBar extends StatelessWidget {
  final String word;
  final bool isFavorited;
  final List<String> tags;
  final String displayText;
  final VoidCallback onToggleFavorite;

  const WordInfoBar({
    super.key,
    required this.word,
    required this.isFavorited,
    required this.tags,
    required this.displayText,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- 左侧：信息栏（星星+单词）+ 释义 ----
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 信息栏：星星 + 单词
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        isFavorited ? Icons.star : Icons.star_border,
                        color: isFavorited ? Colors.amber : Colors.grey,
                      ),
                      iconSize: 26,
                      visualDensity: VisualDensity.compact,
                      tooltip: isFavorited ? '取消收藏' : '收藏到词库',
                      onPressed: onToggleFavorite,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        word,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
                // 释义（居中）
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Center(
                    child: Text(
                      displayText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 24, color: Colors.black87),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ---- 右侧：考纲徽章竖列（纵贯信息区+释义区） ----
          if (tags.isNotEmpty) ...[
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 64), // 一列徽章的宽度
              child: Wrap(
                direction: Axis.vertical,
                spacing: 4,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [for (final t in tags) ExamBadge(code: t)],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 考纲徽章：小圆角矩形，不同考纲不同颜色
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
