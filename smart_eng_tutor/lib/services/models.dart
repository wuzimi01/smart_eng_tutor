import 'dart:ui';

/// OCR 识别出的单词（含在原图中的位置）
class OcrWord {
  final String text;
  final Rect rect;
  const OcrWord(this.text, this.rect);
}
