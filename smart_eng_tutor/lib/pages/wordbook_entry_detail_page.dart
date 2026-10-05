import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../dictionary/registry.dart';
import '../dictionary/section.dart';

/// 词条释义详情页
class WordbookEntryDetailPage extends StatefulWidget {
  final DatabaseHelper dbHelper;
  final String word;                              // ← registry 参数已删

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
  String _text = '查询中…';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dict = DictionaryRegistry.shared.byId(1);   // ← 单例直接拿
    final sections = await dict?.query(widget.word) ?? const <ResultSection>[];
    if (!mounted) return;

    final buf = StringBuffer();
    for (final s in sections) {
      if (s.type == const SectionType('translation')) {
        for (final line in (s.data as TranslationData).lines) {
          buf.writeln(line);
        }
      }
    }

    final text = buf.toString().trim();
    setState(() => _text = text.isEmpty ? '词典中未收录该词' : text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.word)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Text(_text,
            style: const TextStyle(fontSize: 18, height: 1.6)),
      ),
    );
  }
}
