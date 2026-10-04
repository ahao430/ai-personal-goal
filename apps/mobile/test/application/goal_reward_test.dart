import 'package:flutter_test/flutter_test.dart';

import 'package:ai_goal/application/app_services.dart';
import 'package:ai_goal/data/database/app_database.dart';
import 'package:ai_goal/domain/goal/goal_repository.dart';

import '../helpers/test_database.dart';

/// 目标激励（reward）与完成统计（completed_at / countCompletedSince）。
void main() {
  late AppDatabase db;
  late AppServices services;
  late GoalRepository goals;

  setUp(() async {
    db = await openTestDatabase();
    services = AppServices.of(db);
    goals = services.goals;
  });

  tearDown(() async {
    await db.close();
  });

  test('createGoal 带 reward：持久化并可在编辑时清除', () async {
    final goal = await services.goalService.createGoal(
      title: '跑一次半马',
      reward: '买一双新跑鞋',
    );
    expect((await goals.findById(goal.id))!.reward, '买一双新跑鞋');

    await services.goalService.updateGoal(
      goal.id,
      (g) => g.copyWith(reward: null),
    );
    expect((await goals.findById(goal.id))!.reward, isNull);
  });

  test('completeGoal 记录 completedAt 并计入统计；重开后清除', () async {
    final goal = await services.goalService.createGoal(title: '读完一本书');
    expect(await goals.countCompletedSince(DateTime(2000)), 0);

    final done = await services.goalService.completeGoal(goal.id);
    expect(done.completedAt, isNotNull);

    final now = DateTime.now();
    final thisYear = DateTime(now.year, 1, 1);
    final thisMonth = DateTime(now.year, now.month, 1);
    expect(await goals.countCompletedSince(thisYear), 1);
    expect(await goals.countCompletedSince(thisMonth), 1);
    // 未来起点不计入。
    expect(await goals.countCompletedSince(now.add(const Duration(days: 1))), 0);

    // 重开 → completedAt 清空，不再计入统计。
    final reopened = await services.goalService.resumeGoal(goal.id);
    expect(reopened.completedAt, isNull);
    expect(await goals.countCompletedSince(thisYear), 0);
  });

  test('completeGoal 的进度事件带奖励提醒', () async {
    final goal = await services.goalService.createGoal(
      title: '早睡 30 天',
      reward: '一次温泉之旅',
    );
    await services.goalService.completeGoal(goal.id);

    final events =
        await services.progressEvents.findByGoal(goal.id, limit: 5);
    final msg = events.map((e) => e.message).join('\n');
    expect(msg, contains('温泉之旅'));
    expect(msg, contains('早睡 30 天'));
  });

  test('countCompletedSince：completed_at 为空或时间早于起点的不计', () async {
    final t = DateTime(2026, 1, 10);
    // 直接落库构造：一条 v5 时代完成但无 completed_at 的目标（迁移前语义）。
    await db.database.insert('goals', {
      'id': 'goal_legacy',
      'title': '旧数据',
      'status': 'completed',
      'overall_progress': 100.0,
      'created_at': '2025-12-01T00:00:00.000Z',
      'updated_at': '2025-12-01T00:00:00.000Z',
      'completed_at': null,
    });
    await db.database.insert('goals', {
      'id': 'goal_early',
      'title': '去年完成',
      'status': 'completed',
      'overall_progress': 100.0,
      'created_at': '2025-06-01T00:00:00.000Z',
      'updated_at': '2025-06-01T00:00:00.000Z',
      'completed_at': '2025-06-01T00:00:00.000Z',
    });
    await db.database.insert('goals', {
      'id': 'goal_2026',
      'title': '今年完成',
      'status': 'completed',
      'overall_progress': 100.0,
      'created_at': '2026-01-01T00:00:00.000Z',
      'updated_at': '2026-01-05T00:00:00.000Z',
      'completed_at': '2026-01-05T00:00:00.000Z',
    });
    expect(t, isNotNull); // 仅为可读性锚定时间线。

    expect(await goals.countCompletedSince(DateTime(2026, 1, 1)), 1);
    expect(await goals.countCompletedSince(DateTime(2026, 2, 1)), 0);
    expect(await goals.countCompletedSince(DateTime(2025, 1, 1)), 2);
  });

  test('homeView 聚合本月 / 今年完成数', () async {
    final a = await services.goalService.createGoal(title: 'A');
    final b = await services.goalService.createGoal(title: 'B');
    await services.goalService.completeGoal(a.id);
    await services.goalService.completeGoal(b.id);

    final view = await services.overview.homeView();
    expect(view.completedThisMonth, 2);
    expect(view.completedThisYear, 2);
  });
}
