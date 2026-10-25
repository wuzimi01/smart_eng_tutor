import 'package:smart_eng_tutor/services/lookup/lk_models.dart';

/// 词典契约（公开 API：一旦定下按兼容方式演进）
abstract class Dictionary {
  int get id;
  String get name;

  /// 可否作为批量导入来源（默认词典数据量太大，覆写为 false，导入 UI 自动跳过）
  bool get importable => true;

  /// 导入粒度：word=按单词导入；chunk=每个含 eng+zh 的词块各作为一条词条导入
  DictGranularity get granularity => DictGranularity.word;

  /// 声明支持的板块类型（设置矩阵的列由它生成）
  List<SectionType> getCapabilities();

  /// 自举：定位/拷贝/打开自己的数据。失败不抛异常，返回 false 并保持可用降级状态
  Future<bool> init();

  /// 核心查询。查不到返回空列表；内部兜底所有异常，禁止向外抛。
  /// word 可以是单词也可以是词组/词块英文（如 "look forward to"）
  Future<List<ResultSection>> query(String word);

  /// 词根/原型查询（查词策略层用；无此能力的词典返回空）
  Future<List<String>> queryStems(String word) async => [];

  /// 按单词批量取词（word 粒度导入用）；无此能力的词典返回空列表
  Future<List<String>> queryRange(String from, String to) async => [];

  /// 按词块批量取词（chunk 粒度导入用）：范围内每个含 eng+zh 的词块一项。
  /// headWord 仅供导入时展示分组，不写入数据库。
  Future<List<DictChunk>> queryChunkRange(String from, String to) async => [];

  /// 取某词/词块的复习卡片（主卡 + 词块卡）。无此能力的词典返回空列表。
  Future<List<ReviewCard>> queryCards(String word) async => [];

  Future<void> dispose();
}

/// 导入粒度
enum DictGranularity { word, chunk }

/// chunk 粒度导入时的一个词块
class DictChunk {
  final String headWord; // 所属单词（如 look），不落库，仅展示
  final String eng;      // 词块英文（如 look forward to）→ 作为词条 word
  final String zh;       // 词块中文
  final String type;     // chunk / example / proverb ...
  const DictChunk({
    required this.headWord,
    required this.eng,
    required this.zh,
    required this.type,
  });
}
