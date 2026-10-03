import '../core/ai/chat_client.dart';

/// 工具运行上下文：Agent 循环注入的定位信息。
///
/// 例如 propose_plan 需要 conversationId 把提案挂到会话消息上；
/// goalId 让工具在目标详情聊天中默认关联当前目标。
class ToolRunContext {
  const ToolRunContext({this.goalId, this.conversationId});

  final String? goalId;
  final String? conversationId;

  static const empty = ToolRunContext();
}

/// Agent 工具：名称 + 描述 + JSON Schema + 处理器。
///
/// 处理器第二个参数是运行上下文；不需要它的工具也统一接收（保持
/// 签名一致，跨端契约单源，未来 MCP 侧同样带上下文执行）。
class AgentTool {
  const AgentTool({
    required this.name,
    required this.description,
    required this.parametersSchema,
    required this.handler,
  });

  final String name;
  final String description;
  final Map<String, Object?> parametersSchema;
  final Future<Map<String, Object?>> Function(
    Map<String, dynamic> args,
    ToolRunContext context,
  ) handler;
}

/// 工具注册表：Agent 循环的执行入口。
///
/// 执行统一返回 `{ok, data | error}`，error 原样交回模型自行纠正。
class ToolRegistry {
  ToolRegistry(this._tools);

  final List<AgentTool> _tools;

  List<ToolSpec> get specs => [
        for (final t in _tools)
          ToolSpec(
            name: t.name,
            description: t.description,
            parametersSchema: t.parametersSchema,
          ),
      ];

  Future<Map<String, Object?>> execute(
    String name,
    Map<String, dynamic> args, {
    ToolRunContext context = ToolRunContext.empty,
  }) async {
    final matches = _tools.where((t) => t.name == name).toList();
    if (matches.isEmpty) {
      return {'ok': false, 'error': '未知工具: $name'};
    }
    try {
      final data = await matches.first.handler(args, context);
      return {'ok': true, 'data': data};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }
}
