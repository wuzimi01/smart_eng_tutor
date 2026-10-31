import 'package:flutter/material.dart';

/// 复习模式
enum ReviewMode { flashcard, matching }

/// 复习模式选择弹窗（点击"复习"后先弹出）
Future<ReviewMode?> showReviewModeDialog(BuildContext context) {
  return showDialog<ReviewMode>(
    context: context,
    builder: (c) => SimpleDialog(
      title: const Text('选择复习模式'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(c, ReviewMode.flashcard),
          child: const ListTile(
            leading: Icon(Icons.style),
            title: Text('闪卡'),
            subtitle: Text('逐张翻面自评'),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(c, ReviewMode.matching),
          child: const ListTile(
            leading: Icon(Icons.keyboard_double_arrow_right),
            title: Text('连线'),
            subtitle: Text('中英文配对，自动批改'),
          ),
        ),
      ],
    ),
  );
}
