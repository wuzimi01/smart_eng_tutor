import 'package:flutter/material.dart';

/// 考纲徽章：小圆角矩形，不同考纲不同颜色
class ExamBadge extends StatelessWidget {
  final String code;
  const ExamBadge({super.key, required this.code});

  static const Map<String, String> _names = {
    'zk': '中考', 'gk': '高考', 'cet4': '四级', 'cet6': '六级',
    'ky': '考研', 'ielts': '雅思', 'toefl': '托福', 'gre': 'GRE',
  };

  static const Map<String, Color> _colors = {
    'zk': Colors.teal, 'gk': Colors.indigo, 'cet4': Colors.blue,
    'cet6': Colors.blueAccent,
    'ky': Colors.deepPurple, 'ielts': Colors.green,
    'toefl': Colors.orange, 'gre': Colors.red,
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
          fontSize: 12, color: color, fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
