import '../domain/entity_ids.dart';
import '../domain/goal/goal_repository.dart';
import '../domain/phase/phase.dart';
import '../domain/phase/phase_repository.dart';
import '../domain/progress/progress_event.dart';
import '../domain/progress/progress_event_repository.dart';
import '../domain/task/task_repository.dart';
import '../domain/task/task.dart';

/// 进度引擎：事件发射、目标整体进度重算、阶段自动完成。
///
/// 原则（plan.md §11）：重要状态变化都产生 ProgressEvent；
/// overallProgress 只用于统一展示，由 Task 完成度推导。
class ProgressService {
  ProgressService(
    this._goals,
    this._phases,
    this._tasks,
    this._events,
  );

  final GoalRepository _goals;
  final PhaseRepository _phases;
  final TaskRepository _tasks;
  final ProgressEventRepository _events;

  /// 发射一条进度事件。
  Future<ProgressEvent> emit(
    ProgressEventType type, {
    String? goalId,
    String? taskId,
    String? message,
    Map<String, Object?>? data,
    ProgressSource source = ProgressSource.user,
  }) {
    return _events.insert(
      ProgressEvent(
        id: EntityIds.newProgressEventId(),
        goalId: goalId,
        taskId: taskId,
        type: type,
        time: DateTime.now(),
        source: source,
        message: message,
        data: data,
      ),
    );
  }

  /// 按「未取消任务中已完成的比例」重算目标整体进度（四舍五入到整数百分比）。
  ///
  /// 无任务时进度归 0。进度未变化时不写库，避免 updatedAt 抖动。
  Future<double> recalcGoalProgress(String goalId) async {
    final allTasks = await _tasks.findByGoal(goalId);
    final effective =
        allTasks.where((t) => t.status != TaskStatus.cancelled).toList();
    final progress = effective.isEmpty
        ? 0.0
        : (effective
                    .where((t) => t.status == TaskStatus.completed)
                    .length *
                100 /
                effective.length)
            .roundToDouble();

    final goal = await _goals.findById(goalId);
    if (goal == null || goal.overallProgress == progress) return progress;
    await _goals.update(goal.copyWith(overallProgress: progress));
    return progress;
  }

  /// 任务状态变化后的联动：重算所有关联 Goal 的进度，
  /// 并自动完成「全部任务已完成」的阶段。
  Future<void> afterTaskChange(String taskId) async {
    final goalIds = await _tasks.goalIdsOf(taskId);
    for (final goalId in goalIds) {
      await recalcGoalProgress(goalId);
      await autoCompletePhases(goalId);
    }
  }

  /// 阶段下所有未取消任务都完成时，自动标记阶段完成并产生事件。
  Future<void> autoCompletePhases(String goalId) async {
    final phases = await _phases.findByGoal(goalId);
    for (final phase in phases) {
      if (phase.status == PhaseStatus.completed ||
          phase.status == PhaseStatus.cancelled) {
        continue;
      }
      final tasks = await _tasks.findByPhase(phase.id);
      final effective =
          tasks.where((t) => t.status != TaskStatus.cancelled).toList();
      if (effective.isEmpty) continue;
      if (!effective.every((t) => t.status == TaskStatus.completed)) continue;

      await _phases.update(phase.copyWith(status: PhaseStatus.completed));
      await emit(
        ProgressEventType.phaseCompleted,
        goalId: goalId,
        message: '阶段「${phase.title}」全部任务完成',
        source: ProgressSource.system,
      );
    }
  }

  /// 任务的（首个）关联目标 ID，用于事件归属；无关联目标时返回 null。
  Future<String?> primaryGoalIdOf(String taskId) async {
    final ids = await _tasks.goalIdsOf(taskId);
    return ids.isEmpty ? null : ids.first;
  }
}
