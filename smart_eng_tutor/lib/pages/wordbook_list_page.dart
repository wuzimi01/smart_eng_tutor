import 'package:flutter/material.dart';
import 'package:smart_eng_tutor/services/wordbook/wb_models.dart';
import 'package:smart_eng_tutor/services/wordbook/wb_database.dart';
import 'package:smart_eng_tutor/pages/review_page.dart';
import 'package:smart_eng_tutor/services/wordbook/wb_review_service.dart';
import 'package:smart_eng_tutor/services/lookup/lk_registry.dart';
import 'package:smart_eng_tutor/services/lookup/lk_contract.dart';
import 'package:smart_eng_tutor/pages/wordbook_entry_list_page.dart';


/// 词库列表页（新增/删除词库，点击词库 → 词条列表）
class WordbookListPage extends StatefulWidget {
  final WordbookDatabase _wordbookDb;
  const WordbookListPage({super.key, required this._wordbookDb});
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
    final books = await widget._wordbookDb.queryWordbooks();
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
            FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('创建')),
          ],
        );
      },
    );
    if (name == null || name.trim().isEmpty) return;
    final id = await widget._wordbookDb.createBook(name);
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
    final done = await widget._wordbookDb.deleteBook(b.id);
    if (!mounted) return;
    _showSnack(done ? '已删除词库「${b.name}」' : '默认词库不可删除');
    _load();
  }

  // ---------- 复习（针对某个词库） ----------
  Future<void> _startReview(Wordbook b) async {
    final service = ReviewService(widget._wordbookDb, bookId: b.id);
    final session = await service.startSession();
    if (!mounted) return;
    if (session == null) {
      _showSnack('「${b.name}」当前没有到期的复习内容 🎉');
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReviewPage(service: service)),
    );
    _showSnack('复习完成，成绩已记录');
    _load();
  }

  // ---------- 从词典批量导入 ----------
  Future<void> _importFromDict(int bookId, String bookName) async {
    // 选词典（跳过 id=0 读文章收藏、id=1 默认词典，只列导入型词典）
    final dicts = DictionaryRegistry.shared.all.where((d) => d.id >= 2).toList();
    if (dicts.isEmpty) {
      _showSnack('没有可导入的词典');
      return;
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
    if (dict == null || !mounted) return;

    // 输入起止单词（前闭后闭）
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
              child: const Text('导入')),
          ],
        );
      },
    );
    if (range == null || range.length < 2 || !mounted) return;
    final from = range[0].toLowerCase(), to = range[1].toLowerCase();
    if (from.isEmpty || to.isEmpty) {
      _showSnack('起止单词不能为空');
      return;
    }
    final n = await widget._wordbookDb.importRange(dict, from, to, bookId: bookId);
    if (!mounted) return;
    _showSnack(n > 0 ? '已导入 $n 个新单词' : '范围内没有新单词（可能已全部存在）');
    _load();
  }

  // ---------- 长按菜单 ----------
  void _showBookMenu(Wordbook b) {
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download),
              title: Text('从词典导入到「${b.name}」'),
              onTap: () {
                Navigator.pop(c);
                _importFromDict(b.id, b.name);
              },
            ),
            ListTile(
              leading: const Icon(Icons.school),
              title: Text('复习「${b.name}」'),
              onTap: () {
                Navigator.pop(c);
                _startReview(b);
              },
            ),
          ],
        ),
      ),
    );
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
                          // ★ 核对：词条列表页的实际类名/参数名，按你项目里的改
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => WordbookEntryListPage(
                                wordbookDb: widget._wordbookDb,
                                bookId: b.id,
                                bookName: b.name,
                              ),
                            ),
                          );
                          _load();
                        },
                        onLongPress: () => _showBookMenu(b),
                      ),
                    );
                  },
                ),
    );
  }
}
