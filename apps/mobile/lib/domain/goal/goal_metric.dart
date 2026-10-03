import '../time_codec.dart';

/// 可量化目标的度量，例如：体重 73.4kg → 70kg。
///
/// Goal 不强制拥有 Metric；是否需要 Metric 由 AI 在规划时判断。
enum MetricKind {
  numeric,
  percentage,
  count,
  duration,
  distance,
  score,

  /// 计划中的 `enum` 类型：在有限选项间演进（如背单词的册数级别）。
  category;

  static MetricKind parse(String value) => values.firstWhere(
        (v) => v.name == value,
        orElse: () => throw ArgumentError('未知的度量类型: $value'),
      );
}

/// 数值方向：increase 表示越大越好，decrease 表示越小越好（如体重、体脂）。
enum MetricDirection {
  increase,
  decrease;

  static MetricDirection parse(String value) => values.firstWhere(
        (v) => v.name == value,
        orElse: () => throw ArgumentError('未知的度量方向: $value'),
      );
}

class GoalMetric {
  const GoalMetric({
    required this.id,
    required this.goalId,
    required this.name,
    this.unit,
    this.kind = MetricKind.numeric,
    this.currentValue,
    this.targetValue,
    this.direction = MetricDirection.increase,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String goalId;

  /// 展示名，如「体重」「体脂」「存款」。
  final String name;

  /// 单位，如 kg、%、分钟、元。category 类型可为空。
  final String? unit;
  final MetricKind kind;

  final double? currentValue;
  final double? targetValue;
  final MetricDirection direction;

  final DateTime createdAt;
  final DateTime updatedAt;

  static const _keep = Object();

  GoalMetric copyWith({
    String? name,
    Object? unit = _keep,
    MetricKind? kind,
    Object? currentValue = _keep,
    Object? targetValue = _keep,
    MetricDirection? direction,
    DateTime? updatedAt,
  }) {
    return GoalMetric(
      id: id,
      goalId: goalId,
      name: name ?? this.name,
      unit: unit == _keep ? this.unit : unit as String?,
      kind: kind ?? this.kind,
      currentValue:
          currentValue == _keep ? this.currentValue : currentValue as double?,
      targetValue:
          targetValue == _keep ? this.targetValue : targetValue as double?,
      direction: direction ?? this.direction,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'goal_id': goalId,
        'name': name,
        'unit': unit,
        'kind': kind.name,
        'current_value': currentValue,
        'target_value': targetValue,
        'direction': direction.name,
        'created_at': encodeTime(createdAt),
        'updated_at': encodeTime(updatedAt),
      };

  factory GoalMetric.fromMap(Map<String, Object?> map) => GoalMetric(
        id: map['id']! as String,
        goalId: map['goal_id']! as String,
        name: map['name']! as String,
        unit: map['unit'] as String?,
        kind: MetricKind.parse(map['kind']! as String),
        currentValue: (map['current_value'] as num?)?.toDouble(),
        targetValue: (map['target_value'] as num?)?.toDouble(),
        direction: MetricDirection.parse(map['direction']! as String),
        createdAt: decodeTime(map['created_at']! as String),
        updatedAt: decodeTime(map['updated_at']! as String),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is GoalMetric && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'GoalMetric($id, $name ${currentValue ?? '-'} → ${targetValue ?? '-'})';
}

/// Metric 的历史记录点。currentValue 由最新一条记录驱动。
class MetricValue {
  const MetricValue({
    required this.id,
    required this.metricId,
    required this.value,
    required this.recordedAt,
    this.source,
    this.note,
  });

  final String id;
  final String metricId;
  final double value;
  final DateTime recordedAt;

  /// 来源（user / health / ai ...），复用 ProgressSource 的取值空间。
  final String? source;
  final String? note;

  Map<String, Object?> toMap() => {
        'id': id,
        'metric_id': metricId,
        'value': value,
        'recorded_at': encodeTime(recordedAt),
        'source': source,
        'note': note,
      };

  factory MetricValue.fromMap(Map<String, Object?> map) => MetricValue(
        id: map['id']! as String,
        metricId: map['metric_id']! as String,
        value: (map['value']! as num).toDouble(),
        recordedAt: decodeTime(map['recorded_at']! as String),
        source: map['source'] as String?,
        note: map['note'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is MetricValue && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
