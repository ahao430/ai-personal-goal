import 'dart:convert';

import '../core/ai/chat_client.dart';
import '../core/ai/goal_agent_prompts.dart';
import 'app_services.dart';

/// 每日 AI 回顾（plan §46 / docs/ai/prompts.md §2 daily.review）。
///
/// App 打开时基于今天日程 + 昨日未完成项给出 1-3 句行动指引。
/// 成本控制：每天只生成一次（settings 按日期键缓存），
/// 供应商沿用模型链（默认 → 回退），失败静默降级（首页不显示卡片）。
class DailyReviewService {
  DailyReviewService(this._services, {ChatClient? chatClient})
      : _chatClient = chatClient ?? ChatClient();

  static const String featureKey = 'feature.daily_review';

  final AppServices _services;
  final ChatClient _chatClient;

  Future<bool> enabled() async =>
      await _services.settings.read(featureKey) != '0';

  Future<void> setEnabled(bool value) =>
      _services.settings.write(featureKey, value ? '1' : '0');

  /// 今天的回顾（已缓存则直接返回；未开启 / 生成失败返回 null）。
  Future<String?> review({DateTime? now}) async {
    if (!await enabled()) return null;
    final at = now ?? DateTime.now();
    final todayKey = _dayKey(at);
    final cached = await _services.settings.read(todayKey);
    if (cached != null && cached.isNotEmpty) return cached;

    final text = await _generate(at);
    if (text == null) return null;
    await _services.settings.write(todayKey, text);
    // 清理昨天的缓存键，settings 表不留垃圾。
    await _services.settings.delete(_dayKey(at.subtract(const Duration(days: 1))));
    return text;
  }

  Future<String?> _generate(DateTime at) async {
    final chain = await _services.aiProviderService.modelChain();
    if (chain.isEmpty) return null;

    final context = await _buildContext(at);
    final messages = [
      ChatMessage.system('$kGoalAgentSystemPrompt\n\n# 用户数据上下文\n$context'),
      ChatMessage.user(kDailyReviewInstruction),
    ];
    for (final (provider, model) in chain) {
      try {
        final reply = await _chatClient.complete(
          provider: provider,
          model: model,
          messages: messages,
        );
        final text = reply.text?.trim() ?? '';
        if (text.isNotEmpty) return text;
      } on ChatException {
        continue; // 换下一个供应商
      }
    }
    return null;
  }

  Future<String> _buildContext(DateTime at) async {
    final today = await _services.overview.todayView(at);
    String hhmm(DateTime t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    final map = <String, Object?>{
      'now': at.toIso8601String(),
      'scene': 'daily_review',
      'today_schedules': [
        for (final item in today.items.take(6))
          {
            'task': item.task.title,
            if (item.schedule != null) ...{
              'startAt': hhmm(item.schedule!.startAt),
              if (item.schedule!.durationMinutes != null)
                'minutes': item.schedule!.durationMinutes,
            },
            if (item.schedule == null && item.task.dueDate != null)
              'due': hhmm(item.task.dueDate!),
          },
      ],
      'overdue_tasks': [
        for (final t in today.overdueTasks.take(6))
          {'title': t.title, 'due': t.dueDate?.toIso8601String()},
      ],
      'activeGoals': [
        for (final g in (await _services.goals.findAll()).take(5))
          if (g.status.name == 'active')
            {'title': g.title, 'progress': g.overallProgress.round()},
      ],
    };
    return jsonEncode(map);
  }

  static String _dayKey(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return 'daily_review.${d.year}-$mm-$dd';
  }
}

/// daily.review 任务指令（事实源：docs/ai/prompts.md §2）。
const String kDailyReviewInstruction = '''
用户刚打开 App。基于今天日程与昨日未完成项，给出 1-3 句今日行动指引：
先确认是否补做昨日未完成事项，再指出今天最近的一个安排。
没有待办时简短问一句近况，不强制制造任务。
直接输出给用户的话，不要复述数据，不要列表，不要客套开场。
''';
