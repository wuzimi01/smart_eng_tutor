import 'package:flutter/material.dart';
import 'package:smart_eng_tutor/pages/widgets/def_view.dart';
import 'package:smart_eng_tutor/services/wordbook/wb_models.dart';
import 'package:smart_eng_tutor/services/lookup/lk_lookup.dart';
import 'package:smart_eng_tutor/services/lookup/lk_registry.dart';
import 'package:smart_eng_tutor/services/lookup/lk_models.dart';

/// 词条释义详情页：只用词条来源词典查询（无视显示设置），
/// 词组词条显示自身释义 + 下级词块 + 相关单词 chip。
/// 查询逻辑与查词页共用 WordLookup.lookupEntry / relatedWords。
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final lookup = WordLookup(DictionaryRegistry.shared);
    final r = await lookup.lookupEntry(widget.entry.word, widget.entry.dictId);
    if (!mounted) return;
    setState(() {
      _sections = r?.sections ?? const [];
      _related = r?.chips ?? const [];
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.entry.word)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_related.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                children: [
                  for (final w in _related)
                    ActionChip(
                      label: Text('相关单词：$w'),
                      onPressed: () => _openRelated(w),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            WordContentView(word: widget.entry.word, sections: _sections),
          ],
        ),
      ),
    );
  }
}
