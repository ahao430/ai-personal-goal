import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/ai/ai_provider.dart';

/// 从供应商 API 拉取的单个模型。
class FetchedModel {
  const FetchedModel({required this.modelId, this.displayName});

  final String modelId;
  final String? displayName;
}

/// 获取模型列表失败（网络 / 鉴权 / 格式）。
class ModelListException implements Exception {
  ModelListException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 模型列表客户端：一键获取某供应商的可用模型。
///
/// - OpenAI 兼容：`GET {baseURL}/models`，`Authorization: Bearer <key>`
/// - Anthropic：`GET {baseURL}/v1/models`，`x-api-key` + `anthropic-version`
///
/// 通过注入 [http.Client] 便于测试。
class ModelListClient {
  ModelListClient({http.Client? client, this.timeout = const Duration(seconds: 20)})
      : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  Future<List<FetchedModel>> fetchModels(AiProvider provider) async {
    final base = provider.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = provider.apiStyle == ApiStyle.anthropic
        ? Uri.parse('$base/v1/models')
        : Uri.parse('$base/models');

    final headers = <String, String>{
      if (provider.apiKey?.isNotEmpty == true)
        if (provider.apiStyle == ApiStyle.anthropic) ...{
          'x-api-key': provider.apiKey!,
          'anthropic-version': '2023-06-01',
        } else
          'Authorization': 'Bearer ${provider.apiKey!}',
    };

    final http.Response response;
    try {
      response = await _client.get(uri, headers: headers).timeout(timeout);
    } catch (e) {
      throw ModelListException('网络请求失败：$e');
    }

    if (response.statusCode != 200) {
      throw ModelListException(
        '获取模型列表失败（HTTP ${response.statusCode}）：'
        '${_snippet(response.body)}',
      );
    }
    return _parse(response.body);
  }

  /// 兼容两种返回形态：
  /// - OpenAI 风格 `{"data": [{"id": "...", ...}]}`
  /// - Anthropic 风格 `{"data": [{"id": "...", "display_name": "..."}]}`
  /// - 少数服务直接返回数组 `[{"id": "..."}]`
  static List<FetchedModel> _parse(String body) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw ModelListException('返回内容不是合法 JSON：${_snippet(body)}');
    }

    final List<dynamic> items;
    if (decoded is List) {
      items = decoded;
    } else if (decoded is Map && decoded['data'] is List) {
      items = decoded['data']! as List<dynamic>;
    } else {
      throw ModelListException('返回格式无法识别：${_snippet(body)}');
    }

    final models = <FetchedModel>[];
    for (final item in items) {
      if (item is! Map) continue;
      final id = item['id'];
      if (id is! String || id.trim().isEmpty) continue;
      models.add(
        FetchedModel(
          modelId: id.trim(),
          displayName: _readDisplayName(item),
        ),
      );
    }
    if (models.isEmpty) {
      throw ModelListException('模型列表为空，请确认服务与 Key 是否可用');
    }
    return models;
  }

  static String? _readDisplayName(Map<dynamic, dynamic> item) {
    final name = item['display_name'] ?? item['displayName'] ?? item['name'];
    return name is String && name.trim().isNotEmpty ? name.trim() : null;
  }

  static String _snippet(String s) {
    final t = s.trim();
    return t.length <= 200 ? t : '${t.substring(0, 200)}…';
  }
}
