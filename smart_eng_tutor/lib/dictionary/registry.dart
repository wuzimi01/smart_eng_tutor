import 'dictionary.dart';
import 'impls/builtin_dict.dart';

/// 词典注册中心 —— 全 app 唯一知道具体词典的文件。
/// 单例：全局只有一份，通过 [shared] 访问。
class DictionaryRegistry {
  // ===== 单例 =====
  DictionaryRegistry._();          // 私有构造：禁止外部 new
  static final DictionaryRegistry shared = DictionaryRegistry._();

  final List<Dictionary> _dicts = [
    BuiltinDict(),
  ];

  List<Dictionary> get all => List.unmodifiable(_dicts);

  Dictionary? byId(int id) {
    for (final d in _dicts) {
      if (d.id == id) return d;
    }
    return null;
  }

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
