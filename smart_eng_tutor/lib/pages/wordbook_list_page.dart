import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/models.dart';
import 'wordbook_entry_list_page.dart';

/// 词库列表页（新增/删除词库，点击词库 → 词条列表）
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

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1500),
      ));
  }

  // ---------- 新增词库 ----------

  Future<void> _createBook() async {
    final name = await showDialog<String>(
      context: context,
      builder: (c) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('新建词库'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '词库名称，如：考研核心词',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.pop(c, v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(c, ctrl.text),
                child: const Text('创建')),
          ],
        );
      },
    );
    if (name == null || name.trim().isEmpty) return;
    final id = await widget.dbHelper.createBook(name);
    if (!mounted) return;
    if (id == null) {
      _showSnack('创建失败：词库名「${name.trim()}」已存在');
    } else {
      _showSnack('已创建词库「${name.trim()}」');
      _load();
    }
  }

  // ---------- 删除词库 ----------

  Future<void> _deleteBook(Wordbook b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('删除词库「${b.name}」？'),
        content: Text('将同时删除其中全部 ${b.wordCount} 个词条，此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final done = await widget.dbHelper.deleteBook(b.id);
    if (!mounted) return;
    _showSnack(done ? '已删除词库「${b.name}」' : '默认词库不可删除');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的词库'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建词库',
            onPressed: _createBook,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _books.isEmpty
              ? const Center(child: Text('暂无词库'))
              : ListView.separated(
                  itemCount: _books.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final b = _books[i];
                    return Dismissible(
                      key: ValueKey(b.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: Colors.red,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      confirmDismiss: (_) async {
                        _deleteBook(b);
                        return false; // 删除由对话框内决定，滑动本身不删除
                      },
                      child: ListTile(
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
                          _load();
                        },
                      ),
                    );
                  },
                ),
    );
  }
}
