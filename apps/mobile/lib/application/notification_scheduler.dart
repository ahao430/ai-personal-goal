import 'dart:async';

import '../core/notifications/reminder_platform.dart';
import '../domain/schedule/schedule.dart';
import '../domain/task/task.dart';
import 'app_services.dart';

/// 任务提醒调谐器（P7，plan §47：Schedule → Local Notification）。
///
/// - PlanningService 每次任务/日程变化后调用 [syncTask]：
///   取消旧提醒 → 任务开放且有未来日程时安排最近一次（开始前 10 分钟）。
/// - 提案应用后调用 [syncGoal]；App 启动调用 [syncAll] 补排（含重启恢复）。
/// - 通知按钮动作在这里落地：完成了 → completeTask；延后 1 小时 → reschedule。
/// - 开关关闭时取消全部通知，不再新增。
/// - 全部入口静默容错：提醒失败（环境不支持 / 数据不可用）不影响业务流。
class NotificationScheduler {
  NotificationScheduler(this._services, this._platform);

  static const String featureKey = 'feature.task_reminders';

  /// 提前量：日程开始前 10 分钟提醒。
  static const Duration leadTime = Duration(minutes: 10);

  final AppServices _services;
  final ReminderPlatform _platform;

  ReminderPlatform get platform => _platform;

  static const Set<TaskStatus> _openStatuses = {
    TaskStatus.todo,
    TaskStatus.inProgress,
    TaskStatus.postponed,
  };

  Future<bool> enabled() async =>
      await _services.settings.read(featureKey) != '0';

  Future<void> setEnabled(bool value) => _quiet(() async {
        await _services.settings.write(featureKey, value ? '1' : '0');
        if (!value) await _platform.cancelAll();
      });

  /// 启动引导：初始化平台、请求权限、补排全部提醒、订阅动作事件。
  /// 平台异常不阻塞 App 启动。
  Future<void> bootstrap() async {
    try {
      await _platform.init();
      await _platform.requestPermission();
      await syncAll();
    } catch (_) {
      return;
    }
    _platform.events.listen((event) => unawaited(_handleEvent(event)));
  }

  /// 处理通知按钮动作（点击打开由 UI 层订阅 [events] 深链）。
  Future<void> _handleEvent(ReminderEvent event) => _quiet(() async {
        switch (event.action) {
          case ReminderAction.complete:
            await _services.planningService.completeTask(event.taskId);
          case ReminderAction.snooze:
            await _services.planningService.rescheduleTask(
              event.taskId,
              newStartAt: DateTime.now().add(const Duration(hours: 1)),
            );
          case ReminderAction.open:
            break; // 深链由 UI 处理
        }
      });

  /// 平台事件流（转发给 UI 做深链导航）。
  Stream<ReminderEvent> get events => _platform.events;

  /// 单任务同步：先取消旧提醒，再按「最近一次未来日程」重排。
  Future<void> syncTask(String taskId) => _quiet(() async {
        if (!await enabled()) return;
        await _platform.cancelTask(taskId);

        final task = await _services.tasks.findById(taskId);
        if (task == null || !_openStatuses.contains(task.status)) return;

        final schedules = await _services.schedules.findByTask(taskId);
        final now = DateTime.now();
        Schedule? next;
        for (final s in schedules) {
          if (s.status != ScheduleStatus.planned) continue;
          if (!s.startAt.isAfter(now)) continue;
          if (next == null || s.startAt.isBefore(next.startAt)) next = s;
        }
        if (next == null) return;

        final goalId = await _services.progressService.primaryGoalIdOf(taskId);
        final goal =
            goalId == null ? null : await _services.goals.findById(goalId);
        final fireAt = next.startAt.subtract(leadTime).isAfter(now)
            ? next.startAt.subtract(leadTime)
            : next.startAt;
        await _platform.schedule(ReminderRequest(
          taskId: taskId,
          goalId: goalId,
          title: '该做：${task.title}',
          body: goal == null
              ? '按计划现在开始'
              : '目标「${goal.title}」· ${_hhmm(next.startAt)} 开始',
          fireAt: fireAt,
        ));
      });

  /// 目标下全部开放任务重排（提案应用后调用）。
  Future<void> syncGoal(String goalId) => _quiet(() async {
        if (!await enabled()) return;
        for (final task in await _services.tasks.findByGoal(goalId)) {
          await syncTask(task.id);
        }
      });

  /// 全量补排（App 启动 / 设备重启后打开）。
  Future<void> syncAll() => _quiet(() async {
        if (!await enabled()) return;
        for (final goal in await _services.goals.findAll()) {
          await syncGoal(goal.id);
        }
      });

  Future<void> _quiet(Future<void> Function() body) async {
    try {
      await body();
    } catch (_) {
      // 提醒失败不影响业务流。
    }
  }

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
