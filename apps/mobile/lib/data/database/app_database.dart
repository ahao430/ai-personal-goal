import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'schema_migrations.dart';

/// 应用数据库（SQLite）。
///
/// 事实源（source of truth）。UI 不直接接触本类 —— 通过 Repository 访问。
/// 测试时可注入 [databaseFactory]（sqflite_common_ffi）与内存路径。
class AppDatabase {
  AppDatabase._(this.database);

  /// 当前 schema 版本，与 [schemaMigrations] 的最大版本保持一致。
  static const int schemaVersion = 5;

  static const String databaseFileName = 'ai_goal.db';

  final Database database;

  /// 打开（必要时创建并迁移）数据库。
  ///
  /// [path] 为空时使用应用文档目录下的默认路径；
  /// [factory] 为空时使用平台默认实现（测试注入 sqflite_common_ffi）。
  static Future<AppDatabase> open({
    String? path,
    DatabaseFactory? factory,
  }) async {
    final dbFactory = factory ?? databaseFactory;
    final dbPath = path ?? await defaultDatabasePath();
    final db = await dbFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: _onConfigure,
        onCreate: (db, version) =>
            runSchemaMigrations(db.execute, from: 0, to: version),
        onUpgrade: (db, oldVersion, newVersion) =>
            runSchemaMigrations(db.execute, from: oldVersion, to: newVersion),
      ),
    );
    return AppDatabase._(db);
  }

  /// 外键约束每次连接都要显式开启（SQLite 默认关闭）。
  static Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// 设备上的默认数据库路径。
  static Future<String> defaultDatabasePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, databaseFileName);
  }

  Future<void> close() => database.close();
}
