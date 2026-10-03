import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_goal/application/app_services.dart';
import 'package:ai_goal/data/database/app_database.dart';
import 'package:ai_goal/presentation/app_shell.dart';
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

  testWidgets('App 外壳与首页：底部导航 + 空状态渲染', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [servicesProvider.overrideWithValue(services)],
        child: const MaterialApp(home: AppShell()),
      ),
    );
    // widget 测试运行在 FakeAsync 区，ffi 的真实异步需要在 runAsync 中等待完成。
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    // 底部导航三个 Tab
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('目标'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);

    // 首页真实数据空状态
    expect(find.text('今天'), findsOneWidget);
    expect(find.textContaining('今日暂无安排'), findsOneWidget);
    expect(find.text('当前目标'), findsOneWidget);
    expect(find.textContaining('还没有进行中的目标'), findsOneWidget);

    // 图片资源可正常加载（背景 + logo + hero）
    expect(find.byType(Image), findsAtLeast(3));
  });

  testWidgets('首页展示已创建目标与今日任务', (tester) async {
    await tester.runAsync(() async {
      final goal = await services.goalService.createGoal(title: '减重 5kg');
      final phase =
          await services.planningService.createPhase(goalId: goal.id, title: '适应期');
      final task = await services.planningService.createTask(
        title: '晚间快走',
        phaseId: phase.id,
      );
      // 日程锚定在「今天」内（晚间跑测试时 +1h 会跨天，今天列表就空了）
      final now = DateTime.now();
      final plus1h = now.add(const Duration(hours: 1));
      final startAt = plus1h.day == now.day
          ? plus1h
          : DateTime(now.year, now.month, now.day, 23, 55);
      await services.planningService.scheduleTask(
        task.id,
        startAt: startAt,
        durationMinutes: 40,
      );
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [servicesProvider.overrideWithValue(services)],
        child: const MaterialApp(home: AppShell()),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(find.text('减重 5kg'), findsOneWidget);
    expect(find.text('晚间快走'), findsOneWidget);
    expect(find.textContaining('下一步：晚间快走'), findsOneWidget);
  });
}
