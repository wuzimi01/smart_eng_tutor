import 'package:flutter/material.dart';

/// 词条信息栏：收藏星星 + 单词（加大） + 考纲徽章（居左一行）
class WordInfoBar extends StatelessWidget {
  final String word;
  final bool isFavorited;
  final List<String> tags;
  final VoidCallback onToggleFavorite;

  const WordInfoBar({
    super.key,
    required this.word,
    required this.isFavorited,
    required this.tags,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Row(
        children: [
          // 收藏星星
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
          // 所查单词（加大加粗）
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
          // 考纲徽章（最多显示 3 个）
          for (final t in tags.take(3)) ...[
            const SizedBox(width: 6),
            ExamBadge(code: t),
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
