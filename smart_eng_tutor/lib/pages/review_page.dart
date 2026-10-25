import 'dart:math';
import 'package:flutter/material.dart';
import 'package:smart_eng_tutor/services/wordbook/wb_review_service.dart';
import 'package:smart_eng_tutor/services/wordbook/wb_database.dart'
    show ReviewSnapshot;

/// 一次打分动作的快照，用于撤回
class _UndoSnapshot {
  final int itemIdx;       // 会话中的词条下标（打分前）
  final int cardIdx;       // 词条内的卡片下标（打分前）
  final int itemScore;     // 词内累计分（打分前）
  final bool revealed;
  final bool engFirst;
  final ReviewSnapshot? dbSnapshot; // 落库时的数据库旧状态（未落库为 null）

  _UndoSnapshot({
    required this.itemIdx,
    required this.cardIdx,
    required this.itemScore,
    required this.revealed,
    required this.engFirst,
    this.dbSnapshot,
  });
}

class ReviewPage extends StatefulWidget {
  final ReviewService service;
  const ReviewPage({super.key, required this.service});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  ReviewSession? _session;
  bool _revealed = false;
  bool _markedWrong = false;
  bool _engFirst = true;
  final _rand = Random();
  int _itemScore = 2;
  bool _loading = true;

  final List<_UndoSnapshot> _undoStack = [];
  static const _maxUndo = 5;

  @override
  void initState() {
    super.initState();
    widget.service.startSession().then((s) {
      setState(() {
        _session = s;
        _loading = false;
        _engFirst = _rand.nextBool();
      });
    });
  }

  void _nextCard() {
    setState(() {
      _revealed = false;
      _markedWrong = false;
      _engFirst = _rand.nextBool();
    });
  }

  void _score(int quality) async {
    final s = _session!;
    final item = s.current;

    // ★ 打分前拍快照；若这是词内最后一张（会落库），先取数据库旧状态
    ReviewSnapshot? dbSnap;
    if (item.lastCard) {
      dbSnap = await widget.service.getReviewSnapshot(item.entry.id);
    }
    _undoStack.add(_UndoSnapshot(
      itemIdx: s.progress,
      cardIdx: item.cardIdx,
      itemScore: _itemScore,
      revealed: _revealed,
      engFirst: _engFirst,
      dbSnapshot: dbSnap,
    ));
    if (_undoStack.length > _maxUndo) _undoStack.removeAt(0); // 只留 5 次

    _itemScore = quality < _itemScore ? quality : _itemScore;
    if (quality == 0) _itemScore = 0;

    if (!item.lastCard) {
      item.cardIdx++;
      _nextCard();
      return;
    }
    await widget.service.score(item, _itemScore); // 词内最后一张 → 写调度
    _itemScore = 2;
    setState(() => s.advance());
    if (!s.finished) _nextCard();
  }

  // ★ 撤回：弹出最近一次打分，恢复会话位置与数据库状态
  Future<void> _undo() async {
    if (_undoStack.isEmpty || _session == null) return;
    final snap = _undoStack.removeLast();
    final s = _session!;

    // 回退数据库（若那次打分落过库）
    final dbSnap = snap.dbSnapshot;
    if (dbSnap != null) {
      await widget.service.restoreReviewSnapshot(dbSnap);
    }

    setState(() {
      while (s.progress > snap.itemIdx) {
        s.back();
      }
      s.current.cardIdx = snap.cardIdx;
      _itemScore = snap.itemScore;
      _revealed = false;      // ★ 改动：回退到未翻面，重新作答
      _engFirst = snap.engFirst;
      _markedWrong = false;
    });

  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final s = _session;
    if (s == null || s.finished) {
      return Scaffold(
        appBar: AppBar(title: const Text('复习')),
        body: Center(
          child: Text(s == null ? '当前没有到期的复习内容 🎉' : '本轮复习完成 🎉'),
        ),
      );
    }

    final card = s.current.card;
    final front = _engFirst ? card.eng : card.zh;
    final back = _engFirst ? card.zh : card.eng;

    return Scaffold(
      appBar: AppBar(
        title: Text('复习 ${s.progress + 1}/${s.total}'),
        actions: [
          // ★ 右上角撤回按钮（最多连撤 5 次）
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: _undoStack.isEmpty
                ? '撤回（无记录）'
                : '撤回上一次打分（还可撤 ${_undoStack.length} 次）',
            onPressed: _undoStack.isEmpty ? null : _undo,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(front,
                    style: const TextStyle(fontSize: 24),
                    textAlign: TextAlign.center),
              ),
            ),
            if (_revealed)
              Expanded(
                child: Card(
                  color:
                      _markedWrong ? Colors.red.shade50 : Colors.green.shade50,
                  child: Center(
                    child: Text(back,
                        style: const TextStyle(
                            fontSize: 28, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center),
                  ),
                ),
              )
            else
              const Spacer(),
            const SizedBox(height: 16),

            if (!_revealed) ...[
              // ---------- 未翻面 ----------
              Row(children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => setState(() {
                      _revealed = true;
                      _markedWrong = true;
                    }),
                    icon: const Icon(Icons.close),
                    label: const Text('不知道'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => setState(() => _revealed = true),
                    icon: const Icon(Icons.check),
                    label: const Text('答好了'),
                  ),
                ),
              ]),
            ] else if (_markedWrong) ...[
              // ---------- 答错确认态：只有继续 ----------
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => _score(0),
                child: const Text('继续'),
              ),

            ] else ...[
              // ---------- 正常自评 ----------
              const Text('自己对照答案评估：', textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () => _score(2),
                    child: const Text('答对了'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: () => _score(1),
                    child: const Text('不熟练'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonal(
                    style:
                        FilledButton.styleFrom(foregroundColor: Colors.red),
                    onPressed: () => _score(0),
                    child: const Text('答错了'),
                  ),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}
