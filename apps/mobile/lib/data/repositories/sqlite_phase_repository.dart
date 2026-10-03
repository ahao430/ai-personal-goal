import 'package:sqflite/sqflite.dart';

import '../../domain/phase/phase.dart';
import '../../domain/phase/phase_repository.dart';

class SqlitePhaseRepository implements PhaseRepository {
  SqlitePhaseRepository(this._db);

  final Database _db;

  @override
  Future<Phase> insert(Phase phase) async {
    await _db.insert('phases', phase.toMap());
    return phase;
  }

  @override
  Future<Phase> update(Phase phase) async {
    final updated = phase.copyWith(updatedAt: DateTime.now());
    final count = await _db.update(
      'phases',
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [phase.id],
    );
    if (count == 0) {
      throw StateError('Phase 不存在: ${phase.id}');
    }
    return updated;
  }

  @override
  Future<Phase?> findById(String id) async {
    final rows = await _db.query(
      'phases',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Phase.fromMap(rows.first);
  }

  @override
  Future<List<Phase>> findByGoal(String goalId) async {
    final rows = await _db.query(
      'phases',
      where: 'goal_id = ?',
      whereArgs: [goalId],
      orderBy: 'order_index ASC',
    );
    return rows.map(Phase.fromMap).toList();
  }

  @override
  Future<int> nextOrderIndex(String goalId) async {
    final rows = await _db.rawQuery(
      'SELECT COALESCE(MAX(order_index) + 1, 0) AS next '
      'FROM phases WHERE goal_id = ?',
      [goalId],
    );
    return rows.first['next']! as int;
  }

  @override
  Future<void> delete(String id) async {
    await _db.delete('phases', where: 'id = ?', whereArgs: [id]);
  }
}
