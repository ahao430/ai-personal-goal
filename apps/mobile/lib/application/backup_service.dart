import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../core/webdav/webdav_client.dart';
import '../data/database/app_database.dart';
import 'app_services.dart';

/// 备份包清单（zip 内 manifest.json）。
class BackupManifest {
  const BackupManifest({
    required this.app,
    required this.schemaVersion,
    required this.exportedAt,
    this.appVersion,
  });

  final String app;
  final int schemaVersion;
  final DateTime exportedAt;
  final String? appVersion;

  Map<String, Object?> toJson() => {
        'app': app,
        'schemaVersion': schemaVersion,
        'exportedAt': exportedAt.toIso8601String(),
        'appVersion': appVersion,
      };

  static BackupManifest fromJson(Map<String, Object?> json) => BackupManifest(
        app: json['app']! as String,
        schemaVersion: json['schemaVersion']! as int,
        exportedAt: DateTime.parse(json['exportedAt']! as String),
        appVersion: json['appVersion'] as String?,
      );
}

/// WebDAV 配置。
class WebdavConfig {
  const WebdavConfig({
    this.baseUrl = '',
    this.username = '',
    this.password = '',
    this.remoteDir = '/ai-goal-backup',
    this.autoDaily = false,
  });

  /// 坚果云模板（docs：用户名 = 账户邮箱，密码 = 网页端「应用密码」）。
  static const jianguoyun = 'https://dav.jianguoyun.com/dav';

  final String baseUrl;
  final String username;
  final String password;
  final String remoteDir;
  final bool autoDaily;

  bool get isComplete =>
      baseUrl.trim().isNotEmpty && username.trim().isNotEmpty;

  WebdavConfig copyWith({
    String? baseUrl,
    String? username,
    String? password,
    String? remoteDir,
    bool? autoDaily,
  }) =>
      WebdavConfig(
        baseUrl: baseUrl ?? this.baseUrl,
        username: username ?? this.username,
        password: password ?? this.password,
        remoteDir: remoteDir ?? this.remoteDir,
        autoDaily: autoDaily ?? this.autoDaily,
      );

  Map<String, Object?> toJson() => {
        'baseUrl': baseUrl,
        'username': username,
        'password': password,
        'remoteDir': remoteDir,
        'autoDaily': autoDaily,
      };

  static WebdavConfig fromJson(Map<String, Object?> json) => WebdavConfig(
        baseUrl: json['baseUrl'] as String? ?? '',
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        remoteDir: json['remoteDir'] as String? ?? '/ai-goal-backup',
        autoDaily: json['autoDaily'] == true,
      );
}

/// 校验通过的备份（导入用）。
class ValidatedBackup {
  const ValidatedBackup({
    required this.manifest,
    required this.dbPath,
  });

  final BackupManifest manifest;

  /// 已通过「试开 + 迁移」验证的数据库文件（临时目录）。
  final String dbPath;
}

/// 备份与同步（无服务器阶段的备份能力）。
///
/// - 本地：导出 `.aigoal`（zip = manifest + SQLite 快照，VACUUM INTO 一致性
///   快照，无需关库）；导入先试开迁移验证，再替换正式库。
/// - WebDAV：备份包上传 latest + history 双份；恢复下载 latest 走导入。
/// - 自动：每日首次打开 App 备份一次（settings 记日期，静默容错）。
class BackupService {
  BackupService(this._services, {http.Client? client})
      : _client = client ?? http.Client();

  static const String webdavSettingKey = 'backup.webdav';
  static const String lastAutoBackupKey = 'backup.last_auto_date';

  /// history 保留上限（按日滚动，超出不删——坚果云空间用户自管）。
  static const int historyKeepDays = 30;

  final AppServices _services;
  final http.Client _client;

  // ── 本地导出 / 导入 ────────────────────────────────────

  /// 导出备份到临时文件，返回路径（调用方用 share 分享或上传）。
  Future<String> exportToTemp() async {
    final dir = await Directory.systemTemp.createTemp('ai_goal_export');
    final dbSnapshot = p.join(dir.path, 'ai_goal.db');
    // VACUUM INTO：一致性快照，不锁库、不用关连接。
    final escaped = dbSnapshot.replaceAll("'", "''");
    await _services.db.database.execute("VACUUM INTO '$escaped'");

    final manifest = BackupManifest(
      app: 'ai_goal',
      schemaVersion: AppDatabase.schemaVersion,
      exportedAt: DateTime.now(),
    );
    final archive = Archive()
      ..addFile(ArchiveFile.string(
        'manifest.json', jsonEncode(manifest.toJson())))
      ..addFile(ArchiveFile(
          'ai_goal.db', await File(dbSnapshot).length(), await File(dbSnapshot).readAsBytes()));
    final zipBytes = ZipEncoder().encode(archive);

    final outFile = File(p.join(dir.path,
        'ai-goal-backup-${_fileStamp(DateTime.now())}.aigoal'));
    await outFile.writeAsBytes(zipBytes);
    return outFile.path;
  }

