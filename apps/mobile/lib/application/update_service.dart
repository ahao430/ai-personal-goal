import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../domain/settings/app_settings.dart';

/// 检查更新的结果。
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.hasUpdate,
    required this.currentVersion,
    this.latestVersion,
    this.releaseUrl,
    this.notes,
    this.error,
  });

  final bool hasUpdate;
  final String currentVersion;
  final String? latestVersion;

  /// Release 页面（浏览器打开下载 APK）。
  final String? releaseUrl;
  final String? notes;

  /// 检查失败原因（无更新时为 null）。
  final String? error;
}

/// GitHub Releases 检查更新（private 仓库需配置只读 Token）。
///
/// 版本事实源：mobile 的 Release tag（`mobile-v1.0.3`）；
/// 与本地 package_info 的 version 比较。
class UpdateService {
  UpdateService(this._settings, {http.Client? client})
      : _client = client ?? http.Client();

  static const String tokenSettingKey = 'update.github_token';
  static const String repoSlug = 'ahao430/ai-personal-goal';

  final AppSettingsRepository _settings;
  final http.Client _client;

  Future<String?> githubToken() => _settings.read(tokenSettingKey);

  Future<void> setGithubToken(String? token) async {
    final trimmed = token?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await _settings.delete(tokenSettingKey);
    } else {
      await _settings.write(tokenSettingKey, trimmed);
    }
  }

  /// 当前 App 版本（编译期来自 pubspec）。
  ///
  /// PackageInfo 在无平台通道的环境（单测）不可用时回退 0.0.0。
  Future<String> currentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      return '0.0.0';
    }
  }

  Future<UpdateCheckResult> checkForUpdate() async {
    final current = await currentVersion();
    final token = await githubToken();

    http.Response response;
    try {
      response = await _client.get(
        Uri.parse('https://api.github.com/repos/$repoSlug/releases/latest'),
        headers: {
          'accept': 'application/vnd.github+json',
          if (token != null && token.isNotEmpty)
            'authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 15));
    } catch (e) {
      return UpdateCheckResult(
        hasUpdate: false,
        currentVersion: current,
        error: '网络请求失败：$e',
      );
    }

    if (response.statusCode == 404 || response.statusCode == 403) {
      return UpdateCheckResult(
        hasUpdate: false,
        currentVersion: current,
        error: token == null || token.isEmpty
            ? '私有仓库需要配置 GitHub Token 才能查询 Release'
            : 'Token 无效或无权限（${response.statusCode}）',
      );
    }
    if (response.statusCode != 200) {
      return UpdateCheckResult(
        hasUpdate: false,
        currentVersion: current,
        error: 'GitHub 返回 ${response.statusCode}',
      );
    }

    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    final tag = body['tag_name'] as String? ?? '';
    final latest = parseMobileTag(tag);
    if (latest == null) {
      return UpdateCheckResult(
        hasUpdate: false,
        currentVersion: current,
        error: '最新 Release 的 tag 不是 mobile 版本（$tag）',
      );
    }

    return UpdateCheckResult(
      hasUpdate: isNewer(latest, current),
      currentVersion: current,
      latestVersion: latest,
      releaseUrl: body['html_url'] as String?,
      notes: body['body'] as String?,
    );
  }

  /// `mobile-v1.0.3` → `1.0.3`；不匹配返回 null。
  static String? parseMobileTag(String tag) {
    final match = RegExp(r'^mobile-v(\d+\.\d+\.\d+)$').firstMatch(tag.trim());
    return match?.group(1);
  }

  /// 语义化比较：candidate 严格大于 current 才算有更新。
  static bool isNewer(String candidate, String current) {
    final c = _triple(candidate);
    final b = _triple(current);
    if (c == null || b == null) return false;
    for (var i = 0; i < 3; i++) {
      if (c[i] != b[i]) return c[i] > b[i];
    }
    return false;
  }

  static List<int>? _triple(String version) {
    final parts = version.split('.');
    if (parts.length != 3) return null;
    final nums = <int>[];
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null) return null;
      nums.add(n);
    }
    return nums;
  }
}
