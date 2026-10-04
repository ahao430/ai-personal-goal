import 'goal.dart';
import 'goal_metric.dart';

/// Goal 仓储接口。UI / Application 层只依赖此接口，不接触 SQLite。
abstract interface class GoalRepository {
  Future<Goal> insert(Goal goal);
  Future<Goal> update(Goal goal);
  Future<Goal?> findById(String id);

  /// [status] 为空时返回全部（含 archived）。
  Future<List<Goal>> findAll({GoalStatus? status});

  /// 物理删除（级联删除 phases / metrics / 关联）。常规流程请用 archived 状态。
  Future<void> delete(String id);

  /// 活跃目标的轻量计数（首页展示用）。
  Future<int> countByStatus(GoalStatus status);

  /// [from] 之后（含）完成的目标数（首页本月/今年统计用）。
  Future<int> countCompletedSince(DateTime from);
}

/// GoalMetric 与其历史值（MetricValue）的仓储接口。
abstract interface class GoalMetricRepository {
  Future<GoalMetric> insert(GoalMetric metric);
  Future<GoalMetric> update(GoalMetric metric);
  Future<GoalMetric?> findById(String id);
  Future<List<GoalMetric>> findByGoal(String goalId);
  Future<void> delete(String id);

  /// 追加一条历史记录，并把 metric.currentValue 推进为该记录的值。
  Future<MetricValue> addValue(MetricValue value);
  Future<List<MetricValue>> valuesOfMetric(String metricId, {int limit = 50});
}
