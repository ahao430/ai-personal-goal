import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_goal/application/app_services.dart';
import 'package:ai_goal/data/database/app_database.dart';
import 'package:ai_goal/presentation/calendar/calendar_page.dart';
import 'package:ai_goal/presentation/providers.dart';

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

  testWidgets('日历页：默认选中今天并展示当日任务，切换日期联动列表', (tester) async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day, 19);

    await tester.runAsync(() async {
      final goal = await services.goalService.createGoal(title: '学英语');
      final task = await services.planningService.createTask(
        title: '精听一篇',
        goalId: goal.id,
      );
      await services.planningService.scheduleTask(
        task.id,
        startAt: todayStart,
        durationMinutes: 40,
      );
      // 另一天的任务（用于验证切换）
      final next = await services.planningService.createTask(
        title: '明天的事',
        goalId: goal.id,
      );
      await services.planningService.scheduleTask(
        next.id,
        startAt: DateTime(now.year, now.month, now.day + 1, 9),
      );
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [servicesProvider.overrideWithValue(services)],
        child: const MaterialApp(home: CalendarPage()),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    // 月份标题与今日条目
    expect(find.textContaining('年 ${now.month} 月'), findsOneWidget);
    expect(find.text('精听一篇'), findsOneWidget);
    expect(find.textContaining('19:00 · 40 分钟'), findsOneWidget);
    expect(find.textContaining('1 项'), findsOneWidget);

    // 切到明天：列表联动
    final tomorrow = now.day + 1;
    await tester.tap(find.text('$tomorrow').last);
    await tester.pumpAndSettle();
    expect(find.text('明天的事'), findsOneWidget);
    expect(find.text('精听一篇'), findsNothing);
  });

  testWidgets('目标上下文：AppBar 带目标名，只显示该目标条目', (tester) async {
    final now = DateTime.now();
    String? goalAId;
    await tester.runAsync(() async {
      final a = await services.goalService.createGoal(title: '学英语');
      goalAId = a.id;
      final b = await services.goalService.createGoal(title: '减重');
      final t1 = await services.planningService.createTask(
        title: '目标 A 的任务',
        goalId: a.id,
      );
      await services.planningService.scheduleTask(
        t1.id,
        startAt: DateTime(now.year, now.month, now.day, 19),
      );
      final t2 = await services.planningService.createTask(
        title: '目标 B 的任务',
        goalId: b.id,
      );
      await services.planningService.scheduleTask(
        t2.id,
        startAt: DateTime(now.year, now.month, now.day, 20),
      );
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [servicesProvider.overrideWithValue(services)],
        child: MaterialApp(
          home: CalendarPage(goalId: goalAId, goalTitle: '学英语'),
        ),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(find.text('日程 · 学英语'), findsOneWidget);
    expect(find.text('目标 A 的任务'), findsOneWidget);
    expect(find.text('目标 B 的任务'), findsNothing);
  });
}
