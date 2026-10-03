import '../core/external/data_provider.dart';
import '../domain/external/data_source.dart';

/// 外部数据编排（plan §49 的 Context Adapter）。
///
/// 注册全部 DataProvider；[buildExternalContext] 收集「已授权且可用」
/// 的源上下文片段（单源失败静默跳过），拼进 AI 上下文的 external 键。
class ExternalDataService {
  ExternalDataService(this._permissions, this._providers);

  final DataSourcePermissionRepository _permissions;
  final List<DataProvider> _providers;

  List<DataProvider> get providers => List.unmodifiable(_providers);

  DataProvider? providerOf(ExternalSource source) =>
      _providers.where((p) => p.source == source).firstOrNull;

  /// 某源的 App 内授权状态。
  Future<PermissionStatus> statusOf(ExternalSource source) =>
      _permissions.statusOf(source);

  /// 请求授权（weather 直接记录；health 等记录 requested 待版本开放）。
  Future<PermissionStatus> requestPermission(ExternalSource source) async {
    final provider = providerOf(source);
    if (provider == null) return PermissionStatus.notRequested;
    return provider.requestPermission();
  }

  /// 撤销授权（如天气开关关掉）。
  Future<void> revoke(ExternalSource source) =>
      _permissions.setStatus(source, PermissionStatus.notRequested);

  /// Context Adapter：已授权源的上下文片段（无可用数据返回 null）。
  Future<Map<String, Object?>?> buildExternalContext({DateTime? now}) async {
    final out = <String, Object?>{};
    for (final provider in _providers) {
      if (await provider.checkPermission() != PermissionStatus.granted) {
        continue;
      }
      try {
        final data = await provider.readContext(now: now);
        if (data != null) out[provider.source.name] = data;
      } catch (_) {
        // 单源失败不影响其它源与主流程。
      }
    }
    return out.isEmpty ? null : out;
  }
}
