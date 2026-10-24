import 'package:flutter/material.dart';
import 'package:smart_eng_tutor/services/wordbook/wb_review_service.dart';

class ReviewPage extends StatefulWidget {
  final ReviewService service;
  const ReviewPage({super.key, required this.service});
  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  ReviewSession? _session;
  bool _revealed = false;
  bool _showFrontChinese = true; // 正面显示中文（蒙英文）或反之
  int _itemScore = 2; // 词内累计：2 全对 1 有不熟练 0 有答错
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.service.startSession().then((s) {
      setState(() { _session = s; _loading = false; });
    });
  }

  void _score(int quality) {
    final item = _session!.current;
    _itemScore = quality < _itemScore ? quality : _itemScore; // 取最差
    if (quality == 0) _itemScore = 0;
    if (!item.lastCard) {
      setState(() { item.cardIdx++; _revealed = false; });
      return;
    }
    widget.service.score(item, _itemScore); // 词内最后一张 → 写调度
    _itemScore = 2;
    setState(() {
      _session!.advance();
      _revealed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final s = _session;
    if (s == null || s.finished) {
      return Scaffold(
        appBar: AppBar(title: const Text('复习')),
        body: Center(child: Text(s == null ? '当前没有到期的复习内容 🎉' : '本轮复习完成 🎉')),
      );
    }
    final card = s.current.card;
    final front = _showFrontChinese ? card.front : card.back;
    final back = _showFrontChinese ? card.back : card.front;
    return Scaffold(
      appBar: AppBar(
        title: Text('复习 ${s.progress + 1}/${s.total}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: '切换正反面',
            onPressed: () => setState(() => _showFrontChinese = !_showFrontChinese),
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
                child: Text(front, style: const TextStyle(fontSize: 24),
                    textAlign: TextAlign.center),
              ),
            ),
            if (_revealed)
              Expanded(
                child: Card(
                  color: Colors.green.shade50,
                  child: Center(
                    child: Text(back, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center),
                  ),
                ),
              )
            else
              const Spacer(),
            const SizedBox(height: 16),
            if (!_revealed) ...[
              Row(children: [
                Expanded(child: FilledButton.tonalIcon(
                  onPressed: () => setState(() => _revealed = true),
                  icon: const Icon(Icons.close), label: const Text('不知道'))),
                const SizedBox(width: 12),
                Expanded(child: FilledButton.icon(
                  onPressed: () => setState(() => _revealed = true),
                  icon: const Icon(Icons.check), label: const Text('答好了'))),
              ]),
            ] else ...[
              Text('自己对照答案评估：', textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: FilledButton(
                  onPressed: () => _score(2), child: const Text('答对了'))),
                const SizedBox(width: 8),
                Expanded(child: FilledButton.tonal(
                  onPressed: () => _score(1), child: const Text('不熟练'))),
                const SizedBox(width: 8),
                Expanded(child: FilledButton.tonal(
                  style: FilledButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: () => _score(0), child: const Text('答错了'))),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}
