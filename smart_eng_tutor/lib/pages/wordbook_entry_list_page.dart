import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/models.dart';
import 'wordbook_entry_detail_page.dart';

/// 词条列表页（点击词条 → 释义详情；长按进入批量选择模式）
class WordbookEntryListPage extends StatefulWidget {
  final DatabaseHelper dbHelper;
  final int bookId;
  final String bookName;
  const WordbookEntryListPage({
    super.key,
    required this.dbHelper,
    required this.bookId,
    required this.bookName,
  });

  @override
  State<WordbookEntryListPage> createState() => _WordbookEntryListPageState();
}

class _WordbookEntryListPageState extends State<WordbookEntryListPage> {
  List<WordbookEntry> _entries = [];
  bool _loading = true;
  bool _selectMode = false;
  final Set<int> _selectedIds = {}; // 存 entry.id

  List<WordbookEntry> get _selectedEntries =>
      _entries.where((e) => _selectedIds.contains(e.id)).toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await widget.dbHelper.queryEntries(widget.bookId);
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
      // 重载后清掉已不存在的选择
      _selectedIds.removeWhere(
          (id) => !entries.any((e) => e.id == id));
      if (_selectMode && _selectedIds.isEmpty) _selectMode = false;
    });
  }

  void _exitSelectMode() =>
      setState(() { _selectMode = false; _selectedIds.clear(); });

  void _toggleSelect(WordbookEntry e) {
    setState(() {
      if (!_selectedIds.add(e.id)) _selectedIds.remove(e.id);
      if (_selectedIds.isEmpty) _selectMode = false;
    });
  }

  // ---------- 批量操作 ----------

  Future<void> _batchDelete() async {
    final sel = _selectedEntries;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除词条'),
        content: Text('确定删除选中的 ${sel.length} 个词条？此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    final n = await widget.dbHelper.deleteWords(sel.map((e) => e.id).toList());
    if (!mounted) return;
    _showSnack('已删除 $n 个词条');
    _load();
  }

  /// 弹出目标词库选择框，返回选中的词库 id（null = 取消）
  Future<int?> _pickTargetBook() async {
    final books = await widget.dbHelper.queryOtherBooks(widget.bookId);
    if (!mounted) return null;
    if (books.isEmpty) {
      _showSnack('没有其他词库，请先在词库页新建');
      return null;
    }
    return showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('选择目标词库'),
        children: books
            .map((b) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(c, b.id),
                  child: Text('${b.name}（${b.wordCount} 个单词）'),
                ))
            .toList(),
      ),
    );
  }

  Future<void> _batchCopy() async {
    final target = await _pickTargetBook();
    if (target == null) return;
    final n = await widget.dbHelper.copyWords(_selectedEntries, target);
    if (!mounted) return;
    _showSnack('已复制 $n 个词条');
    _exitSelectMode();
  }

  Future<void> _batchMove() async {
    final target = await _pickTargetBook();
    if (target == null) return;
    final n = await widget.dbHelper.moveWords(_selectedEntries, target);
    if (!mounted) return;
    _showSnack('已移动 $n 个词条');
    _load();
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

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 选择模式下按返回键先退出选择模式
      canPop: !_selectMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectMode) _exitSelectMode();
      },
      child: Scaffold(
        appBar: _selectMode ? _buildSelectAppBar() : _buildNormalAppBar(),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _entries.isEmpty
                ? const Center(child: Text('词库为空，去主页收藏单词吧'))
                : ListView.separated(
                    itemCount: _entries.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final e = _entries[i];
                      final isSelected = _selectedIds.contains(e.id);
                      return ListTile(
                        leading: _selectMode
                            ? Icon(
                                isSelected
                                    ? Icons.check_box
                                    : Icons.check_box_outline_blank,
                                color: isSelected ? Colors.blue : null,
                              )
                            : const Icon(Icons.star_outline),
                        title: Text(e.word,
                            style: const TextStyle(fontSize: 18)),
                        // translation 已从数据模型移除，摘要行删掉；
                        // 如想在列表区分来源词典，后续可用 dictId 查词典名
                        trailing: _selectMode
                            ? null
                            : const Icon(Icons.chevron_right),
                        onTap: () {
                          if (_selectMode) {
                            _toggleSelect(e);
                          } else {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => WordbookEntryDetailPage(
                                  dbHelper: widget.dbHelper,
                                  word: e.word,
                                ),
                              ),
                            );
                          }
                        },
                        // 长按进入选择模式并选中该项；已在选择模式中长按 = 切换选中
                        onLongPress: () {
                          if (!_selectMode) setState(() => _selectMode = true);
                          _toggleSelect(e);
                        },
                      );
                    },
                  ),
      ),
    );
  }

  PreferredSizeWidget _buildNormalAppBar() {
    return AppBar(
      title: Text(widget.bookName),
      actions: [
        IconButton(
          icon: const Icon(Icons.checklist),
          tooltip: '批量操作',
          onPressed: _entries.isEmpty
              ? null
              : () => setState(() => _selectMode = true),
        ),
      ],
    );
  }

  PreferredSizeWidget _buildSelectAppBar() {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: '退出选择',
        onPressed: _exitSelectMode,
      ),
      title: Text('已选 ${_selectedIds.length} 项'),
      actions: [
        // 全选/取消全选
        IconButton(
          icon: Icon(_selectedIds.length == _entries.length
              ? Icons.deselect
              : Icons.select_all),
          tooltip: _selectedIds.length == _entries.length ? '取消全选' : '全选',
          onPressed: () => setState(() {
            if (_selectedIds.length == _entries.length) {
              _selectedIds.clear();
            } else {
              _selectedIds.addAll(_entries.map((e) => e.id));
            }
          }),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          tooltip: '批量操作',
          enabled: _selectedIds.isNotEmpty,
          onSelected: (v) {
            switch (v) {
              case 'delete': _batchDelete();
              case 'copy':   _batchCopy();
              case 'move':   _batchMove();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'delete', child: ListTile(
                leading: Icon(Icons.delete_outline), title: Text('批量删除'))),
            PopupMenuItem(value: 'copy', child: ListTile(
                leading: Icon(Icons.copy_all), title: Text('复制到其他词库'))),
            PopupMenuItem(value: 'move', child: ListTile(
                leading: Icon(Icons.drive_file_move), title: Text('剪切到其他词库'))),
          ],
        ),
      ],
    );
  }
}
