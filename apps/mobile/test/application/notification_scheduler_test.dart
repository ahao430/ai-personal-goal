import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_goal/application/app_services.dart';
import 'package:ai_goal/application/notification_scheduler.dart';
import 'package:ai_goal/core/notifications/reminder_platform.dart';
import 'package:ai_goal/data/database/app_database.dart';
import 'package:ai_goal/domain/planning/plan_proposal.dart';
import 'package:ai_goal/domain/schedule/schedule.dart';
import 'package:ai_goal/domain/task/task.dart';

import '../helpers/test_database.dart';

/// 记录型 fake：不触平台通道。
class FakeReminderPlatform implements ReminderPlatform {
  final scheduled = <ReminderRequest>[];
  final cancelledTaskIds = <String>[];
  var cancelAllCount = 0;
  final _controller = StreamController<ReminderEvent>.broadcast();

  void emit(ReminderEvent event) => _controller.add(event);

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> schedule(ReminderRequest request) async =>
      scheduled.add(request);

  @override
  Future<void> cancelTask(String taskId) async =>
      cancelledTaskIds.add(taskId);

  @override
  Future<void> cancelAll() async => cancelAllCount++;

  @override
  Stream<ReminderEvent> get events => _controller.stream;
}

void main() {
  late AppDatabase db;
  late AppServices services;
  late FakeReminderPlatform platform;
  late NotificationScheduler scheduler;

  setUp(() async {
    db = await openTestDatabase();
    platform = FakeReminderPlatform();
    services = AppServices.of(db, reminderPlatform: platform);
    scheduler = services.notificationScheduler;
  });

  tearDown(() async {
    await db.close();
  });

  Future<(String goalId, String taskId)> seedTaskWithSchedule({
    DateTime? startAt,
  }) async {
    final goal = await services.goalService.createGoal(title: '学英语');
    final task = await services.planningService.createTask(
      title: '背 100 词',
      goalId: goal.id,
    );
    if (startAt != null) {
      await services.planningService.scheduleTask(task.id, startAt: startAt);
    }
    // 让 fire-and-forget 钩子链路跑完，避免串扰后续断言。
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return (goal.id, task.id);
  }

  test('有未来日程：先取消再安排，提前 10 分钟提醒', () async {
    final (goalId, taskId) = await seedTaskWithSchedule(
      startAt: DateTime.now().add(const Duration(hours: 2)),
    );

    // 钩子已同步过；显式再同步一次得到确定性单条结果。
    platform.scheduled.clear();
    platform.cancelledTaskIds.clear();
    await scheduler.syncTask(taskId);

    final request = platform.scheduled.single;
    expect(request.taskId, taskId);
    expect(request.goalId, goalId);
    expect(request.title, contains('背 100 词'));
    expect(request.body, contains('学英语'));
    final expected = DateTime.now()
        .add(const Duration(hours: 2))
        .subtract(const Duration(minutes: 10));
    expect(
      request.fireAt.difference(expected).inSeconds.abs(),
      lessThanOrEqualTo(2),
    );
    expect(platform.cancelledTaskIds.single, taskId);
  });

  test('日程在过去：只取消，不安排', () async {
    final (_, taskId) = await seedTaskWithSchedule(
      startAt: DateTime.now().subtract(const Duration(hours: 2)),
    );

    platform.cancelledTaskIds.clear();
    await scheduler.syncTask(taskId);

    expect(platform.scheduled, isEmpty);
    expect(platform.cancelledTaskIds.single, taskId);
  });

  test('完成任务：只取消提醒', () async {
    final (_, taskId) = await seedTaskWithSchedule(
      startAt: DateTime.now().add(const Duration(hours: 2)),
    );
    await services.planningService.completeTask(taskId);
    await Future<void>.delayed(const Duration(milliseconds: 150));

    platform.scheduled.clear();
    platform.cancelledTaskIds.clear();
    await scheduler.syncTask(taskId);

    expect(platform.scheduled, isEmpty);
    expect(platform.cancelledTaskIds.single, taskId);
    expect(
      (await services.tasks.findById(taskId))!.status,
      TaskStatus.completed,
    );
  });

  test('开关关闭：取消全部且不再新增；重新开启后 syncAll 补排', () async {
    final (goalId, taskId) = await seedTaskWithSchedule(
      startAt: DateTime.now().add(const Duration(hours: 2)),
    );

    await scheduler.setEnabled(false);
    expect(platform.cancelAllCount, 1);

    platform.scheduled.clear();
    platform.cancelledTaskIds.clear();
    await scheduler.syncTask(taskId);
    expect(platform.scheduled, isEmpty);
    expect(platform.cancelledTaskIds, isEmpty, reason: '关闭后 syncTask 直接跳过');

    await scheduler.setEnabled(true);
    platform.scheduled.clear();
    await scheduler.syncAll();
    expect(platform.scheduled, isNotEmpty);
    expect(platform.scheduled.last.goalId, goalId);
  });

  test('reschedule 任务：新提醒按新时间落位', () async {
    final (_, taskId) = await seedTaskWithSchedule(
      startAt: DateTime.now().add(const Duration(hours: 2)),
    );
    await services.planningService.rescheduleTask(
      taskId,
      newStartAt: DateTime.now().add(const Duration(hours: 8)),
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));

    platform.scheduled.clear();
    await scheduler.syncTask(taskId);

    final fireAt = platform.scheduled.single.fireAt;
    final expected = DateTime.now()
        .add(const Duration(hours: 8))
        .subtract(const Duration(minutes: 10));
    expect(
      fireAt.difference(expected).inSeconds.abs(),
      lessThanOrEqualTo(2),
    );
  });

  test('通知按钮动作：snooze → 改期 +1 小时；complete → 完成任务', () async {
    final (_, taskId) = await seedTaskWithSchedule(
      startAt: DateTime.now().add(const Duration(hours: 2)),
    );

    await scheduler.bootstrap();
    platform.emit(ReminderEvent(
      taskId: taskId,
      goalId: 'goal_x',
      action: ReminderAction.snooze,
    ));
    await Future<void>.delayed(const Duration(milliseconds: 150));

    final schedules = await services.schedules.findByTask(taskId);
    final planned =
        schedules.where((s) => s.status == ScheduleStatus.planned).toList()
          ..sort((a, b) => a.startAt.compareTo(b.startAt));
    expect(
      planned.last.startAt.difference(DateTime.now()).inMinutes,
      inInclusiveRange(50, 70),
    );

    platform.emit(ReminderEvent(
      taskId: taskId,
      goalId: 'goal_x',
      action: ReminderAction.complete,
    ));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(
      (await services.tasks.findById(taskId))!.status,
      TaskStatus.completed,
    );
  });

  test('装配钩子：PlanningService 变化自动触发提醒同步', () async {
    final goal = await services.goalService.createGoal(title: '跑步');
    await services.planningService.createTask(
      title: '跑 3km',
      goalId: goal.id,
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));

    // createTask 的 onTaskChanged 钩子 → syncTask → 平台 cancel。
    // 这条链路全部经 AppServices 装配，无需手动调用调度器。
    expect(platform.cancelledTaskIds, isNotEmpty);
  });

  test('提案应用后整目标补排', () async {
    final proposal = await services.proposalService.create(
      kind: ProposalKind.create,
      goalTitle: '三个月减掉 5kg',
      phases: [
        ProposalPhaseDraft(title: '适应期', tasks: [
          ProposalTaskDraft(
            title: '晚间快走',
            scheduleStartAt: DateTime.now().add(const Duration(days: 1)),
          ),
        ]),
      ],
    );
    final result = await services.proposalService.apply(proposal.id);
    await Future<void>.delayed(const Duration(milliseconds: 150));

    platform.scheduled.clear();
    await scheduler.syncGoal(result.goalId);

    expect(platform.scheduled, hasLength(1));
    expect(platform.scheduled.single.title, contains('晚间快走'));
  });
}
