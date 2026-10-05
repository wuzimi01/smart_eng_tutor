/// 板块类型标识（稳定标识符，进入配置矩阵与渲染注册表，不可随意改名）
class SectionType {
  final String value;
  const SectionType(this.value);

  static const translation = SectionType('translation');
  static const phonetic    = SectionType('phonetic');
  static const example     = SectionType('example');
  static const tag         = SectionType('tag');       // 考纲徽章
  static const similar     = SectionType('similar');   // 形近词（预留）
  static const inflection  = SectionType('inflection');// 词形变化（预留）

  /// 未知新功能兜底：词典可自定义类型名，UI 无渲染器时走通用兜底组件
  factory SectionType.custom(String name) => SectionType(name);

  @override
  bool operator ==(Object other) => other is SectionType && other.value == value;
  @override
  int get hashCode => value.hashCode;
  @override
  String toString() => value;
}

/// 各板块类型的数据载体（结构由类型约定）
class TranslationData {
  final List<String> lines; // 逐行释义
  const TranslationData(this.lines);
}

class PhoneticData {
  final List<String> items;
  const PhoneticData(this.items);
}

class TagData {
  final List<String> codes; // 如 ['cet4', 'gk']
  const TagData(this.codes);
}

/// 查询结果的统一板块单元
class ResultSection {
  final SectionType type;
  final int dictId;          // 来源词典
  final String? title;       // 显示标题；null = UI 按 type 取默认名
  final Object data;         // 对应类型的 Data 类；custom 类型为 Map<String, Object?>
  final int? sortHint;       // 排序建议（用户配置优先于它）

  const ResultSection({
    required this.type,
    required this.dictId,
    this.title,
    required this.data,
    this.sortHint,
  });
}
