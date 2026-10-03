import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ai_goal/application/app_services.dart';
import 'package:ai_goal/application/daily_review_service.dart';
import 'package:ai_goal/core/ai/chat_client.dart';
import 'package:ai_goal/data/database/app_database.dart';
import 'package:ai_goal/domain/ai/ai_provider.dart';

import '../helpers/test_database.dart';

const kUtf8Json = {'content-type': 'application/json; charset=utf-8'};

String _text(String text) =>
    '{"choices":[{"message":{"role":"assistant","content":"$text"}}]}';

AiProvider _providerOf(String id) => AiProvider(
      id: id,
      name: id,
      apiStyle: ApiStyle.openaiCompatible,
      baseUrl: 'https://$id.example.com/v1',
      apiKey: 'sk-$id',
      createdAt: DateTime(2026, 10, 3),
      updatedAt: DateTime(2026, 10, 3),
    );

void main() {
  late AppDatabase db;
  late AppServices services;
  final now = DateTime(2026, 10, 3, 9, 30);

  setUp(() async {
    db = await openTestDatabase();
    services = AppServices.of(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedProvider(String id, {String model = 'glm-4.6'}) async {
    final provider =
        await services.aiProviderService.addProvider(_providerOf(id));
    await services.aiProviderService.addManualModel(provider.id, model);
    await services.aiProviderService.setDefaultModel(provider.id, model);
  }

  test('未配置供应商 → null（首页不显示卡片）', () async {
    final service = DailyReviewService(
      services,
      chatClient: ChatClient(
        client: MockClient((_) => throw StateError('不应发起请求')),
      ),
    );
    expect(await service.review(now: now), isNull);
  });

  test('功能开关关闭 → null 且不发请求', () async {
    await seedProvider('provider_main');
    final service = DailyReviewService(
      services,
      chatClient: ChatClient(
        client: MockClient((_) => throw StateError('不应发起请求')),
      ),
    );
    await service.setEnabled(false);
    expect(await service.review(now: now), isNull);
  });

  test('生成成功：写缓存，当天第二次不再发请求', () async {
    await seedProvider('provider_main');
    var calls = 0;
    final service = DailyReviewService(
      services,
      chatClient: ChatClient(
        client: MockClient((_) async {
          calls++;
          return http.Response(_text('昨天有一项没完成，今天 19:00 有晚间快走。'),
              200, headers: kUtf8Json);
        }),
      ),
    );

    final first = await service.review(now: now);
    expect(first, contains('晚间快走'));
    final second = await service.review(now: now);
    expect(second, first);
    expect(calls, 1);

    // 缓存键按天隔离：明天会重新生成
    final tomorrow = await service.review(
        now: now.add(const Duration(days: 1)));
    expect(tomorrow, isNotNull);
    expect(calls, 2);
  });

  test('供应商回退：首选 401 → 备用成功', () async {
    await seedProvider('provider_a', model: 'model-a');
    await seedProvider('provider_b', model: 'model-b');
    // 第二次 seed 会覆盖默认模型，显式切回 a 作为首选
    await services.aiProviderService.setDefaultModel('provider_a', 'model-a');
    final hosts = <String>[];
    final service = DailyReviewService(
      services,
      chatClient: ChatClient(
        client: MockClient((request) async {
          hosts.add(request.url.host);
          if (hosts.length == 1) {
            return http.Response('{"error":"unauthorized"}', 401);
          }
          return http.Response(_text('来自备用模型'), 200, headers: kUtf8Json);
        }),
      ),
    );

    final review = await service.review(now: now);
    expect(review, '来自备用模型');
    expect(hosts.first, 'provider_a.example.com');
    expect(hosts.last, 'provider_b.example.com');
  });

  test('空响应（全部供应商都返回空）→ null', () async {
    await seedProvider('provider_main');
    final service = DailyReviewService(
      services,
      chatClient: ChatClient(
        client: MockClient((_) async => http.Response(
            '{"choices":[{"message":{"role":"assistant","content":null}}]}',
            200, headers: kUtf8Json)),
      ),
    );
    expect(await service.review(now: now), isNull);
  });

  test('关闭开关后清理旧缓存再开启会重新生成', () async {
    await seedProvider('provider_main');
    var calls = 0;
    final service = DailyReviewService(
      services,
      chatClient: ChatClient(
        client: MockClient((_) async {
          calls++;
          return http.Response(_text('指引'), 200, headers: kUtf8Json);
        }),
      ),
    );
    await service.review(now: now);
    expect(calls, 1);

    // 关闭 → null（缓存逻辑不读旧值）
    await service.setEnabled(false);
    expect(await service.review(now: now), isNull);

    // 重新开启 → 由于同日缓存键仍在，直接命中缓存不重新生成
    await service.setEnabled(true);
    final again = await service.review(now: now);
    expect(again, '指引');
    expect(calls, 1);
  });
}
