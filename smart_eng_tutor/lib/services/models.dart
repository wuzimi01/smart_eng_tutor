import 'dart:ui';

/// OCR 识别出的单词（含在原图中的位置）
class OcrWord {
  final String text;
  final Rect rect;
  const OcrWord(this.text, this.rect);
}

/// 词库（当前只有默认词库，为多词库预留）
class Wordbook {
  final int id;
  final String name;
  final int wordCount;
  const Wordbook({
    required this.id,
    required this.name,
    this.wordCount = 0,
  });
}

/// 词库中的词条
class WordbookEntry {
  final int id;
  final int bookId;
  final String word;
  final String? translation; // 收藏时顺带存的释义快照，可为空
  final String createdAt;
  const WordbookEntry({
    required this.id,
    required this.bookId,
    required this.word,
    this.translation,
    required this.createdAt,
  });
}