  /// 校验备份文件：解包 + manifest 校验 + 试开并迁移到当前 schema。
  /// 通过返回快照路径（临时文件，导入成功前不要删除原库）。
  Future<ValidatedBackup> validate(String backupPath) async {
    final data = await File(backupPath).readAsBytes();
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(data);
    } catch (_) {
      throw const BackupException('不是有效的备份文件（无法解压）');
    }
    final manifestFile = archive.findFile('manifest.json');
    final dbFile = archive.findFile('ai_goal.db');
    if (manifestFile == null || dbFile == null) {
      throw const BackupException('备份包不完整（缺 manifest 或数据库）');
    }

    final BackupManifest manifest;
    try {
      manifest = BackupManifest.fromJson(
          jsonDecode(utf8.decode(manifestFile.content as List<int>))
              as Map<String, Object?>);
    } catch (_) {
      throw const BackupException('备份 manifest 无法解析');
    }
    if (manifest.app != 'ai_goal') {
      throw BackupException('不是本应用的备份（${manifest.app}）');
    }

    // 解出 db → 临时目录试开（旧 schema 会经 onUpgrade 迁移到当前版本）
    final dir = await Directory.systemTemp.createTemp('ai_goal_import');
    final dbPath = p.join(dir.path, 'ai_goal.db');
    await File(dbPath).writeAsBytes(dbFile.content as List<int>);
    try {
      final probe = await AppDatabase.open(path: dbPath);
      await probe.close();
    } catch (e) {
      throw BackupException('备份数据库无法打开：$e');
    }
    return ValidatedBackup(
        manifest: BackupManifest(
          app: manifest.app,
          schemaVersion: AppDatabase.schemaVersion,
          exportedAt: manifest.exportedAt,
          appVersion: manifest.appVersion,
        ),
        dbPath: dbPath);
  }

  /// 应用备份：关闭当前库 → 用校验过的快照替换正式库。
  /// 调用方随后必须重建 AppServices（重启 App）。
  Future<void> apply(ValidatedBackup backup) async {
    await _services.close();
    final target = await AppDatabase.defaultDatabasePath();
    await File(backup.dbPath).copy(target);
  }

  // ── WebDAV ─────────────────────────────────────────────

  Future<WebdavConfig> webdavConfig() async {
    final raw = await _services.settings.read(webdavSettingKey);
    if (raw == null || raw.isEmpty) return const WebdavConfig();
    try {
      return WebdavConfig.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (_) {
      return const WebdavConfig();
    }
  }

  Future<void> saveWebdavConfig(WebdavConfig config) =>
      _services.settings.write(
          webdavSettingKey, jsonEncode(config.toJson()));

  WebdavClient _clientOf(WebdavConfig config) => WebdavClient(
        baseUrl: config.baseUrl,
        username: config.username,
        password: config.password,
        client: _client,
      );

  /// 连接测试（建目录 + 探针上传）。
  Future<String?> testWebdav(WebdavConfig config) async {
    if (!config.isComplete) return '请先填写服务器地址与账号';
    return _clientOf(config).test(config.remoteDir);
  }

  /// 备份到 WebDAV：latest（固定名覆盖）+ history/（按时间戳追加）。
  Future<void> backupToWebdav() async {
    final config = await webdavConfig();
    if (!config.isComplete) {
      throw const BackupException('WebDAV 未配置');
    }
    final client = _clientOf(config);
    final local = await exportToTemp();
    final dir = config.remoteDir;
    await client.ensureDir(dir);
    await client.putFile('$dir/latest.aigoal', local);
    await client.ensureDir('$dir/history');
    await client.putFile(
      '$dir/history/backup-${_fileStamp(DateTime.now())}.aigoal',
      local,
    );
  }

  /// 从 WebDAV 下载 latest 到临时文件并校验，返回可导入的备份。
  Future<ValidatedBackup> fetchLatestBackup() async {
    final config = await webdavConfig();
    if (!config.isComplete) {
      throw const BackupException('WebDAV 未配置');
    }
    final tmp = p.join(Directory.systemTemp.createTempSync('ai_goal_dl').path,
        'latest.aigoal');
    await _clientOf(config).getFile('${config.remoteDir}/latest.aigoal', tmp);
    return validate(tmp);
  }

  // ── 每日自动备份 ───────────────────────────────────────

  /// 每天首次调用时备份一次（main 启动 fire-and-forget，静默容错）。
  Future<void> autoBackupIfDue({DateTime? now}) async {
    try {
      final config = await webdavConfig();
      if (!config.autoDaily || !config.isComplete) return;
      final at = now ?? DateTime.now();
      final today = '${at.year}-${at.month.toString().padLeft(2, '0')}'
          '-${at.day.toString().padLeft(2, '0')}';
      if (await _services.settings.read(lastAutoBackupKey) == today) return;
      await backupToWebdav();
      await _services.settings.write(lastAutoBackupKey, today);
    } catch (_) {
      // 自动备份失败不打扰用户；下次打开再试。
    }
  }

  static String _fileStamp(DateTime t) =>
      '${t.year}${t.month.toString().padLeft(2, '0')}'
      '${t.day.toString().padLeft(2, '0')}-'
      '${t.hour.toString().padLeft(2, '0')}'
      '${t.minute.toString().padLeft(2, '0')}'
      '${t.second.toString().padLeft(2, '0')}';
}

class BackupException implements Exception {
  const BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}
