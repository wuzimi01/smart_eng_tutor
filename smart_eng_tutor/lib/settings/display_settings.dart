import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../dictionary/section.dart';

/// 显示开关：某词典的某类内容是否显示。
/// key: "show.《dictId》.《typeName》"，默认开。
class DisplaySettings extends ChangeNotifier {
  DisplaySettings._();
  static final DisplaySettings shared = DisplaySettings._();

  late final SharedPreferences _sp;

  Future<void> init() async {
    _sp = await SharedPreferences.getInstance();
  }

  bool isVisible(int dictId, SectionType type) =>
      _sp.getBool('show.$dictId.${type.name}') ?? true;

  Future<void> setVisible(int dictId, SectionType type, bool v) async {
    await _sp.setBool('show.$dictId.${type.name}', v);
    notifyListeners();
  }
}
