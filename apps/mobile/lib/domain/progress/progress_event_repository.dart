import 'progress_event.dart';

abstract interface class ProgressEventRepository {
  Future<ProgressEvent> insert(ProgressEvent event);

  /// 某 Goal 的最近事件，按时间倒序。
  Future<List<ProgressEvent>> findByGoal(
    String goalId, {
    int limit = 50,
  });

  Future<List<ProgressEvent>> findByTask(
    String taskId, {
    int limit = 50,
  });

  /// 全局最近事件（首页「需要处理」等场景），按时间倒序。
  Future<List<ProgressEvent>> recent({int limit = 50});
}
