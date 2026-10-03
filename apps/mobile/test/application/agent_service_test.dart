import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ai_goal/application/agent_service.dart';
import 'package:ai_goal/application/app_services.dart';
import 'package:ai_goal/core/ai/chat_client.dart';
import 'package:ai_goal/data/database/app_database.dart';
import 'package:ai_goal/domain/ai/ai_provider.dart';

import '../helpers/test_database.dart';
const kUtf8Json = {'content-type': 'application/json; charset=utf-8'};


/// OpenAI 风格响应体构造。
String _text(String text) =>
    '{"choices":[{"message":{"role":"assistant","content":'
    '${text.isEmpty ? 'null' : '"$text"'}}}]}';

String _toolCall(String id, String name, Map<String, Object?> args) =>
    jsonEncode({
      'choices': [
        {
          'message': {
            'role': 'assistant',
            'content': null,
            'tool_calls': [
              {
                'id': id,
                'type': 'function',
                'function': {'name': name, 'arguments': jsonEncode(args)},
              },
            ],
          },
        },
      ],
    });

/// 顺序执行的 Mock HTTP 客户端。
http.Client _seq(List<http.Response> responses, {void Function()? onRequest}) {
  var i = 0;
  return MockClient((request) async {
    onRequest?.call();
    return responses[i++ % responses.length];
  });
}

AiProvider _providerOf(String id, String name) => AiProvider(
      id: id,
      name: name,
      apiStyle: ApiStyle.openaiCompatible,
      baseUrl: 'https://$id.example.com/v1',
      apiKey: 'sk-$id',
      createdAt: DateTime(2026, 10, 3),
      updatedAt: DateTime(2026, 10, 3),
    );

/// 配一个已设默认模型的供应商。
Future<AiProvider> _seedProvider(AppServices s, String id, String name,
    {String model = 'glm-4.6'}) async {
  final provider = await s.aiProviderService.addProvider(_providerOf(id, name));
  await s.aiProviderService.addManualModel(provider.id, model);
  await s.aiProviderService.setDefaultModel(provider.id, model);
  return provider;
}

