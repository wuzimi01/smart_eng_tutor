import 'package:smart_eng_tutor/services/lookup/lk_contract.dart';
import 'package:smart_eng_tutor/services/lookup/lk_models.dart';
import 'package:smart_eng_tutor/services/lookup/lk_display_settings.dart';
import 'package:smart_eng_tutor/services/lookup/lk_registry.dart';

/// 查词业务：
/// - 词根扩展 → 去重 → 逐候选查询
/// - 只查“设置中至少有一类内容开着”的词典；查出的内容再按设置逐板块过滤
/// - 首页 search/select 与词库详情页共用本类
class WordLookup {
  final DictionaryRegistry registry;
  final DisplaySettings _settings = DisplaySettings.shared;

  WordLookup(this.registry);

  Dictionary? get _mainDict => registry.byId(1); // 词根扩展以主词典为准

  /// 首页搜索：词根扩展后，第一个“有可见内容”的候选即命中
  Future<LookupResult> search(String word) async {
    if (_mainDict == null) {
      return const LookupResult(chips: [], displayText: '词典未就绪');
    }
    final stems = await _mainDict!.queryStems(word);
    final unique = <String>{word, ...stems}.toList();
    for (final c in unique) {
      final r = await _queryAll(c);
      if (r != null) return r;
    }
    return const LookupResult(chips: [], displayText: '未找到释义');
  }

  /// 指定词查询：首页切 chip、词库详情页共用
  Future<LookupResult> select(String word) async {
    final r = await _queryAll(word);
    return r ??
        LookupResult(
          chips: const [],
          selected: word,
          displayText: '「$word」没有释义',
        );
  }

  /// 聚合所有（设置允许的）词典；无任何可见内容返回 null
  Future<LookupResult?> _queryAll(String word) async {
    final visible = <ResultSection>[];
    for (final dict in registry.all) {
      // 该词典声明的板块全部被关掉 → 连查都不查
      final caps = dict.getCapabilities();
      if (!caps.any((t) => _settings.isVisible(dict.id, t))) continue;

      final sections = await dict.query(word);
      // 查到的板块再按设置逐个过滤（例如只关例句）
      final kept = sections
          .where((s) => _settings.isVisible(s.dictId, s.type))
          .toList();
      visible.addAll(kept);
    }
    if (visible.isEmpty) return null;

    visible.sort((a, b) => (a.sortHint ?? 0).compareTo(b.sortHint ?? 0));
    return LookupResult(
      chips: const [],
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
