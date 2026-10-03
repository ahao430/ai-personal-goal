import 'ai_model_info.dart';
import 'ai_provider.dart';

/// AI 供应商与模型缓存的仓储接口。
abstract interface class AiProviderRepository {
  Future<AiProvider> insert(AiProvider provider);
  Future<AiProvider> update(AiProvider provider);
  Future<AiProvider?> findById(String id);

  /// [enabled] 为空时返回全部。
  Future<List<AiProvider>> findAll({bool? enabled});

  /// 删除供应商（模型缓存经外键级联删除）。
  Future<void> delete(String id);

  /// 用一次拉取结果替换该供应商的 fetched 模型；
  /// manual 条目保留，与 fetched 同名时 manual 优先。
  Future<List<AiModelInfo>> replaceFetchedModels(
    String providerId,
    List<AiModelInfo> fetched,
  );

  Future<List<AiModelInfo>> modelsOfProvider(String providerId);

  /// 手动补录模型（manual，长期保留）。
  Future<AiModelInfo> addManualModel(AiModelInfo model);

  Future<void> deleteModel(String providerId, String modelId);
}
