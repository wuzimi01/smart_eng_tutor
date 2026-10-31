import 'package:flutter/material.dart';

/// 解析行内标记：^文本^ = 加粗，*文本* = 下划线。
/// 所有显示词条文本的地方统一走这里，避免漏码显示原文。
List<InlineSpan> parseInline(String text, {TextStyle? base}) {
  final spans = <InlineSpan>[];
  final reg = RegExp(r'\^([^\^]+)\^|\*([^*]+)\*');
  int last = 0;
  for (final m in reg.allMatches(text)) {
    if (m.start > last) {
      spans.add(TextSpan(text: text.substring(last, m.start)));
    }
    final bold = m[1] != null;
    final content = bold ? m[1]! : m[2]!;
    spans.add(TextSpan(
      text: content,
      style: (base ?? const TextStyle()).copyWith(
        fontWeight: bold ? FontWeight.bold : null,
        decoration: bold ? null : TextDecoration.underline,
        decorationThickness: 2,
      ),
    ));
    last = m.end;
  }
  if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
  return spans;
}


/// 快捷组件：把带标记的字符串直接渲染成富文本
   class InlineText extends StatelessWidget {
     final String text;
     final TextStyle? style;
     final TextAlign? textAlign;
     final int? maxLines;
     final TextOverflow? overflow;
     const InlineText(this.text,
         {super.key, this.style, this.textAlign, this.maxLines, this.overflow});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: style ?? DefaultTextStyle.of(context).style,
        children: parseInline(text),
      ),
      textAlign: textAlign ?? TextAlign.start,
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
    );
  }
}