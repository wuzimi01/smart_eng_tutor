/// 行内标记（^加粗^ / $下划线$）处理工具
class LkTextUtils {
  static final _markReg = RegExp(r'[\^$]');
  /// 剥离标记，得到纯文本（用于存储主键、搜索匹配）
  static String strip(String s) => s.replaceAll(_markReg, '');
}
