import 'package:uuid/uuid.dart';

/// 实体 ID 统一使用「前缀 + UUID」的字符串形式（goal_xxx / task_xxx ...）。
///
/// 不使用数据库自增 ID 作为跨设备唯一标识，未来云同步可直接复用这些 ID。
abstract final class EntityIds {
  static const _uuid = Uuid();

  static String newGoalId() => 'goal_${_uuid.v4()}';
  static String newPhaseId() => 'phase_${_uuid.v4()}';
  static String newTaskId() => 'task_${_uuid.v4()}';
  static String newScheduleId() => 'schedule_${_uuid.v4()}';
  static String newProgressEventId() => 'event_${_uuid.v4()}';
  static String newMetricId() => 'metric_${_uuid.v4()}';
  static String newMetricValueId() => 'metric_value_${_uuid.v4()}';
  static String newProviderId() => 'provider_${_uuid.v4()}';
  static String newProposalId() => 'prop_${_uuid.v4()}';
}
