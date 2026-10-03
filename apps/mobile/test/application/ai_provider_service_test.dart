import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ai_goal/application/ai_provider_service.dart';
import 'package:ai_goal/core/ai/model_list_client.dart';
import 'package:ai_goal/data/database/app_database.dart';
import 'package:ai_goal/data/repositories/sqlite_ai_provider_repository.dart';
import 'package:ai_goal/data/repositories/sqlite_settings_repository.dart';
import 'package:ai_goal/domain/ai/ai_provider.dart';
import 'package:ai_goal/domain/ai/default_model.dart';
import 'package:ai_goal/domain/entity_ids.dart';

import '../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late AiProviderService service;

  setUp(() async {
    db = await openTestDatabase();
    service = AiProviderService(
      SqliteAiProviderRepository(db.database),
      SqliteAppSettingsRepository(db.database),
      modelListClient: ModelListClient(client: MockClient(
        (_) async => http.Response(
          '{"data":[{"id":"glm-4.6"},{"id":"glm-4.5-air"}]}',
          200,
        ),
      )),
    );
  });

  tearDown(() async {
    await db.close();
  });

  AiProvider mk() => AiProvider(
        id: EntityIds.newProviderId(),
        name: '智谱官方',
        apiStyle: ApiStyle.openaiCompatible,
        baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
        apiKey: 'sk-test',
        createdAt: DateTime(2026, 10, 3),
        updatedAt: DateTime(2026, 10, 3),
      );

  test('完整流程：添加供应商 → 一键拉取 → 选默认模型 → 删除联动清除', () async {
    // 1. 添加
    final p = await service.addProvider(mk());
    expect(await service.allProviders(), hasLength(1));

    // 2. 一键获取模型列表（走 MockClient）
    final models = await service.fetchAndCacheModels(p.id);
    expect(models.map((m) => m.modelId).toSet(), {'glm-4.6', 'glm-4.5-air'});
    // 缓存读取与拉取一致
    expect(await service.cachedModels(p.id), hasLength(2));

    // 3. 选择默认模型
    await service.setDefaultModel(p.id, 'glm-4.6');
    expect(
      await service.defaultModelSelection(),
      DefaultModelSelection(providerId: p.id, modelId: 'glm-4.6'),
    );

    // 4. 手动补录并设为默认
    await service.addManualModel(p.id, 'glm-5-preview');
    await service.setDefaultModel(p.id, 'glm-5-preview');
    expect((await service.defaultModelSelection())!.modelId, 'glm-5-preview');

    // 5. 删除供应商 → 默认模型一并清除
    await service.deleteProvider(p.id);
    expect(await service.allProviders(), isEmpty);
    expect(await service.defaultModelSelection(), isNull);
  });

  test('拉取失败不影响已有缓存（异常上抛，缓存不变）', () async {
    final failing = AiProviderService(
      SqliteAiProviderRepository(db.database),
      SqliteAppSettingsRepository(db.database),
      modelListClient: ModelListClient(client: MockClient(
        (_) async => http.Response('{"error":"rate limited"}', 429),
      )),
    );
    final p = await failing.addProvider(mk());
    await service.fetchAndCacheModels(p.id); // 先成功缓存一次

    await expectLater(
      failing.fetchAndCacheModels(p.id),
      throwsA(isA<ModelListException>()),
    );
    expect(await service.cachedModels(p.id), hasLength(2));
  });

  test('启停供应商', () async {
    final p = await service.addProvider(mk());
    await service.setProviderEnabled(p.id, false);
    expect((await service.allProviders()).single.enabled, isFalse);
  });
}
