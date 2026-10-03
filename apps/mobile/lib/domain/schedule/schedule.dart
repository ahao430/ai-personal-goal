import '../time_codec.dart';

/// Schedule 表达「什么时候做」：某个 Task 在某个时间段的安排。
///
/// 同一个 Task 可以被多次重新安排（历史 Schedule 保留，供 AI 分析偏差）。
enum ScheduleStatus {
  planned,
  completed,
  cancelled,
  missed;

  static ScheduleStatus parse(String value) => values.firstWhere(
        (v) => v.name == value,
        orElse: () => throw ArgumentError('未知的日程状态: $value'),
      );
}

class Schedule {
  const Schedule({
    required this.id,
    required this.taskId,
    required this.startAt,
    this.endAt,
    this.durationMinutes,
    this.status = ScheduleStatus.planned,
    this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String taskId;

  final DateTime startAt;
  final DateTime? endAt;

  /// 预计时长（分钟）。endAt 与 durationMinutes 至少提供一个，便于通知排程。
  final int? durationMinutes;

  final ScheduleStatus status;
  final String? note;

  final DateTime createdAt;
  final DateTime updatedAt;

  static const _keep = Object();

  Schedule copyWith({
    DateTime? startAt,
    Object? endAt = _keep,
    Object? durationMinutes = _keep,
    ScheduleStatus? status,
    Object? note = _keep,
    DateTime? updatedAt,
  }) {
    return Schedule(
      id: id,
      taskId: taskId,
      startAt: startAt ?? this.startAt,
      endAt: endAt == _keep ? this.endAt : endAt as DateTime?,
      durationMinutes: durationMinutes == _keep
          ? this.durationMinutes
          : durationMinutes as int?,
      status: status ?? this.status,
      note: note == _keep ? this.note : note as String?,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'task_id': taskId,
        'start_at': encodeTime(startAt),
        'end_at': encodeTimeOrNull(endAt),
        'duration_minutes': durationMinutes,
        'status': status.name,
        'note': note,
        'created_at': encodeTime(createdAt),
        'updated_at': encodeTime(updatedAt),
      };

  factory Schedule.fromMap(Map<String, Object?> map) => Schedule(
        id: map['id']! as String,
        taskId: map['task_id']! as String,
        startAt: decodeTime(map['start_at']! as String),
        endAt: decodeTimeOrNull(map['end_at'] as String?),
        durationMinutes: map['duration_minutes'] as int?,
        status: ScheduleStatus.parse(map['status']! as String),
        note: map['note'] as String?,
        createdAt: decodeTime(map['created_at']! as String),
        updatedAt: decodeTime(map['updated_at']! as String),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Schedule && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Schedule($id, task=$taskId, $startAt)';
}
