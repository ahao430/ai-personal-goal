import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ai_goal/application/agent_service.dart';
import 'package:ai_goal/application/app_services.dart';
import 'package:ai_goal/core/ai/chat_client.dart';
import 'package:ai_goal/data/database/app_database.dart';
import 'package:ai_goal/domain/ai/ai_provider.dart';
import 'package:ai_goal/domain/goal/goal.dart';
import 'package:ai_goal/domain/planning/plan_proposal.dart';

import '../helpers/test_database.dart';

// 固定 AI Evaluation 用例集（plan §50 / docs/ai/evaluation.md）。
// 这些是「系统 ↔ 模型行为契约」测试：给定模型响应序列，
// 断言系统的工具执行、错误回传、上下文质量与确认规则符合预期。
// 接真实模型跑分时复用同一批用例定义。
const kUtf8Json = {'content-type': 'application/json; charset=utf-8'};

String _text(String text) =>
    '{"choices":[{"message":{"role":"assistant","content":"$text"}}]}';

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

void main() {
  late AppDatabase db;
  late AppServices services;

  setUp(() async {
    db = await openTestDatabase();
    services = AppServices.of(db);
    final provider = await services.aiProviderService.addProvider(AiProvider(
      id: 'provider_eval',
      name: '智谱官方',
      apiStyle: ApiStyle.openaiCompatible,
      baseUrl: 'https://provider_eval.example.com/v1',
      apiKey: 'sk-eval',
      createdAt: DateTime(2026, 10, 3),
      updatedAt: DateTime(2026, 10, 3),
    ));
    await services.aiProviderService.addManualModel(provider.id, 'glm-4.6');
    await services.aiProviderService.setDefaultModel(provider.id, 'glm-4.6');
  });

  tearDown(() async {
    await db.close();
  });

  AgentService makeAgent(http.Client client) =>
      AgentService(services, chatClient: ChatClient(client: client));

  Future<Goal> seedGoal() =>
      services.goalService.createGoal(title: '三个月减掉 5kg');

  /// 从 capturedBodies 提取回传给模型的工具结果列表。
  List<Map> toolResultsIn(List<Map> bodies) {
    final results = <Map>[];
    for (final body in bodies) {
      for (final m in body['messages'] as List) {
        if ((m as Map)['role'] == 'tool') {
          results.add(jsonDecode(m['content'] as String) as Map);
        }
      }
    }
    return results;
  }

  group('EV-1 工具选择（Tool Selection）', () {
    test('规划意图 → propose_plan（而非逐个 create_goal）', () async {
      final queue = <http.Response>[
        http.Response(
          _toolCall('c1', 'propose_plan', {
            'kind': 'create',
            'title': '学摄影',
            'phases': [
              {
                'title': '基础',
                'tasks': [
                  {'title': '了解曝光三要素'}
                ],
              }
            ],
          }),
          200, headers: kUtf8Json,
        ),
        http.Response(_text('已生成提案'), 200, headers: kUtf8Json),
      ];
      final result = await makeAgent(MockClient((_) async =>
              queue.isNotEmpty ? queue.removeAt(0) : http.Response(
                  _text('已生成提案'), 200, headers: kUtf8Json)))
          .send(userText: '我想学摄影');

      expect(result.proposalId, isNotNull);
      expect(await services.goals.findAll(), isEmpty, reason: 'EV-1：结构性变更不直写');
    });

    test('汇报意图 → get_tasks + complete_task 两步路由', () async {
      final goal = await seedGoal();
      final task = await services.planningService
          .createTask(title: '晚间快走', goalId: goal.id);

      var round = 0;
      final result = await makeAgent(MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        round++;
        if (round == 1) {
          return http.Response(
            _toolCall('c1', 'get_tasks', {'goalId': goal.id}),
            200, headers: kUtf8Json,
          );
        }
        if (round == 2) {
          // 从上一轮 tool 结果提取 taskId（模拟真实模型读上下文）
          var taskId = task.id;
          for (final m in (body['messages'] as List).reversed) {
            if ((m as Map)['role'] == 'tool') {
              final payload = jsonDecode(m['content'] as String) as Map;
              final tasks = payload['data']?['tasks'];
              if (tasks is List && tasks.isNotEmpty) {
                taskId = (tasks.first as Map)['id'];
                break;
              }
            }
          }
          return http.Response(
            _toolCall('c2', 'complete_task', {'taskId': taskId}),
            200, headers: kUtf8Json,
          );
        }
        return http.Response(_text('已记录完成。'), 200, headers: kUtf8Json);
      })).send(userText: '快走完成了');

      expect(result.text, contains('完成'));
      expect(
        (await services.tasks.findById(task.id))!.status.name,
        'completed',
        reason: 'EV-1：汇报正确路由到 complete_task',
      );
    });
  });

  group('EV-2 工具参数（Tool Arguments）', () {
    test('错误参数 → {ok:false} 原样回传模型自行纠正', () async {
      final bodies = <Map>[];
      var round = 0;
      final agent = makeAgent(MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        bodies.add(body);
        round++;
        if (round == 1) {
          return http.Response(
            _toolCall('c1', 'propose_plan', {'kind': 'create'}),
            200, headers: kUtf8Json, // 缺 title → ArgumentError
          );
        }
        if (round == 2) {
          // 断言错误已回传，然后纠正
          final toolResults = toolResultsIn([body]);
          expect(toolResults.last['ok'], isFalse);
          expect(toolResults.last['error'], contains('goalTitle'));
          return http.Response(
            _toolCall('c1b', 'propose_plan', {
              'kind': 'create',
              'title': '学英语',
              'phases': [
                {
                  'title': '起步',
                  'tasks': [
                    {'title': '背 50 词'}
                  ],
                }
              ],
            }),
            200, headers: kUtf8Json,
          );
        }
        return http.Response(_text('已修正并生成提案'), 200, headers: kUtf8Json);
      }));

      final result = await agent.send(userText: '帮我规划学英语');
      expect(result.proposalId, isNotNull, reason: 'EV-2：纠错后成功提案');
    });

    test('引用不存在的实体 → 明确错误信息', () async {
      final result = await services.agentService.tools.execute(
        'record_metric_value',
        {'goalId': 'goal_missing', 'metricName': '体重', 'value': 70},
      );
      expect(result['ok'], isFalse);
      expect(result['error'], contains('体重'));
    });
  });

  group('EV-3 上下文质量（Context Quality）', () {
    test('上下文包含场景 / 目标摘要 / 当前目标与开放任务', () async {
      final goal = await seedGoal();
      await services.planningService
          .createTask(title: '晚间快走', goalId: goal.id);

      final bodies = <Map>[];
      final agent = makeAgent(MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map);
        return http.Response(_text('好的'), 200, headers: kUtf8Json);
      }));
      await agent.send(userText: '今天做什么？', goalId: goal.id);

      final system =
          (bodies.first['messages'] as List).first as Map;
      final context = system['content'] as String;
      expect(context, contains('"scene":"goal_detail"'));
      expect(context, contains('三个月减掉 5kg'));
      expect(context, contains('晚间快走'));
      // 不倾倒全库：上下文里有条数上限
      expect(context.length, lessThan(6000), reason: 'EV-3：上下文紧凑');
    });
  });

  group('EV-4 确认规则（Confirmation Rules）', () {
    test('目标级操作必须走确认卡片：确认前状态不变', () async {
      final goal = await seedGoal();
      final proposal = await services.proposalService.create(
        goalId: goal.id,
        kind: ProposalKind.action,
        action: ProposalActions.cancel,
        reason: '不想做了',
      );
      expect(proposal.status, ProposalStatus.pending);
      expect(
        (await services.goals.findById(goal.id))!.status,
        GoalStatus.active,
        reason: 'EV-4：取消必须用户确认',
      );

      await services.proposalService.apply(proposal.id);
      expect(
        (await services.goals.findById(goal.id))!.status,
        GoalStatus.cancelled,
      );
    });
  });

  group('EV-5 回退（Fallback）', () {
    test('首选模型 401 → 备用供应商接手，回退信息透出', () async {
      final a = await services.aiProviderService.addProvider(AiProvider(
        id: 'provider_a',
        name: '首选',
        apiStyle: ApiStyle.openaiCompatible,
        baseUrl: 'https://provider_a.example.com/v1',
        apiKey: 'sk-a',
        createdAt: DateTime(2026, 10, 3),
        updatedAt: DateTime(2026, 10, 3),
      ));
      final b = await services.aiProviderService.addProvider(AiProvider(
        id: 'provider_b',
        name: '备用',
        apiStyle: ApiStyle.openaiCompatible,
        baseUrl: 'https://provider_b.example.com/v1',
        apiKey: 'sk-b',
        createdAt: DateTime(2026, 10, 3),
        updatedAt: DateTime(2026, 10, 3),
      ));
      await services.aiProviderService.addManualModel(a.id, 'model-a');
      await services.aiProviderService.addManualModel(b.id, 'model-b');
      await services.aiProviderService.setDefaultModel(a.id, 'model-a');

      final hosts = <String>[];
      var call = 0;
      final result = await makeAgent(MockClient((request) async {
        hosts.add(request.url.host);
        call++;
        if (call == 1) return http.Response('{"error":"unauthorized"}', 401);
        return http.Response(_text('来自备用'), 200, headers: kUtf8Json);
      })).send(userText: 'hi');

      expect(result.text, '来自备用');
      expect(hosts.first, 'provider_a.example.com');
      expect(hosts.last, isNot(hosts.first), reason: 'EV-5：回退到其它供应商');
      expect(result.fallbackNote, contains('已自动切换'));
    });
  });
}
