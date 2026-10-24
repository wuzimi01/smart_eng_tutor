import 'package:smart_eng_tutor/services/lookup/lk_registry.dart';
import 'package:smart_eng_tutor/services/lookup/lk_models.dart';
import 'package:smart_eng_tutor/services/wordbook/wb_database.dart';
import 'package:smart_eng_tutor/services/wordbook/wb_models.dart';

/// 一次复习中的一张卡片
class ReviewItem {
  final WordbookEntry entry;
  final List<ReviewCard> cards;
  int cardIdx = 0;
  ReviewItem(this.entry, this.cards);
  ReviewCard get card => cards[cardIdx];
  bool get lastCard => cardIdx >= cards.length - 1;
}

/// 一次复习会话（词 → 展开成卡片队列）
class ReviewSession {
  final List<ReviewItem> items;
  int _idx = 0;
  ReviewSession(this.items);
  bool get finished => _idx >= items.length;
  ReviewItem get current => items[_idx];
  void advance() => _idx++;
  int get total => items.length;
  int get progress => _idx;
}

class ReviewService {
  final WordbookDatabase _wb;
  final int bookId; // 只复习这个词库
  ReviewService(this._wb, {required this.bookId});

  /// 开始一轮复习：取该词库的到期词，展开成卡片队列
  Future<ReviewSession?> startSession({int maxWords = 20}) async {
    final due = await _wb.queryDueReviews(bookId: bookId, limit: maxWords);
    if (due.isEmpty) return null;
    final items = <ReviewItem>[];
    for (final e in due) {
      final dict = DictionaryRegistry.shared.byId(e.dictId ?? 1);
      if (dict == null) continue;
      final cards = await dict.queryCards(e.word);
      if (cards.isEmpty) continue;
      items.add(ReviewItem(e, cards));
    }
    return items.isEmpty ? null : ReviewSession(items);
  }

  /// 打分：词内最后一张卡打分时写调度。
  /// quality: 2=答对 1=不熟练 0=答错
  Future<void> score(ReviewItem item, int quality) async {
    await _wb.recordReview(item.entry.word, item.entry.bookId, quality);
  }
}
