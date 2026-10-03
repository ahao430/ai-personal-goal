import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/ai/ai_provider.dart';

/// 对话消息（协议无关）。role：system / user / assistant / tool。
class ChatMessage {
  const ChatMessage.system(String text)
      : role = 'system',
        content = text,
        toolCallId = null,
        toolCalls = null;

  const ChatMessage.user(String text)
      : role = 'user',
        content = text,
        toolCallId = null,
        toolCalls = null;

  const ChatMessage.assistant({String? text, this.toolCalls})
      : role = 'assistant',
        content = text,
        toolCallId = null;

  const ChatMessage.tool({required this.toolCallId, required String result})
      : role = 'tool',
        content = result,
        toolCalls = null;

  final String role;
  final String? content;

  /// assistant 消息请求的工具调用。
  final List<ToolCall>? toolCalls;

  /// tool 消息对应的调用 ID。
  final String? toolCallId;
}

/// 模型请求的一次工具调用。
class ToolCall {
  const ToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;
  final Map<String, dynamic> arguments;
}

/// 暴露给模型的工具定义。
class ToolSpec {
  const ToolSpec({
    required this.name,
    required this.description,
    required this.parametersSchema,
  });

  final String name;
  final String description;

  /// JSON Schema（object 类型）。
  final Map<String, Object?> parametersSchema;
}

/// 模型的一轮回复：文本与（可选的）工具调用。
class AssistantReply {
  const AssistantReply({this.text, this.toolCalls = const []});

  final String? text;
  final List<ToolCall> toolCalls;

  bool get wantsTools => toolCalls.isNotEmpty;
}

/// 对话调用失败（网络 / 鉴权 / 协议）。
class ChatException implements Exception {
  ChatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 协议无关的对话客户端：OpenAI 兼容 / Anthropic 双协议，支持 Tool Calling。
///
/// 通过注入 [http.Client] 便于测试。
class ChatClient {
  ChatClient({
    http.Client? client,
    this.timeout = const Duration(seconds: 60),
    this.maxTokens = 4096,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;
  final int maxTokens;

  Future<AssistantReply> complete({
    required AiProvider provider,
    required String model,
    required List<ChatMessage> messages,
    List<ToolSpec> tools = const [],
  }) async {
    final base = provider.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final isAnthropic = provider.apiStyle == ApiStyle.anthropic;
    final uri = Uri.parse(
      isAnthropic ? '$base/v1/messages' : '$base/chat/completions',
    );

    final body = isAnthropic
        ? _buildAnthropicBody(model, messages, tools)
        : _buildOpenAiBody(model, messages, tools);

    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (provider.apiKey?.isNotEmpty == true)
        if (isAnthropic) ...{
          'x-api-key': provider.apiKey!,
          'anthropic-version': '2023-06-01',
        } else
          'Authorization': 'Bearer ${provider.apiKey!}',
    };

    http.Response response;
    try {
      response = await _client
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(timeout);
    } catch (e) {
      throw ChatException('网络请求失败：$e');
    }
    if (response.statusCode != 200) {
      throw ChatException(
        'AI 调用失败（HTTP ${response.statusCode}）：${_snippet(response.body)}',
      );
    }
    return isAnthropic
        ? _parseAnthropic(response.body)
        : _parseOpenAi(response.body);
  }

  // ── OpenAI 兼容 ───────────────────────────────────────

  Map<String, Object?> _buildOpenAiBody(
    String model,
    List<ChatMessage> messages,
    List<ToolSpec> tools,
  ) =>
      {
        'model': model,
        'messages': [for (final m in messages) _openAiMessage(m)],
        if (tools.isNotEmpty)
          'tools': [
            for (final t in tools)
              {
                'type': 'function',
                'function': {
                  'name': t.name,
                  'description': t.description,
                  'parameters': t.parametersSchema,
                },
              },
          ],
        'tool_choice': 'auto',
      };

  Map<String, Object?> _openAiMessage(ChatMessage m) {
    switch (m.role) {
      case 'system':
        return {'role': 'system', 'content': m.content};
      case 'user':
        return {'role': 'user', 'content': m.content};
      case 'tool':
        return {
          'role': 'tool',
          'tool_call_id': m.toolCallId,
          'content': m.content ?? '',
        };
      case 'assistant':
      default:
        final calls = m.toolCalls;
        if (calls != null && calls.isNotEmpty) {
          return {
            'role': 'assistant',
            'content': m.content ?? '',
            'tool_calls': [
              for (final c in calls)
                {
                  'id': c.id,
                  'type': 'function',
                  'function': {
                    'name': c.name,
                    'arguments': jsonEncode(c.arguments),
                  },
                },
            ],
          };
        }
        return {'role': 'assistant', 'content': m.content ?? ''};
    }
  }

  AssistantReply _parseOpenAi(String body) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw ChatException('返回内容不是合法 JSON：${_snippet(body)}');
    }
    final choices = decoded is Map ? decoded['choices'] : null;
    if (choices is! List || choices.isEmpty) {
      throw ChatException('AI 返回缺少 choices：${_snippet(body)}');
    }
    final message = choices.first['message'];
    if (message is! Map) {
      throw ChatException('AI 返回缺少 message');
    }
    final text = message['content'] as String?;
    final rawCalls = message['tool_calls'];
    final toolCalls = <ToolCall>[];
    if (rawCalls is List) {
      for (final raw in rawCalls) {
        if (raw is! Map) continue;
        final function = raw['function'];
        if (function is! Map) continue;
        final name = function['name'];
        if (name is! String) continue;
        Map<String, dynamic> args = {};
        final rawArgs = function['arguments'];
        if (rawArgs is String && rawArgs.trim().isNotEmpty) {
          try {
            args = jsonDecode(rawArgs) as Map<String, dynamic>;
          } catch (_) {
            args = {};
          }
        } else if (rawArgs is Map) {
          args = Map<String, dynamic>.from(rawArgs);
        }
        toolCalls.add(
          ToolCall(id: (raw['id'] ?? 'call_${toolCalls.length}') as String,
              name: name, arguments: args),
        );
      }
    }
    return AssistantReply(text: text, toolCalls: toolCalls);
  }

