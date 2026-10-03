import 'package:sqflite/sqflite.dart';

import '../../domain/task/task.dart';
import '../../domain/task/task_repository.dart';
import '../../domain/time_codec.dart';

class SqliteTaskRepository implements TaskRepository {
  SqliteTaskRepository(this._db);

  final Database _db;

  @override
  Future<Task> insert(Task task) async {
    await _db.insert('tasks', task.toMap());
    return task;
  }

  @override
  Future<Task> update(Task task) async {
    final updated = task.copyWith(updatedAt: DateTime.now());
    final count = await _db.update(
      'tasks',
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [task.id],
    );
    if (count == 0) {
      throw StateError('Task 不存在: ${task.id}');
    }
    return updated;
  }

  @override
  Future<Task?> findById(String id) async {
    final rows = await _db.query(
      'tasks',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Task.fromMap(rows.first);
  }

  @override
  Future<List<Task>> findByPhase(String phaseId) async {
    final rows = await _db.query(
      'tasks',
      where: 'phase_id = ?',
      whereArgs: [phaseId],
      orderBy: 'created_at ASC',
    );
    return rows.map(Task.fromMap).toList();
  }

  @override
  Future<List<Task>> findByGoal(String goalId) async {
    final rows = await _db.rawQuery(
      'SELECT t.* FROM tasks t '
      'INNER JOIN goal_tasks gt ON gt.task_id = t.id '
      'WHERE gt.goal_id = ? '
      'ORDER BY t.created_at ASC',
      [goalId],
    );
    return rows.map(Task.fromMap).toList();
  }

  @override
  Future<List<Task>> findDueBetween(DateTime from, DateTime to) async {
    final rows = await _db.query(
      'tasks',
      where: 'due_date >= ? AND due_date < ? AND status != ?',
      whereArgs: [
        encodeTime(from),
        encodeTime(to),
        TaskStatus.cancelled.columnName,
      ],
      orderBy: 'due_date ASC',
    );
    return rows.map(Task.fromMap).toList();
  }

  @override
  Future<List<Task>> findScheduledBetween(DateTime from, DateTime to) async {
    final rows = await _db.rawQuery(
      'SELECT DISTINCT t.* FROM tasks t '
      'INNER JOIN schedules s ON s.task_id = t.id '
      'WHERE s.start_at >= ? AND s.start_at < ? AND s.status = ? '
      'ORDER BY s.start_at ASC',
      [encodeTime(from), encodeTime(to), 'planned'],
    );
    return rows.map(Task.fromMap).toList();
  }

  @override
  Future<void> delete(String id) async {
    await _db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> linkToGoal(
    String taskId,
    String goalId, {
    bool primary = false,
  }) async {
    await _db.insert(
      'goal_tasks',
      {
        'goal_id': goalId,
        'task_id': taskId,
        'is_primary': primary ? 1 : 0,
        'created_at': encodeTime(DateTime.now()),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<void> unlinkFromGoal(String taskId, String goalId) async {
    await _db.delete(
      'goal_tasks',
      where: 'goal_id = ? AND task_id = ?',
      whereArgs: [goalId, taskId],
    );
  }

  @override
  Future<List<String>> goalIdsOf(String taskId) async {
    final rows = await _db.query(
      'goal_tasks',
      columns: ['goal_id'],
      where: 'task_id = ?',
      whereArgs: [taskId],
    );
    return rows.map((r) => r['goal_id']! as String).toList();
  }
}
