import 'package:flutter_test/flutter_test.dart';

import 'package:ai_goal/application/app_services.dart';
import 'package:ai_goal/data/database/app_database.dart';
import 'package:ai_goal/domain/goal/goal.dart';
import 'package:ai_goal/domain/goal/goal_metric.dart';
import 'package:ai_goal/domain/phase/phase.dart';
import 'package:ai_goal/domain/planning/plan_proposal.dart';
import 'package:ai_goal/domain/schedule/schedule.dart';
import 'package:ai_goal/domain/task/task.dart';

import '../helpers/test_database.dart';

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

  Future<PlanProposal> createProposal({
    String? conversationId,
    String? goalId,
    ProposalKind kind = ProposalKind.create,
  }) async =>
      await services.proposalService.create(
        conversationId: conversationId,
        goalId: goalId,
        kind: kind,
        goalTitle: kind == ProposalKind.create ? '三个月减掉 5kg' : null,
        targetDate: DateTime(2026, 12, 31),
        metricName: '体重',
        metricUnit: 'kg',
        metricStartValue: 72.5,
        metricTargetValue: 67.5,
        metricDecrease: true,
        phases: [
          ProposalPhaseDraft(
            title: '适应期',
            description: '建立运动习惯',
            tasks: [
              ProposalTaskDraft(
                title: '晚间快走 30 分钟',
                estimatedMinutes: 30,
                scheduleStartAt: DateTime(2026, 10, 5, 19),
                scheduleMinutes: 30,
              ),
              ProposalTaskDraft(title: '记录基础体重'),
            ],
          ),
          ProposalPhaseDraft(title: '提升期', tasks: const []),
        ],
      );

  test('apply(create)：目标 + 指标 + 阶段 + 任务 + 日程一次落库', () async {
    final conv = await services.conversations.create(title: 't');
    final proposal = await createProposal(conversationId: conv.id);

    final result = await services.proposalService.apply(proposal.id);

    expect(result.phasesCreated, 2);
    expect(result.tasksCreated, 2);
    expect(result.schedulesCreated, 1);

    // 目标与指标
    final goal = await services.goals.findById(result.goalId);
    expect(goal!.title, '三个月减掉 5kg');
    final metrics = await services.metrics.findByGoal(goal.id);
    final metric = metrics.single;
    expect(metric.name, '体重');
    expect(metric.targetValue, 67.5);
    expect(metric.direction, MetricDirection.decrease);

    // 阶段顺序与任务归属
    final phases = await services.phases.findByGoal(goal.id);
    expect(phases.map((p) => p.title), ['适应期', '提升期']);
    final tasks = await services.tasks.findByGoal(goal.id);
    expect(tasks.map((t) => t.title), contains('晚间快走 30 分钟'));
    final walked = tasks.firstWhere((t) => t.title.contains('快走'));
    expect(walked.phaseId, phases.first.id);
    expect(walked.estimatedMinutes, 30);

    // 日程已排
    final schedules = await services.schedules.findByTask(walked.id);
    expect(schedules.single.status, ScheduleStatus.planned);

    // 提案状态与事件、会话活动消息
    final after = await services.proposals.findById(proposal.id);
    expect(after!.status, ProposalStatus.applied);
    final events = await services.progressEvents.findByGoal(goal.id);
    expect(
      events.any((e) => e.type.columnName == 'plan_applied'),
      isTrue,
    );
    final messages = await services.conversations.messages(conv.id);
    expect(
      messages.any((m) => m.role == 'activity' && m.content == '已应用计划'),
      isTrue,
    );
  });

  test('apply(adjust)：改期 + 取消阶段/任务 + 新增阶段', () async {
    final goal = await services.goalService.createGoal(title: '学英语');
    final phase1 = await services.planningService.createPhase(
        goalId: goal.id, title: '背单词');
    final phase2 = await services.planningService.createPhase(
        goalId: goal.id, title: '练听力');
    final t1 = await services.planningService.createTask(
        title: '背 100 词', phaseId: phase1.id);
    final t2 = await services.planningService.createTask(
        title: '精听一篇', phaseId: phase2.id);
    final tKeep = await services.planningService.createTask(
        title: '保持任务', goalId: goal.id, phaseId: phase1.id);
    await services.planningService.completeTask(tKeep.id);

    final proposal = await services.proposalService.create(
      goalId: goal.id,
      kind: ProposalKind.adjust,
      targetDate: DateTime(2027, 1, 31),
      removePhaseIds: [phase2.id],
      removeTaskIds: [t1.id],
      phases: [
        ProposalPhaseDraft(title: '口语期', tasks: [
          ProposalTaskDraft(title: '跟读 10 分钟'),
        ]),
      ],
      reason: '听力阶段进度落后，先集中口语',
    );

    final result = await services.proposalService.apply(proposal.id);
    expect(result.goalId, goal.id);
    expect(result.phasesCreated, 1);

    // 目标日期已更新
    final updated = await services.goals.findById(goal.id);
    expect(updated!.targetDate, isNotNull);

    // 阶段2取消；阶段1保留（仅剩的已完成任务 + 被取消的 t1 → 自动完成）
    final p1 = await services.phases.findById(phase1.id);
    final p2 = await services.phases.findById(phase2.id);
    expect(p1!.status, PhaseStatus.completed);
    expect(p2!.status, PhaseStatus.cancelled);

    // t1 被取消、t2 随阶段取消、已完成的不动
    final task1 = await services.tasks.findById(t1.id);
    final task2 = await services.tasks.findById(t2.id);
    final taskKeep = await services.tasks.findById(tKeep.id);
    expect(task1!.status, TaskStatus.cancelled);
    expect(task2!.status, TaskStatus.cancelled);
    expect(taskKeep!.status, TaskStatus.completed);

    // 新阶段挂上
    final phases = await services.phases.findByGoal(goal.id);
    expect(phases.map((p) => p.title), contains('口语期'));
  });

  test('同一会话新提案取代旧 pending 提案', () async {
    final conv = await services.conversations.create(title: 't');
    final first = await createProposal(conversationId: conv.id);
    final second = await createProposal(conversationId: conv.id);

    final firstAfter = await services.proposals.findById(first.id);
    expect(firstAfter!.status, ProposalStatus.superseded);
    expect(
      (await services.proposals.findById(second.id))!.status,
      ProposalStatus.pending,
    );
  });

  test('apply 两次：第二次抛 StateError', () async {
    final proposal = await createProposal();
    await services.proposalService.apply(proposal.id);
    expect(
      () => services.proposalService.apply(proposal.id),
      throwsA(isA<StateError>()),
    );
  });

  test('dismiss：pending → dismissed，幂等，写会话活动消息', () async {
    final conv = await services.conversations.create(title: 't');
    final proposal = await createProposal(conversationId: conv.id);
    await services.proposalService.dismiss(proposal.id);
    await services.proposalService.dismiss(proposal.id);

    final after = await services.proposals.findById(proposal.id);
    expect(after!.status, ProposalStatus.dismissed);
    final messages = await services.conversations.messages(conv.id);
    expect(
      messages.any((m) => m.role == 'activity' && m.content == '已忽略该计划'),
      isTrue,
    );
  });

  test('校验：create 缺标题 / 缺阶段；adjust 指向不存在的目标', () async {
    expect(
      () => services.proposalService.create(
          kind: ProposalKind.create, goalTitle: null),
      throwsArgumentError,
    );
    expect(
      () => services.proposalService.create(
        kind: ProposalKind.create,
        goalTitle: '有标题',
        phases: const [],
      ),
      throwsArgumentError,
    );
    expect(
      () => services.proposalService.create(
        kind: ProposalKind.adjust,
        goalId: 'goal_missing',
        targetDate: DateTime(2027, 1, 1),
      ),
      throwsArgumentError,
    );
  });

  test('apply(action=pause)：二次确认后暂停目标，会话留回执', () async {
    final goal = await services.goalService.createGoal(title: '学英语');
    final conv = await services.conversations.create(title: 't');
    final proposal = await services.proposalService.create(
      conversationId: conv.id,
      goalId: goal.id,
      kind: ProposalKind.action,
      action: ProposalActions.pause,
      reason: '用户说先放一放',
    );
    // 目标标题自动回填（确认卡片渲染用）
    expect(proposal.goalTitle, '学英语');

    final result = await services.proposalService.apply(proposal.id);
    expect(result.goalId, goal.id);

    final updated = await services.goals.findById(goal.id);
    expect(updated!.status, GoalStatus.paused);
    expect(
      (await services.proposals.findById(proposal.id))!.status,
      ProposalStatus.applied,
    );
    final messages = await services.conversations.messages(conv.id);
    expect(
      messages.any((m) => m.role == 'activity' && m.content == '已暂停该目标'),
      isTrue,
    );
  });

  test('action 校验：非法操作 / 缺目标', () async {
    expect(
      () => services.proposalService.create(
        kind: ProposalKind.action,
        action: 'destroy_world',
        goalId: 'goal_x',
      ),
      throwsArgumentError,
    );
    expect(
      () => services.proposalService.create(
          kind: ProposalKind.action, action: ProposalActions.cancel),
      throwsArgumentError,
    );
  });

  test('dismiss(action)：目标保持原状态，回执文案为放弃操作', () async {
    final goal = await services.goalService.createGoal(title: '学英语');
    final conv = await services.conversations.create(title: 't');
    final proposal = await services.proposalService.create(
      conversationId: conv.id,
      goalId: goal.id,
      kind: ProposalKind.action,
      action: ProposalActions.cancel,
    );
    await services.proposalService.dismiss(proposal.id);

    expect((await services.goals.findById(goal.id))!.status, GoalStatus.active);
    final messages = await services.conversations.messages(conv.id);
    expect(
      messages.any((m) => m.content.contains('已放弃取消目标')),
      isTrue,
    );
  });

  test('apply(action=cancel)：取消目标并带原因', () async {
    final goal = await services.goalService.createGoal(title: '学英语');
    final proposal = await services.proposalService.create(
      goalId: goal.id,
      kind: ProposalKind.action,
      action: ProposalActions.cancel,
      reason: '方向变了',
    );
    await services.proposalService.apply(proposal.id);
    expect(
      (await services.goals.findById(goal.id))!.status,
      GoalStatus.cancelled,
    );
  });
}
