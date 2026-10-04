import 'package:flutter/material.dart';
import '../services/database_helper.dart';

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
  String _text = '查询中…';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final trans = await widget.dbHelper.queryTranslation(widget.word);
    if (!mounted) return;
    if (trans == null) {
      setState(() => _text = '词典中未收录该词');
      return;
    }
    final buffer = StringBuffer();
    for (final row in trans) {
      buffer.writeln(row['word']);
      buffer.writeln(row['translation']);
    }
    setState(() => _text = buffer.toString().trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.word)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Text(_text, style: const TextStyle(fontSize: 18, height: 1.6)),
      ),
    );
  }
}
