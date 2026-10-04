import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/models.dart';
import 'wordbook_entry_list_page.dart';

/// 词库列表页（点击词库 → 词条列表）
class WordbookListPage extends StatefulWidget {
  final DatabaseHelper dbHelper;
  const WordbookListPage({super.key, required this.dbHelper});

  @override
  State<WordbookListPage> createState() => _WordbookListPageState();
}

class _WordbookListPageState extends State<WordbookListPage> {
  List<Wordbook> _books = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final books = await widget.dbHelper.queryWordbooks();
    if (!mounted) return;
    setState(() {
      _books = books;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的词库')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _books.isEmpty
              ? const Center(child: Text('暂无词库'))
              : ListView.separated(
                  itemCount: _books.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final b = _books[i];
                    return ListTile(
                      leading: const Icon(Icons.menu_book),
                      title: Text(b.name),
                      subtitle: Text('${b.wordCount} 个单词'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => WordbookEntryListPage(
                              dbHelper: widget.dbHelper,
                              bookId: b.id,
                              bookName: b.name,
                            ),
                          ),
                        );
                        _load(); // 返回时刷新计数
                      },
                    );
                  },
                ),
    );
  }
}
