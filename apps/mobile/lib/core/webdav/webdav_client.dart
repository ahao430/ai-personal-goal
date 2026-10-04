import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// WebDAV 客户端（PUT / GET / MKCOL / PROPFIND Depth:0）。
///
/// 坚果云兼容：`https://dav.jianguoyun.com/dav/`，用户名 = 账户邮箱，
/// 密码 = 网页端生成的「应用密码」（不是登录密码）。
class WebdavClient {
  WebdavClient({
    required String baseUrl,
    this.username,
    this.password,
    http.Client? client,
  })  : _baseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), ''),
        _client = client ?? http.Client();

  final String _baseUrl;
  final String? username;
  final String? password;
  final http.Client _client;

  Map<String, String> get _authHeaders {
    if (username == null || username!.isEmpty) return const {};
    final token = base64Encode(utf8.encode('$username:${password ?? ''}'));
    return {'authorization': 'Basic $token'};
  }

  Uri _uri(String remotePath) {
    final clean = remotePath.startsWith('/') ? remotePath : '/$remotePath';
    return Uri.parse('$_baseUrl$clean');
  }

  /// 创建远端目录（幂等：已存在 405 视为成功）。
  Future<void> ensureDir(String remoteDir) async {
    final response = await _client.send(http.Request('MKCOL', _uri(remoteDir))
      ..headers.addAll(_authHeaders));
    final status = response.statusCode;
    await response.stream.drain();
    if (status != 201 && status != 405 && status != 301) {
      throw WebdavException('创建目录失败（$remoteDir）：HTTP $status');
    }
  }

  /// 上传本地文件。
  Future<void> putFile(String remotePath, String localPath) async {
    final bytes = await File(localPath).readAsBytes();
    await putBytes(remotePath, bytes);
  }

  Future<void> putBytes(String remotePath, Uint8List bytes) async {
    final response = await _client.put(_uri(remotePath), body: bytes,
        headers: {..._authHeaders, 'content-type': 'application/octet-stream'});
    if (response.statusCode != 200 &&
        response.statusCode != 201 &&
        response.statusCode != 204) {
      throw WebdavException('上传失败（$remotePath）：HTTP ${response.statusCode}');
    }
  }

  /// 下载到本地文件；远端不存在抛 [WebdavException]（404）。
  Future<void> getFile(String remotePath, String localPath) async {
    final response = await _client.get(_uri(remotePath), headers: _authHeaders);
    if (response.statusCode != 200) {
      throw WebdavException(
        response.statusCode == 404
            ? '云端没有备份（$remotePath）'
            : '下载失败（$remotePath）：HTTP ${response.statusCode}',
      );
    }
    await File(localPath).writeAsBytes(response.bodyBytes);
  }

  /// 连通性测试：建目录 + 上传探针文件。
  /// 返回 null = 成功；否则返回错误信息。
  Future<String?> test(String remoteDir) async {
    try {
      await ensureDir(remoteDir);
      await putBytes(
        '$remoteDir/.ai-goal-probe',
        Uint8List.fromList(utf8.encode(DateTime.now().toIso8601String())),
      );
      return null;
    } on WebdavException catch (e) {
      return e.message;
    } catch (e) {
      return '无法连接：$e';
    }
  }
}

class WebdavException implements Exception {
  WebdavException(this.message);

  final String message;

  @override
  String toString() => message;
}
