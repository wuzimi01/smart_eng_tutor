import 'package:flutter/material.dart';
import 'package:smart_eng_tutor/services/wordbook/wb_database.dart';
import 'package:smart_eng_tutor/pages/flashcard_review_page.dart';
import 'package:smart_eng_tutor/services/wordbook/wb_review_service.dart';
import 'package:smart_eng_tutor/services/lookup/lk_registry.dart';
import 'package:smart_eng_tutor/services/lookup/lk_contract.dart';
import 'package:smart_eng_tutor/pages/widgets/review_mode_dialog.dart';
import 'package:smart_eng_tutor/pages/match_review_page.dart';
/// 词库通用操作：复习 / 从词典导入。
/// wordbook_list_page 与 wordbook_entry_list_page 共用。

/// 复习某个词库：先选模式（闪卡/连线）。
/// 返回 true = 实际开始了复习；false = 取消或无到期内容。
Future<bool> startBookReview(
    BuildContext context, WordbookDatabase db, int bookId, String bookName,
    {void Function()? onFinish}) async {
  final mode = await showReviewModeDialog(context);
  if (mode == null || !context.mounted) return false;

  if (mode == ReviewMode.matching) {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MatchReviewPage(db: db, bookId: bookId, bookName: bookName),
      ),
    );
    onFinish?.call();
    return true;
  }

  // ---------- 闪卡（原逻辑）----------
  final service = ReviewService(db, bookId: bookId);
  final session = await service.startSession();
  if (!context.mounted) return false;
  if (session == null) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('「$bookName」当前没有到期的复习内容 🎉'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1500),
      ));
    return false;
  }
  await Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => ReviewPage(service: service)),
  );
  onFinish?.call();
  return true;
}

/// 从词典批量导入到指定词库。返回导入数量（取消返回 -1）。
Future<int> importFromDictDialog(
    BuildContext context, WordbookDatabase db, int bookId, String bookName) async {
  final dicts =
      DictionaryRegistry.shared.all.where((d) => d.importable).toList();
  if (dicts.isEmpty) {
    if (!context.mounted) return -1;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('没有可导入的词典'),
        behavior: SnackBarBehavior.floating,
      ));
    return -1;
  }
  final dict = await showDialog<Dictionary>(
    context: context,
    builder: (c) => SimpleDialog(
      title: const Text('选择词典'),
      children: [
        for (final d in dicts)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, d),
            child: Text(d.name),
          ),
      ],
    ),
  );
  if (dict == null || !context.mounted) return -1;

  final range = await showDialog<List<String>>(
    context: context,
    builder: (c) {
      final fromCtrl = TextEditingController();
      final toCtrl = TextEditingController();
      return AlertDialog(
        title: Text('从「${dict.name}」导入到「$bookName」'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: fromCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: '起始单词',
                  hintText: '如 abandon',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: toCtrl,
              decoration: const InputDecoration(
                  labelText: '结束单词',
                  hintText: '如 academy',
                  border: OutlineInputBorder()),
              onSubmitted: (_) =>
                  Navigator.pop(c, [fromCtrl.text.trim(), toCtrl.text.trim()]),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(c, [fromCtrl.text.trim(), toCtrl.text.trim()]),
            child: const Text('导入'),
          ),
        ],
      );
    },
  );
  if (range == null || range.length < 2 || !context.mounted) return -1;
  final from = range[0].toLowerCase(), to = range[1].toLowerCase();
  if (from.isEmpty || to.isEmpty) return -1;

  final n = await db.importRange(dict, from, to, bookId: bookId);
  return n;
}
