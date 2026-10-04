import 'database_helper.dart';

/// 收藏操作的返回结果
class FavoriteResult {
  final bool favorited; // 收藏后状态
  final String message;
  const FavoriteResult(this.favorited, this.message);
}

/// 单词本业务：收藏/取消收藏（默认词库，为多词库预留 bookId 参数）
class WordbookService {
  final DatabaseHelper dbHelper;
  WordbookService(this.dbHelper);

  /// 切换收藏状态：已收藏 → 取消；未收藏 → 收藏并快照当前释义
  Future<FavoriteResult> toggle(String word, {int? bookId, int? dictId}) async {
    if (await dbHelper.isFavorited(word)) {
      await dbHelper.removeWord(word);
      return const FavoriteResult(false, '已取消收藏');
    }
    final r = await dbHelper.addWord(word, bookId: bookId, dictId: dictId);
    return switch (r) {
      'added'  => const FavoriteResult(true, '⭐ 已收藏到默认词库'),
      'exists' => const FavoriteResult(true, '该词已在词库中'),
      _        => const FavoriteResult(false, '收藏失败'),
    };
  }



  /// 当前是否已收藏（进详情页时点亮按钮用）
  Future<bool> isFavorited(String word) => dbHelper.isFavorited(word);
}
