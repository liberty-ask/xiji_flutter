/// 客户端输入校验的公共规则（与服务端 ValidationUtils 保持同一口径）。
class Validators {
  static final RegExp _chinaMobile = RegExp(r'^1[3-9]\d{9}$');

  /// 中国大陆手机号：1 开头、第二位 3-9、共 11 位。
  static bool isChinaMobile(String value) => _chinaMobile.hasMatch(value);
}
