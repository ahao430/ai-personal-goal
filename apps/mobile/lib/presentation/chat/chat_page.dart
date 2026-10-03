import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/config/app_palette.dart';
import '../../core/motion/motion.dart';
import '../../domain/ai/conversation.dart';
import '../../domain/planning/plan_proposal.dart';
import '../providers.dart';
import '../widgets/action_confirm_card.dart';
import '../widgets/plan_proposal_card.dart';
import '../widgets/warm_card.dart';

/// 聊天页：自然语言 → Agent（工具调用）→ 数据落库 → UI 刷新。
/// [goalId] 非空时为「讨论这个目标」上下文。
/// AI 的结构性变更走 propose_plan 提案，在本页渲染确认卡片。
class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key, this.goalId});

  final String? goalId;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _scrollController = ScrollController();
  List<ConversationMessage> _messages = [];
  Map<String, PlanProposal> _proposals = {};
  String? _conversationId;
  bool _running = false;
  String? _applyingProposalId;

  bool get _hasContent => _messages.any(
      (m) => m.role == 'user' || m.role == 'assistant' || m.role == 'activity');

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    // 恢复该上下文最近的一次会话（goal 场景取该目标最新会话）
    final services = ref.read(servicesProvider);
    final recent = await services.conversations.recent(limit: 20);
    final conv =
        recent.where((c) => c.goalId == widget.goalId).firstOrNull;
    if (conv == null || !mounted) return;
    await _reloadMessages(conv.id);
  }

  /// 从库里重读当前会话的消息与提案（发送完成 / 应用提案后调用）。
  Future<void> _reloadMessages(String conversationId) async {
    final services = ref.read(servicesProvider);
    final messages = await services.conversations.messages(conversationId);
    final proposals = await services.proposals.findByConversation(conversationId);
    if (!mounted) return;
    setState(() {
      _conversationId = conversationId;
      _messages = messages;
      _proposals = {
        for (final p in proposals) p.id: p,
      };
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _running) return;
    final services = ref.read(servicesProvider);
    setState(() {
      _running = true;
      _input.clear();
      _messages = [
        ..._messages,
        ConversationMessage(
          id: 'local_${DateTime.now().microsecondsSinceEpoch}',
          conversationId: _conversationId ?? '',
          role: 'user',
          content: text,
          createdAt: DateTime.now(),
        ),
      ];
    });
    _scrollToBottom();

    try {
      final result = await services.agentService.send(
        goalId: widget.goalId,
        userText: text,
        conversationId: _conversationId,
        onActivity: (activity) {
          if (!mounted) return;
          setState(() => _messages = [..._messages, _localActivity(activity)]);
          _scrollToBottom();
        },
      );
      if (!mounted) return;
      // 消息与提案已落库，统一重读（含确认卡片挂载）。
      await _reloadMessages(result.conversationId);
      if (!mounted) return;
      _scrollToBottom();
      if (result.fallbackNote != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.fallbackNote!)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages = [
            ..._messages,
            _localActivity(e.toString(), error: true),
          ]);
    } finally {
      if (mounted) setState(() => _running = false);
      // AI 可能改了目标数据：刷新所有列表
      invalidateAll(ref);
    }
  }

  /// 应用计划提案（确认卡片 [应用计划]）。
  Future<void> _applyProposal(PlanProposal proposal) async {
    if (_applyingProposalId != null) return;
    final services = ref.read(servicesProvider);
    setState(() => _applyingProposalId = proposal.id);
    try {
      final result = await services.proposalService.apply(proposal.id);
      if (!mounted) return;
      await _reloadMessages(proposal.conversationId ?? _conversationId ?? '');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(proposal.kind == ProposalKind.action
            ? '已${ProposalActions.label(proposal.action ?? '')}'
            : '计划已应用：${result.phasesCreated} 个阶段、'
                '${result.tasksCreated} 个任务'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('应用失败：$e')));
    } finally {
      if (mounted) setState(() => _applyingProposalId = null);
      invalidateAll(ref);
    }
  }

  /// [修改]：不忽略提案，聚焦输入框让用户直接描述想改的地方；
  /// AI 随后重新 propose_plan（旧提案自动被取代）。
  void _editProposal(PlanProposal proposal) {
    _input.text = '关于这个计划，我想调整：';
    _input.selection = TextSelection.fromPosition(
      TextPosition(offset: _input.text.length),
    );
    _inputFocus.requestFocus();
  }

  /// action 卡片 [取消]：忽略提案并刷新。
  Future<void> _cancelAction(PlanProposal proposal) async {
    final services = ref.read(servicesProvider);
    try {
      await services.proposalService.dismiss(proposal.id);
    } catch (_) {/* 非 pending 视为已处理 */}
    final convId = proposal.conversationId ?? _conversationId;
    if (convId != null) await _reloadMessages(convId);
  }

  ConversationMessage _localActivity(String text, {bool error = false}) =>
      ConversationMessage(
        id: 'local_${DateTime.now().microsecondsSinceEpoch}',
        conversationId: _conversationId ?? '',
        role: 'activity',
        content: error ? '出错了：$text' : text,
        createdAt: DateTime.now(),
      );

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 60,
        duration: AppMotion.normal,
        curve: AppCurves.standard,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.goalId == null ? '和 AI 聊聊' : '讨论这个目标'),
      ),
      body: Column(
        children: [
          Expanded(
            child: !_hasContent && !_running ? _emptyHint(theme) : _list(theme),
          ),
          _inputBar(theme),
        ],
      ),
    );
  }

  Widget _emptyHint(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: MotionEffects.staggerIn([
        const SizedBox(height: 24),
        Icon(FontAwesomeIcons.wandMagicSparkles,
            size: 40, color: AppPalette.sunsetOrange),
        const SizedBox(height: 12),
        Text(
          '告诉 AI 今天发生了什么，或让它帮你规划',
          style: theme.textTheme.titleMedium
              ?.copyWith(color: AppPalette.warmBrown, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          '试试：\n'
          '「我想三个月减掉 5kg，帮我做个计划」\n'
          '「昨天的英语跟读完成了」\n'
          '「今天不做，明天再做」',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppPalette.warmBrown.withValues(alpha: 0.6),
            height: 1.9,
          ),
        ),
      ]),
    );
  }

  Widget _list(ThemeData theme) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      itemCount: _messages.length + (_running ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == _messages.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: _TypingBubble(),
          );
        }
        return MotionEffects.entrance(_bubble(theme, _messages[i]));
      },
    );
  }

  Widget _bubble(ThemeData theme, ConversationMessage message) {
    switch (message.role) {
      case 'user':
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10, left: 48),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppPalette.sunsetOrange,
              borderRadius: BorderRadius.circular(18)
                  .copyWith(bottomRight: const Radius.circular(6)),
            ),
            child: Text(
              message.content,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: Colors.white, height: 1.5),
            ),
          ),
        );
      case 'activity':
        return Align(
          alignment: Alignment.center,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFFFE8DA),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const FaIcon(FontAwesomeIcons.gear,
                    size: 11, color: AppPalette.sunsetOrange),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    message.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppPalette.warmBrown.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      case 'assistant':
      default:
        final proposal = message.proposalId == null
            ? null
            : _proposals[message.proposalId];
        return Align(
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(right: 48),
                child: WarmCard(
                  background: AppPalette.cardBgAmber,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  borderRadius: 18,
                  child: Text(
                    message.content,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppPalette.warmBrown, height: 1.6),
                  ),
                ),
              ),
              if (proposal != null)
                proposal.kind == ProposalKind.action
                    ? ActionConfirmCard(
                        proposal: proposal,
                        busy: _applyingProposalId == proposal.id,
                        onConfirm: () => _applyProposal(proposal),
                        onCancel: () => _cancelAction(proposal),
                      )
                    : PlanProposalCard(
                        proposal: proposal,
                        busy: _applyingProposalId == proposal.id,
                        onApply: () => _applyProposal(proposal),
                        onEdit: () => _editProposal(proposal),
                      ),
            ],
          ),
        );
    }
  }

  Widget _inputBar(ThemeData theme) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                focusNode: _inputFocus,
                enabled: !_running,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(
                  hintText: '告诉 AI…',
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              style: IconButton.styleFrom(
                backgroundColor: AppPalette.sunsetOrange,
                disabledBackgroundColor: const Color(0xFFFFD9C2),
              ),
              onPressed: _running ? null : _send,
              icon: _running
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const FaIcon(FontAwesomeIcons.paperPlane, size: 16),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18)
              .copyWith(bottomLeft: const Radius.circular(6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              _dot(i),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dot(int i) {
    return Container(
      width: 7,
      height: 7,
      decoration: const BoxDecoration(
        color: AppPalette.sunsetOrange,
        shape: BoxShape.circle,
      ),
    );
  }
}
