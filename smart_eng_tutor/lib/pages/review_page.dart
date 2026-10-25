import 'dart:math';
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
  bool _engFirst = true; // 本张卡的方向（随机）
  final _rand = Random();
  int _itemScore = 2; // 词内累计：2 全对 1 有不熟练 0 有答错
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.service.startSession().then((s) {
      setState(() {
        _session = s;
        _loading = false;
        _engFirst = _rand.nextBool(); // 首张卡随机
      });
    });
  }

  void _nextCard() {
    setState(() {
      _revealed = false;
      _engFirst = _rand.nextBool(); // ★ 每张卡 50% 英文在先
    });
  }

  void _score(int quality) {
    final item = _session!.current;
    _itemScore = quality < _itemScore ? quality : _itemScore;
    if (quality == 0) _itemScore = 0;
    if (!item.lastCard) {
      item.cardIdx++;
      _nextCard();
      return;
    }
    widget.service.score(item, _itemScore); // 词内最后一张 → 写调度
    _itemScore = 2;
    setState(() => _session!.advance());
    if (!_session!.finished) _nextCard();
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
    final front = _engFirst ? card.eng : card.zh;
    final back = _engFirst ? card.zh : card.eng;
    return Scaffold(
      appBar: AppBar(title: Text('复习 ${s.progress + 1}/${s.total}')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(front, style: const TextStyle(fontSize: 24), textAlign: TextAlign.center),
              ),
            ),
            if (_revealed)
              Expanded(
                child: Card(
                  color: Colors.green.shade50,
                  child: Center(
                    child: Text(back,
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
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
              const Text('自己对照答案评估：', textAlign: TextAlign.center),
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
