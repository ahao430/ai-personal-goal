import 'package:sqflite/sqflite.dart';

import '../../domain/goal/goal.dart';
import '../../domain/goal/goal_metric.dart';
import '../../domain/goal/goal_repository.dart';
import '../../domain/time_codec.dart';

class SqliteGoalRepository implements GoalRepository {
  SqliteGoalRepository(this._db);

  final Database _db;

  @override
  Future<Goal> insert(Goal goal) async {
    await _db.insert('goals', goal.toMap());
    return goal;
  }

  @override
  Future<Goal> update(Goal goal) async {
    final updated = goal.copyWith(updatedAt: DateTime.now());
    final count = await _db.update(
      'goals',
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [goal.id],
    );
    if (count == 0) {
      throw StateError('Goal 不存在: ${goal.id}');
    }
    return updated;
  }

  @override
  Future<Goal?> findById(String id) async {
    final rows = await _db.query(
      'goals',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Goal.fromMap(rows.first);
  }

  @override
  Future<List<Goal>> findAll({GoalStatus? status}) async {
    final rows = await _db.query(
      'goals',
      where: status == null ? null : 'status = ?',
      whereArgs: status == null ? null : [status.name],
      orderBy: 'updated_at DESC',
    );
    return rows.map(Goal.fromMap).toList();
  }

  @override
  Future<void> delete(String id) async {
    await _db.delete('goals', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<int> countByStatus(GoalStatus status) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM goals WHERE status = ?',
      [status.name],
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }
}

class SqliteGoalMetricRepository implements GoalMetricRepository {
  SqliteGoalMetricRepository(this._db);

  final Database _db;

  @override
  Future<GoalMetric> insert(GoalMetric metric) async {
    await _db.insert('goal_metrics', metric.toMap());
    return metric;
  }

  @override
  Future<GoalMetric> update(GoalMetric metric) async {
    final updated = metric.copyWith(updatedAt: DateTime.now());
    final count = await _db.update(
      'goal_metrics',
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [metric.id],
    );
    if (count == 0) {
      throw StateError('GoalMetric 不存在: ${metric.id}');
    }
    return updated;
  }

  @override
  Future<GoalMetric?> findById(String id) async {
    final rows = await _db.query(
      'goal_metrics',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : GoalMetric.fromMap(rows.first);
  }

  @override
  Future<List<GoalMetric>> findByGoal(String goalId) async {
    final rows = await _db.query(
      'goal_metrics',
      where: 'goal_id = ?',
      whereArgs: [goalId],
      orderBy: 'created_at ASC',
    );
    return rows.map(GoalMetric.fromMap).toList();
  }

  @override
  Future<void> delete(String id) async {
    await _db.delete('goal_metrics', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<MetricValue> addValue(MetricValue value) async {
    await _db.transaction((txn) async {
      await txn.insert('metric_values', value.toMap());
      await txn.update(
        'goal_metrics',
        {
          'current_value': value.value,
          'updated_at': encodeTime(DateTime.now()),
        },
        where: 'id = ?',
        whereArgs: [value.metricId],
      );
    });
    return value;
  }

  @override
  Future<List<MetricValue>> valuesOfMetric(
    String metricId, {
    int limit = 50,
  }) async {
    final rows = await _db.query(
      'metric_values',
      where: 'metric_id = ?',
      whereArgs: [metricId],
      orderBy: 'recorded_at DESC',
      limit: limit,
    );
    return rows.map(MetricValue.fromMap).toList();
  }
}
