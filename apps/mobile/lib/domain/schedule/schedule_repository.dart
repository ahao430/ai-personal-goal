import 'schedule.dart';

abstract interface class ScheduleRepository {
  Future<Schedule> insert(Schedule schedule);
  Future<Schedule> update(Schedule schedule);
  Future<Schedule?> findById(String id);

  /// 某 Task 的全部安排（含历史），按开始时间升序。
  Future<List<Schedule>> findByTask(String taskId);

  /// startAt 落在 [from, to)（本地时间）内的安排，按开始时间升序。
  Future<List<Schedule>> findBetween(DateTime from, DateTime to);

  Future<void> delete(String id);
}
