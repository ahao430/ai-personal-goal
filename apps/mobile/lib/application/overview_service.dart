import '../domain/goal/goal.dart';
import '../domain/goal/goal_metric.dart';
import '../domain/goal/goal_repository.dart';
import '../domain/phase/phase.dart';
import '../domain/phase/phase_repository.dart';
import '../domain/progress/progress_event.dart';
import '../domain/progress/progress_event_repository.dart';
import '../domain/schedule/schedule.dart';
import '../domain/schedule/schedule_repository.dart';
import '../domain/task/task.dart';
import '../domain/task/task_repository.dart';

/// 「今天」列表项：任务与（可选）其今日日程，由服务层联查好。
class TodayItem {
  const TodayItem({required this.task, this.schedule});

  final Task task;
  final Schedule? schedule;
}

/// 首页「今天」区块。
class TodayView {
  const TodayView({
    required this.items,
    required this.overdueTasks,
  });

  /// 今日安排 + 今日截止（已去重：有日程的任务只出现一次），按时间升序。
  final List<TodayItem> items;

  /// 已经过期仍未完成的任务（需要处理）。
  final List<Task> overdueTasks;

  bool get isEmpty => items.isEmpty && overdueTasks.isEmpty;
}

/// 首页聚合视图。
class HomeView {
  const HomeView({
    required this.today,
    required this.activeGoals,
    this.primaryGoal,
    this.currentPhase,
    this.nextTask,
    this.primaryMetrics = const [],
  });

  final TodayView today;
  final List<Goal> activeGoals;

  /// 当前目标：最近更新过的活跃目标。
  final Goal? primaryGoal;
  final Phase? currentPhase;

  /// 下一步：当前目标最早到期的未完成任务。
  final Task? nextTask;
  final List<GoalMetric> primaryMetrics;
}

/// 目标详情聚合视图。
class GoalDetailData {
  const GoalDetailData({
    required this.goal,
    required this.phases,
    required this.tasksByPhase,
    required this.unphasedTasks,
    required this.metrics,
    required this.recentEvents,
  });

  final Goal goal;
  final List<Phase> phases;

  /// phaseId → 任务列表（保持插入顺序）。
  final Map<String, List<Task>> tasksByPhase;

  /// 未挂阶段的任务。
  final List<Task> unphasedTasks;

  final List<GoalMetric> metrics;
  final List<ProgressEvent> recentEvents;
}

/// 日历月视图：某月内有日程（planned）或截止的开放任务，按日分组。
class CalendarViewData {
  const CalendarViewData({required this.month, required this.itemsByDay});

  /// 该月 1 号（锚点，含年月信息）。
  final DateTime month;

  /// day-of-month → 当日条目（日程时间排序）。
  final Map<int, List<TodayItem>> itemsByDay;

  List<TodayItem> itemsOf(int day) => itemsByDay[day] ?? const [];
}

/// 只读聚合查询（UI 的数据来源）。写操作走 GoalService / PlanningService。
class OverviewService {
  OverviewService(
    this._goals,
    this._phases,
    this._tasks,
    this._schedules,
    this._metrics,
    this._events,
  );

  final GoalRepository _goals;
  final PhaseRepository _phases;
  final TaskRepository _tasks;
  final ScheduleRepository _schedules;
  final GoalMetricRepository _metrics;
  final ProgressEventRepository _events;

  static const Set<TaskStatus> _openStatuses = {
    TaskStatus.todo,
    TaskStatus.inProgress,
    TaskStatus.postponed,
  };

  Future<HomeView> homeView({DateTime? now}) async {
    final at = now ?? DateTime.now();
    final today = await todayView(at);

    final active = await _goals.findAll(status: GoalStatus.active);
    Goal? primary;
    Phase? currentPhase;
    Task? nextTask;
    List<GoalMetric> primaryMetrics = const [];

    if (active.isNotEmpty) {
      primary = active.first; // findAll 按 updated_at DESC
      final phases = await _phases.findByGoal(primary.id);
      currentPhase = phases
          .where((p) => p.status != PhaseStatus.completed && p.status != PhaseStatus.cancelled)
          .firstOrNull;
      nextTask = await _nextTaskOf(primary.id);
      primaryMetrics = await _metrics.findByGoal(primary.id);
    }

    return HomeView(
      today: today,
      activeGoals: active,
      primaryGoal: primary,
      currentPhase: currentPhase,
      nextTask: nextTask,
      primaryMetrics: primaryMetrics,
    );
  }

