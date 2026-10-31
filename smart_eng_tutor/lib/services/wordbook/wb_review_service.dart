import 'package:smart_eng_tutor/services/lookup/lk_registry.dart';
import 'package:smart_eng_tutor/services/lookup/lk_models.dart';
import 'package:smart_eng_tutor/services/wordbook/wb_database.dart';
import 'package:smart_eng_tutor/services/wordbook/wb_models.dart';

class ReviewItem {
  final WordbookEntry entry;
  final List<ReviewCard> cards; // 已按重要度降序
  int cardIdx = 0;

  ReviewItem(this.entry, List<ReviewCard> allCards)
      : cards = allCards
          ..sort((a, b) => b.importance.compareTo(a.importance)) {
    if (cards.length > 4) cards.removeRange(4, cards.length); // 单词最多 4 张
  }

  ReviewCard get card => cards[cardIdx];
  bool get lastCard => cardIdx >= cards.length - 1;
}

class ReviewSession {
  final List<ReviewItem> items;
  int _idx = 0;
  ReviewSession(this.items);

  bool get finished => _idx >= items.length;
  ReviewItem get current => items[_idx];
  void advance() => _idx++;
  void back() => _idx = (_idx - 1).clamp(0, items.length - 1); // ★ 撤回用
  int get total => items.length;
  int get progress => _idx;
}

class ReviewService {
  final WordbookDatabase _wb;
  final int bookId;
  ReviewService(this._wb, {required this.bookId});

  Future<ReviewSession?> startSession({int maxWords = 20}) async {
    final due = await _wb.queryDueReviews(bookId: bookId, limit: maxWords);
    if (due.isEmpty) return null;

    final items = <ReviewItem>[];
    for (final e in due) {
      // 来源词典；找不到（如收藏词 dictId=0）→ 用主词典出卡
      final dict = DictionaryRegistry.shared.byId(e.dictId ?? 1) ??
          DictionaryRegistry.shared.byId(1);
      if (dict == null) continue;
      final cards = await dict.queryCards(e.word);
      if (cards.isEmpty) continue;
      items.add(ReviewItem(e, cards));
    }
    return items.isEmpty ? null : ReviewSession(items);
  }

  /// quality: 2=答对 1=不熟练 0=答错（wb_database 内映射 FSRS Good/Hard/Again）
  Future<void> score(ReviewItem item, int quality) async {
    await _wb.recordReview(item.entry.id, quality);
  }

  /// ★ 打分前取数据库快照（撤回用）
  Future<ReviewSnapshot?> getReviewSnapshot(int entryId) =>
      _wb.getReviewSnapshot(entryId);

  /// ★ 撤销打分：恢复词条复习状态
  Future<void> restoreReviewSnapshot(ReviewSnapshot snap) =>
      _wb.restoreReviewSnapshot(snap);
}
