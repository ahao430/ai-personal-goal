/// 应用级键值设置的仓储接口。
///
/// 存放少量全局偏好（默认模型、搜索模式等），值为字符串（通常是 JSON）。
/// 不要当成业务数据表使用 —— 业务数据有自己的领域表。
abstract interface class AppSettingsRepository {
  Future<String?> read(String key);

  /// 写入或覆盖。
  Future<void> write(String key, String value);

  Future<void> delete(String key);
}
