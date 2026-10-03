import 'package:flutter_test/flutter_test.dart';

import 'package:ai_goal/application/app_services.dart';
import 'package:ai_goal/data/database/app_database.dart';
import 'package:ai_goal/domain/goal/goal_metric.dart';

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

  test('完成率 / 逾期数 / 有效任务数（取消剔除）', () async {
    final goal = await services.goalService.createGoal(title: '学英语');
    final done1 =
        await services.planningService.createTask(title: 'a', goalId: goal.id);
    final done2 =
        await services.planningService.createTask(title: 'b', goalId: goal.id);
    final open =
        await services.planningService.createTask(title: 'c', goalId: goal.id);
    final overdue = await services.planningService.createTask(
      title: 'd',
      goalId: goal.id,
      dueDate: DateTime.now().subtract(const Duration(days: 2)),
    );
    final cancelled =
        await services.planningService.createTask(title: 'e', goalId: goal.id);
    for (final t in [done1, done2]) {
      await services.planningService.completeTask(t.id);
    }
    await services.planningService.cancelTask(cancelled.id);
    expect(overdue.id, isNotNull); // 逾期任务保持开放
    expect(open.id, isNotNull);

    final a = await services.analysisService.analyze(goal.id);
    expect(a.tasksTotal, 5);
    expect(a.tasksCancelled, 1);
    expect(a.tasksEffective, 4);
    expect(a.tasksCompleted, 2);
    expect(a.completionRate, 50);
    expect(a.tasksOverdue, 1);
    expect(a.hasSignals, isTrue); // 有逾期 + 完成率 < 100
  });

  test('近 14 天延期频次：postponeRate 与 hasSignals', () async {
    final goal = await services.goalService.createGoal(title: '跑步');
    final t1 =
        await services.planningService.createTask(title: '跑 3km', goalId: goal.id);
    final t2 =
        await services.planningService.createTask(title: '拉伸', goalId: goal.id);
    await services.planningService.postponeTask(t1.id);
    await services.planningService.postponeTask(t1.id,
        to: DateTime.now().add(const Duration(days: 1)));
    await services.planningService.completeTask(t2.id);

    final a = await services.analysisService.analyze(goal.id);
    expect(a.postponedRecent, 2);
    expect(a.completedRecent, 1);
    expect(a.postponeRate, 67); // 2/3
    expect(a.hasSignals, isTrue); // 延期 ≥ 2
  });

  test('指标趋势：下降方向改善为 true，方向错误为 false', () async {
    final goal = await services.goalService.createGoal(title: '减重');
    final weight = await services.goalService.addMetric(
      goal.id,
      name: '体重',
      unit: 'kg',
      direction: MetricDirection.decrease,
      initialValue: 72.5,
      targetValue: 67.5,
    );
    await services.goalService.recordMetricValue(weight.id, 71.0);

    final a = await services.analysisService.analyze(goal.id);
    final trend = a.metricTrends.single;
    expect(trend.name, '体重');
    expect(trend.first, 72.5);
    expect(trend.last, 71.0);
    expect(trend.delta, -1.5);
    expect(trend.improved, isTrue);
    expect(trend.samples, 2);

    // 反例：回升超过窗口初值 = 偏离目标
    await services.goalService.recordMetricValue(weight.id, 73.0);
    final a2 = await services.analysisService.analyze(goal.id);
    expect(a2.metricTrends.single.improved, isFalse);
  });

  test('无信号：全部完成且无延期无逾期 → hasSignals=false', () async {
    final goal = await services.goalService.createGoal(title: '读完一本书');
    final t =
        await services.planningService.createTask(title: '读 30 页', goalId: goal.id);
    await services.planningService.completeTask(t.id);

    final a = await services.analysisService.analyze(goal.id);
    expect(a.completionRate, 100);
    expect(a.tasksOverdue, 0);
    expect(a.postponedRecent, 0);
    expect(a.hasSignals, isFalse);
  });

  test('analyze 不存在的目标抛 StateError', () async {
    expect(
      () => services.analysisService.analyze('goal_missing'),
      throwsStateError,
    );
  });
}
