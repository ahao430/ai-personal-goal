import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ai_goal/core/ai/chat_client.dart';
import 'package:ai_goal/domain/ai/ai_provider.dart';
const kUtf8Json = {'content-type': 'application/json; charset=utf-8'};


AiProvider provider({
  ApiStyle style = ApiStyle.openaiCompatible,
  String baseUrl = 'https://api.example.com/v1',
}) =>
    AiProvider(
      id: 'provider_t',
      name: 'test',
      apiStyle: style,
      baseUrl: baseUrl,
      apiKey: 'sk-abc',
      createdAt: DateTime(2026, 10, 3),
      updatedAt: DateTime(2026, 10, 3),
    );

const tools = [
  ToolSpec(
    name: 'get_goals',
    description: '获取目标',
    parametersSchema: {'type': 'object', 'properties': {}},
  ),
];

void main() {
  group('ChatClient · OpenAI 兼容', () {
    test('请求形态：/chat/completions + Bearer + tools + tool_choice', () async {
      Map<String, dynamic>? capturedBody;
      final client = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          '{"choices":[{"message":{"role":"assistant","content":"你好"}}]}',
          200, headers: kUtf8Json,
        );
      });

      final reply = await ChatClient(client: client).complete(
        provider: provider(),
        model: 'glm-4.6',
        messages: const [
          ChatMessage.system('sys'),
          ChatMessage.user('hi'),
        ],
        tools: tools,
      );

      expect(reply.text, '你好');
      expect(reply.toolCalls, isEmpty);
      expect(capturedBody!['model'], 'glm-4.6');
      expect(capturedBody!['tool_choice'], 'auto');
    });

    test('解析 tool_calls（arguments 为 JSON 字符串）', () async {
      final body = jsonEncode({
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'content': null,
              'tool_calls': [
                {
                  'id': 'call_1',
                  'type': 'function',
                  'function': {
                    'name': 'create_goal',
                    'arguments': jsonEncode({'title': '减重'}),
                  },
                },
              ],
            },
          },
        ],
      });
      final client = MockClient(
        (_) async => http.Response(body, 200, headers: kUtf8Json),
      );

      final reply = await ChatClient(client: client).complete(
        provider: provider(),
        model: 'm',
        messages: const [ChatMessage.user('帮我建目标')],
        tools: tools,
      );

      expect(reply.wantsTools, isTrue);
      expect(reply.toolCalls.single.name, 'create_goal');
      expect(reply.toolCalls.single.arguments['title'], '减重');
    });

    test('工具结果回传为 role:tool / tool_call_id', () async {
      Map<String, dynamic>? capturedBody;
      final client = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          '{"choices":[{"message":{"content":"done"}}]}',
          200, headers: kUtf8Json,
        );
      });

      await ChatClient(client: client).complete(
        provider: provider(),
        model: 'm',
        messages: const [
          ChatMessage.user('hi'),
          ChatMessage.assistant(toolCalls: [
            ToolCall(id: 'call_1', name: 'get_goals', arguments: {}),
          ]),
          ChatMessage.tool(toolCallId: 'call_1', result: '{"ok":true}'),
        ],
        tools: tools,
      );

      final messages = capturedBody!['messages'] as List;
      final toolMsg = messages.last as Map;
      expect(toolMsg['role'], 'tool');
      expect(toolMsg['tool_call_id'], 'call_1');
      final assistantMsg = messages[1] as Map;
      expect(
        (assistantMsg['tool_calls'] as List).single['function']['name'],
        'get_goals',
      );
    });
  });

  group('ChatClient · Anthropic', () {
    test('请求形态：/v1/messages + x-api-key + system 顶层 + input_schema',
        () async {
      Map<String, dynamic>? capturedBody;
      final client = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          '{"content":[{"type":"text","text":"你好"}]}',
          200, headers: kUtf8Json,
        );
      });

      final reply = await ChatClient(client: client).complete(
        provider: provider(
          style: ApiStyle.anthropic,
          baseUrl: 'https://api.anthropic.com',
        ),
        model: 'claude-sonnet-4',
        messages: const [
          ChatMessage.system('sys'),
          ChatMessage.user('hi'),
        ],
        tools: tools,
      );

      expect(reply.text, '你好');
      expect(capturedBody!['system'], 'sys');
      expect(capturedBody!['max_tokens'], greaterThan(0));
      expect(
        (capturedBody!['tools'] as List).single['input_schema'],
        isNotNull,
      );
    });

    test('连续 tool 结果合并为单条 user 消息的 tool_result 块', () async {
      Map<String, dynamic>? capturedBody;
      final client = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{"content":[{"type":"text","text":"ok"}]}', 200, headers: kUtf8Json);
      });

      await ChatClient(client: client).complete(
        provider: provider(style: ApiStyle.anthropic, baseUrl: 'https://a.com'),
        model: 'm',
        messages: const [
          ChatMessage.user('hi'),
          ChatMessage.assistant(toolCalls: [
            ToolCall(id: 'c1', name: 'get_goals', arguments: {}),
            ToolCall(id: 'c2', name: 'get_tasks', arguments: {}),
          ]),
          ChatMessage.tool(toolCallId: 'c1', result: '{"ok":true}'),
          ChatMessage.tool(toolCallId: 'c2', result: '{"ok":true}'),
        ],
        tools: tools,
      );

      final messages = capturedBody!['messages'] as List;
      final last = messages.last as Map;
      expect(last['role'], 'user');
      final blocks = last['content'] as List;
      expect(blocks, hasLength(2));
      expect(blocks.first['type'], 'tool_result');
      expect(blocks.first['tool_use_id'], 'c1');
    });

    test('解析 tool_use 块', () async {
      final client = MockClient((_) async => http.Response(
            '{"content":[{"type":"text","text":"好的"},'
            '{"type":"tool_use","id":"u1","name":"complete_task","input":{"taskId":"task_1"}}]}',
            200, headers: kUtf8Json,
          ));

      final reply = await ChatClient(client: client).complete(
        provider: provider(style: ApiStyle.anthropic, baseUrl: 'https://a.com'),
        model: 'm',
        messages: const [ChatMessage.user('完成了')],
        tools: tools,
      );

      expect(reply.text, '好的');
      expect(reply.toolCalls.single.name, 'complete_task');
      expect(reply.toolCalls.single.arguments['taskId'], 'task_1');
    });
  });

  test('非 200 抛 ChatException，携带状态码', () async {
    final client =
        MockClient((_) async => http.Response('{"error":"rate limited"}', 429));
    expect(
      () => ChatClient(client: client).complete(
        provider: provider(),
        model: 'm',
        messages: const [ChatMessage.user('hi')],
        tools: tools,
      ),
      throwsA(
        isA<ChatException>().having((e) => e.message, 'message', contains('429')),
      ),
    );
  });
}
