import 'package:flutter/material.dart';
import 'package:smart_eng_tutor/pages/widgets/def_view.dart';
import 'package:smart_eng_tutor/services/wordbook/wb_database.dart';
import 'package:smart_eng_tutor/services/wordbook/wb_models.dart';
import 'package:smart_eng_tutor/services/lookup/lk_lookup.dart';
import 'package:smart_eng_tutor/services/lookup/lk_registry.dart';
import 'package:smart_eng_tutor/services/lookup/lk_models.dart';

/// 词条释义详情页：只用词条来源词典查询（无视显示设置）。
/// 顶部显示复习情况；相关单词 = 词典 impl 的 relatedHeads（词块→head）。
class WordbookEntryDetailPage extends StatefulWidget {
  final WordbookEntry entry;
  const WordbookEntryDetailPage({super.key, required this.entry});

  @override
  State<WordbookEntryDetailPage> createState() =>
      _WordbookEntryDetailPageState();
}

class _WordbookEntryDetailPageState extends State<WordbookEntryDetailPage> {
  List<ResultSection> _sections = const [];
  List<String> _related = const [];
  WordbookEntry? _entry; // 带最新复习状态

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 释义 + 相关词
    final lookup = WordLookup(DictionaryRegistry.shared);
    final r = await lookup.lookupEntry(widget.entry.word, widget.entry.dictId);
    final related = await DictionaryRegistry.shared
        .implFor(widget.entry.dictId)
        .relatedHeads(widget.entry.word);

    // 复习状态（找不到就用传入的占位数据）
    WordbookEntry? entry = widget.entry;
    if (widget.entry.id > 0) {
      entry = await WordbookDatabase.instance.getEntry(widget.entry.id) ??
          await WordbookDatabase.instance
              .findEntry(widget.entry.bookId, widget.entry.word) ??
          widget.entry;
    } else {
      entry = await WordbookDatabase.instance
          .findEntry(widget.entry.bookId, widget.entry.word);
    }

    if (!mounted) return;
    setState(() {
      _sections = r?.sections ?? const [];
      _related = related;
      _entry = entry ?? widget.entry;
    });
  }

  void _openRelated(String word) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WordbookEntryDetailPage(
          entry: WordbookEntry(
            id: -1,
            bookId: widget.entry.bookId,
            dictId: widget.entry.dictId, // 相关单词通常在同一词典
            word: word,
          ),
        ),
      ),
    );
  }

  // ---------- 复习情况 UI ----------

  static const _progressText = ['生词', '学习中', '复习中', '重学中'];

  Widget _reviewBadge() {
    final e = _entry;
    if (e == null || e.progress == 0) return const SizedBox.shrink();

    final now = DateTime.now().millisecondsSinceEpoch;
    final due = DateTime.fromMillisecondsSinceEpoch(e.dueAt);
    String dueText;
    if (e.dueAt <= now) {
      dueText = '已到期';
    } else {
      final days = due.difference(DateTime.now()).inDays;
      final hours = due.difference(DateTime.now()).inHours;
      dueText = days >= 1 ? '$days天后' : '$hours小时后';
    }

    final color = switch (e.progress) {
      1 => Colors.orange,
      2 => Colors.green,
      3 => Colors.redAccent,
      _ => Colors.grey,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 8),
        Text('${_progressText[e.progress]} · $dueText',
            style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.entry.word)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _reviewBadge(),
            WordContentView(word: widget.entry.word, sections: _sections),
            // ★ 相关词汇：显示在释义下方
            if (_related.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final w in _related)
                    ActionChip(
                      label: Text(w),
                      onPressed: () => _openRelated(w),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
