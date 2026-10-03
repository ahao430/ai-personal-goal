import 'dart:convert';

import '../time_codec.dart';

/// ProgressEvent 记录真实发生的变化，是进度分析的事实依据。
///
/// 不要只依赖 task.status —— 状态会被覆盖，事件不会。
enum ProgressEventType {
  taskCompleted,
  taskStarted,
  taskPostponed,
  taskCancelled,
  metricUpdated,
  phaseCompleted,
  phaseCancelled,
  planApplied,
  goalUpdated,
  goalPaused,
  goalResumed,
  scheduleChanged,
  userReport;

  static ProgressEventType parse(String value) => values.firstWhere(
        (v) => v.name == value,
        orElse: () => throw ArgumentError('未知的进度事件类型: $value'),
      );

  String get columnName {
    switch (this) {
      case taskCompleted:
        return 'task_completed';
      case taskStarted:
        return 'task_started';
      case taskPostponed:
        return 'task_postponed';
      case taskCancelled:
        return 'task_cancelled';
      case metricUpdated:
        return 'metric_updated';
      case phaseCompleted:
        return 'phase_completed';
      case phaseCancelled:
        return 'phase_cancelled';
      case planApplied:
        return 'plan_applied';
      case goalUpdated:
        return 'goal_updated';
      case goalPaused:
        return 'goal_paused';
      case goalResumed:
        return 'goal_resumed';
      case scheduleChanged:
        return 'schedule_changed';
      case userReport:
        return 'user_report';
    }
  }

  static ProgressEventType fromColumnName(String value) => values.firstWhere(
        (v) => v.columnName == value,
        orElse: () => throw ArgumentError('未知的进度事件类型: $value'),
      );
}

/// 事件来源：用户、聊天、系统、健康数据、定位、日历、AI、通知。
enum ProgressSource {
  user,
  chat,
  system,
  health,
  location,
  calendar,
  ai,
  notification;

  static ProgressSource parse(String value) => values.firstWhere(
        (v) => v.name == value,
        orElse: () => throw ArgumentError('未知的进度事件来源: $value'),
      );
}

class ProgressEvent {
  const ProgressEvent({
    required this.id,
    this.goalId,
    this.taskId,
    required this.type,
    required this.time,
    required this.source,
    this.message,
    this.data,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? time;

  final String id;
  final String? goalId;
  final String? taskId;

  final ProgressEventType type;

  /// 事件发生的时间（区别于 createdAt：补录时两者不同）。
  final DateTime time;

  final ProgressSource source;

  /// 用户可读描述，如「昨天的英语跟读完成了」。
  final String? message;

  /// 结构化附加数据（如 metric 变更前后的值），JSON 编码存储。
  final Map<String, Object?>? data;

  /// 事件写入数据库的时间。
  final DateTime createdAt;

  ProgressEvent copyWith({
    ProgressEventType? type,
    DateTime? time,
    ProgressSource? source,
    String? message,
    Map<String, Object?>? data,
  }) {
    return ProgressEvent(
      id: id,
      goalId: goalId,
      taskId: taskId,
      type: type ?? this.type,
      time: time ?? this.time,
      source: source ?? this.source,
      message: message ?? this.message,
      data: data ?? this.data,
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'goal_id': goalId,
        'task_id': taskId,
        'type': type.columnName,
        'time': encodeTime(time),
        'source': source.name,
        'message': message,
        'data': data == null ? null : jsonEncode(data),
        'created_at': encodeTime(createdAt),
      };

  factory ProgressEvent.fromMap(Map<String, Object?> map) => ProgressEvent(
        id: map['id']! as String,
        goalId: map['goal_id'] as String?,
        taskId: map['task_id'] as String?,
        type: ProgressEventType.fromColumnName(map['type']! as String),
        time: decodeTime(map['time']! as String),
        source: ProgressSource.parse(map['source']! as String),
        message: map['message'] as String?,
        data: map['data'] == null
            ? null
            : jsonDecode(map['data']! as String) as Map<String, Object?>,
        createdAt: decodeTime(map['created_at']! as String),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is ProgressEvent && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'ProgressEvent($id, ${type.columnName}, ${source.name})';
}
