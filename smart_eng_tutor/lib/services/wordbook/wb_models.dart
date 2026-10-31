/// 词库
class Wordbook {
  final int id;
  final String name;
  final int wordCount;
  const Wordbook({required this.id, required this.name, this.wordCount = 0});
}

/// 词条。progress 直接采用 FSRS 四态：
/// 0=New 生词 1=Learning 学习中 2=Review 复习 3=Relearning 重学
class WordbookEntry {
  final int id;
  final int bookId;
  final int? dictId;
  final String word;
  final int progress;
  final int dueAt;
  final String? contexts; // ★ 历史上下文 JSON，暂不解析，预留
  const WordbookEntry({
    required this.id,
    required this.bookId,
    this.dictId,
    required this.word,
    this.progress = 0,
    this.dueAt = 0,
    this.contexts,
  });
}

