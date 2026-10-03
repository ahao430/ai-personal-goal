import 'dart:convert';

import '../core/ai/chat_client.dart';
import '../core/ai/goal_agent_prompts.dart';
import '../domain/ai/ai_provider.dart';
import 'ai_provider_service.dart';
import 'ai_tools.dart';
import 'app_services.dart';
import 'context_builder.dart';
import 'tool_registry.dart';

/// Agent 未就绪（未配置供应商等），UI 可引导去设置。
class AgentNotConfiguredException implements Exception {
  AgentNotConfiguredException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 一次 Agent 运行的结果。
class AgentRunResult {
  const AgentRunResult({
    required this.conversationId,
    required this.text,
    this.fallbackNote,
    this.proposalId,
  });

  final String conversationId;
  final String text;

  /// 供应商回退提示（null = 用首选模型完成）。
  final String? fallbackNote;

  /// 本次运行产出的计划提案（null = 没有结构性变更提案）。
  final String? proposalId;
}

/// Goal Agent（plan §18/44）：自然语言 → 工具调用 → SQLite → 回答。
///
/// 模型链：默认模型 → 其他已启用供应商（各取缓存中第一个模型）。
/// 单个模型失败自动切换，切换信息通过 [AgentRunResult.fallbackNote] 透出。
class AgentService {
  AgentService(this._services, {ChatClient? chatClient})
      : _chatClient = chatClient ?? ChatClient(),
        tools = buildGoalTools(_services);

  static const int maxToolRounds = 8;
  static const int historyForModel = 10;

  final AppServices _services;
  final ChatClient _chatClient;
  final ToolRegistry tools;

  AiProviderService get _providers => _services.aiProviderService;
  ContextBuilder get _context => _services.contextBuilder;

  /// 发送一条用户消息，跑完工具循环，返回回答。
  ///
  /// [onActivity] 在工具执行 / 模型切换时回调（聊天页展示「正在做什么」）。
  Future<AgentRunResult> send({
    String? goalId,
    required String userText,
    String? conversationId,
    void Function(String activity)? onActivity,
  }) async {
    final chain = await _modelChain();
    if (chain.isEmpty) {
      throw AgentNotConfiguredException(
        '尚未配置 AI 供应商或默认模型，请先到「我的 → AI 供应商与模型」完成配置。',
      );
    }

    // 会话与消息落库
    var convId = conversationId;
    if (convId == null || await _services.conversations.findById(convId) == null) {
      final conv = await _services.conversations.create(
        goalId: goalId,
        title: userText.length > 24 ? '${userText.substring(0, 24)}…' : userText,
      );
      convId = conv.id;
    }
    await _services.conversations.appendMessage(convId,
        role: 'user', content: userText);

    // 模型侧历史：只回放 user / assistant 文本
    final history = (await _services.conversations.messages(convId))
        .where((m) => m.role == 'user' || m.role == 'assistant')
        .toList();
    final replay = history.length <= historyForModel
        ? history
        : history.sublist(history.length - historyForModel);

    final contextJson =
        await _context.build(goalId: goalId, scene: goalId == null ? 'chat' : 'goal_detail');
    final baseMessages = <ChatMessage>[
      ChatMessage.system('$kGoalAgentSystemPrompt\n\n# 用户数据上下文\n$contextJson'),
      for (final m in replay)
        m.role == 'user' ? ChatMessage.user(m.content) : ChatMessage.assistant(text: m.content),
    ];

    Object? lastError;
    String? fallbackNote;
    for (var i = 0; i < chain.length; i++) {
      final (provider, model) = chain[i];
      try {
        final (text, proposalId) = await _runToolLoop(
          provider: provider,
          model: model,
          messages: baseMessages,
          context: ToolRunContext(goalId: goalId, conversationId: convId),
          onActivity: onActivity,
        );
        await _services.conversations.appendMessage(convId,
            role: 'assistant', content: text, proposalId: proposalId);
        if (fallbackNote != null) {
          await _services.conversations.appendMessage(convId,
              role: 'activity', content: fallbackNote);
        }
        return AgentRunResult(
          conversationId: convId,
          text: text,
          fallbackNote: fallbackNote,
          proposalId: proposalId,
        );
      } on ChatException catch (e) {
        lastError = e;
        if (i + 1 < chain.length) {
          final (nextProvider, nextModel) = chain[i + 1];
          fallbackNote =
              '当前模型暂时不可用，已自动切换到 ${nextProvider.name} / $nextModel';
          onActivity?.call(fallbackNote);
        }
      }
    }
    throw ChatException('AI 调用失败：$lastError');
  }

