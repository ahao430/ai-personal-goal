import '../domain/goal/goal.dart';
import '../domain/goal/goal_metric.dart';
import '../domain/progress/progress_event.dart';
import '../domain/task/task.dart';
import 'app_services.dart';

/// 单个指标的近期趋势。
class MetricTrend {
  const MetricTrend({
    required this.name,
    required this.unit,
    required this.current,
    required this.target,
    required this.first,
    required this.last,
    required this.samples,
    required this.improved,
  });

  final String name;
  final String? unit;
  final double? current;
  final double? target;

  /// 观察窗口内的第一个 / 最后一个值（first 可能等于 last）。
  final double? first;
  final double? last;
  final int samples;

  /// 窗口内是否朝目标方向前进。
  final bool improved;

  double? get delta => (first != null && last != null) ? last! - first! : null;
}

/// 目标执行分析（plan §46 / docs/ai/prompts.md §2 progress.analysis）。
///
/// 这是给 AI 的聚合事实：完成率、延期率、逾期数、指标趋势、
/// 近期事件时间线 —— 模型据此做偏差诊断，不自己数原始列表。
class GoalAnalysis {
  const GoalAnalysis({
    required this.goal,
    required this.tasksTotal,
    required this.tasksCompleted,
    required this.tasksCancelled,
    required this.tasksOverdue,
    required this.postponedRecent,
    required this.completedRecent,
    required this.recentEvents,
    required this.metricTrends,
  });

  final Goal goal;

  final int tasksTotal;
  final int tasksCompleted;
  final int tasksCancelled;

  /// 已过期仍未完成的任务数。
  final int tasksOverdue;

  /// 近 14 天 task_postponed / task_completed 事件数。
  final int postponedRecent;
  final int completedRecent;

  final List<ProgressEvent> recentEvents;
  final List<MetricTrend> metricTrends;

  /// 有效任务数（剔除已取消，进度分母与之一致）。
  int get tasksEffective => tasksTotal - tasksCancelled;

  /// 完成率 0-100（无有效任务返回 null）。
  int? get completionRate => tasksEffective == 0
      ? null
      : (tasksCompleted * 100 / tasksEffective).round();

  /// 近 14 天延期频次占（延期+完成）的比例 0-100；样本不足返回 null。
  int? get postponeRate {
    final sample = postponedRecent + completedRecent;
    if (sample == 0) return null;
    return (postponedRecent * 100 / sample).round();
  }

  bool get hasSignals =>
      (completionRate != null && completionRate! < 100) ||
      tasksOverdue > 0 ||
      postponedRecent >= 2 ||
      metricTrends.any((t) => t.samples >= 2 && !t.improved);
}

/// 计算目标执行分析（只读聚合）。
class AnalysisService {
  AnalysisService(this._services);

  final AppServices _services;

  static const Duration window = Duration(days: 14);

  Future<GoalAnalysis> analyze(String goalId, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    final goal = await _services.goals.findById(goalId);
    if (goal == null) {
      throw StateError('Goal 不存在: $goalId');
    }

    final tasks = await _services.tasks.findByGoal(goalId);
    final effective =
        tasks.where((t) => t.status != TaskStatus.cancelled).toList();
    final completed = effective.where((t) => t.status == TaskStatus.completed);
    final overdue = effective.where((t) =>
        t.dueDate != null &&
        t.dueDate!.isBefore(DateTime(at.year, at.month, at.day)) &&
        t.status != TaskStatus.completed);

    final events = await _services.progressEvents.findByGoal(goalId, limit: 30);
    final windowStart = at.subtract(window);
    final inWindow = events
        .where((e) => e.time.isAfter(windowStart))
        .toList()
        .reversed
        .toList(); // 时间升序
    final postponed = inWindow
        .where((e) => e.type == ProgressEventType.taskPostponed)
        .length;
    final completedCount = inWindow
        .where((e) => e.type == ProgressEventType.taskCompleted)
        .length;

    final metrics = await _services.metrics.findByGoal(goalId);
    final trends = <MetricTrend>[
      for (final m in metrics) await _trendOf(m, windowStart),
    ];

    return GoalAnalysis(
      goal: goal,
      tasksTotal: tasks.length,
      tasksCompleted: completed.length,
      tasksCancelled: tasks.length - effective.length,
      tasksOverdue: overdue.length,
      postponedRecent: postponed,
      completedRecent: completedCount,
      recentEvents: inWindow.take(10).toList(),
      metricTrends: trends,
    );
  }

  /// 窗口内指标趋势：取最近 14 天的值序列，判断是否朝目标方向前进。
  Future<MetricTrend> _trendOf(GoalMetric m, DateTime windowStart) async {
    final history = await _services.metrics.valuesOfMetric(m.id, limit: 30);
    final inWindow = history
        .where((v) => v.recordedAt.isAfter(windowStart))
        .toList()
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));

    final first = inWindow.isNotEmpty ? inWindow.first.value : null;
    final last = inWindow.isNotEmpty ? inWindow.last.value : m.currentValue;
    final decrease = m.direction == MetricDirection.decrease;
    final improved = (first != null && last != null)
        ? (decrease ? last < first : last > first)
        : false;

    return MetricTrend(
      name: m.name,
      unit: m.unit,
      current: m.currentValue,
      target: m.targetValue,
      first: first,
      last: last,
      samples: inWindow.length,
      improved: improved,
    );
  }
}