void main() {
  late AppDatabase db;
  late AppServices services;

  setUp(() async {
    db = await openTestDatabase();
    services = AppServices.of(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('未配置供应商时抛 AgentNotConfiguredException，不发起网络请求',
      () async {
    final agent = AgentService(
      services,
      chatClient: ChatClient(
        client: MockClient((_) => throw StateError('不应发起网络请求')),
      ),
    );
    expect(
      () => agent.send(userText: '你好'),
      throwsA(isA<AgentNotConfiguredException>()),
    );
  });

  test('完整闭环：自然语言 → 工具调用 → SQLite 落库 → 回答', () async {
    await _seedProvider(services, 'provider_main', '智谱官方');

    // 模拟真实模型：从上一轮工具结果里读取 goalId 用于下一个调用
    var round = 0;
    final client = MockClient((request) async {
      round++;
      final body = jsonDecode(request.body) as Map;
      String? goalId;
      for (final m in body['messages'] as List) {
        if ((m as Map)['role'] != 'tool') continue;
        final payload = jsonDecode(m['content'] as String) as Map;
        final data = payload['data'];
        if (data is Map && data['goal'] is Map) {
          goalId = (data['goal'] as Map)['id'] as String;
        }
      }
      if (round == 1) {
        return http.Response(
          _toolCall('c1', 'create_goal',
              {'title': '三个月减掉5kg', 'targetDate': '2026-12-31'}),
          200, headers: kUtf8Json,
        );
      }
      if (round == 2) {
        return http.Response(
          _toolCall('c2', 'create_task', {'goalId': goalId, 'title': '晚间快走'}),
          200, headers: kUtf8Json,
        );
      }
      return http.Response(
        _text('已为你创建目标「三个月减掉5kg」和第一个任务「晚间快走」。'),
        200, headers: kUtf8Json,
      );
    });

    final agent = AgentService(services, chatClient: ChatClient(client: client));

    final activities = <String>[];
    final result = await agent.send(
      userText: '我想三个月减掉5kg',
      onActivity: activities.add,
    );

    expect(result.text, contains('三个月减掉5kg'));
    expect(activities, containsAll(['正在创建目标…', '正在创建任务…']));

    // 数据真实落库
    final goals = await services.goals.findAll();
    expect(goals.single.title, '三个月减掉5kg');
    expect(goals.single.targetDate, isNotNull);
    final tasks = await services.tasks.findByGoal(goals.single.id);
    expect(tasks.single.title, '晚间快走');

    // 会话持久化：user + assistant
    final messages =
        await services.conversations.messages(result.conversationId);
    expect(
      messages.where((m) => m.role == 'user').single.content,
      '我想三个月减掉5kg',
    );
    expect(
      messages.where((m) => m.role == 'assistant').single.content,
      contains('晚间快走'),
    );
  });

  test('工具执行错误回传给模型并继续循环', () async {
    await _seedProvider(services, 'provider_main', '智谱官方');
    final agent = AgentService(
      services,
      chatClient: ChatClient(client: _seq([
        http.Response(_toolCall('c1', 'no_such_tool', {}), 200, headers: kUtf8Json),
        http.Response(_toolCall('c2', 'get_goals', {}), 200, headers: kUtf8Json),
        http.Response(_text('当前还没有目标。'), 200, headers: kUtf8Json),
      ])),
    );

    final result = await agent.send(userText: '看看我的目标');
    expect(result.text, '当前还没有目标。');
  });

  test('供应商回退：首选失败自动切换到备用', () async {
    final a = await _seedProvider(services, 'provider_a', '首选', model: 'model-a');
    final b = await _seedProvider(services, 'provider_b', '备用', model: 'model-b');
    // 默认指向 A
    await services.aiProviderService.setDefaultModel(a.id, 'model-a');

    final hosts = <String>[];
    var call = 0;
    final client = MockClient((request) async {
      hosts.add(request.url.host);
      call++;
      if (call == 1) {
        return http.Response('{"error":"unauthorized"}', 401);
      }
      return http.Response(_text('来自备用模型'), 200, headers: kUtf8Json);
    });

    final result = await AgentService(
      services,
      chatClient: ChatClient(client: client),
    ).send(userText: 'hi');

    expect(hosts.first, 'provider_a.example.com');
    expect(hosts.last, 'provider_b.example.com');
    expect(result.text, '来自备用模型');
    expect(result.fallbackNote, contains('备用'));
    // b 只用于回退断言存在
    expect(b.id, 'provider_b');
  });

  test('工具轮数超限保护', () async {
    await _seedProvider(services, 'provider_main', '智谱官方');
    // 每轮都要求调用工具，永远不给文本回答（循环取同一个响应）
    final agent = AgentService(
      services,
      chatClient: ChatClient(client: _seq([
        http.Response(_toolCall('c_loop', 'get_goals', {}), 200, headers: kUtf8Json),
      ])),
    );
    expect(
      () => agent.send(userText: 'hi'),
      throwsA(isA<ChatException>()),
    );
  });

  test('结构性规划走 propose_plan：提案挂到 assistant 消息，不直接落目标', () async {
    await _seedProvider(services, 'provider_main', '智谱官方');

    final client = _seq([
      http.Response(
        _toolCall('c1', 'propose_plan', {
          'kind': 'create',
          'title': '三个月减掉 5kg',
          'targetDate': '2026-12-31T00:00:00',
          'metric': {
            'name': '体重',
            'unit': 'kg',
            'startValue': 72.5,
            'targetValue': 67.5,
            'direction': 'decrease',
          },
          'phases': [
            {
              'title': '适应期',
              'tasks': [
                {'title': '晚间快走 30 分钟', 'estimatedMinutes': 30},
              ],
            },
          ],
          'reason': '每周约 0.4kg，安全节奏',
        }),
        200, headers: kUtf8Json,
      ),
      http.Response(
        _text('我拟了一个三阶段推进的计划，点下面的「应用计划」确认开始。'),
        200, headers: kUtf8Json,
      ),
    ]);

    final result = await AgentService(
      services,
      chatClient: ChatClient(client: client),
    ).send(userText: '我想三个月减掉5kg，帮我做个计划');

    // 没有直接创建目标 —— 一切等用户确认
    expect(await services.goals.findAll(), isEmpty);
    expect(result.proposalId, isNotNull);

    // assistant 消息挂上提案，提案处于 pending
    final messages =
        await services.conversations.messages(result.conversationId);
    final assistant =
        messages.where((m) => m.role == 'assistant').single;
    expect(assistant.proposalId, result.proposalId);
    final proposal =
        await services.proposals.findById(result.proposalId!);
    expect(proposal!.status.name, 'pending');
    expect(proposal.goalTitle, '三个月减掉 5kg');

    // 确认后应用：目标 + 阶段 + 任务落库
    await services.proposalService.apply(result.proposalId!);
    final goals = await services.goals.findAll();
    expect(goals.single.title, '三个月减掉 5kg');
  });

  test('多轮对话：历史回放给模型', () async {
    await _seedProvider(services, 'provider_main', '智谱官方');
    final bodies = <String>[];
    final client = MockClient((request) async {
      bodies.add(request.body);
      return http.Response(_text('好的'), 200, headers: kUtf8Json);
    });
    final agent = AgentService(
      services,
      chatClient: ChatClient(client: client),
    );

    final first = await agent.send(userText: '第一句');
    await agent.send(
      userText: '第二句',
      conversationId: first.conversationId,
    );

    // 第二次请求包含两句 user 历史
    final second = jsonDecode(bodies[1]) as Map;
    final roles = (second['messages'] as List)
        .map((m) => (m as Map)['role'])
        .toList();
    expect(roles.where((r) => r == 'user'), hasLength(2));
    expect(roles.where((r) => r == 'assistant'), hasLength(1));
  });
}
