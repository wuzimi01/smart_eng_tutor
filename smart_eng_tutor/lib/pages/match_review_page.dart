import 'dart:math';

import 'package:flutter/material.dart';
import 'package:smart_eng_tutor/services/wordbook/wb_database.dart';
import 'package:smart_eng_tutor/services/lookup/lk_registry.dart';
import 'package:smart_eng_tutor/services/lookup/lk_text_utils.dart';

/// 一条连线题目：词条 + 英文 + 对应中文
class _MatchItem {
  final int entryId;
  final String eng;
  final String zh;
  _MatchItem({required this.entryId, required this.eng, required this.zh});
}

/// 一条用户连线（左列下标 ↔ 右列下标）
class _Link {
  final int left; // 英文列下标
  final int right; // 中文列下标
  _Link(this.left, this.right);
}

/// 连线复习页：N 个英文 + N 个中文打乱配对，全部连完才能提交，提交后批改
class MatchReviewPage extends StatefulWidget {
  final WordbookDatabase db;
  final int bookId;
  final String bookName;
  final int groupSize; // 每组几个词
  const MatchReviewPage({
    super.key,
    required this.db,
    required this.bookId,
    required this.bookName,
    this.groupSize = 6,
  });

  @override
  State<MatchReviewPage> createState() => _MatchReviewPageState();
}

class _MatchReviewPageState extends State<MatchReviewPage> {
  final _rand = Random();

  List<_MatchItem> _items = []; // 本组题目（原始顺序）
  List<int> _leftIdx = []; // 英文列：_items 下标的打乱序列
  List<int> _rightIdx = []; // 中文列：_items 下标的打乱序列
  List<_Link> _links = [];
  int? _selLeft; // 当前选中的左列下标
  int? _selRight;

  bool _graded = false; // 是否已提交批改
  bool _loading = true;

  // 配对颜色（最多 6 组）
  static const _pairColors = [
    Colors.blue, Colors.orange, Colors.purple,
    Colors.teal, Colors.pink, Colors.indigo,
  ];

  @override
  void initState() {
    super.initState();
    _newGroup();
  }