  /// 工具循环：模型请求工具 → 执行 → 结果回填 → 再问，直到文本回答。
  ///
  /// 返回 (回答文本, 提案 ID)。提案来自本轮 propose_plan 的工具结果，
  /// 会挂到 assistant 消息上供 UI 渲染确认卡片。
  Future<(String, String?)> _runToolLoop({
    required AiProvider provider,
    required String model,
    required List<ChatMessage> messages,
    required ToolRunContext context,
    void Function(String activity)? onActivity,
  }) async {
    var working = messages;
    String? proposalId;
    for (var round = 0; round < maxToolRounds; round++) {
      final reply = await _chatClient.complete(
        provider: provider,
        model: model,
        messages: working,
        tools: tools.specs,
      );
      if (!reply.wantsTools) {
        final text = reply.text?.trim() ?? '';
        if (text.isEmpty) {
          throw ChatException('AI 返回了空回复');
        }
        return (text, proposalId);
      }
      working = [
        ...working,
        ChatMessage.assistant(text: reply.text, toolCalls: reply.toolCalls),
      ];
      for (final call in reply.toolCalls) {
        onActivity?.call(activityLabel(call.name));
        final result = await tools.execute(call.name, call.arguments,
            context: context);
        final data = result['ok'] == true ? result['data'] : null;
        if ((call.name == 'propose_plan' || call.name == 'propose_action') &&
            data is Map) {
          final id = data['proposalId'];
          if (id is String && id.isNotEmpty) proposalId = id;
        }
        working = [
          ...working,
          ChatMessage.tool(
            toolCallId: call.id,
            result: jsonEncode(result),
          ),
        ];
      }
    }
    throw ChatException('工具调用轮数超过上限（$maxToolRounds）');
  }

  /// 模型链（plan §23）：默认模型优先，其余已启用供应商各补一个候选。
  Future<List<(AiProvider, String)>> _modelChain() => _providers.modelChain();

  /// 工具名 → 用户可读的活动标签。
  static String activityLabel(String toolName) {
    final labels = <String, String>{
      'get_goals': '正在查看目标…',
      'create_goal': '正在创建目标…',
      'update_goal': '正在更新目标…',
      'pause_goal': '正在暂停目标…',
      'resume_goal': '正在恢复目标…',
      'complete_goal': '正在完成目标…',
      'get_phases': '正在查看阶段…',
      'create_phase': '正在添加阶段…',
      'get_tasks': '正在查看任务…',
      'create_task': '正在创建任务…',
      'complete_task': '正在完成任务…',
      'postpone_task': '正在延期任务…',
      'cancel_task': '正在取消任务…',
      'schedule_task': '正在安排时间…',
      'reschedule_task': '正在调整时间…',
      'get_progress': '正在查看进度…',
      'user_report': '正在记录汇报…',
        'get_metrics': '正在查看指标…',
        'record_metric_value': '正在记录数值…',
        'propose_plan': '正在拟定计划提案…',
        'propose_action': '正在发起确认…',
        'analyze_progress': '正在分析进度…',
        'web_search': '正在联网搜索…',
        'fetch_web_page': '正在阅读网页…',
      };
    return labels[toolName] ?? '正在处理…';
  }
}
