import 'package:sqflite/sqflite.dart';

import '../../domain/progress/progress_event.dart';
import '../../domain/progress/progress_event_repository.dart';

class SqliteProgressEventRepository implements ProgressEventRepository {
  SqliteProgressEventRepository(this._db);

  final Database _db;

  @override
  Future<ProgressEvent> insert(ProgressEvent event) async {
    await _db.insert('progress_events', event.toMap());
    return event;
  }

  @override
  Future<List<ProgressEvent>> findByGoal(
    String goalId, {
    int limit = 50,
  }) async {
    final rows = await _db.query(
      'progress_events',
      where: 'goal_id = ?',
      whereArgs: [goalId],
      orderBy: 'time DESC',
      limit: limit,
    );
    return rows.map(ProgressEvent.fromMap).toList();
  }

  @override
  Future<List<ProgressEvent>> findByTask(
    String taskId, {
    int limit = 50,
  }) async {
    final rows = await _db.query(
      'progress_events',
      where: 'task_id = ?',
      whereArgs: [taskId],
      orderBy: 'time DESC',
      limit: limit,
    );
    return rows.map(ProgressEvent.fromMap).toList();
  }

  @override
  Future<List<ProgressEvent>> recent({int limit = 50}) async {
    final rows = await _db.query(
      'progress_events',
      orderBy: 'time DESC',
      limit: limit,
    );
    return rows.map(ProgressEvent.fromMap).toList();
  }
}
