import 'package:sqflite/sqflite.dart';

import '../../domain/schedule/schedule.dart';
import '../../domain/schedule/schedule_repository.dart';
import '../../domain/time_codec.dart';

class SqliteScheduleRepository implements ScheduleRepository {
  SqliteScheduleRepository(this._db);

  final Database _db;

  @override
  Future<Schedule> insert(Schedule schedule) async {
    await _db.insert('schedules', schedule.toMap());
    return schedule;
  }

  @override
  Future<Schedule> update(Schedule schedule) async {
    final updated = schedule.copyWith(updatedAt: DateTime.now());
    final count = await _db.update(
      'schedules',
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [schedule.id],
    );
    if (count == 0) {
      throw StateError('Schedule 不存在: ${schedule.id}');
    }
    return updated;
  }

  @override
  Future<Schedule?> findById(String id) async {
    final rows = await _db.query(
      'schedules',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Schedule.fromMap(rows.first);
  }

  @override
  Future<List<Schedule>> findByTask(String taskId) async {
    final rows = await _db.query(
      'schedules',
      where: 'task_id = ?',
      whereArgs: [taskId],
      orderBy: 'start_at ASC',
    );
    return rows.map(Schedule.fromMap).toList();
  }

  @override
  Future<List<Schedule>> findBetween(DateTime from, DateTime to) async {
    final rows = await _db.query(
      'schedules',
      where: 'start_at >= ? AND start_at < ?',
      whereArgs: [encodeTime(from), encodeTime(to)],
      orderBy: 'start_at ASC',
    );
    return rows.map(Schedule.fromMap).toList();
  }

  @override
  Future<void> delete(String id) async {
    await _db.delete('schedules', where: 'id = ?', whereArgs: [id]);
  }
}
