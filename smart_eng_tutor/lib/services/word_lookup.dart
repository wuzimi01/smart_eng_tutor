import './database_helper.dart';

/// 一次查询的完整结果（UI 只负责显示，不做业务判断）
class LookupResult {
  final List<String> chips; // 候选词列表
  final String? selected; // 默认选中的词
  final String displayText; // 释义文本
  final List<String> tags; // 选中词的考纲标签，如 ['cet4', 'gk']

  const LookupResult({
    required this.chips,
    this.selected,
    required this.displayText,
    this.tags = const [],
  });
}

/// 查词业务：词根扩展 → 去重 → 逐个查释义
class WordLookup {
  final DatabaseHelper dbHelper;
  WordLookup(this.dbHelper);

  /// 输入词搜索：查原型，自动展示第一个有释义的候选
  Future<LookupResult> search(String word) async {
    final stems = await dbHelper.queryStems(word);
    final candidates = <String>[word, ...stems];
    final unique = <String>[];
    for (final c in candidates) {
      if (!unique.contains(c)) unique.add(c);
    }

    // 按顺序找第一个有释义的候选
    for (final c in unique) {
      final text = await _formatTranslation(c);
      if (text != null) {
        final tags = await dbHelper.queryTags(c);
        return LookupResult(
          chips: unique,
          selected: c,
          displayText: text,
          tags: tags,
        );
      }
    }
    return const LookupResult(chips: [], displayText: '未找到释义');
  }

  /// 用户手动选中某个候选词
  Future<LookupResult> select(String word) async {
    final text = await _formatTranslation(word);
    final tags = await dbHelper.queryTags(word);
    return LookupResult(
      chips: const [],
      selected: word,
      displayText: text ?? '「$word」没有释义',
      tags: tags,
    );
  }

  /// 查释义并拼成显示文本；查不到返回 null
  Future<String?> _formatTranslation(String word) async {
    final trans = await dbHelper.queryTranslation(word);
    if (trans == null) return null;
    final buffer = StringBuffer();
    for (final row in trans) {
      buffer.writeln(row['word']);
      buffer.writeln(row['translation']);
    }
    return buffer.toString().trim();
  }
}
