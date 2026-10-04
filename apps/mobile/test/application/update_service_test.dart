import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ai_goal/application/update_service.dart';
import 'package:ai_goal/domain/settings/app_settings.dart';

const kUtf8Json = {'content-type': 'application/json; charset=utf-8'};

/// 轻量 settings 内存替身。
class FakeSettings implements AppSettingsRepository {
  FakeSettings({Map<String, String>? initial})
      : stored = initial ?? {};

  final Map<String, String> stored;

  @override
  Future<String?> read(String key) async => stored[key];

  @override
  Future<void> write(String key, String value) async => stored[key] = value;

  @override
  Future<void> delete(String key) async => stored.remove(key);
}

void main() {
  group('纯函数：tag 解析与版本比较', () {
    test('parseMobileTag', () {
      expect(UpdateService.parseMobileTag('mobile-v1.0.3'), '1.0.3');
      expect(UpdateService.parseMobileTag('mobile-v0.10.12'), '0.10.12');
      expect(UpdateService.parseMobileTag('api-v1.0.0'), isNull);
      expect(UpdateService.parseMobileTag('v1.0.0'), isNull);
      expect(UpdateService.parseMobileTag('mobile-v1.0'), isNull);
    });

    test('isNewer：语义化比较', () {
      expect(UpdateService.isNewer('1.0.4', '1.0.3'), isTrue);
      expect(UpdateService.isNewer('1.1.0', '1.0.99'), isTrue);
      expect(UpdateService.isNewer('2.0.0', '1.9.9'), isTrue);
      expect(UpdateService.isNewer('1.0.3', '1.0.3'), isFalse);
      expect(UpdateService.isNewer('1.0.2', '1.0.3'), isFalse);
      expect(UpdateService.isNewer('bad', '1.0.3'), isFalse);
    });
  });

  group('checkForUpdate', () {
    test('未配置 token 收到 404 → 引导配置的错误信息', () async {
      final service = UpdateService(
        FakeSettings(),
        client: MockClient(
          (_) async => http.Response('{"message":"Not Found"}', 404),
        ),
      );
      final result = await service.checkForUpdate();
      expect(result.hasUpdate, isFalse);
      expect(result.error, contains('GitHub Token'));
    });

    test('配置 token → 带 Authorization 头；Release 字段透传', () async {
      var carriedAuth = false;
      final service = UpdateService(
        FakeSettings(initial: {'update.github_token': 'ghp_test'}),
        client: MockClient((request) async {
          carriedAuth =
              request.headers['authorization'] == 'Bearer ghp_test';
          return http.Response(
            jsonEncode({
              'tag_name': 'mobile-v1.9.9',
              'html_url':
                  'https://github.com/ahao430/ai-personal-goal/releases/latest',
              'body': '修复若干问题',
            }),
            200, headers: kUtf8Json,
          );
        }),
      );

      // currentVersion 在测试环境回退 '0.0.0'（PackageInfo 平台通道不可用），
      // 因此 1.9.9 一定判定为有更新。
      final result = await service.checkForUpdate();
      expect(carriedAuth, isTrue);
      expect(result.latestVersion, '1.9.9');
      expect(result.releaseUrl, contains('releases/latest'));
      expect(result.notes, '修复若干问题');
      expect(result.hasUpdate, isTrue);
    });

    test('latest tag 不是 mobile 版本 → 明确错误', () async {
      final service = UpdateService(
        FakeSettings(initial: {'update.github_token': 't'}),
        client: MockClient((_) async => http.Response(
              jsonEncode({'tag_name': 'api-v0.1.0', 'body': ''}),
              200, headers: kUtf8Json,
            )),
      );
      final result = await service.checkForUpdate();
      expect(result.error, contains('api-v0.1.0'));
    });

    test('网络异常 → error 透传', () async {
      final service = UpdateService(
        FakeSettings(initial: {'update.github_token': 't'}),
        client: MockClient(
          (_) async => throw http.ClientException('断网'),
        ),
      );
      final result = await service.checkForUpdate();
      expect(result.error, contains('网络请求失败'));
    });

    test('token 存取与清除', () async {
      final settings = FakeSettings();
      final service = UpdateService(settings, client: MockClient((_) async {
        throw StateError('不应发起请求');
      }));
      expect(await service.githubToken(), isNull);
      await service.setGithubToken(' ghp_x ');
      expect(await service.githubToken(), 'ghp_x');
      await service.setGithubToken('  ');
      expect(await service.githubToken(), isNull);
    });
  });
}
