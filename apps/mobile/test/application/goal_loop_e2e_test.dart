import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ai_goal/application/agent_service.dart';
import 'package:ai_goal/application/app_services.dart';
import 'package:ai_goal/core/ai/chat_client.dart';
import 'package:ai_goal/core/notifications/reminder_platform.dart';
import 'package:ai_goal/data/database/app_database.dart';
import 'package:ai_goal/domain/ai/ai_provider.dart';
import 'package:ai_goal/domain/goal/goal.dart';
import 'package:ai_goal/domain/planning/plan_proposal.dart';
import 'package:ai_goal/domain/task/task.dart';

import '../helpers/test_database.dart';
import 'notification_scheduler_test.dart' show FakeReminderPlatform;

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

/// 可编程模型：测试在每次 send 前推入本轮响应。
class _ScriptedModel {
  final _responses = <http.Response>[];
  final capturedBodies = <Map>[];

  http.Client get client => MockClient((request) async {
        capturedBodies.add(jsonDecode(request.body) as Map);
        if (_responses.isEmpty) {
          return http.Response(_text('好的'), 200, headers: kUtf8Json);
        }
        return _responses.removeAt(0);
      });

  void enqueue(List<http.Response> responses) => _responses.addAll(responses);
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 150));

void main() {
  late AppDatabase db;
  late AppServices services;
  late FakeReminderPlatform platform;
  late _ScriptedModel model;
  late AgentService agent;

  setUp(() async {
    db = await openTestDatabase();
    platform = FakeReminderPlatform();
    services = AppServices.of(db, reminderPlatform: platform);
    model = _ScriptedModel();
    agent =
        AgentService(services, chatClient: ChatClient(client: model.client));

    final provider = await services.aiProviderService.addProvider(AiProvider(
      id: 'provider_e2e',
      name: '智谱官方',
      apiStyle: ApiStyle.openaiCompatible,
      baseUrl: 'https://provider_e2e.example.com/v1',
      apiKey: 'sk-e2e',
      createdAt: DateTime(2026, 10, 3),
      updatedAt: DateTime(2026, 10, 3),
    ));
    await services.aiProviderService.addManualModel(provider.id, 'glm-4.6');
    await services.aiProviderService.setDefaultModel(provider.id, 'glm-4.6');
  });

  tearDown(() async {
    await db.close();
  });

  test('完整 Goal Loop（plan §51 V1 完成标准的自动化）', () async {
    // ── 1. 自然语言规划 → 提案（不直接落库） ──────────────
    final walkAt = DateTime.now().add(const Duration(hours: 3));
    model.enqueue([
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
                {
                  'title': '晚间快走 30 分钟',
                  'estimatedMinutes': 30,
                  'startAt': walkAt.toIso8601String(),
                  'durationMinutes': 30,
                },
              ],
            },
            {'title': '提升期'},
          ],
          'reason': '三个月 5kg，每周约 0.4kg',
        }),
        200, headers: kUtf8Json,
      ),
      http.Response(_text('计划已生成，确认后开始。'), 200, headers: kUtf8Json),
    ]);

    var result = await agent.send(userText: '我想三个月减掉5kg，帮我做个计划');
    expect(await services.goals.findAll(), isEmpty, reason: '确认前不落库');
    expect(result.proposalId, isNotNull);

    // ── 2. 确认应用 → 全套落库 + 提醒已排 + 今天可见 ───────
    final applyResult =
        await services.proposalService.apply(result.proposalId!);
    await _settle();
    expect(applyResult.phasesCreated, 2);
    expect(applyResult.tasksCreated, 1);

    final goal = (await services.goals.findById(applyResult.goalId))!;
    expect(goal.status, GoalStatus.active);
    expect((await services.metrics.findByGoal(goal.id)).single.name, '体重');

    // 以日程时间为锚点查当天视图（消除测试运行时刻的跨天不确定性）
    final home = await services.overview.homeView(now: walkAt);
    expect(
      home.today.items.map((i) => i.task.title),
      contains('晚间快走 30 分钟'),
    );

    final task = (await services.tasks.findByGoal(goal.id))
        .firstWhere((t) => t.title.contains('快走'));
    expect(
      platform.scheduled.map((r) => r.taskId),
      contains(task.id),
      reason: '应用后自动排提醒',
    );

    // ── 3. 从通知完成（通知按钮动作，App 可能未打开过 UI） ──
    await services.notificationScheduler.bootstrap();
    platform.emit(ReminderEvent(
      taskId: task.id,
      goalId: goal.id,
      action: ReminderAction.complete,
    ));
    await _settle();
    expect(
      (await services.tasks.findById(task.id))!.status,
      TaskStatus.completed,
    );

    // ── 4. 向 AI 汇报 → AI 更新进度（指标） ───────────────
    model.enqueue([
      http.Response(
        _toolCall('c2', 'record_metric_value', {
          'goalId': goal.id,
          'metricName': '体重',
          'value': 71.8,
        }),
        200, headers: kUtf8Json,
      ),
      http.Response(_text('已记录，进展不错。'), 200, headers: kUtf8Json),
    ]);
    result = await agent.send(
      userText: '顺便记录下，今天早上体重 71.8',
      conversationId: result.conversationId,
    );
    expect(
      (await services.metrics.findByGoal(goal.id)).single.currentValue,
      71.8,
    );
    final events = await services.progressEvents.findByGoal(goal.id);
    expect(events.any((e) => e.type.columnName == 'metric_updated'), isTrue);

    // ── 5. AI 分析 → 调整提案 → 应用 ─────────────────────
    model.enqueue([
      http.Response(
        _toolCall('c3', 'analyze_progress', {'goalId': goal.id}),
        200, headers: kUtf8Json,
      ),
      http.Response(
        _toolCall('c4', 'propose_plan', {
          'kind': 'adjust',
          'goalId': goal.id,
          'phases': [
            {
              'title': '巩固期',
              'tasks': [
                {'title': '加入两次力量训练', 'estimatedMinutes': 45},
              ],
            },
          ],
          'reason': '适应期已完成，提升训练多样性',
        }),
        200, headers: kUtf8Json,
      ),
      http.Response(_text('建议加入力量训练，确认后生效。'), 200, headers: kUtf8Json),
    ]);
    result = await agent.send(
      userText: '感觉适应得不错，帮我调整下计划',
      conversationId: result.conversationId,
    );
    expect(result.proposalId, isNotNull);
    expect(
      (await services.proposals.findById(result.proposalId!))!.kind,
      ProposalKind.adjust,
    );

    await services.proposalService.apply(result.proposalId!);
    expect(
      (await services.phases.findByGoal(goal.id)).map((p) => p.title),
      contains('巩固期'),
    );

    // ── 6. 二次确认：暂停提案 → 确认前不生效 → 确认后暂停 ─
    model.enqueue([
      http.Response(
        _toolCall('c5', 'propose_action', {
          'action': 'pause_goal',
          'goalId': goal.id,
          'reason': '用户说先放一放',
        }),
        200, headers: kUtf8Json,
      ),
      http.Response(_text('已发起暂停确认。'), 200, headers: kUtf8Json),
    ]);
    result = await agent.send(
      userText: '最近太忙，先放一放',
      conversationId: result.conversationId,
    );
    expect(result.proposalId, isNotNull);
    expect(
      (await services.goals.findById(goal.id))!.status,
      GoalStatus.active,
      reason: '确认前不生效',
    );

    await services.proposalService.apply(result.proposalId!);
    expect(
      (await services.goals.findById(goal.id))!.status,
      GoalStatus.paused,
    );
    await services.goalService.resumeGoal(goal.id);

    // ── 7. 收尾：完成剩余任务 → 目标达成 ──────────────────
    final remaining = (await services.tasks.findByGoal(goal.id))
        .where((t) => t.status != TaskStatus.completed)
        .toList();
    for (final t in remaining) {
      await services.planningService.completeTask(t.id);
    }

    model.enqueue([
      http.Response(
        _toolCall('c8', 'complete_goal', {'goalId': goal.id}),
        200, headers: kUtf8Json,
      ),
      http.Response(_text('恭喜，目标达成！'), 200, headers: kUtf8Json),
    ]);
    result = await agent.send(
      userText: '全部任务完成了，这个目标达成了！',
      conversationId: result.conversationId,
    );
    expect(result.text, contains('达成'));

    final finalGoal = await services.goals.findById(goal.id);
    expect(finalGoal!.status, GoalStatus.completed);
    expect(finalGoal.overallProgress, 100);

    // 会话全程可回放（提案卡片挂载在消息上）
    final messages =
        await services.conversations.messages(result.conversationId);
    expect(messages.where((m) => m.proposalId != null), isNotEmpty);
    expect(
      messages.where((m) => m.role == 'user'),
      hasLength(5),
      reason: '五轮用户输入全程同一会话',
    );
  });
}
