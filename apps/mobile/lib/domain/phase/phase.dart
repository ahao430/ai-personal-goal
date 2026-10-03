import '../time_codec.dart';

/// Phase 是 Goal 的阶段性进展（不是 Todo 分组）。
///
/// 例如「做出 AI Goal App」→ 产品设计 ✓ / MVP UI ● / App 开发 ○ ...
enum PhaseStatus {
  todo,
  inProgress,
  completed,
  cancelled;

  static PhaseStatus parse(String value) => values.firstWhere(
        (v) => v.name == value,
        orElse: () => throw ArgumentError('未知的阶段状态: $value'),
      );

  String get columnName {
    switch (this) {
      case todo:
        return 'todo';
      case inProgress:
        return 'in_progress';
      case completed:
        return 'completed';
      case cancelled:
        return 'cancelled';
    }
  }

  static PhaseStatus fromColumnName(String value) => values.firstWhere(
        (v) => v.columnName == value,
        orElse: () => throw ArgumentError('未知的阶段状态: $value'),
      );
}

class Phase {
  const Phase({
    required this.id,
    required this.goalId,
    required this.title,
    this.description,
    this.status = PhaseStatus.todo,
    this.orderIndex = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String goalId;
  final String title;
  final String? description;
  final PhaseStatus status;

  /// 同一 Goal 内的展示顺序，从 0 开始。
  final int orderIndex;

  final DateTime createdAt;
  final DateTime updatedAt;

  static const _keep = Object();

  Phase copyWith({
    String? title,
    Object? description = _keep,
    PhaseStatus? status,
    int? orderIndex,
    DateTime? updatedAt,
  }) {
    return Phase(
      id: id,
      goalId: goalId,
      title: title ?? this.title,
      description:
          description == _keep ? this.description : description as String?,
      status: status ?? this.status,
      orderIndex: orderIndex ?? this.orderIndex,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'goal_id': goalId,
        'title': title,
        'description': description,
        'status': status.columnName,
        'order_index': orderIndex,
        'created_at': encodeTime(createdAt),
        'updated_at': encodeTime(updatedAt),
      };

  factory Phase.fromMap(Map<String, Object?> map) => Phase(
        id: map['id']! as String,
        goalId: map['goal_id']! as String,
        title: map['title']! as String,
        description: map['description'] as String?,
        status: PhaseStatus.fromColumnName(map['status']! as String),
        orderIndex: map['order_index']! as int,
        createdAt: decodeTime(map['created_at']! as String),
        updatedAt: decodeTime(map['updated_at']! as String),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Phase && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Phase($id, $title, ${status.columnName})';
}