  Future<TodayView> todayView(DateTime at) async {
    final dayStart = DateTime(at.year, at.month, at.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    final scheduledToday =
        (await _schedules.findBetween(dayStart, dayEnd))
            .where((s) => s.status == ScheduleStatus.planned)
            .toList();

    final items = <TodayItem>[];
    final scheduledTaskIds = <String>{};
    for (final s in scheduledToday) {
      final task = await _tasks.findById(s.taskId);
      if (task == null || !_openStatuses.contains(task.status)) continue;
      scheduledTaskIds.add(task.id);
      items.add(TodayItem(task: task, schedule: s));
    }
    // 今天截止但未排日程的任务（去重后追加）
    final dueToday = (await _tasks.findDueBetween(dayStart, dayEnd))
        .where((t) =>
            _openStatuses.contains(t.status) && !scheduledTaskIds.contains(t.id))
        .toList();
    items.addAll(dueToday.map((t) => TodayItem(task: t)));

    final overdue = (await _tasks.findDueBetween(
      DateTime(2000),
      dayStart,
    ))
        .where((t) => _openStatuses.contains(t.status))
        .toList();

    return TodayView(items: items, overdueTasks: overdue);
  }

  Future<GoalDetailData> goalDetail(String goalId) async {
    final goal = await _goals.findById(goalId);
    if (goal == null) {
      throw StateError('Goal 不存在: $goalId');
    }
    final phases = await _phases.findByGoal(goalId);
    final tasks = await _tasks.findByGoal(goalId);

    final byPhase = <String, List<Task>>{};
    final unphased = <Task>[];
    for (final task in tasks) {
      final pid = task.phaseId;
      if (pid == null) {
        unphased.add(task);
      } else {
        byPhase.putIfAbsent(pid, () => []).add(task);
      }
    }

    return GoalDetailData(
      goal: goal,
      phases: phases,
      tasksByPhase: byPhase,
      unphasedTasks: unphased,
      metrics: await _metrics.findByGoal(goalId),
      recentEvents: await _events.findByGoal(goalId, limit: 20),
    );
  }

  /// 目标下一步：未完成任务中最早截止（无截止按创建时间）。
  Future<Task?> _nextTaskOf(String goalId) async {
    final tasks = await _tasks.findByGoal(goalId);
    final open = tasks.where((t) => _openStatuses.contains(t.status)).toList();
    if (open.isEmpty) return null;
    open.sort((a, b) {
      final ad = a.dueDate ?? a.createdAt;
      final bd = b.dueDate ?? b.createdAt;
      return ad.compareTo(bd);
    });
    return open.first;
  }

  /// 日历月视图聚合：[month] 传任意当月时间。
  ///
  /// 有 planned 日程的任务按日程落位（同任务多个日程都展示）；
  /// 无日程但有截止日期的任务按截止日落位。
  Future<CalendarViewData> calendarView(DateTime month, {String? goalId}) async {
    final monthStart = DateTime(month.year, month.month, 1);
    final monthEnd = DateTime(month.year, month.month + 1, 1);

    // 目标上下文：只展示该目标的任务。
    final Set<String> allowed;
    if (goalId != null) {
      allowed = {
        for (final t in await _tasks.findByGoal(goalId)) t.id,
      };
    } else {
      allowed = const {};
    }
    final bool filterByGoal = goalId != null;

    // 月内 planned 日程，按任务分组。
    final scheduleByTask = <String, List<Schedule>>{};
    for (final s
        in (await _schedules.findBetween(monthStart, monthEnd))
            .where((s) => s.status == ScheduleStatus.planned)) {
      scheduleByTask.putIfAbsent(s.taskId, () => []).add(s);
    }

    // 月内有日程的任务 + 月内截止的任务（可能无日程）。
    final taskById = <String, Task>{
      for (final t in await _tasks.findScheduledBetween(monthStart, monthEnd))
        t.id: t,
      for (final t in await _tasks.findDueBetween(monthStart, monthEnd))
        t.id: t,
    };

    final itemsByDay = <int, List<TodayItem>>{};
    void add(DateTime at, TodayItem item) =>
        itemsByDay.putIfAbsent(at.day, () => []).add(item);

    for (final task in taskById.values) {
      if (!_openStatuses.contains(task.status)) continue;
      if (filterByGoal && !allowed.contains(task.id)) continue;

      final schedules = scheduleByTask[task.id] ?? const <Schedule>[];
      if (schedules.isNotEmpty) {
        for (final s in schedules) {
          add(s.startAt, TodayItem(task: task, schedule: s));
        }
      } else if (task.dueDate != null) {
        add(task.dueDate!, TodayItem(task: task));
      }
    }

    for (final list in itemsByDay.values) {
      list.sort((a, b) {
        DateTime itemTime(TodayItem item) =>
            item.schedule?.startAt ?? item.task.dueDate ?? DateTime(9999);
        return itemTime(a).compareTo(itemTime(b));
      });
    }

    return CalendarViewData(month: monthStart, itemsByDay: itemsByDay);
  }
}
