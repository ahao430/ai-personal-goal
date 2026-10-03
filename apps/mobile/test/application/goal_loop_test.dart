import 'package:flutter_test/flutter_test.dart';

import 'package:ai_goal/application/app_services.dart';
import 'package:ai_goal/application/goal_service.dart';
import 'package:ai_goal/application/planning_service.dart';
import 'package:ai_goal/data/database/app_database.dart';
import 'package:ai_goal/domain/goal/goal.dart';
import 'package:ai_goal/domain/goal/goal_metric.dart';
import 'package:ai_goal/domain/phase/phase.dart';
import 'package:ai_goal/domain/progress/progress_event.dart';
import 'package:ai_goal/domain/schedule/schedule.dart';
import 'package:ai_goal/domain/task/task.dart';

import '../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late AppServices services;
  late GoalService goals;
  late PlanningService planning;

  setUp(() async {
    db = await openTestDatabase();
    services = AppServices.of(db);
    goals = services.goalService;
    planning = services.planningService;
  });

  tearDown(() async {
    await db.close();
  });

  Future<List<ProgressEvent>> eventsOf(String goalId) =>
      services.progressEvents.findByGoal(goalId);

  /// 标准场景：一个目标、两个阶段；阶段一有 3 个任务。
  Future<(String, List<String>)> seed() async {
    final goal = await goals.createGoal(
      title: '三个月减掉 5kg',
      description: '73.4kg → 68.4kg',
      targetDate: DateTime(2027, 1, 3),
    );
    final p1 = await planning.createPhase(goalId: goal.id, title: '适应期');
    await planning.createPhase(goalId: goal.id, title: '强化期');
    final t1 = await planning.createTask(
      title: '晚间快走 40 分钟',
      phaseId: p1.id,
      estimatedMinutes: 40,
    );
    final t2 = await planning.createTask(
      title: '记录体重',
      phaseId: p1.id,
    );
    final t3 = await planning.createTask(
      title: '戒宵夜',
      phaseId: p1.id,
    );
    return (goal.id, [t1.id, t2.id, t3.id]);
  }

  group('GoalService · 目标生命周期', () {
    test('创建默认 active / 0%，暂停与恢复产生事件且幂等', () async {
      final goal = await goals.createGoal(title: '读 12 本书');
      expect(goal.status, GoalStatus.active);
      expect(goal.overallProgress, 0);

      await goals.pauseGoal(goal.id);
      await goals.pauseGoal(goal.id); // 幂等：不重复发事件
      final pausedEvents = await eventsOf(goal.id);
      expect(
        pausedEvents.where((e) => e.type == ProgressEventType.goalPaused),
        hasLength(1),
      );
      expect((await services.goals.findById(goal.id))!.status, GoalStatus.paused);

      await goals.resumeGoal(goal.id);
      final types =
          (await eventsOf(goal.id)).map((e) => e.type).toSet();
      expect(types, containsAll([ProgressEventType.goalPaused, ProgressEventType.goalResumed]));
    });

    test('updateGoal 支持 mapper 编辑并产生 goal_updated 事件', () async {
      final goal = await goals.createGoal(title: '学英语', description: '雅思');
      await goals.updateGoal(
        goal.id,
        (g) => g.copyWith(title: '考雅思 7 分', description: null),
      );
      final updated = await services.goals.findById(goal.id);
      expect(updated!.title, '考雅思 7 分');
      expect(updated.description, isNull); // 可显式置空
      expect(
        (await eventsOf(goal.id))
            .where((e) => e.type == ProgressEventType.goalUpdated),
        isNotEmpty,
      );
    });

    test('Metric：初值入历史，记录推进 currentValue 并产生事件', () async {
      final goal = await goals.createGoal(title: '减重');
      final metric = await goals.addMetric(
        goal.id,
        name: '体重',
        unit: 'kg',
        direction: MetricDirection.decrease,
        initialValue: 73.4,
        targetValue: 68.4,
      );
      expect(metric.currentValue, 73.4);
      expect(await services.metrics.valuesOfMetric(metric.id), hasLength(1));

      await goals.recordMetricValue(metric.id, 72.6);
      final refreshed = await services.metrics.findById(metric.id);
      expect(refreshed!.currentValue, 72.6);
      expect(await services.metrics.valuesOfMetric(metric.id), hasLength(2));

      final event = (await eventsOf(goal.id))
          .singleWhere((e) => e.type == ProgressEventType.metricUpdated);
      expect(event.data?['from'], 73.4);
      expect(event.data?['to'], 72.6);
    });
  });

  group('PlanningService · 任务与日程', () {
    test('createTask 按 phaseId 自动关联 Goal；阶段 orderIndex 自增', () async {
      final (goalId, taskIds) = await seed();
      expect(await services.tasks.findByGoal(goalId), hasLength(3));
      expect(taskIds.toSet(), hasLength(3));

      final phases = await services.phases.findByGoal(goalId);
      expect(phases.map((p) => p.orderIndex).toList(), [0, 1]);
      expect(
        (await services.tasks.goalIdsOf(taskIds.first)),
        [goalId],
      );
    });

    test('completeTask：状态+completedAt+日程完成+事件+进度重算+阶段自动完成', () async {
      final (goalId, taskIds) = await seed();
      await planning.scheduleTask(
        taskIds.first,
        startAt: DateTime.now().add(const Duration(hours: 2)),
        durationMinutes: 40,
      );

      final done = await planning.completeTask(taskIds.first);
      expect(done.status, TaskStatus.completed);
      expect(done.completedAt, isNotNull);
      // 未开始的日程随任务完成
      final schedules = await services.schedules.findByTask(taskIds.first);
      expect(schedules.every((s) => s.status == ScheduleStatus.completed), isTrue);

      // 幂等：再次完成不产生重复事件
      await planning.completeTask(taskIds.first);
      expect(
        (await eventsOf(goalId))
            .where((e) => e.type == ProgressEventType.taskCompleted),
        hasLength(1),
      );

      // 进度：1/3 → 33
      expect((await services.goals.findById(goalId))!.overallProgress, 33);
    });

    test('进度按未取消任务计算；全部完成时阶段自动完成', () async {
      final (goalId, taskIds) = await seed();

      // 取消一个：分母 2
      await planning.cancelTask(taskIds[2]);
      expect((await services.goals.findById(goalId))!.overallProgress, 0);

      await planning.completeTask(taskIds[0]);
      await planning.completeTask(taskIds[1]);
      expect((await services.goals.findById(goalId))!.overallProgress, 100);

      // 阶段一全部（未取消）任务完成 → 自动完成 + 事件
      final phase1 =
          (await services.phases.findByGoal(goalId)).first;
      expect(phase1.status, PhaseStatus.completed);
      expect(
        (await eventsOf(goalId))
            .where((e) => e.type == ProgressEventType.phaseCompleted),
        hasLength(1),
      );
    });

    test('startTask 进入进行中并把阶段置为 in_progress', () async {
      final (goalId, taskIds) = await seed();
      await planning.startTask(taskIds.first);

      expect(
        (await services.tasks.findById(taskIds.first))!.status,
        TaskStatus.inProgress,
      );
      final phase1 = (await services.phases.findByGoal(goalId)).first;
      expect(phase1.status, PhaseStatus.inProgress);
      expect(
        (await eventsOf(goalId))
            .any((e) => e.type == ProgressEventType.taskStarted),
        isTrue,
      );
    });

    test('postponeTask(to)：状态延期、旧日程取消、新日程落位', () async {
      final (goalId, taskIds) = await seed();
      final now = DateTime.now();
      await planning.scheduleTask(
        taskIds.first,
        startAt: now.add(const Duration(hours: 1)),
      );

      final tomorrow = now.add(const Duration(days: 1));
      await planning.postponeTask(taskIds.first, to: tomorrow);

      expect(
        (await services.tasks.findById(taskIds.first))!.status,
        TaskStatus.postponed,
      );
      final schedules = await services.schedules.findByTask(taskIds.first);
      final planned =
          schedules.where((s) => s.status == ScheduleStatus.planned).toList();
      expect(planned, hasLength(1));
      // 时间列毫秒精度：按毫秒比较，避免微秒截断误报
      expect(
        planned.single.startAt.millisecondsSinceEpoch,
        tomorrow.millisecondsSinceEpoch,
      );

      expect(
        (await eventsOf(goalId))
            .any((e) => e.type == ProgressEventType.taskPostponed),
        isTrue,
      );

      // 完成的任务不能延期
      await planning.completeTask(taskIds.first);
      expect(
        () => planning.postponeTask(taskIds.first),
        throwsStateError,
      );
    });

    test('rescheduleTask：延期任务恢复 todo，产生 schedule_changed 事件', () async {
      final (goalId, taskIds) = await seed();
      await planning.postponeTask(taskIds.first);

      final next = DateTime.now().add(const Duration(days: 2));
      await planning.rescheduleTask(taskIds.first, newStartAt: next);

      expect(
        (await services.tasks.findById(taskIds.first))!.status,
        TaskStatus.todo,
      );
      final planned = (await services.schedules.findByTask(taskIds.first))
          .where((s) => s.status == ScheduleStatus.planned)
          .single;
      expect(
        planned.startAt.millisecondsSinceEpoch,
        next.millisecondsSinceEpoch,
      );
      expect(
        (await eventsOf(goalId))
            .any((e) => e.type == ProgressEventType.scheduleChanged),
        isTrue,
      );
    });

    test('recordUserReport 落 user_report 事件', () async {
      final (goalId, taskIds) = await seed();
      await planning.recordUserReport(
        goalId,
        '今天快走完成了，膝盖有点酸',
        taskId: taskIds.first,
      );
      final report = (await eventsOf(goalId))
          .singleWhere((e) => e.type == ProgressEventType.userReport);
      expect(report.taskId, taskIds.first);
      expect(report.source, ProgressSource.user);
    });
  });

  group('ProgressService · 进度引擎', () {
    test('进度四舍五入：2/3 → 67', () async {
      final (goalId, taskIds) = await seed();
      await planning.completeTask(taskIds[0]);
      await planning.completeTask(taskIds[1]);
      expect((await services.goals.findById(goalId))!.overallProgress, 67);
    });

    test('跨 Goal 任务：完成一次，两个目标进度都更新', () async {
      final goalA = await goals.createGoal(title: '做 AI Goal App');
      final goalB = await goals.createGoal(title: '学 Flutter');
      final task = await planning.createTask(
        title: '学习 Riverpod',
        goalId: goalA.id,
      );
      // 手动把任务也挂到目标 B（跨目标共享）
      await services.tasks.linkToGoal(task.id, goalB.id);

      await planning.completeTask(task.id);

      expect((await services.goals.findById(goalA.id))!.overallProgress, 100);
      expect((await services.goals.findById(goalB.id))!.overallProgress, 100);
    });
  });

  test('P1 完整闭环：创建→规划→排期→开始→完成→汇报→指标（无 AI）', () async {
    final goal = await goals.createGoal(
      title: '做出 AI Goal App',
      targetDate: DateTime(2026, 12, 31),
    );
    final phase = await planning.createPhase(goalId: goal.id, title: 'MVP UI');
    final task = await planning.createTask(
      title: '设计目标详情页',
      phaseId: phase.id,
      estimatedMinutes: 60,
    );
    await planning.scheduleTask(
      task.id,
      startAt: DateTime(2026, 10, 3, 20),
      durationMinutes: 60,
    );

    await planning.startTask(task.id);
    await planning.completeTask(task.id);
    await planning.recordUserReport(goal.id, '首页做完了，明天开始详情页');
    final metric = await goals.addMetric(goal.id, name: '完成页面数',
        kind: MetricKind.count, initialValue: 1, targetValue: 8);
    await goals.recordMetricValue(metric.id, 2);
    await goals.completeGoal(goal.id);

    // 验证最终状态
    final finalGoal = await services.goals.findById(goal.id);
    expect(finalGoal!.status, GoalStatus.completed);
    expect(finalGoal.overallProgress, 100);
    expect((await services.phases.findByGoal(goal.id)).single.status,
        PhaseStatus.completed);

    final types = (await eventsOf(goal.id)).map((e) => e.type).toSet();
    expect(
      types,
      containsAll([
        ProgressEventType.taskStarted,
        ProgressEventType.taskCompleted,
        ProgressEventType.scheduleChanged,
        ProgressEventType.phaseCompleted,
        ProgressEventType.userReport,
        ProgressEventType.metricUpdated,
      ]),
    );
  });
}
