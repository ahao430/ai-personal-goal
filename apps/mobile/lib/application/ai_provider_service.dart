import '../core/ai/model_list_client.dart';
import '../domain/ai/ai_model_info.dart';
import '../domain/ai/ai_provider.dart';
import '../domain/ai/ai_provider_repository.dart';
import '../domain/ai/default_model.dart';
import '../domain/settings/app_settings.dart';

/// AI 供应商用例编排：供应商 CRUD、一键拉取模型、手动补录、默认模型联动。
///
/// UI 只与本服务交互，不直接碰 Repository / HTTP 客户端。
class AiProviderService {
  AiProviderService(
    this._providers,
    this._settings, {
    ModelListClient? modelListClient,
  }) : modelListClient = modelListClient ?? ModelListClient();

  final AiProviderRepository _providers;
  final AppSettingsRepository _settings;
  final ModelListClient modelListClient;

  // ── 供应商 ─────────────────────────────────────────────

  Future<AiProvider> addProvider(AiProvider provider) =>
      _providers.insert(provider);

  Future<AiProvider> updateProvider(AiProvider provider) =>
      _providers.update(provider);

  Future<void> setProviderEnabled(String providerId, bool enabled) async {
    final provider = await _providers.findById(providerId);
    if (provider == null) return;
    await _providers.update(provider.copyWith(enabled: enabled));
  }

  Future<List<AiProvider>> allProviders() => _providers.findAll();

  /// 删除供应商；若默认模型指向它，则一并清除默认模型设置。
  Future<void> deleteProvider(String providerId) async {
    final defaultModel = await defaultModelSelection();
    await _providers.delete(providerId);
    if (defaultModel?.providerId == providerId) {
      await clearDefaultModel();
    }
  }

  // ── 模型列表 ───────────────────────────────────────────

  /// 一键获取：调用供应商 API 拉取模型并替换 fetched 缓存。
  Future<List<AiModelInfo>> fetchAndCacheModels(String providerId) async {
    final provider = await _providers.findById(providerId);
    if (provider == null) {
      throw StateError('供应商不存在: $providerId');
    }
    final fetched = await modelListClient.fetchModels(provider);
    final now = DateTime.now();
    return _providers.replaceFetchedModels(
      providerId,
      fetched
          .map(
            (m) => AiModelInfo(
              providerId: providerId,
              modelId: m.modelId,
              displayName: m.displayName,
              source: AiModelSource.fetched,
              updatedAt: now,
            ),
          )
          .toList(),
    );
  }

  /// 读取缓存（不触发网络）。
  Future<List<AiModelInfo>> cachedModels(String providerId) =>
      _providers.modelsOfProvider(providerId);

  /// 手动补录模型（部分服务的 /models 不全）。
  Future<AiModelInfo> addManualModel(
    String providerId,
    String modelId, {
    String? displayName,
  }) {
    return _providers.addManualModel(
      AiModelInfo(
        providerId: providerId,
        modelId: modelId.trim(),
        displayName: displayName?.trim().isEmpty == true ? null : displayName?.trim(),
        source: AiModelSource.manual,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> removeModel(String providerId, String modelId) async {
    await _providers.deleteModel(providerId, modelId);
    final defaultModel = await defaultModelSelection();
    if (defaultModel?.providerId == providerId &&
        defaultModel?.modelId == modelId) {
      await clearDefaultModel();
    }
  }

  // ── 默认模型 ───────────────────────────────────────────

  Future<DefaultModelSelection?> defaultModelSelection() async {
    final raw = await _settings.read(kDefaultModelSettingKey);
    return DefaultModelSelection.decode(raw);
  }

  Future<void> setDefaultModel(String providerId, String modelId) async {
    await _settings.write(
      kDefaultModelSettingKey,
      DefaultModelSelection(providerId: providerId, modelId: modelId).encode(),
    );
  }

  Future<void> clearDefaultModel() =>
      _settings.delete(kDefaultModelSettingKey);

  /// 模型链：默认模型优先，其余已启用供应商各补一个候选模型。
  ///
  /// Agent 对话与每日回顾等内部任务共用同一条链（plan §23 Fallback）。
  Future<List<(AiProvider, String)>> modelChain() async {
    final chain = <(AiProvider, String)>[];
    final defaultSelection = await defaultModelSelection();
    final enabled = (await allProviders()).where((p) => p.enabled).toList();

    if (defaultSelection != null) {
      final provider = enabled
          .where((p) => p.id == defaultSelection.providerId)
          .firstOrNull;
      if (provider != null) {
        chain.add((provider, defaultSelection.modelId));
      }
    }
    for (final provider in enabled) {
      if (chain.any((c) => c.$1.id == provider.id)) continue;
      final models = await cachedModels(provider.id);
      if (models.isNotEmpty) {
        chain.add((provider, models.first.modelId));
      }
    }
    return chain;
  }
}
