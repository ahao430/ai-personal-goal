/// 时间列编解码约定。
///
/// 所有时间列统一存「截断到毫秒的 UTC ISO8601」字符串：
/// - 固定 3 位毫秒 → 字典序与时间序一致，SQL 的范围比较 / ORDER BY 安全；
/// - 统一 UTC → 为未来云同步的多时区合并铺路；
/// - 读取时转回本地时间，供 UI 展示。
library;

String encodeTime(DateTime t) => DateTime.fromMillisecondsSinceEpoch(
      t.millisecondsSinceEpoch,
      isUtc: true,
    ).toIso8601String();

String? encodeTimeOrNull(DateTime? t) => t == null ? null : encodeTime(t);

DateTime decodeTime(String s) => DateTime.parse(s).toLocal();

DateTime? decodeTimeOrNull(String? s) => s == null ? null : decodeTime(s);
