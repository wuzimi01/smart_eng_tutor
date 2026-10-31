import 'package:smart_eng_tutor/services/lookup/lk_contract.dart';
import 'package:smart_eng_tutor/services/lookup/lk_models.dart';
import 'package:smart_eng_tutor/services/lookup/lk_display_settings.dart';
import 'package:smart_eng_tutor/services/lookup/lk_registry.dart';

/// 查词业务。
/// 词组命中（如 "look forward to"）时，chips 给出相关单词（首词 "look"）。
/// 词条详情页共用 [_sectionsFrom] / relatedWords，只是查询范围不同。
class WordLookup {
  final DictionaryRegistry registry;
  final DisplaySettings _settings = DisplaySettings.shared;
  WordLookup(this.registry);

  Dictionary? get _mainDict => registry.byId(1);

  /// 首页搜索：词根扩展后，第一个"有可见内容"的候选即命中
  Future<LookupResult> search(String word) async {
    if (_mainDict == null) {
      return const LookupResult(chips: [], displayText: '词典未就绪');
    }
    final stems = await _mainDict!.queryStems(word);
    final unique = <String>{word, ...stems}.toList();
    for (final c in unique) {
      final r = await _queryAll(c, extraChips: unique); // ★ 词根变体作为 chips
      if (r != null) return r;
    }
    return const LookupResult(chips: [], displayText: '未找到释义');
  }


  /// 指定词查询：首页切 chip、词库详情页共用
  Future<LookupResult> select(String word) async {
    final r = await _queryAll(word);
    return r ??
        LookupResult(
          chips: relatedWords(word),
          selected: word,
          displayText: '「$word」没有释义',
        );
  }

  /// 词条详情：
  /// - dictId 有效（>0）→ 只用该词条来源词典查，忽略显示设置；
  /// - dictId 为 0/null → 按当前显示设置查全部词典（与首页搜索一致）。
  Future<LookupResult?> lookupEntry(String word, int? dictId) async {
    if (dictId == null || dictId <= 0) {
      return _queryAll(word);
    }
    final dict = registry.byId(dictId);
    if (dict == null) return null;
    final sections = await dict.query(word);
    if (sections.isEmpty) return null;
    sections.sort((a, b) => (a.sortHint ?? 0).compareTo(b.sortHint ?? 0));
    return LookupResult(
      chips: relatedWords(word),
      selected: word,
      displayText: _displayFromSections(sections) ?? '（无显示内容）',
      tags: _tagsFromSections(sections),
      sections: sections,
    );
  }


  /// 词组（含空格）→ 相关单词 = 首词
  static List<String> relatedWords(String word) {
    final w = word.trim();
    if (!w.contains(' ')) return const [];
    final first = w.split(' ').first;
    return first.isEmpty ? const [] : [first];
  }

  Future<LookupResult?> _queryAll(String word,
      {List<String>? extraChips}) async {
    final visible = <ResultSection>[];
    for (final dict in registry.all) {
      final caps = dict.getCapabilities();
      if (!caps.any((t) => _settings.isVisible(dict.id, t))) continue;
      final sections = await dict.query(word);
      final kept = sections
          .where((s) => _settings.isVisible(s.dictId, s.type))
          .toList();
      visible.addAll(kept);
    }
    if (visible.isEmpty) return null;
    visible.sort((a, b) => (a.sortHint ?? 0).compareTo(b.sortHint ?? 0));

    // ★ chips = 词根变体（去重，词组时附加首词）
    final chips = <String>{
      word,
      ...?extraChips,
      ...relatedWords(word),
    }.toList();

    return LookupResult(
      chips: chips,
      selected: word,
      displayText: _displayFromSections(visible) ?? '（无显示内容）',
      tags: _tagsFromSections(visible),
      sections: visible,
    );
  }


  String? _displayFromSections(List<ResultSection> sections) {
    final buf = StringBuffer();
    for (final s in sections) {
      if (s.type == SectionType.translation) {
        buf.writeln((s.data as TranslationData).lines.join('\n'));
      }
    }
    final t = buf.toString().trim();
    return t.isEmpty ? null : t;
  }

  List<String> _tagsFromSections(List<ResultSection> sections) {
    for (final s in sections) {
      if (s.type == const SectionType('tag')) return (s.data as TagData).codes;
    }
    return const [];
  }
}
