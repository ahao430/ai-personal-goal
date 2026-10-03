import '../time_codec.dart';

/// Task 是具体执行动作。「什么时候做」由 Schedule 表达，不要混进 Task。
enum TaskStatus {
  todo,
  inProgress,
  completed,
  postponed,
  cancelled;

  static TaskStatus parse(String value) => values.firstWhere(
        (v) => v.name == value,
        orElse: () => throw ArgumentError('未知的任务状态: $value'),
      );

  String get columnName {
    switch (this) {
      case todo:
        return 'todo';
      case inProgress:
        return 'in_progress';
      case completed:
        return 'completed';
      case postponed:
        return 'postponed';
      case cancelled:
        return 'cancelled';
    }
  }

  static TaskStatus fromColumnName(String value) => values.firstWhere(
        (v) => v.columnName == value,
        orElse: () => throw ArgumentError('未知的任务状态: $value'),
      );
}

enum TaskPriority {
  low,
  medium,
  high;

  static TaskPriority parse(String value) => values.firstWhere(
        (v) => v.name == value,
        orElse: () => throw ArgumentError('未知的任务优先级: $value'),
      );
}

class Task {
  const Task({
    required this.id,
    required this.title,
    this.description,
    this.phaseId,
    this.status = TaskStatus.todo,
    this.priority = TaskPriority.medium,
    this.estimatedMinutes,
    this.dueDate,
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String? description;

  /// 所属 Phase。跨 Goal 关联通过 goal_tasks 表，而非这一列。
  final String? phaseId;

  final TaskStatus status;
  final TaskPriority priority;

  /// 预计耗时（分钟）。
  final int? estimatedMinutes;

  /// 截止时间（当天 23:59:59 语义由调用方保证）。
  final DateTime? dueDate;

  /// 完成时间，仅在 status == completed 时有值。
  final DateTime? completedAt;

  final DateTime createdAt;
  final DateTime updatedAt;

  static const _keep = Object();

  Task copyWith({
    String? title,
    Object? description = _keep,
    Object? phaseId = _keep,
    TaskStatus? status,
    TaskPriority? priority,
    Object? estimatedMinutes = _keep,
    Object? dueDate = _keep,
    Object? completedAt = _keep,
    DateTime? updatedAt,
  }) {
    return Task(
      id: id,
      title: title ?? this.title,
      description:
          description == _keep ? this.description : description as String?,
      phaseId: phaseId == _keep ? this.phaseId : phaseId as String?,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      estimatedMinutes: estimatedMinutes == _keep
          ? this.estimatedMinutes
          : estimatedMinutes as int?,
      dueDate: dueDate == _keep ? this.dueDate : dueDate as DateTime?,
      completedAt:
          completedAt == _keep ? this.completedAt : completedAt as DateTime?,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'description': description,
        'phase_id': phaseId,
        'status': status.columnName,
        'priority': priority.name,
        'estimated_minutes': estimatedMinutes,
        'due_date': encodeTimeOrNull(dueDate),
        'completed_at': encodeTimeOrNull(completedAt),
        'created_at': encodeTime(createdAt),
        'updated_at': encodeTime(updatedAt),
      };

  factory Task.fromMap(Map<String, Object?> map) => Task(
        id: map['id']! as String,
        title: map['title']! as String,
        description: map['description'] as String?,
        phaseId: map['phase_id'] as String?,
        status: TaskStatus.fromColumnName(map['status']! as String),
        priority: TaskPriority.parse(map['priority']! as String),
        estimatedMinutes: map['estimated_minutes'] as int?,
        dueDate: decodeTimeOrNull(map['due_date'] as String?),
        completedAt: decodeTimeOrNull(map['completed_at'] as String?),
        createdAt: decodeTime(map['created_at']! as String),
        updatedAt: decodeTime(map['updated_at']! as String),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Task && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Task($id, $title, ${status.columnName})';
}
