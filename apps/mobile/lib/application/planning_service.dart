import '../domain/entity_ids.dart';
import '../domain/progress/progress_event.dart';
import '../domain/phase/phase.dart';
import '../domain/phase/phase_repository.dart';
import '../domain/schedule/schedule.dart';
import '../domain/schedule/schedule_repository.dart';
import '../domain/task/task.dart';
import '../domain/task/task_repository.dart';
import 'progress_service.dart';

/// 计划用例：Phase / Task / Schedule 的创建与状态流转。
///
/// 所有状态变化都会通过 [ProgressService] 产生 ProgressEvent，
/// 并联动目标进度重算与阶段自动完成。
/// [onTaskChanged] 在任务/日程变化后触发（fire-and-forget）——
/// 装配层用它驱动 P7 的通知重排，UI 与 AI 工具自动同步提醒。
class PlanningService {
  PlanningService(
    this._phases,
    this._tasks,
    this._schedules,
    this._progress, {
    this.onTaskChanged,
  });

  final PhaseRepository _phases;
  final TaskRepository _tasks;
  final ScheduleRepository _schedules;
  final ProgressService _progress;

  /// 任务或其日程变化后的回调（taskId）。
  final void Function(String taskId)? onTaskChanged;

  void _notifyChanged(String taskId) => onTaskChanged?.call(taskId);

  // ── Phase ──────────────────────────────────────────────

