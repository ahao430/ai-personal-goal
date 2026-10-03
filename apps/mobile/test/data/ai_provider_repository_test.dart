import 'package:flutter_test/flutter_test.dart';

import 'package:ai_goal/data/database/app_database.dart';
import 'package:ai_goal/data/repositories/sqlite_ai_provider_repository.dart';
import 'package:ai_goal/data/repositories/sqlite_settings_repository.dart';
import 'package:ai_goal/domain/ai/ai_model_info.dart';
import 'package:ai_goal/domain/ai/ai_provider.dart';
import 'package:ai_goal/domain/ai/default_model.dart';

import '../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late SqliteAiProviderRepository providers;
  late SqliteAppSettingsRepository settings;

  setUp(() async {
    db = await openTestDatabase();
    providers = SqliteAiProviderRepository(db.database);
    settings = SqliteAppSettingsRepository(db.database);
  });

  tearDown(() async {
    await db.close();
  });

  AiProvider mkProvider(String id, {bool enabled = true}) => AiProvider(
        id: id,
        name: '供应商 $id',
        apiStyle: ApiStyle.openaiCompatible,
        baseUrl: 'https://example.com/v1',
        apiKey: 'sk-test-key-123456',
        enabled: enabled,
        createdAt: DateTime(2026, 10, 3),
        updatedAt: DateTime(2026, 10, 3),
      );

  AiModelInfo mkModel(String providerId, String modelId,
          {AiModelSource source = AiModelSource.fetched}) =>
      AiModelInfo(
        providerId: providerId,
        modelId: modelId,
        source: source,
        updatedAt: DateTime(2026, 10, 3),
      );

  group('AiProviderRepository', () {
    test('插入 / 查询 / 启停 / 更新', () async {
      await providers.insert(mkProvider('provider_a'));
      await providers.insert(mkProvider('provider_b', enabled: false));

      final all = await providers.findAll();
      expect(all, hasLength(2));

      expect(await providers.findAll(enabled: true), hasLength(1));

      final a = (await providers.findById('provider_a'))!;
      expect(a.maskedApiKey, '••••3456');

      final renamed = await providers.update(a.copyWith(name: '智谱官方'));
      expect(renamed.name, '智谱官方');
      expect((await providers.findById('provider_a'))!.name, '智谱官方');
    });

    test('更新不存在的供应商抛错', () async {
      expect(
        () => providers.update(mkProvider('provider_ghost')),
        throwsStateError,
      );
    });

    test('一键拉取语义：fetched 全量替换，manual 保留且优先', () async {
      const pid = 'provider_m';
      await providers.insert(mkProvider(pid));

      // 第一次拉取
      await providers.replaceFetchedModels(pid, [
        mkModel(pid, 'glm-4.6'),
        mkModel(pid, 'glm-4.5-air'),
      ]);
      // 手动补录（服务列表里没有的）
      await providers.addManualModel(
        mkModel(pid, 'my-custom-model', source: AiModelSource.manual),
      );

      // 第二次拉取：上游已下架 glm-4.5-air，新增 glm-5
      final merged = await providers.replaceFetchedModels(pid, [
        mkModel(pid, 'glm-4.6'),
        mkModel(pid, 'glm-5'),
      ]);

      expect(
        merged.map((m) => m.modelId).toSet(),
        {'glm-4.6', 'glm-5', 'my-custom-model'},
      );
      // manual 条目在同名冲突时优先保留
      final custom = merged.singleWhere((m) => m.modelId == 'my-custom-model');
      expect(custom.source, AiModelSource.manual);
    });

    test('删除供应商级联删除模型缓存', () async {
      const pid = 'provider_del';
      await providers.insert(mkProvider(pid));
      await providers.replaceFetchedModels(pid, [mkModel(pid, 'm1')]);

      await providers.delete(pid);

      expect(await providers.findById(pid), isNull);
      expect(await providers.modelsOfProvider(pid), isEmpty);
    });

    test('手动模型覆盖同名 fetched 条目', () async {
      const pid = 'provider_ov';
      await providers.insert(mkProvider(pid));
      await providers.replaceFetchedModels(pid, [mkModel(pid, 'glm-4.6')]);

      await providers.addManualModel(
        mkModel(pid, 'glm-4.6', source: AiModelSource.manual),
      );

      final models = await providers.modelsOfProvider(pid);
      expect(models.single.source, AiModelSource.manual);
    });
  });

  group('AppSettingsRepository', () {
    test('读写删与默认模型编解码', () async {
      expect(await settings.read(kDefaultModelSettingKey), isNull);

      final selection =
          DefaultModelSelection(providerId: 'provider_a', modelId: 'glm-4.6');
      await settings.write(kDefaultModelSettingKey, selection.encode());

      expect(
        DefaultModelSelection.decode(await settings.read(kDefaultModelSettingKey)),
        selection,
      );

      await settings.delete(kDefaultModelSettingKey);
      expect(await settings.read(kDefaultModelSettingKey), isNull);
      // 删除不存在的键不应抛错
      await settings.delete(kDefaultModelSettingKey);
    });
  });
}
