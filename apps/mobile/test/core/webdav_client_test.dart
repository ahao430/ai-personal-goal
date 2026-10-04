import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ai_goal/core/webdav/webdav_client.dart';

void main() {
  group('WebdavClient', () {
    test('Basic Auth 头 + PUT / GET / MKCOL 请求形态', () async {
      final requests = <http.Request>[];
      final bodies = <String, Uint8List>{};
      final client = MockClient((request) async {
        requests.add(request);
        if (request.method == 'PUT') {
          bodies[request.url.path] = request.bodyBytes;
          return http.Response('', 201);
        }
        if (request.method == 'MKCOL') return http.Response('', 201);
        if (request.method == 'GET') {
          final bytes = bodies[request.url.path];
          if (bytes == null) return http.Response('', 404);
          return http.Response.bytes(bytes, 200);
        }
        return http.Response('', 500);
      });
      final dav = WebdavClient(
        baseUrl: 'https://dav.jianguoyun.com/dav/',
        username: 'user@example.com',
        password: 'app-password',
        client: client,
      );

      final tmp = Directory.systemTemp.createTempSync('webdav_test');
      final local = '${tmp.path}/backup.aigoal';
      File(local).writeAsBytesSync(utf8.encode('backup-bytes'));

      await dav.putFile('/ai-goal-backup/latest.aigoal', local);
      await dav.ensureDir('/ai-goal-backup/history');
      await dav.getFile('/ai-goal-backup/latest.aigoal', '${tmp.path}/dl.aigoal');

      // Basic Auth：base64(user:pass)
      final expected = 'Basic '
          '${base64Encode(utf8.encode('user@example.com:app-password'))}';
      expect(requests.first.headers['authorization'], expected);
      expect(requests.first.url.toString(),
          'https://dav.jianguoyun.com/dav/ai-goal-backup/latest.aigoal');

      // 下载内容与上传一致
      expect(File('${tmp.path}/dl.aigoal').readAsStringSync(), 'backup-bytes');
    });

    test('ensureDir 幂等：405（已存在）不抛错，500 抛错', () async {
      final client = MockClient((request) async =>
          request.url.path.contains('exists') ? http.Response('', 405) : http.Response('', 500));
      final dav = WebdavClient(
          baseUrl: 'https://dav.example.com', client: client);
      await dav.ensureDir('/exists');
      expect(() => dav.ensureDir('/broken'), throwsA(isA<WebdavException>()));
    });

    test('getFile 404 → 明确「云端没有备份」提示', () async {
      final dav = WebdavClient(
        baseUrl: 'https://dav.example.com',
        client: MockClient((_) async => http.Response('', 404)),
      );
      final tmp = Directory.systemTemp.createTempSync('webdav_404');
      expect(
        () => dav.getFile('/x/latest.aigoal', '${tmp.path}/x'),
        throwsA(isA<WebdavException>()
            .having((e) => e.message, 'message', contains('云端没有备份'))),
      );
    });

    test('test：成功返回 null；失败返回错误信息', () async {
      final ok = WebdavClient(
        baseUrl: 'https://dav.example.com',
        client: MockClient((request) async {
          if (request.method == 'MKCOL') return http.Response('', 201);
          return http.Response('', 201);
        }),
      );
      expect(await ok.test('/dir'), isNull);

      final bad = WebdavClient(
        baseUrl: 'https://dav.example.com',
        client: MockClient((_) async => http.Response('unauthorized', 401)),
      );
      expect(await bad.test('/dir'), contains('401'));
    });
  });
}
