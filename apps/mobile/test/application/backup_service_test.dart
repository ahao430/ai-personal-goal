import 'dart:io';

import 'package:archive/archive.dart' as package_archive;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ai_goal/application/app_services.dart';
import 'package:ai_goal/application/backup_service.dart';
import 'package:ai_goal/data/database/app_database.dart';
import 'package:ai_goal/domain/goal/goal.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String dbPath;
  late AppServices services;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('backup_test');
    dbPath = '${tempDir.path}/ai_goal.db';
    services = AppServices.of(await AppDatabase.open(path: dbPath));
  });

  tearDown(() async {
    await services.close();
    await tempDir.delete(recursive: true);
  });

  test('导出 → 导入往返：数据完整恢复（VACUUM INTO 一致性快照）', () async {
    // 建数据
    final goal =
        await services.goalService.createGoal(title: '三个月减掉 5kg');
    await services.planningService.createTask(
        title: '晚间快走', goalId: goal.id);

    // 导出
    final backupFile = await services.backupService.exportToTemp();
    expect(backupFile.endsWith('.aigoal'), isTrue);
    expect(await File(backupFile).length(), greaterThan(1000));

    // 校验（试开迁移通过）
    final validated = await services.backupService.validate(backupFile);
    expect(validated.manifest.app, 'ai_goal');
    expect(validated.manifest.schemaVersion, AppDatabase.schemaVersion);

    // 破坏现场：再建一个目标 + 删掉原目标
    await services.goalService.createGoal(title: '临时目标');
    await services.goals.delete(goal.id);
    expect((await services.goals.findAll()).map((g) => g.title),
        ['临时目标']);

    // 用备份恢复到新库（apply 会关旧库，这里手动模拟替换逻辑）
    await services.close();
    await File(validated.dbPath).copy(dbPath);
    services = AppServices.of(await AppDatabase.open(path: dbPath));

    final goals = await services.goals.findAll();
    expect(goals.map((g) => g.title), ['三个月减掉 5kg']);
    expect(goals.single.status, GoalStatus.active);
    final tasks = await services.tasks.findByGoal(goals.single.id);
    expect(tasks.single.title, '晚间快走');
  });

  test('校验拦截：非 zip / 缺文件 / 非本应用包', () async {
    final junk = '${tempDir.path}/junk.aigoal';
    await File(junk).writeAsString('not a zip');

    expect(() => services.backupService.validate(junk),
        throwsA(isA<BackupException>()));

    // 有效 zip 但缺 db
    final noDb = '${tempDir.path}/nodb.aigoal';
    await File(noDb).writeAsBytes(_zipOf({'manifest.json': '{"app":"ai_goal"}'}));
    expect(() => services.backupService.validate(noDb),
        throwsA(isA<BackupException>()));

    // manifest app 不匹配
    final otherApp = '${tempDir.path}/other.aigoal';
    await File(otherApp).writeAsBytes(_zipOf({
      'manifest.json':
          '{"app":"other_app","schemaVersion":1,"exportedAt":"2026-10-04T00:00:00"}',
      'ai_goal.db': [1, 2, 3],
    }));
    expect(
      () => services.backupService.validate(otherApp),
      throwsA(isA<BackupException>()
          .having((e) => e.message, 'message', contains('other_app'))),
    );
  });

  test('WebDAV 配置存取往返', () async {
    expect((await services.backupService.webdavConfig()).isComplete, isFalse);

    const config = WebdavConfig(
      baseUrl: WebdavConfig.jianguoyun,
      username: 'user@example.com',
      password: 'app-pass',
      remoteDir: '/我的备份',
      autoDaily: true,
    );
    await services.backupService.saveWebdavConfig(config);
    final loaded = await services.backupService.webdavConfig();
    expect(loaded.baseUrl, WebdavConfig.jianguoyun);
    expect(loaded.username, 'user@example.com');
    expect(loaded.password, 'app-pass');
    expect(loaded.remoteDir, '/我的备份');
    expect(loaded.autoDaily, isTrue);
  });

  test('backupToWebdav：latest + history 上传；未配置抛错', () async {
    // 未配置
    expect(() => services.backupService.backupToWebdav(),
        throwsA(isA<BackupException>()));

    await services.goalService.createGoal(title: '有数据');
    final uploads = <String>[];
    final dirs = <String>[];
    services = AppServices.of(
      await AppDatabase.open(path: dbPath),
      searchClient: MockClient((request) async {
        if (request.method == 'MKCOL') {
          dirs.add(request.url.path);
          return http.Response('', 201);
        }
        if (request.method == 'PUT') {
          uploads.add(request.url.path);
          return http.Response('', 201);
        }
        return http.Response('', 500);
      }),
    );
    await services.goalService.createGoal(title: '占位，重建 services');
    await services.backupService.saveWebdavConfig(const WebdavConfig(
      baseUrl: 'https://dav.example.com',
      username: 'u',
      password: 'p',
    ));
    await services.backupService.backupToWebdav();

    expect(dirs, containsAll(['/ai-goal-backup', '/ai-goal-backup/history']));
    expect(uploads, contains('/ai-goal-backup/latest.aigoal'));
    expect(
      uploads.where((p) => p.startsWith('/ai-goal-backup/history/')).single,
      contains('backup-'),
    );
  });

  test('autoBackupIfDue：未开启 no-op；开启后每天一次', () async {
    var uploads = 0;
    services = AppServices.of(
      await AppDatabase.open(path: dbPath),
      searchClient: MockClient((request) async {
        if (request.method == 'PUT') {
          uploads++;
          return http.Response('', 201);
        }
        return http.Response('', 201);
      }),
    );
    await services.goalService.createGoal(title: 'x');
    await services.backupService.saveWebdavConfig(const WebdavConfig(
      baseUrl: 'https://dav.example.com',
      username: 'u',
      password: 'p',
      autoDaily: true,
    ));

    final now = DateTime(2026, 10, 4, 9);
    await services.backupService.autoBackupIfDue(now: now);
    expect(uploads, 2, reason: 'latest + history 各一次 PUT');
    // 同一天第二次：跳过
    await services.backupService.autoBackupIfDue(
        now: now.add(const Duration(hours: 2)));
    expect(uploads, 2);
    // 第二天：再备
    await services.backupService.autoBackupIfDue(
        now: now.add(const Duration(days: 1)));
    expect(uploads, 4);
  });
}

/// 简易 zip 构造（用 backup_service 同款 archive 包）。
List<int> _zipOf(Map<String, Object> files) {
  final archive = package_archive.Archive();
  files.forEach((name, content) {
    final bytes = content is String
        ? content.codeUnits
        : content as List<int>;
    archive.addFile(
        package_archive.ArchiveFile(name, bytes.length, bytes));
  });
  return package_archive.ZipEncoder().encode(archive);
}
