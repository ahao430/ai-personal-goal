import 'package:ai_goal/data/database/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 打开一个全新的内存 SQLite（sqflite_common_ffi，桌面测试环境）。
/// 每个测试独立建库，隔离互不影响。
Future<AppDatabase> openTestDatabase() async {
  sqfliteFfiInit();
  return AppDatabase.open(
    path: inMemoryDatabasePath,
    factory: databaseFactoryFfi,
  );
}
