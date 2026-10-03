import 'package:flutter_test/flutter_test.dart';

import 'package:ai_goal/data/database/app_database.dart';
import 'package:ai_goal/data/repositories/sqlite_goal_repository.dart';
import 'package:ai_goal/data/repositories/sqlite_phase_repository.dart';
import 'package:ai_goal/data/repositories/sqlite_progress_event_repository.dart';
import 'package:ai_goal/data/repositories/sqlite_schedule_repository.dart';
import 'package:ai_goal/data/repositories/sqlite_task_repository.dart';
import 'package:ai_goal/domain/entity_ids.dart';
import 'package:ai_goal/domain/goal/goal.dart';
import 'package:ai_goal/domain/goal/goal_metric.dart';
import 'package:ai_goal/domain/phase/phase.dart';
import 'package:ai_goal/domain/progress/progress_event.dart';
import 'package:ai_goal/domain/schedule/schedule.dart';
import 'package:ai_goal/domain/task/task.dart';

import '../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late SqliteGoalRepository goals;
  late SqliteGoalMetricRepository metrics;
  late SqlitePhaseRepository phases;
  late SqliteTaskRepository tasks;
  late SqliteScheduleRepository schedules;
  late SqliteProgressEventRepository events;

  setUp(() async {
    db = await openTestDatabase();
    goals = SqliteGoalRepository(db.database);
    metrics = SqliteGoalMetricRepository(db.database);
    phases = SqlitePhaseRepository(db.database);
    tasks = SqliteTaskRepository(db.database);
    schedules = SqliteScheduleRepository(db.database);
    events = SqliteProgressEventRepository(db.database);
  });

  tearDown(() async {
    await db.close();
  });

  /// 构造一个减重目标：metric + 两个阶段。
  Future<String> seedWeightLossGoal() async {
    final now = DateTime(2026, 10, 3);
    final goal = await goals.insert(
      Goal(
        id: EntityIds.newGoalId(),
        title: '三个月减掉 5kg',
        description: '73.4kg → 68.4kg',
        targetDate: DateTime(2027, 1, 3),
        createdAt: now,
        updatedAt: now,
      ),
    );
    await metrics.insert(
      GoalMetric(
        id: EntityIds.newMetricId(),
        goalId: goal.id,
        name: '体重',
        unit: 'kg',
        kind: MetricKind.numeric,
        currentValue: 73.4,
        targetValue: 68.4,
        direction: MetricDirection.decrease,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await phases.insert(
      Phase(
        id: EntityIds.newPhaseId(),
        goalId: goal.id,
        title: '适应期',
        orderIndex: 0,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await phases.insert(
      Phase(
        id: EntityIds.newPhaseId(),
        goalId: goal.id,
        title: '强化期',
        orderIndex: 1,
        createdAt: now,
        updatedAt: now,
      ),
    );
    return goal.id;
  }

  group('GoalRepository', () {
    test('插入 / 查询 / 状态过滤 / 计数', () async {
      final goalId = await seedWeightLossGoal();
      await goals.insert(
        Goal(
          id: EntityIds.newGoalId(),
          title: '已归档目标',
          status: GoalStatus.archived,
          createdAt: DateTime(2026, 9, 1),
          updatedAt: DateTime(2026, 9, 1),
        ),
      );

      final found = await goals.findById(goalId);
      expect(found!.title, '三个月减掉 5kg');

      final active = await goals.findAll(status: GoalStatus.active);
      expect(active, hasLength(1));
      expect(await goals.countByStatus(GoalStatus.active), 1);
      expect(await goals.findAll(), hasLength(2));
    });

    test('更新不存在的 Goal 抛错', () async {
      final now = DateTime(2026, 10, 3);
      final goal = Goal(
        id: 'goal_missing',
        title: '幽灵目标',
        createdAt: now,
        updatedAt: now,
      );
      expect(() => goals.update(goal), throwsStateError);
    });

    test('暂停 / 恢复目标（状态流转）', () async {
      final goalId = await seedWeightLossGoal();
      final goal = (await goals.findById(goalId))!;

      final paused = await goals.update(goal.copyWith(status: GoalStatus.paused));
      expect(paused.status, GoalStatus.paused);
      expect((await goals.findById(goalId))!.status, GoalStatus.paused);

      final resumed = await goals.update(paused.copyWith(status: GoalStatus.active));
      expect(resumed.status, GoalStatus.active);
    });
  });

  group('PhaseRepository', () {
    test('按 orderIndex 排序返回，nextOrderIndex 递增', () async {
      final goalId = await seedWeightLossGoal();

      final list = await phases.findByGoal(goalId);
      expect(list.map((p) => p.title).toList(), ['适应期', '强化期']);

      expect(await phases.nextOrderIndex(goalId), 2);
    });
  });

  group('TaskRepository', () {
    test('完成 Task（记录 completedAt）与延期', () async {
      final goalId = await seedWeightLossGoal();
      final phase = (await phases.findByGoal(goalId)).first;
      final now = DateTime(2026, 10, 3);

      final task = await tasks.insert(
        Task(
          id: EntityIds.newTaskId(),
          title: '晚间快走 40 分钟',
          phaseId: phase.id,
          dueDate: DateTime(2026, 10, 3, 23, 59),
          estimatedMinutes: 40,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await tasks.linkToGoal(task.id, goalId, primary: true);

      // 完成
      final done = await tasks.update(
        task.copyWith(status: TaskStatus.completed, completedAt: DateTime(2026, 10, 3, 21, 5)),
      );
      expect(done.status, TaskStatus.completed);
      final restored = await tasks.findById(task.id);
      expect(restored!.completedAt, isNotNull);

      // 延期
      final postponed = await tasks.update(done.copyWith(status: TaskStatus.postponed));
      expect(postponed.status, TaskStatus.postponed);
    });

    test('跨 Goal 关联：一个 Task 挂到两个 Goal', () async {
      final now = DateTime(2026, 10, 3);
      final goalA = await goals.insert(Goal(
        id: EntityIds.newGoalId(),
        title: '做 AI Goal App',
        createdAt: now,
        updatedAt: now,
      ));
      final goalB = await goals.insert(Goal(
        id: EntityIds.newGoalId(),
        title: '学习 Flutter',
        createdAt: now,
        updatedAt: now,
      ));
      final task = await tasks.insert(Task(
        id: EntityIds.newTaskId(),
        title: '学习 Riverpod',
        createdAt: now,
        updatedAt: now,
      ));

      await tasks.linkToGoal(task.id, goalA.id);
      await tasks.linkToGoal(task.id, goalB.id);

      expect(await tasks.goalIdsOf(task.id), unorderedEquals([goalA.id, goalB.id]));
      expect(await tasks.findByGoal(goalB.id), hasLength(1));

      await tasks.unlinkFromGoal(task.id, goalA.id);
      expect(await tasks.goalIdsOf(task.id), [goalB.id]);
    });

    test('findDueBetween 只返回区间内未取消的任务', () async {
      final now = DateTime(2026, 10, 3);
      Future<Task> mk(String title, DateTime? due) => tasks.insert(Task(
            id: EntityIds.newTaskId(),
            title: title,
            dueDate: due,
            createdAt: now,
            updatedAt: now,
          ));

      await mk('今天截止', DateTime(2026, 10, 3, 20, 0));
      await mk('明天截止', DateTime(2026, 10, 4, 20, 0));
      await mk('已取消-今天', DateTime(2026, 10, 3, 21, 0))
          .then((t) => tasks.update(t.copyWith(status: TaskStatus.cancelled)));

      final today = await tasks.findDueBetween(
        DateTime(2026, 10, 3),
        DateTime(2026, 10, 4),
      );
      expect(today.map((t) => t.title).toList(), ['今天截止']);
    });
  });

  group('ScheduleRepository', () {
    test('按时间区间查询与按任务查询（含历史）', () async {
      final now = DateTime(2026, 10, 3);
      final task = await tasks.insert(Task(
        id: EntityIds.newTaskId(),
        title: '跑步',
        createdAt: now,
        updatedAt: now,
      ));

      Schedule mk(int day, int hour) => Schedule(
            id: EntityIds.newScheduleId(),
            taskId: task.id,
            startAt: DateTime(2026, 10, day, hour),
            durationMinutes: 60,
            createdAt: now,
            updatedAt: now,
          );

      await schedules.insert(mk(3, 18));
      final moved = await schedules.insert(mk(4, 19));
      // 重新安排：同 Task 产生第二条 Schedule，旧的标记取消
      await schedules.update(moved.copyWith(status: ScheduleStatus.cancelled));
      await schedules.insert(mk(5, 19));

      final ofTask = await schedules.findByTask(task.id);
      expect(ofTask, hasLength(3)); // 历史保留，供 AI 分析偏差

      final day4 = await schedules.findBetween(
        DateTime(2026, 10, 4),
        DateTime(2026, 10, 5),
      );
      expect(day4.single.status, ScheduleStatus.cancelled);
    });
  });

  group('GoalMetricRepository', () {
    test('addValue 追加历史并推进 currentValue', () async {
      final goalId = await seedWeightLossGoal();
      final metric = (await metrics.findByGoal(goalId)).single;
      expect(metric.currentValue, 73.4);

      await metrics.addValue(MetricValue(
        id: EntityIds.newMetricValueId(),
        metricId: metric.id,
        value: 72.6,
        recordedAt: DateTime(2026, 10, 10, 8, 0),
        source: 'user',
      ));
      await metrics.addValue(MetricValue(
        id: EntityIds.newMetricValueId(),
        metricId: metric.id,
        value: 71.9,
        recordedAt: DateTime(2026, 10, 17, 8, 0),
        source: 'health',
      ));

      final refreshed = (await metrics.findByGoal(goalId)).single;
      expect(refreshed.currentValue, 71.9);

      final history = await metrics.valuesOfMetric(metric.id);
      expect(history.map((v) => v.value).toList(), [71.9, 72.6]); // 倒序
    });
  });

  group('ProgressEventRepository', () {
    test('按 Goal / Task / 最近事件查询（倒序）', () async {
      final goalId = await seedWeightLossGoal();
      final phase = (await phases.findByGoal(goalId)).first;
      final now = DateTime(2026, 10, 3);
      final task = await tasks.insert(Task(
        id: EntityIds.newTaskId(),
        title: '快走',
        phaseId: phase.id,
        createdAt: now,
        updatedAt: now,
      ));

      Future<void> add(ProgressEventType type, int hour, String msg) =>
          events.insert(ProgressEvent(
            id: EntityIds.newProgressEventId(),
            goalId: goalId,
            taskId: task.id,
            type: type,
            time: DateTime(2026, 10, 3, hour),
            source: ProgressSource.user,
            message: msg,
          ));

      await add(ProgressEventType.taskStarted, 9, '开始');
      await add(ProgressEventType.taskCompleted, 10, '完成');
      await add(ProgressEventType.userReport, 21, '今天走完了');

      final byGoal = await events.findByGoal(goalId);
      expect(byGoal.first.message, '今天走完了');
      expect(byGoal, hasLength(3));

      final byTask = await events.findByTask(task.id);
      expect(byTask.first.type, ProgressEventType.userReport);

      final recent = await events.recent(limit: 2);
      expect(recent, hasLength(2));
    });
  });

  test('端到端：创建→规划→执行→记录（P1 数据层闭环，无 AI）', () async {
    final goalId = await seedWeightLossGoal();
    final phase = (await phases.findByGoal(goalId)).first;
    final now = DateTime(2026, 10, 3);

    // 1. 创建任务并挂到 Goal
    final task = await tasks.insert(Task(
      id: EntityIds.newTaskId(),
      title: '设计目标详情页',
      phaseId: phase.id,
      estimatedMinutes: 60,
      createdAt: now,
      updatedAt: now,
    ));
    await tasks.linkToGoal(task.id, goalId, primary: true);

    // 2. 安排到今晚 20:00
    final schedule = await schedules.insert(Schedule(
      id: EntityIds.newScheduleId(),
      taskId: task.id,
      startAt: DateTime(2026, 10, 3, 20),
      durationMinutes: 60,
      createdAt: now,
      updatedAt: now,
    ));

    // 3. 执行：完成 + 记录事件
    await tasks.update(
      task.copyWith(status: TaskStatus.completed, completedAt: DateTime(2026, 10, 3, 21)),
    );
    await schedules.update(schedule.copyWith(status: ScheduleStatus.completed));
    await events.insert(ProgressEvent(
      id: EntityIds.newProgressEventId(),
      goalId: goalId,
      taskId: task.id,
      type: ProgressEventType.taskCompleted,
      time: DateTime(2026, 10, 3, 21),
      source: ProgressSource.user,
      message: '首页做完了',
    ));

    // 4. 验证状态
    expect((await tasks.findById(task.id))!.status, TaskStatus.completed);
    expect(
      (await events.findByGoal(goalId)).single.type,
      ProgressEventType.taskCompleted,
    );
    expect((await tasks.findByGoal(goalId)), isNotEmpty);
    expect((await schedules.findBetween(
      DateTime(2026, 10, 3),
      DateTime(2026, 10, 4),
    )), hasLength(1));
  });
}