  /// 从词库随机抽一组有释义的词（释义剥标记后去重，保证组内互不相同）
  Future<void> _newGroup() async {
    setState(() {
      _loading = true;
      _graded = false;
      _links = [];
      _selLeft = null;
      _selRight = null;
    });
    final entries = await widget.db.queryEntries(widget.bookId);
    if (!mounted) return;
    final candidates = entries.toList()..shuffle(_rand);
    final items = <_MatchItem>[];
    final usedZh = <String>{};
    for (final e in candidates) {
      if (items.length >= widget.groupSize) break;
      final cards =
          await DictionaryRegistry.shared.implFor(e.dictId).queryCards(e.word);
      if (cards.isEmpty) continue;
      final zh = cards.first.zh.trim();
      final plain = LkTextUtils.strip(zh);
      if (plain.isEmpty || usedZh.contains(plain)) continue; // 释义重复的跳过
      usedZh.add(plain);
      items.add(_MatchItem(entryId: e.id, eng: e.word, zh: zh));
    }
    if (!mounted) return;
    if (items.length < 3) {
      setState(() => _loading = false);
      _showSnack('词库中可用词条不足（至少需要 3 个有释义的单词）');
      return;
    }
    // 两列独立打乱（存的是 _items 下标，批改按下标对应，避免错位）
    setState(() {
      _items = items;
      _leftIdx = List<int>.generate(items.length, (i) => i)..shuffle(_rand);
      _rightIdx = List<int>.generate(items.length, (i) => i)..shuffle(_rand);
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

  // ---------- 列文本（列下标 → 词条） ----------
  String _leftText(int i) => _items[_leftIdx[i]].eng;
  String _rightText(int i) => _items[_rightIdx[i]].zh;

  // ---------- 交互 ----------
  void _tapLeft(int i) {
    if (_graded || _loading) return;
    // 点已连线的项 = 取消该连线
    final existing = _links.indexWhere((l) => l.left == i);
    if (existing >= 0) {
      setState(() {
        _links.removeAt(existing);
        _selLeft = null;
        _selRight = null;
      });
      return;
    }
    setState(() {
      _selLeft = _selLeft == i ? null : i;
      _tryLink();
    });
  }

  void _tapRight(int i) {
    if (_graded || _loading) return;
    final existing = _links.indexWhere((l) => l.right == i);
    if (existing >= 0) {
      setState(() {
        _links.removeAt(existing);
        _selLeft = null;
        _selRight = null;
      });
      return;
    }
    setState(() {
      _selRight = _selRight == i ? null : i;
      _tryLink();
    });
  }

  /// 两边各选中一个且均未连线 → 成一条线（在 _tap* 的 setState 内调用）
  void _tryLink() {
    if (_selLeft == null || _selRight == null) return;
    final l = _selLeft!, r = _selRight!;
    if (_links.any((x) => x.left == l || x.right == r)) return;
    _links.add(_Link(l, r));
    _selLeft = null;
    _selRight = null;
  }

  // ---------- 批改 ----------
  /// 一条连线是否正确：左右列指向的必须是同一个词条
  bool _isLinkCorrect(_Link l) =>
      _leftIdx[l.left] == _rightIdx[l.right];

  void _submit() {
    setState(() => _graded = true);
    final correct = _links.where(_isLinkCorrect).length;
    _showSnack('批改完成：$correct / ${_items.length} 正确');
  }

  // ---------- 辅助查询 ----------
  int? _linkIndexOfLeft(int i) {
    final idx = _links.indexWhere((l) => l.left == i);
    return idx >= 0 ? idx : null;
  }

  int? _linkIndexOfRight(int i) {
    final idx = _links.indexWhere((l) => l.right == i);
    return idx >= 0 ? idx : null;
  }

  Color _borderColor({required int? linkIdx, required bool selected}) {
    if (_graded && linkIdx != null) {
      // 批改后：连线正确绿 / 错误红
      return _isLinkCorrect(_links[linkIdx]) ? Colors.green : Colors.red;
    }
    if (linkIdx != null) return _pairColors[linkIdx % _pairColors.length];
    if (selected) return Theme.of(context).colorScheme.primary;
    return Colors.grey;
  }

  Color _fillColor({required int? linkIdx, required bool selected}) {
    if (linkIdx != null) {
      return _pairColors[linkIdx % _pairColors.length].withValues(alpha: 0.12);
    }
    if (selected) {
      return Theme.of(context).colorScheme.primary.withValues(alpha: 0.15);
    }
    return Colors.grey.withValues(alpha: 0.08);
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('连线 · ${widget.bookName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '换一组',
            onPressed: _loading ? null : _newGroup,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.length < 3
              ? const Center(child: Text('词条不足，无法连线'))
              : _buildBoard(),
      bottomNavigationBar: _items.length < 3
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _graded
                    ? FilledButton.tonal(
                        onPressed: _newGroup,
                        child: const Text('下一组'),
                      )
                    : FilledButton(
                        // 全部连完才能提交，防误触
                        onPressed: _links.length == _items.length
                            ? _submit
                            : null,
                        child: Text(
                          _links.length == _items.length
                              ? '提交'
                              : '提交（还剩 ${_items.length - _links.length} 个未连线）',
                        ),
                      ),
              ),
            ),
    );
  }

  Widget _buildBoard() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // ---------- 左列：英文 ----------
          Expanded(
            child: Column(
              children: [
                for (int i = 0; i < _leftIdx.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: _buildTile(
                        text: _leftText(i),
                        linkIdx: _linkIndexOfLeft(i),
                        selected: _selLeft == i,
                        onTap: () => _tapLeft(i),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // ---------- 右列：中文 ----------
          Expanded(
            child: Column(
              children: [
                for (int i = 0; i < _rightIdx.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: _buildTile(
                        text: _rightText(i),
                        linkIdx: _linkIndexOfRight(i),
                        selected: _selRight == i,
                        onTap: () => _tapRight(i),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTile({
    required String text,
    required int? linkIdx,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final color = _borderColor(linkIdx: linkIdx, selected: selected);
    final fill = _fillColor(linkIdx: linkIdx, selected: selected);
    final gradedColor = (_graded && linkIdx != null) ? color : null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: fill,
          border: Border.all(color: color, width: selected ? 2 : 1.2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(
            text,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              height: 1.2,
              color: gradedColor ?? Theme.of(context).colorScheme.onSurface,
              fontWeight:
                  linkIdx != null || selected ? FontWeight.w600 : null,
            ),
          ),
        ),
      ),
    );
  }
}
