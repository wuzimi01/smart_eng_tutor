import 'section.dart';

/// 词典契约（公开 API：一旦定下按兼容方式演进）
abstract class Dictionary {
  int get id;
  String get name;

  /// 声明支持的板块类型（设置矩阵的列由它生成）
  List<SectionType> getCapabilities();

  /// 自举：定位/拷贝/打开自己的数据。失败不抛异常，返回 false 并保持可用降级状态
  Future<bool> init();

  /// 核心查询。查不到返回空列表；内部兜底所有异常，禁止向外抛
  Future<List<ResultSection>> query(String word);

  /// 词根/原型查询（查词策略层用；无此能力的词典返回空）
  Future<List<String>> queryStems(String word) async => [];

  Future<void> dispose();
}
