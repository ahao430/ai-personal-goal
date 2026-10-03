import 'package:sqflite/sqflite.dart';

import '../../domain/settings/app_settings.dart';

class SqliteAppSettingsRepository implements AppSettingsRepository {
  SqliteAppSettingsRepository(this._db);

  final Database _db;

  @override
  Future<String?> read(String key) async {
    final rows = await _db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value']! as String;
  }

  @override
  Future<void> write(String key, String value) async {
    await _db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> delete(String key) async {
    await _db.delete('settings', where: 'key = ?', whereArgs: [key]);
  }
}