  // ── Anthropic ─────────────────────────────────────────

  Map<String, Object?> _buildAnthropicBody(
    String model,
    List<ChatMessage> messages,
    List<ToolSpec> tools,
  ) {
    final system = StringBuffer();
    final converted = <Map<String, Object?>>[];
    // Anthropic 要求 tool_result 作为 user 消息内容块，
    // 连续的 tool 消息需合并进同一条 user 消息。
    var pendingToolResults = <Map<String, Object?>>[];

    void flushToolResults() {
      if (pendingToolResults.isEmpty) return;
      converted.add({
        'role': 'user',
        'content': List<Object?>.of(pendingToolResults),
      });
      pendingToolResults = [];
    }

    for (final m in messages) {
      switch (m.role) {
        case 'system':
          if (m.content != null) {
            if (system.isNotEmpty) system.write('\n\n');
            system.write(m.content);
          }
        case 'user':
          flushToolResults();
          converted.add({'role': 'user', 'content': m.content ?? ''});
        case 'tool':
          pendingToolResults.add({
            'type': 'tool_result',
            'tool_use_id': m.toolCallId,
            'content': m.content ?? '',
          });
        case 'assistant':
        default:
          flushToolResults();
          final content = <Object?>[
            if (m.content?.isNotEmpty == true)
              {'type': 'text', 'text': m.content},
            for (final c in m.toolCalls ?? <ToolCall>[])
              {
                'type': 'tool_use',
                'id': c.id,
                'name': c.name,
                'input': c.arguments,
              },
          ];
          if (content.isEmpty) content.add({'type': 'text', 'text': ''});
          converted.add({'role': 'assistant', 'content': content});
      }
    }
    flushToolResults();

    return {
      'model': model,
      'max_tokens': maxTokens,
      if (system.isNotEmpty) 'system': system.toString(),
      'messages': converted,
      if (tools.isNotEmpty)
        'tools': [
          for (final t in tools)
            {
              'name': t.name,
              'description': t.description,
              'input_schema': t.parametersSchema,
            },
        ],
    };
  }

  AssistantReply _parseAnthropic(String body) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw ChatException('返回内容不是合法 JSON：${_snippet(body)}');
    }
    final content = decoded is Map ? decoded['content'] : null;
    if (content is! List) {
      throw ChatException('AI 返回缺少 content：${_snippet(body)}');
    }
    final texts = <String>[];
    final toolCalls = <ToolCall>[];
    for (final block in content) {
      if (block is! Map) continue;
      switch (block['type']) {
        case 'text':
          final t = block['text'];
          if (t is String && t.isNotEmpty) texts.add(t);
        case 'tool_use':
          final name = block['name'];
          if (name is! String) continue;
          final input = block['input'];
          toolCalls.add(
            ToolCall(
              id: (block['id'] ?? 'call_${toolCalls.length}') as String,
              name: name,
              arguments: input is Map
                  ? Map<String, dynamic>.from(input)
                  : const {},
            ),
          );
      }
    }
    return AssistantReply(
      text: texts.isEmpty ? null : texts.join('\n'),
      toolCalls: toolCalls,
    );
  }

  static String _snippet(String s) {
    final t = s.trim();
    return t.length <= 200 ? t : '${t.substring(0, 200)}…';
  }
}
