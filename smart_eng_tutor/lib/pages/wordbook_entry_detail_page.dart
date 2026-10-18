import 'package:flutter/material.dart';

import 'package:smart_eng_tutor/pages/widgets/def_view.dart';
import 'package:smart_eng_tutor/services/wordbook/wb_database.dart';
import 'package:smart_eng_tutor/services/lookup/lk_models.dart';      // ResultSection
import 'package:smart_eng_tutor/services/lookup/lk_registry.dart';    // DictionaryRegistry

/// 词条释义详情页
class WordbookEntryDetailPage extends StatefulWidget {
  final WordbookDatabase wordbookDb;
  final String word;

  const WordbookEntryDetailPage({
    super.key,
    required this.wordbookDb,
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
