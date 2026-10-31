import 'package:smart_eng_tutor/services/lookup/lk_contract.dart';
import 'package:smart_eng_tutor/services/lookup/impls/lk_builtin_dict.dart';
import 'package:smart_eng_tutor/services/lookup/impls/lk_complete_guide_dict.dart';

/// 词典注册中心 —— 全 app 唯一知道具体词典的文件。
/// 单例：全局只有一份，通过 [shared] 访问。
class DictionaryRegistry {
  // ===== 单例 =====
  DictionaryRegistry._(); // 私有构造：禁止外部 new
  static final DictionaryRegistry shared = DictionaryRegistry._();

  final List<Dictionary> _dicts = [
    BuiltinDict(),
    CompleteGuideDict(), // 全攻略（id=2）
  ];

  List<Dictionary> get all => List.unmodifiable(_dicts);

  Dictionary? byId(int id) {
    for (final d in _dicts) {
      if (d.id == id) return d;
    }
    return null;
  }
  /// 按词典 ID 取实现；dictId 为空或未注册时回退第一个注册的词典（内置）。
  /// 注意：dictId=0 的词条也会拿到内置词典，若需"按显示设置查全部"
  /// 请走 WordLookup.lookupEntry(word, dictId)。
  Dictionary implFor(int? dictId) =>
      dictId == null ? _dicts.first : (byId(dictId) ?? _dicts.first);

  Future<void> initAll() async {
    for (final d in _dicts) {
      await d.init();
    }
  }

  Future<void> disposeAll() async {
    for (final d in _dicts) {
      await d.dispose();
    }
  }
}
