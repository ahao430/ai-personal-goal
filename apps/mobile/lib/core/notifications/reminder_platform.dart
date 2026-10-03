import 'dart:async';
import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// 平台通知事件（点击打开 / 按钮动作）。
enum ReminderAction { open, complete, snooze }

class ReminderEvent {
  const ReminderEvent({
    required this.taskId,
    required this.goalId,
    required this.action,
  });

  final String taskId;
  final String? goalId;
  final ReminderAction action;
}

/// 一条任务提醒的调度请求。
class ReminderRequest {
  const ReminderRequest({
    required this.taskId,
    required this.goalId,
    required this.title,
    required this.body,
    required this.fireAt,
  });

  final String taskId;
  final String? goalId;
  final String title;
  final String body;

  /// 触发时间（本地时间）。
  final DateTime fireAt;

  /// 通知 id（int32）：同一任务固定一个 id，重排即覆盖。
  static int idOf(String taskId) => taskId.hashCode & 0x7FFFFFFF;

  Map<String, Object?> toPayload() =>
      {'taskId': taskId, 'goalId': ?goalId};
}

/// 平台无关的任务提醒能力。
///
/// application 层（NotificationScheduler）只依赖此接口；
/// 测试注入 fake 记录调用，不真触系统通知。
abstract interface class ReminderPlatform {
  Future<void> init();

  /// 请求通知权限；true = 已授权。
  Future<bool> requestPermission();

  Future<void> schedule(ReminderRequest request);

  Future<void> cancelTask(String taskId);

  Future<void> cancelAll();

  /// 点击通知 / 按钮动作事件（含冷启动时的 launch notification）。
  Stream<ReminderEvent> get events;
}

/// flutter_local_notifications 实现（Android 优先，iOS 基本可用）。
///
/// 所有平台调用都有异常防护：通知失败（平台不可用 / 权限缺失）不应
/// 影响业务流 —— 测试与桌面环境静默降级为 no-op。
class ReminderPlatformImpl implements ReminderPlatform {
  final _plugin = FlutterLocalNotificationsPlugin();
  final _events = StreamController<ReminderEvent>.broadcast();

  static const _channelId = 'task_reminders';
  static const _channelName = '任务提醒';
  static const _actionComplete = 'complete';
  static const _actionSnooze = 'snooze';

  @override
  Future<void> init() => _guard(() async {
        tzdata.initializeTimeZones();
        try {
          final zone = await FlutterTimezone.getLocalTimezone();
          tz.setLocalLocation(tz.getLocation(zone.identifier));
        } catch (_) {
          // 时区名不可用时退回 UTC —— 提醒时间可能偏移，但不崩溃。
        }

        await _plugin.initialize(
          settings: const InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher'),
            iOS: DarwinInitializationSettings(),
          ),
          onDidReceiveNotificationResponse: _onResponse,
        );

        // 冷启动由通知拉起时，补发一次 launch 事件。
        final launch = await _plugin.getNotificationAppLaunchDetails();
        final response = launch?.notificationResponse;
        if (launch?.didNotificationLaunchApp == true && response != null) {
          _handle(response);
        }
      });

  void _onResponse(NotificationResponse response) => _handle(response);

  void _handle(NotificationResponse response) {
    final payload = _decode(response.payload);
    if (payload == null) return;
    switch (response.actionId) {
      case _actionComplete:
        _events.add(ReminderEvent(
          taskId: payload['taskId'] as String,
          goalId: payload['goalId'] as String?,
          action: ReminderAction.complete,
        ));
      case _actionSnooze:
        _events.add(ReminderEvent(
          taskId: payload['taskId'] as String,
          goalId: payload['goalId'] as String?,
          action: ReminderAction.snooze,
        ));
      default:
        _events.add(ReminderEvent(
          taskId: payload['taskId'] as String,
          goalId: payload['goalId'] as String?,
          action: ReminderAction.open,
        ));
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        final granted =
            await android.requestNotificationsPermission() ?? false;
        // 精确闹钟尽力而为：未授予则降级 inexact（系统在低功耗模式窗口触发）。
        final exact = await android.canScheduleExactNotifications() ?? false;
        if (!exact) {
          await android.requestExactAlarmsPermission();
        }
        return granted;
      }
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        return await ios.requestPermissions(alert: true, sound: true) ?? false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> schedule(ReminderRequest request) => _guard(() async {
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        final exact = await android?.canScheduleExactNotifications() ?? false;

        await _plugin.zonedSchedule(
          id: ReminderRequest.idOf(request.taskId),
          title: request.title,
          body: request.body,
          scheduledDate: tz.TZDateTime.from(request.fireAt, tz.local),
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              _channelName,
              channelDescription: '按计划时间提醒任务（开始前 10 分钟）',
              importance: Importance.high,
              priority: Priority.high,
              actions: [
                const AndroidNotificationAction(_actionComplete, '完成了',
                    showsUserInterface: true),
                const AndroidNotificationAction(_actionSnooze, '延后 1 小时',
                    showsUserInterface: true),
              ],
            ),
            iOS: const DarwinNotificationDetails(),
          ),
          androidScheduleMode: exact
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,
        );
      });

  @override
  Future<void> cancelTask(String taskId) => _guard(() =>
      _plugin.cancel(id: ReminderRequest.idOf(taskId)));

  @override
  Future<void> cancelAll() => _guard(_plugin.cancelAll);

  @override
  Stream<ReminderEvent> get events => _events.stream;

  Future<void> _guard(Future<void> Function() body) async {
    try {
      await body();
    } catch (_) {
      // 平台不可用（测试 / 桌面 / 插件未注册）：静默降级为 no-op。
    }
  }

  static Map<String, Object?>? _decode(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      return jsonDecode(payload) as Map<String, Object?>;
    } catch (_) {
      return null;
    }
  }
}
