import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../dictionary/registry.dart';
import '../dictionary/section.dart';
import 'widgets/word_content_view.dart';

/// 词条释义详情页
class WordbookEntryDetailPage extends StatefulWidget {
  final DatabaseHelper dbHelper;
  final String word;

  const WordbookEntryDetailPage({
    super.key,
    required this.dbHelper,
    required this.word,
  });

  @override
  State<WordbookEntryDetailPage> createState() =>
      _WordbookEntryDetailPageState();
}

class _WordbookEntryDetailPageState extends State<WordbookEntryDetailPage> {
  List<ResultSection> _sections = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dict = DictionaryRegistry.shared.byId(1);
    final sections =
        await dict?.query(widget.word) ?? const <ResultSection>[];
    if (!mounted) return;
    setState(() => _sections = sections);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.word)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: WordContentView(
          word: widget.word,
          sections: _sections,
          // chips / onChipTap 不传 → 详情页无候选行，纯内容
        ),
      ),
    );
  }
}
