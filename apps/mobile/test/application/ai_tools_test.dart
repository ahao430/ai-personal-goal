import 'package:flutter_test/flutter_test.dart';

import 'package:ai_goal/application/ai_tools.dart';
import 'package:ai_goal/application/app_services.dart';
import 'package:ai_goal/application/tool_registry.dart';
import 'package:ai_goal/data/database/app_database.dart';

import '../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late AppServices services;
  late ToolRegistry tools;

  setUp(() async {
    db = await openTestDatabase();
    services = AppServices.of(db);
    tools = buildGoalTools(services);
  });

  tearDown(() async {
    await db.close();
  });

  test('create_goal → get_goals 全链路', () async {
    final created = await tools.execute('create_goal', {
      'title': '三个月减掉 5kg',
      'targetDate': '2026-12-31',
    });
    expect(created['ok'], isTrue);
    final goalId =
        ((created['data'] as Map)['goal'] as Map)['id'] as String;

    final listed = await tools.execute('get_goals', {'status': 'active'});
    final goals = (listed['data'] as Map)['goals'] as List;
    expect(goals.single['title'], '三个月减掉 5kg');

    // goalId 可用于后续工具
    final tasks = await tools.execute('get_tasks', {'goalId': goalId});
    expect((tasks['data'] as Map)['tasks'], isEmpty);
  });

  test('create_task + complete_task：进度联动', () async {
    final created = await tools.execute(
        'create_goal', {'title': '做 AI Goal App'});
    final goalId =
        ((created['data'] as Map)['goal'] as Map)['id'] as String;

    final t1 = await tools.execute('create_task', {
      'goalId': goalId,
      'title': '设计首页',
    });
    final t2 = await tools.execute('create_task', {
      'goalId': goalId,
      'title': '写测试',
    });
    final id1 = ((t1['data'] as Map)['task'] as Map)['id'] as String;
    final id2 = ((t2['data'] as Map)['task'] as Map)['id'] as String;

    await tools.execute('complete_task', {'taskId': id1});
    final goal = await services.goals.findById(goalId);
    expect(goal!.overallProgress, 50);

    // 取消另一个 → 100%
    await tools.execute('cancel_task', {'taskId': id2});
    expect((await services.goals.findById(goalId))!.overallProgress, 100);
  });

  test('schedule_task + reschedule_task + user_report', () async {
    final created = await tools.execute('create_goal', {'title': '学英语'});
    final goalId =
        ((created['data'] as Map)['goal'] as Map)['id'] as String;
    final task = await tools.execute('create_task', {
      'goalId': goalId,
      'title': '背单词',
    });
    final taskId = ((task['data'] as Map)['task'] as Map)['id'] as String;

    final scheduled = await tools.execute('schedule_task', {
      'taskId': taskId,
      'startAt': '2026-10-04T19:00:00',
      'durationMinutes': 30,
    });
    expect(scheduled['ok'], isTrue);

    final rescheduled = await tools.execute('reschedule_task', {
      'taskId': taskId,
      'newStartAt': '2026-10-05T20:00:00',
    });
    expect(rescheduled['ok'], isTrue);
    // 旧日程取消，只有一条 planned
    final planned = (await services.schedules.findByTask(taskId))
        .where((s) => s.status.name == 'planned');
    expect(planned, hasLength(1));

    final report = await tools.execute('user_report', {
      'goalId': goalId,
      'message': '今天背完了 50 个词',
      'taskId': taskId,
    });
    expect(report['ok'], isTrue);
    final events = await services.progressEvents.findByGoal(goalId);
    expect(events.where((e) => e.type.columnName == 'user_report'),
        hasLength(1));
  });

  test('record_metric_value：按名称定位指标并推进', () async {
    final goal = await services.goalService.createGoal(title: '减重');
    await services.goalService.addMetric(
      goal.id,
      name: '体重',
      unit: 'kg',
      initialValue: 73.4,
      targetValue: 68.4,
    );

    final result = await tools.execute('record_metric_value', {
      'goalId': goal.id,
      'metricName': '体重',
      'value': 72.6,
    });
    expect(result['ok'], isTrue);
    final metrics = await services.metrics.findByGoal(goal.id);
    expect(metrics.single.currentValue, 72.6);

    // 指标不存在 → 错误回传模型
    final missing = await tools.execute('record_metric_value', {
      'goalId': goal.id,
      'metricName': '体脂',
      'value': 20,
    });
    expect(missing['ok'], isFalse);
    expect((missing['error'] as String), contains('体脂'));
  });

  test('未知工具返回错误而非抛异常', () async {
    final result = await tools.execute('nope', {});
    expect(result['ok'], isFalse);
    expect(result['error'], contains('未知工具'));
  });

  test('工具 schema 全部暴露给模型', () {
    final names = tools.specs.map((s) => s.name).toList();
    expect(names, containsAll([
      'get_goals', 'create_goal', 'update_goal', 'pause_goal', 'resume_goal',
      'complete_goal', 'get_phases', 'create_phase', 'get_tasks',
      'create_task', 'complete_task', 'postpone_task', 'cancel_task',
      'schedule_task', 'reschedule_task', 'get_progress', 'user_report',
      'get_metrics', 'record_metric_value', 'propose_plan',
    ]));
  });

  test('propose_plan：不落目标数据，只存 pending 提案并挂会话', () async {
    final conv = await services.conversations.create(title: '规划');
    final result = await tools.execute('propose_plan', {
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
              'startAt': '2026-10-05T19:00:00',
            },
          ],
        },
      ],
      'reason': '三个月 5kg，每周约 0.4kg，安全可控',
    }, context: ToolRunContext(conversationId: conv.id));

    expect(result['ok'], isTrue);
    final data = result['data'] as Map;
    final proposalId = data['proposalId'] as String;

    // 目标数据未被直接创建
    expect(await services.goals.findAll(), isEmpty);

    final proposal = await services.proposals.findById(proposalId);
    expect(proposal!.conversationId, conv.id);
    expect(proposal.status.name, 'pending');
    expect(proposal.goalTitle, '三个月减掉 5kg');
    expect(proposal.metricDecrease, isTrue);
    expect(proposal.phases.single.tasks.single.estimatedMinutes, 30);
    expect(proposal.phases.single.tasks.single.scheduleStartAt, isNotNull);
  });

  test('propose_plan：adjust 指向不存在的目标 → 错误回传', () async {
    final result = await tools.execute('propose_plan', {
      'kind': 'adjust',
      'goalId': 'goal_missing',
      'targetDate': '2027-01-31T00:00:00',
    });
    expect(result['ok'], isFalse);
    expect(result['error'], contains('goal_missing'));
  });

  test('analyze_progress：聚合事实返回给模型', () async {
    final created = await tools.execute('create_goal', {'title': '跑步'});
    final goalId =
        ((created['data'] as Map)['goal'] as Map)['id'] as String;
    final overdue = await tools.execute('create_task', {
      'goalId': goalId,
      'title': '昨天的跑',
      'dueDate': DateTime.now()
          .subtract(const Duration(days: 2))
          .toIso8601String(),
    });
    final ok = await tools.execute('create_task',
        {'goalId': goalId, 'title': '今天的跑'});
    await tools.execute('complete_task',
        {'taskId': ((ok['data'] as Map)['task'] as Map)['id'] as String});
    expect(overdue, isNotNull);

    final result = await tools.execute('analyze_progress', {
      'goalId': goalId,
    }, context: const ToolRunContext());
    expect(result['ok'], isTrue);
    final data = result['data'] as Map;
    final stats = data['taskStats'] as Map;
    expect(stats['total'], 2);
    expect(stats['completed'], 1);
    expect(stats['overdue'], 1);
    expect(stats['completionRate'], 50);
    expect(data['hasSignals'], isTrue);
  });

  test('propose_action：生成 action 提案并挂会话', () async {
    final created = await tools.execute('create_goal', {'title': '学英语'});
    final goalId =
        ((created['data'] as Map)['goal'] as Map)['id'] as String;
    final conv = await services.conversations.create(title: 't');

    final result = await tools.execute('propose_action', {
      'action': 'pause_goal',
      'goalId': goalId,
      'reason': '用户说先放一放',
    }, context: ToolRunContext(conversationId: conv.id));
    expect(result['ok'], isTrue);

    final id = (result['data'] as Map)['proposalId'] as String;
    final proposal = await services.proposals.findById(id);
    expect(proposal!.kind.name, 'action');
    expect(proposal.action, 'pause_goal');
    expect(proposal.goalTitle, '学英语');
    expect(proposal.conversationId, conv.id);
    expect(proposal.status.name, 'pending');
  });

  test('propose_action：非法操作 → 错误回传', () async {
    final created = await tools.execute('create_goal', {'title': 'x'});
    final goalId =
        ((created['data'] as Map)['goal'] as Map)['id'] as String;
    final result = await tools.execute('propose_action', {
      'action': 'nuke_goal',
      'goalId': goalId,
    });
    expect(result['ok'], isFalse);
    expect(result['error'], contains('不支持的操作'));
  });
}
