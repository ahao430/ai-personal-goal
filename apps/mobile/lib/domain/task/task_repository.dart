import 'task.dart';

abstract interface class TaskRepository {
  Future<Task> insert(Task task);
  Future<Task> update(Task task);
  Future<Task?> findById(String id);

  Future<List<Task>> findByPhase(String phaseId);

  /// 通过 goal_tasks 关联查询某 Goal 的任务（Task 可属于多个 Goal）。
  Future<List<Task>> findByGoal(String goalId);

  /// dueDate 落在 [from, to)（本地时间）且未取消的任务。
  Future<List<Task>> findDueBetween(DateTime from, DateTime to);

  /// Schedule 落在 [from, to)（本地时间）内的任务（去重）。
  Future<List<Task>> findScheduledBetween(DateTime from, DateTime to);

  Future<void> delete(String id);

  /// Task 与 Goal 的多对多关联（跨目标共享任务）。
  Future<void> linkToGoal(String taskId, String goalId, {bool primary = false});
  Future<void> unlinkFromGoal(String taskId, String goalId);
  Future<List<String>> goalIdsOf(String taskId);
}
