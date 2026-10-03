import '../time_codec.dart';

/// Goal（目标）是顶层聚合根。
///
/// Goal 不只是一个 percentage：进展由 Outcome（Metrics）与
/// Process（Phases / Tasks / Schedule）共同表达，整体进度只用于统一展示。
enum GoalStatus {
  active,
  paused,
  completed,
  cancelled,
  archived;

  static GoalStatus parse(String value) => values.firstWhere(
        (v) => v.name == value,
        orElse: () => throw ArgumentError('未知的目标状态: $value'),
      );
}

class Goal {
  const Goal({
    required this.id,
    required this.title,
    this.description,
    this.status = GoalStatus.active,
    this.startDate,
    this.targetDate,
    this.overallProgress = 0,
    required this.createdAt,
    required this.updatedAt,
  }) : assert(overallProgress >= 0 && overallProgress <= 100);

  final String id;
  final String title;
  final String? description;

  /// 目标生命周期状态。删除类操作优先使用 archived 而不是物理删除。
  final GoalStatus status;

  final DateTime? startDate;
  final DateTime? targetDate;

  /// 0 ~ 100，仅用于统一展示；真实进展看 Metric 与 ProgressEvent。
  final double overallProgress;

  final DateTime createdAt;
  final DateTime updatedAt;

  static const _keep = Object();

  Goal copyWith({
    String? title,
    Object? description = _keep,
    GoalStatus? status,
    Object? startDate = _keep,
    Object? targetDate = _keep,
    double? overallProgress,
    DateTime? updatedAt,
  }) {
    return Goal(
      id: id,
      title: title ?? this.title,
      description:
          description == _keep ? this.description : description as String?,
      status: status ?? this.status,
      startDate: startDate == _keep ? this.startDate : startDate as DateTime?,
      targetDate: targetDate == _keep ? this.targetDate : targetDate as DateTime?,
      overallProgress: overallProgress ?? this.overallProgress,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// 行映射使用数据库列名（snake_case），时间统一存 UTC ISO8601 字符串。
  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'description': description,
        'status': status.name,
        'start_date': encodeTimeOrNull(startDate),
        'target_date': encodeTimeOrNull(targetDate),
        'overall_progress': overallProgress,
        'created_at': encodeTime(createdAt),
        'updated_at': encodeTime(updatedAt),
      };

  factory Goal.fromMap(Map<String, Object?> map) => Goal(
        id: map['id']! as String,
        title: map['title']! as String,
        description: map['description'] as String?,
        status: GoalStatus.parse(map['status']! as String),
        startDate: decodeTimeOrNull(map['start_date'] as String?),
        targetDate: decodeTimeOrNull(map['target_date'] as String?),
        overallProgress: (map['overall_progress']! as num).toDouble(),
        createdAt: decodeTime(map['created_at']! as String),
        updatedAt: decodeTime(map['updated_at']! as String),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Goal && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Goal($id, $title, ${status.name}, $overallProgress%)';
}
