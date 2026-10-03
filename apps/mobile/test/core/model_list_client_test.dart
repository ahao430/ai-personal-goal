import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ai_goal/core/ai/model_list_client.dart';
import 'package:ai_goal/domain/ai/ai_provider.dart';

http.Response ok(String body) => http.Response(body, 200);

AiProvider provider({
  ApiStyle style = ApiStyle.openaiCompatible,
  String baseUrl = 'https://api.example.com/v1',
  String? apiKey = 'sk-abc',
}) =>
    AiProvider(
      id: 'provider_t',
      name: 'test',
      apiStyle: style,
      baseUrl: baseUrl,
      apiKey: apiKey,
      createdAt: DateTime(2026, 10, 3),
      updatedAt: DateTime(2026, 10, 3),
    );

void main() {
  group('ModelListClient', () {
    test('OpenAI 兼容：GET {base}/models + Bearer 头，解析 data 列表', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return ok('{"object":"list","data":['
            '{"id":"gpt-4o","object":"model","owned_by":"openai"},'
            '{"id":"gpt-4o-mini","object":"model"}'
            ']}');
      });

      final models =
          await ModelListClient(client: client).fetchModels(provider());

      expect(captured.url.toString(), 'https://api.example.com/v1/models');
      expect(captured.headers['Authorization'], 'Bearer sk-abc');
      expect(models.map((m) => m.modelId).toList(),
          ['gpt-4o', 'gpt-4o-mini']);
    });

    test('Anthropic 风格：GET {base}/v1/models + x-api-key 头，解析 display_name',
        () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return ok('{"data":['
            '{"type":"model","id":"claude-sonnet-4-20250514","display_name":"Claude Sonnet 4"}'
            '],"has_more":false}');
      });

      final models = await ModelListClient(client: client).fetchModels(
        provider(style: ApiStyle.anthropic, baseUrl: 'https://api.anthropic.com'),
      );

      expect(captured.url.toString(), 'https://api.anthropic.com/v1/models');
      expect(captured.headers['x-api-key'], 'sk-abc');
      expect(captured.headers['anthropic-version'], '2023-06-01');
      expect(captured.headers.containsKey('Authorization'), isFalse);
      expect(models.single.modelId, 'claude-sonnet-4-20250514');
      expect(models.single.displayName, 'Claude Sonnet 4');
    });

    test('Base URL 末尾斜杠被规范化', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return ok('{"data":[{"id":"m1"}]}');
      });

      await ModelListClient(client: client)
          .fetchModels(provider(baseUrl: 'https://api.example.com/v1/'));

      expect(captured.url.toString(), 'https://api.example.com/v1/models');
    });

    test('直接返回数组的服务也能解析', () async {
      final client = MockClient((_) async => ok('[{"id":"m1"},{"id":"m2"}]'));
      final models =
          await ModelListClient(client: client).fetchModels(provider());
      expect(models, hasLength(2));
    });

    test('无 Key 时不带鉴权头（部分本地服务允许匿名）', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return ok('{"data":[{"id":"m1"}]}');
      });

      await ModelListClient(client: client)
          .fetchModels(provider(apiKey: null));

      expect(captured.headers.containsKey('Authorization'), isFalse);
    });

    test('非 200 响应抛出带状态码的异常', () async {
      final client = MockClient(
        (_) async => http.Response('{"error":"invalid api key"}', 401),
      );
      expect(
        () => ModelListClient(client: client).fetchModels(provider()),
        throwsA(
          isA<ModelListException>()
              .having((e) => e.message, 'message', contains('401')),
        ),
      );
    });

    test('非法 JSON / 无法识别结构 / 空列表 均抛错', () async {
      final badJson = MockClient((_) async => ok('<html>gateway error</html>'));
      expect(
        () => ModelListClient(client: badJson).fetchModels(provider()),
        throwsA(isA<ModelListException>()),
      );

      final badShape =
          MockClient((_) async => ok('{"unexpected": {"a": 1}}'));
      expect(
        () => ModelListClient(client: badShape).fetchModels(provider()),
        throwsA(isA<ModelListException>()),
      );

      final emptyList = MockClient((_) async => ok('{"data": []}'));
      expect(
        () => ModelListClient(client: emptyList).fetchModels(provider()),
        throwsA(isA<ModelListException>()),
      );
    });

    test('缺 id 的条目被跳过', () async {
      final client = MockClient(
        (_) async => ok('{"data":[{"no_id": true},{"id":"ok"}]}'),
      );
      final models =
          await ModelListClient(client: client).fetchModels(provider());
      expect(models.single.modelId, 'ok');
    });
  });
}
