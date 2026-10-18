import 'package:smart_eng_tutor/services/lookup/lk_contract.dart';
import 'package:smart_eng_tutor/services/lookup/lk_models.dart';
import 'package:smart_eng_tutor/services/lookup/lk_registry.dart';

/// 查词业务：词根扩展 → 去重 → 逐个查释义（经注册中心）
class WordLookup {
  final DictionaryRegistry registry;
  WordLookup(this.registry);

  Dictionary? get _dict => registry.byId(1); // 主释义词典；多词典后改为聚合

  Future<LookupResult> search(String word) async {
    final dict = _dict;
    if (dict == null) return const LookupResult(chips: [], displayText: '词典未就绪');

    final stems = await dict.queryStems(word);
    final unique = <String>{word, ...stems}.toList();

    for (final c in unique) {
      final sections = await dict.query(c);
      final text = _displayFromSections(sections);
      if (text != null) {
        return LookupResult(
          chips: unique,
          selected: c,
          displayText: text,
          tags: _tagsFromSections(sections),
          sections: sections,
        );
      }
    }
    return LookupResult(chips: [], displayText: '未找到释义');
  }

  Future<LookupResult> select(String word) async {
    final dict = _dict;
    final sections = await dict?.query(word) ?? const [];
    final text = _displayFromSections(sections);
    return LookupResult(
      chips: const [],
      selected: word,
      displayText: text ?? '「$word」没有释义',
      tags: _tagsFromSections(sections),
      sections: sections,
    );
  }

  String? _displayFromSections(List<ResultSection> sections) {
    final buf = StringBuffer();
    for (final s in sections) {
      if (s.type == SectionType.translation) {
        for (final line in (s.data as TranslationData).lines) {
          buf.writeln(line);
        }
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
