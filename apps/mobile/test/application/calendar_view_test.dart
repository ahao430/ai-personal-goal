import 'package:flutter_test/flutter_test.dart';

import 'package:ai_goal/application/app_services.dart';
import 'package:ai_goal/data/database/app_database.dart';

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

  test('月视图：日程落位 / 截止落位 / 完成剔除 / 目标过滤', () async {
    final goalA = await services.goalService.createGoal(title: '学英语');
    final goalB = await services.goalService.createGoal(title: '减重');

    final now = DateTime.now();
    final tenth = DateTime(now.year, now.month, 10, 19);
    final fifteenth = DateTime(now.year, now.month, 15);
    final nextMonth = DateTime(now.year, now.month + 1, 3, 9);

    final scheduled = await services.planningService.createTask(
      title: '精听一篇',
      goalId: goalA.id,
    );
    await services.planningService.scheduleTask(scheduled.id, startAt: tenth);

    final dueOnly = await services.planningService.createTask(
      title: '背 100 词',
      goalId: goalA.id,
      dueDate: fifteenth,
    );

    final done = await services.planningService.createTask(
      title: '已完成的',
      goalId: goalA.id,
    );
    await services.planningService.scheduleTask(
      done.id,
      startAt: DateTime(now.year, now.month, 20, 8),
    );
    await services.planningService.completeTask(done.id);

    final otherGoal = await services.planningService.createTask(
      title: '目标 B 的任务',
      goalId: goalB.id,
    );
    await services.planningService.scheduleTask(otherGoal.id, startAt: tenth);

    final nextMonthTask = await services.planningService.createTask(
      title: '下月的任务',
      goalId: goalA.id,
    );
    await services.planningService.scheduleTask(nextMonthTask.id,
        startAt: nextMonth);

    // 全部目标视图
    final data =
        await services.overview.calendarView(DateTime(now.year, now.month));

    // 10 号：日程任务 + 目标 B 的日程任务（不过滤时都在）
    final day10 = data.itemsOf(10);
    expect(day10.map((i) => i.task.title), containsAll(['精听一篇', '目标 B 的任务']));
    expect(day10.first.schedule, isNotNull);

    // 15 号：只有截止、无日程
    final day15 = data.itemsOf(15);
    expect(day15.single.task.id, dueOnly.id);
    expect(day15.single.schedule, isNull);

    // 20 号：已完成任务不出现
    expect(data.itemsOf(20), isEmpty);
    // 下月的任务不出现在本月
    expect(data.itemsOf(3), isEmpty);

    // 目标过滤视图：只看 goalA
    final dataA = await services.overview.calendarView(
      DateTime(now.year, now.month),
      goalId: goalA.id,
    );
    expect(
      dataA.itemsOf(10).map((i) => i.task.title),
      ['精听一篇'],
      reason: '目标 B 的任务被过滤',
    );

    // 下月视图
    final dataNext = await services.overview.calendarView(
      DateTime(now.year, now.month + 1),
    );
    expect(dataNext.itemsOf(3).single.task.title, '下月的任务');
  });

  test('同任务多个日程都落位且按时间排序', () async {
    final goal = await services.goalService.createGoal(title: '跑步');
    final task = await services.planningService.createTask(
      title: '跑 3km',
      goalId: goal.id,
    );
    final now = DateTime.now();
    final late = DateTime(now.year, now.month, 12, 20);
    final early = DateTime(now.year, now.month, 12, 7);
    await services.planningService.scheduleTask(task.id, startAt: late);
    await services.planningService.scheduleTask(task.id, startAt: early);

    final data =
        await services.overview.calendarView(DateTime(now.year, now.month));
    final day12 = data.itemsOf(12);
    expect(day12, hasLength(2));
    expect(
      day12.map((i) => i.schedule!.startAt.hour),
      [7, 20],
      reason: '按时间升序',
    );
  });

  test('空月：没有任何条目', () async {
    final now = DateTime.now();
    final data =
        await services.overview.calendarView(DateTime(now.year, now.month));
    expect(data.itemsByDay, isEmpty);
    expect(data.month.month, now.month);
  });
}