  Future<Phase> createPhase({
    required String goalId,
    required String title,
    String? description,
  }) async {
    final now = DateTime.now();
    return _phases.insert(
      Phase(
        id: EntityIds.newPhaseId(),
        goalId: goalId,
        title: title,
        description: description,
        orderIndex: await _phases.nextOrderIndex(goalId),
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<Phase> updatePhase(String id, Phase Function(Phase current) edit) async {
    final current = await _phases.findById(id);
    if (current == null) {
      throw StateError('Phase 不存在: $id');
    }
    return _phases.update(edit(current));
  }

  /// 手动完成阶段（区别于全部任务完成后的自动完成）。
  Future<Phase> completePhase(String id) async {
    final phase = await updatePhase(
      id,
      (p) => p.status == PhaseStatus.completed ? p : p.copyWith(status: PhaseStatus.completed),
    );
    if (phase.status == PhaseStatus.completed) {
      await _progress.emit(
        ProgressEventType.phaseCompleted,
        goalId: phase.goalId,
        message: '阶段「${phase.title}」标记完成',
      );
    }
    return phase;
  }

  /// 取消阶段：先取消其未完成任务（各自产生事件并重算进度），
  /// 再把阶段置为 cancelled（幂等）。
  Future<Phase> cancelPhase(String id) async {
    final current = await _phases.findById(id);
    if (current == null) {
      throw StateError('Phase 不存在: $id');
    }
    if (current.status == PhaseStatus.cancelled) return current;

    final tasks = await _tasks.findByPhase(id);
    for (final t in tasks.where((t) =>
        t.status != TaskStatus.completed &&
        t.status != TaskStatus.cancelled)) {
      await cancelTask(t.id);
    }
    final phase =
        await _phases.update(current.copyWith(status: PhaseStatus.cancelled));
    await _progress.emit(
      ProgressEventType.phaseCancelled,
      goalId: phase.goalId,
      message: '取消阶段「${phase.title}」',
    );
    return phase;
  }

  // ── Task ───────────────────────────────────────────────

  /// 创建任务。给了 [phaseId] 则自动关联到该阶段所属 Goal；
  /// 也可直接给 [goalId]（不挂阶段）或两者都给。
  Future<Task> createTask({
    required String title,
    String? description,
    String? goalId,
    String? phaseId,
    TaskPriority priority = TaskPriority.medium,
    int? estimatedMinutes,
    DateTime? dueDate,
  }) async {
    String? resolvedGoalId = goalId;
    if (phaseId != null) {
      final phase = await _phases.findById(phaseId);
      if (phase == null) {
        throw StateError('Phase 不存在: $phaseId');
      }
      resolvedGoalId ??= phase.goalId;
    }
    final now = DateTime.now();
    final task = await _tasks.insert(
      Task(
        id: EntityIds.newTaskId(),
        title: title,
        description: description,
        phaseId: phaseId,
        priority: priority,
        estimatedMinutes: estimatedMinutes,
        dueDate: dueDate,
        createdAt: now,
        updatedAt: now,
      ),
    );
    if (resolvedGoalId != null) {
      await _tasks.linkToGoal(task.id, resolvedGoalId, primary: true);
    }
    _notifyChanged(task.id);
    return task;
  }

  Future<Task> updateTask(String id, Task Function(Task current) edit) async {
    final current = await _tasks.findById(id);
    if (current == null) {
      throw StateError('Task 不存在: $id');
    }
    return _tasks.update(edit(current));
  }

  /// 开始任务：todo/postponed → in_progress，所在阶段随之进入进行中。
  Future<Task> startTask(String id) async {
    final task = await _requireTask(id);
    if (task.status == TaskStatus.completed) return task;
    if (task.status == TaskStatus.inProgress) return task;

    final updated = await _tasks.update(
      task.copyWith(status: TaskStatus.inProgress),
    );
    await _progress.emit(
      ProgressEventType.taskStarted,
      goalId: await _progress.primaryGoalIdOf(id),
      taskId: id,
      message: '开始「${task.title}」',
    );
    if (task.phaseId != null) {
      final phase = await _phases.findById(task.phaseId!);
      if (phase != null && phase.status == PhaseStatus.todo) {
        await _phases.update(phase.copyWith(status: PhaseStatus.inProgress));
      }
    }
    return updated;
  }

  /// 完成任务（幂等）：记录 completedAt、完成其 planned 日程、
  /// 产生事件并重算目标进度。
  Future<Task> completeTask(String id) async {
    final task = await _requireTask(id);
    if (task.status == TaskStatus.completed) return task;

    final now = DateTime.now();
    final updated = await _tasks.update(
      task.copyWith(status: TaskStatus.completed, completedAt: now),
    );
    // 任务既已完成，其未开始的日程一并完成。
    final schedules = await _schedules.findByTask(id);
    for (final s in schedules.where((s) => s.status == ScheduleStatus.planned)) {
      await _schedules.update(s.copyWith(status: ScheduleStatus.completed));
    }
    await _progress.emit(
      ProgressEventType.taskCompleted,
      goalId: await _progress.primaryGoalIdOf(id),
      taskId: id,
      message: '完成「${task.title}」',
    );
    await _progress.afterTaskChange(id);
    _notifyChanged(id);
    return updated;
  }

  /// 延期任务（可选给定新时间；给了新时间会顺带重排日程）。
  Future<Task> postponeTask(String id, {DateTime? to}) async {
    final task = await _requireTask(id);
    if (task.status == TaskStatus.completed) {
      throw StateError('任务已完成，不能延期: $id');
    }
    final updated = await _tasks.update(
      task.copyWith(status: TaskStatus.postponed),
    );
    await _progress.emit(
      ProgressEventType.taskPostponed,
      goalId: await _progress.primaryGoalIdOf(id),
      taskId: id,
      message: to == null ? '延期「${task.title}」' : '延期「${task.title}」到 $_short(to)',
    );
    if (to != null) {
      // 推迟到指定时间：取消旧安排并落一个新日程（状态保持 postponed）。
      await _cancelPlannedSchedules(id);
      await _insertSchedule(id, to);
    }
    await _progress.afterTaskChange(id);
    _notifyChanged(id);
    return updated;
  }

  /// 取消任务（进度分母中剔除已取消任务）。
  Future<Task> cancelTask(String id) async {
    final task = await _requireTask(id);
    if (task.status == TaskStatus.cancelled) return task;

    final updated = await _tasks.update(task.copyWith(status: TaskStatus.cancelled));
    final schedules = await _schedules.findByTask(id);
    for (final s in schedules.where((s) => s.status == ScheduleStatus.planned)) {
      await _schedules.update(s.copyWith(status: ScheduleStatus.cancelled));
    }
    await _progress.emit(
      ProgressEventType.taskCancelled,
      goalId: await _progress.primaryGoalIdOf(id),
      taskId: id,
      message: '取消「${task.title}」',
    );
    await _progress.afterTaskChange(id);
    _notifyChanged(id);
    return updated;
  }

  // ── Schedule ───────────────────────────────────────────

  /// 为任务追加一个日程（保留历史日程）。
  Future<Schedule> scheduleTask(
    String taskId, {
    required DateTime startAt,
    int? durationMinutes,
    String? note,
  }) async {
    final task = await _requireTask(taskId);
    final schedule =
        await _insertSchedule(taskId, startAt, durationMinutes, note);
    await _progress.emit(
      ProgressEventType.scheduleChanged,
      goalId: await _progress.primaryGoalIdOf(taskId),
      taskId: taskId,
      message: '安排「${task.title}」$_short(startAt)',
    );
    _notifyChanged(taskId);
    return schedule;
  }

  /// 重新安排：取消旧的 planned 日程，插入新日程；
  /// 延期中的任务自动恢复为 todo（有了新承诺时间）。
  Future<Schedule> rescheduleTask(
    String taskId, {
    required DateTime newStartAt,
    int? durationMinutes,
    String? note,
  }) async {
    final task = await _requireTask(taskId);
    await _cancelPlannedSchedules(taskId);
    final schedule =
        await _insertSchedule(taskId, newStartAt, durationMinutes, note);
    if (task.status == TaskStatus.postponed) {
      await _tasks.update(task.copyWith(status: TaskStatus.todo));
    }
    await _progress.emit(
      ProgressEventType.scheduleChanged,
      goalId: await _progress.primaryGoalIdOf(taskId),
      taskId: taskId,
      message: '「${task.title}」改期到 $_short(newStartAt)',
    );
    _notifyChanged(taskId);
    return schedule;
  }

  Future<void> _cancelPlannedSchedules(String taskId) async {
    final existing = await _schedules.findByTask(taskId);
    for (final s in existing.where((s) => s.status == ScheduleStatus.planned)) {
      await _schedules.update(s.copyWith(status: ScheduleStatus.cancelled));
    }
  }

  Future<Schedule> _insertSchedule(
    String taskId,
    DateTime startAt, [
    int? durationMinutes,
    String? note,
  ]) async {
    final now = DateTime.now();
    return _schedules.insert(
      Schedule(
        id: EntityIds.newScheduleId(),
        taskId: taskId,
        startAt: startAt,
        durationMinutes: durationMinutes,
        note: note,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  // ── 用户汇报 ───────────────────────────────────────────

  /// 用户自由汇报（P6 起由 AI 解析为具体操作；P1 先落事件）。
  Future<ProgressEvent> recordUserReport(
    String goalId,
    String message, {
    String? taskId,
  }) {
    return _progress.emit(
      ProgressEventType.userReport,
      goalId: goalId,
      taskId: taskId,
      message: message,
    );
  }

  // ── helpers ────────────────────────────────────────────

  Future<Task> _requireTask(String id) async {
    final task = await _tasks.findById(id);
    if (task == null) {
      throw StateError('Task 不存在: $id');
    }
    return task;
  }

  static String _short(DateTime t) =>
      '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
