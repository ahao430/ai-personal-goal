import '../domain/entity_ids.dart';
import '../domain/goal/goal.dart';
import '../domain/goal/goal_metric.dart';
import '../domain/goal/goal_repository.dart';
import '../domain/progress/progress_event.dart';
import 'progress_service.dart';

/// 目标生命周期用例：创建 / 编辑 / 暂停恢复 / 完成 / 取消 / 归档，
/// 以及 GoalMetric 的建立与记录。
class GoalService {
  GoalService(this._goals, this._metrics, this._progress);

  final GoalRepository _goals;
  final GoalMetricRepository _metrics;
  final ProgressService _progress;

  Future<Goal> createGoal({
    required String title,
    String? description,
    DateTime? startDate,
    DateTime? targetDate,
    String? reward,
  }) {
    final now = DateTime.now();
    return _goals.insert(
      Goal(
        id: EntityIds.newGoalId(),
        title: title,
        description: description,
        startDate: startDate,
        targetDate: targetDate,
        reward: reward,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// 通用编辑：拿到当前值做 copyWith，返回更新后的 Goal 并产生 goal_updated 事件。
  ///
  /// 用函数入参（而非散列参数）以完整保留 copyWith 的「置空 vs 不变」语义。
  Future<Goal> updateGoal(String id, Goal Function(Goal current) edit) async {
    final current = await _goals.findById(id);
    if (current == null) {
      throw StateError('Goal 不存在: $id');
    }
    final next = edit(current);
    final updated = await _goals.update(next);
    await _progress.emit(
      ProgressEventType.goalUpdated,
      goalId: id,
      message: '更新了目标「${updated.title}」',
    );
    return updated;
  }

  Future<Goal> pauseGoal(String id, {String? reason}) async {
    final goal = await _transition(id, GoalStatus.paused);
    if (goal == null) return (await _goals.findById(id))!;
    await _progress.emit(
      ProgressEventType.goalPaused,
      goalId: id,
      message: reason == null ? '暂停目标「${goal.title}」' : '暂停目标「${goal.title}」：$reason',
    );
    return goal;
  }

  Future<Goal> resumeGoal(String id) async {
    final goal = await _transition(id, GoalStatus.active);
    if (goal == null) return (await _goals.findById(id))!;
    await _progress.emit(
      ProgressEventType.goalResumed,
      goalId: id,
      message: '恢复目标「${goal.title}」',
    );
    return goal;
  }

  Future<Goal> completeGoal(String id) async {
    final goal = await _transition(id, GoalStatus.completed);
    if (goal == null) return (await _goals.findById(id))!;
    await _progress.emit(
      ProgressEventType.goalUpdated,
      goalId: id,
      message: goal.reward == null
          ? '目标「${goal.title}」完成 🎉'
          : '目标「${goal.title}」完成 🎉 记得奖励自己：${goal.reward}',
    );
    return goal;
  }

  Future<Goal> cancelGoal(String id, {String? reason}) async {
    final goal = await _transition(id, GoalStatus.cancelled);
    if (goal == null) return (await _goals.findById(id))!;
    await _progress.emit(
      ProgressEventType.goalUpdated,
      goalId: id,
      message: reason == null ? '取消目标「${goal.title}」' : '取消目标「${goal.title}」：$reason',
    );
    return goal;
  }

  Future<Goal> archiveGoal(String id) async {
    final goal = await _transition(id, GoalStatus.archived);
    return goal ?? (await _goals.findById(id))!;
  }

  /// 状态迁移；已是目标状态时返回 null（不写库、不发事件）。
  ///
  /// 进入 completed 时记录 completedAt（首页统计依据）；
  /// 离开 completed（重开/取消/归档）时清空，避免统计被污染。
  Future<Goal?> _transition(String id, GoalStatus status) async {
    final current = await _goals.findById(id);
    if (current == null) {
      throw StateError('Goal 不存在: $id');
    }
    if (current.status == status) return null;
    return _goals.update(
      current.copyWith(
        status: status,
        completedAt: status == GoalStatus.completed ? DateTime.now() : null,
      ),
    );
  }

  // ── Metrics ────────────────────────────────────────────

  /// 为目标建立度量（可选能力，不是所有目标都需要）。
  Future<GoalMetric> addMetric(
    String goalId, {
    required String name,
    String? unit,
    MetricKind kind = MetricKind.numeric,
    MetricDirection direction = MetricDirection.increase,
    double? initialValue,
    double? targetValue,
  }) async {
    final now = DateTime.now();
    final metric = await _metrics.insert(
      GoalMetric(
        id: EntityIds.newMetricId(),
        goalId: goalId,
        name: name,
        unit: unit,
        kind: kind,
        currentValue: initialValue,
        targetValue: targetValue,
        direction: direction,
        createdAt: now,
        updatedAt: now,
      ),
    );
    if (initialValue != null) {
      await _metrics.addValue(MetricValue(
        id: EntityIds.newMetricValueId(),
        metricId: metric.id,
        value: initialValue,
        recordedAt: now,
        source: ProgressSource.user.name,
      ));
    }
    return metric;
  }

  /// 记录一次指标值（如体重），推进 currentValue 并产生 metric_updated 事件。
  Future<double> recordMetricValue(
    String metricId,
    double value, {
    String? note,
  }) async {
    final metric = await _metrics.findById(metricId);
    if (metric == null) {
      throw StateError('Metric 不存在: $metricId');
    }
    final from = metric.currentValue;
    await _metrics.addValue(MetricValue(
      id: EntityIds.newMetricValueId(),
      metricId: metricId,
      value: value,
      recordedAt: DateTime.now(),
      source: ProgressSource.user.name,
      note: note,
    ));
    await _progress.emit(
      ProgressEventType.metricUpdated,
      goalId: metric.goalId,
      message: '${metric.name}：${_fmt(from)} → ${_fmt(value)}${metric.unit ?? ''}',
      data: {
        'metricId': metricId,
        'metricName': metric.name,
        'from': from,
        'to': value,
        if (metric.unit != null) 'unit': metric.unit,
      },
    );
    return value;
  }

  static String _fmt(double? v) =>
      v == null ? '—' : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());
}
