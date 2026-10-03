import 'package:sqflite/sqflite.dart';

import '../../domain/external/data_source.dart';

class SqliteDataSourcePermissionRepository
    implements DataSourcePermissionRepository {
  SqliteDataSourcePermissionRepository(this._db);

  final Database _db;

  @override
  Future<PermissionStatus> statusOf(ExternalSource source) async {
    final rows = await _db.query(
      'data_source_permissions',
      where: 'source = ?',
      whereArgs: [source.name],
      limit: 1,
    );
    if (rows.isEmpty) return PermissionStatus.notRequested;
    return DataSourcePermission.fromMap(rows.first).status;
  }

  @override
  Future<List<DataSourcePermission>> findAll() async {
    final rows = await _db.query('data_source_permissions');
    return rows.map(DataSourcePermission.fromMap).toList();
  }

  @override
  Future<void> setStatus(ExternalSource source, PermissionStatus status) async {
    await _db.insert(
      'data_source_permissions',
      DataSourcePermission(
        source: source,
        status: status,
        updatedAt: DateTime.now(),
      ).toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
