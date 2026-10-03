import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../application/app_services.dart';
import '../../application/overview_service.dart';
import '../../core/config/app_palette.dart';
import '../../core/motion/motion.dart';
import '../../domain/task/task.dart';
import '../chat/chat_page.dart';
import '../calendar/calendar_page.dart';
import '../goal_detail/goal_detail_page.dart';
import '../providers.dart';
import '../settings/settings_page.dart';
import '../widgets/animated_progress.dart';
import '../widgets/task_tile.dart';
import '../widgets/warm_card.dart';

/// 首页：回答「今天应该做什么？当前目标进展如何？有什么需要处理？」（plan §28）
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeAsync = ref.watch(homeViewProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/bg_home.png',
              fit: BoxFit.cover,
              errorBuilder: _blankFallback,
            ),
          ),
          SafeArea(
            child: homeAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('数据加载失败：$e')),
              data: (view) => RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(homeViewProvider);
                  await ref.read(homeViewProvider.future);
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  children: MotionEffects.staggerIn([
                    _header(context, ref, theme),
                    const SizedBox(height: 16),
                    _heroCard(context, theme),
                    _reviewCard(context, ref, theme),
                    const SizedBox(height: 16),
                    _todaySection(context, ref, theme, view.today),
                    const SizedBox(height: 14),
                    _currentGoalSection(context, theme, view),
                    if (view.today.overdueTasks.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _attentionSection(context, ref, theme, view.today),
                    ],
                  ]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _blankFallback(
    BuildContext _,
    Object _,
    StackTrace? _,
  ) =>
      const ColoredBox(color: AppPalette.cream);

  Widget _header(BuildContext context, WidgetRef ref, ThemeData theme) {
    final hour = DateTime.now().hour;
    final greeting = hour < 5
        ? '夜深了'
        : hour < 11
            ? '早上好'
            : hour < 14
                ? '中午好'
                : hour < 18
                    ? '下午好'
                    : '晚上好';
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final now = DateTime.now();

    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.asset(
            'assets/images/logo.png',
            width: 46,
            height: 46,
            errorBuilder: (_, _, _) => const SizedBox(
              width: 46,
              height: 46,
              child: ColoredBox(color: AppPalette.sunsetOrange),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$greeting，继续推进目标',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: AppPalette.warmBrown,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '${now.month}月${now.day}日 · 周${weekdays[now.weekday - 1]}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppPalette.warmBrown.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: '设置',
          style: IconButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: AppPalette.sunsetOrange,
          ),
          onPressed: () => pushMotion(
            context,
            SettingsPage(services: ref.read(servicesProvider)),
          ),
          icon: const FaIcon(FontAwesomeIcons.gear, size: 18),
        ),
      ],
    );
  }

  /// 每日 AI 回顾卡（P6）：未开启 / 未配置 / 生成失败时整卡隐藏。
  Widget _reviewCard(BuildContext context, WidgetRef ref, ThemeData theme) {
    final reviewAsync = ref.watch(dailyReviewProvider);
    final review = reviewAsync.asData?.value;
    if (review == null || review.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: WarmCard(
        background: AppPalette.cardBgOrange,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => pushMotion(context, const ChatPage()),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const FaIcon(FontAwesomeIcons.wandMagicSparkles,
                      size: 14, color: AppPalette.sunsetOrange),
                  const SizedBox(width: 8),
                  Text(
                    '今天的 AI 回顾',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AppPalette.warmBrown.withValues(alpha: 0.65),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                review,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppPalette.warmBrown,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heroCard(BuildContext context, ThemeData theme) {    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: 170,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/images/hero.png',
              fit: BoxFit.cover,
              errorBuilder: _blankFallback,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.45, 1],
                  colors: [Colors.transparent, Color(0xB34A2C2A)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const FaIcon(FontAwesomeIcons.bullseye,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        '把目标，变成今天的行动',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppPalette.sunsetOrange,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        onPressed: () => pushMotion(context, const ChatPage()),
                        icon: const FaIcon(
                            FontAwesomeIcons.wandMagicSparkles,
                            size: 14),
                        label: const Text('和 AI 聊聊'),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '告诉 AI 今天发生了什么',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 今天 ─────────────────────────────────────────────

  Widget _todaySection(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    TodayView today,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _sectionTitle(theme, FontAwesomeIcons.calendarDay, '今天',
                  today.items.length),
            ),
            IconButton(
              tooltip: '日历视图',
              style: IconButton.styleFrom(
                foregroundColor: AppPalette.sunsetOrange,
              ),
              onPressed: () => pushMotion(context, const CalendarPage()),
              icon: const FaIcon(FontAwesomeIcons.calendarDays, size: 17),
            ),
          ],
        ),
        const SizedBox(height: 8),
        WarmCard(
          background: AppPalette.cardBgOrange,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: today.items.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    '今日暂无安排。去「目标」页创建目标，或给任务安排时间。',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppPalette.warmBrown.withValues(alpha: 0.6),
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (final item in today.items)
                      _todayTile(context, ref, item),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _todayTile(BuildContext context, WidgetRef ref, TodayItem item) {
    final services = ref.read(servicesProvider);
    final schedule = item.schedule;
    final time = schedule == null
        ? '今天截止'
        : '${schedule.startAt.hour.toString().padLeft(2, '0')}:'
            '${schedule.startAt.minute.toString().padLeft(2, '0')}'
            '${schedule.durationMinutes != null ? ' · ${schedule.durationMinutes} 分钟' : ''}';
    return TaskTile(
      task: item.task,
      trailingTime: time,
      onChanged: (_) async {
        await services.planningService.completeTask(item.task.id);
        invalidateAll(ref);
      },
      onAction: (action) =>
          _handleTaskAction(context, ref, services, item.task, action),
    );
  }

  // ── 当前目标 ─────────────────────────────────────────

  Widget _currentGoalSection(
    BuildContext context,
    ThemeData theme,
    HomeView view,
  ) {
    final goal = view.primaryGoal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(theme, FontAwesomeIcons.rocket, '当前目标',
            view.activeGoals.length),
        const SizedBox(height: 8),
        if (goal == null)
          WarmCard(
            background: AppPalette.cardBgAmber,
            child: Text(
              '还没有进行中的目标。\n点右下角 + 创建第一个目标。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppPalette.warmBrown.withValues(alpha: 0.7),
                height: 1.6,
              ),
            ),
          )
        else
          WarmCard(
            background: AppPalette.cardBgCoral,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        goal.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: AppPalette.warmBrown,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    AnimatedPercent(value: goal.overallProgress),
                  ],
                ),
                const SizedBox(height: 8),
                AnimatedProgressBar(value: goal.overallProgress),
                const SizedBox(height: 10),
                Text(
                  [
                    if (view.currentPhase != null) '阶段：${view.currentPhase!.title}',
                    if (view.nextTask != null) '下一步：${view.nextTask!.title}',
                    if (goal.targetDate != null)
                      '目标日 ${goal.targetDate!.month}/${goal.targetDate!.day}',
                  ].join('\n'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppPalette.warmBrown.withValues(alpha: 0.75),
                    height: 1.7,
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => _openDetail(context, goal.id),
                    child: const Text('查看目标'),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ── 需要处理 ─────────────────────────────────────────

  Widget _attentionSection(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    TodayView today,
  ) {
    final services = ref.read(servicesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
            theme, FontAwesomeIcons.triangleExclamation, '需要处理', null),
        const SizedBox(height: 8),
        WarmCard(
          background: AppPalette.cardBgAmber,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            children: [
              for (final task in today.overdueTasks)
                TaskTile(
                  task: task,
                  onChanged: (_) async {
                    await services.planningService.completeTask(task.id);
                    invalidateAll(ref);
                  },
                  onAction: (action) =>
                      _handleTaskAction(context, ref, services, task, action),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 共享 ─────────────────────────────────────────────

  Widget _sectionTitle(ThemeData theme, IconData icon, String title, int? count) {
    return Row(
      children: [
        FaIcon(icon, size: 15, color: AppPalette.sunsetOrange),
        const SizedBox(width: 6),
        Text(title, style: theme.textTheme.titleMedium),
        if (count != null && count > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: AppPalette.sunsetOrange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text('$count',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: AppPalette.sunsetOrange)),
          ),
        ],
      ],
    );
  }

  void _openDetail(BuildContext context, String goalId) {
    pushMotion(context, GoalDetailPage(goalId: goalId));
  }

  Future<void> _handleTaskAction(
    BuildContext context,
    WidgetRef ref,
    AppServices services,
    Task task,
    String action,
  ) async {
    final planning = services.planningService;
    switch (action) {
      case 'start':
        await planning.startTask(task.id);
      case 'complete':
        await planning.completeTask(task.id);
      case 'postpone':
        await planning.postponeTask(task.id);
      case 'cancel':
        await planning.cancelTask(task.id);
      case 'reopen':
        await planning.updateTask(
          task.id,
          (t) => t.copyWith(status: TaskStatus.todo, completedAt: null),
        );
        await services.progressService.afterTaskChange(task.id);
      case 'schedule':
        if (context.mounted) {
          final picked = await pickScheduleTime(context, initial: task.dueDate);
          if (picked != null) {
            await planning.scheduleTask(
              task.id,
              startAt: picked.$1,
              durationMinutes: picked.$2,
            );
          }
        }
    }
    invalidateAll(ref);
  }
}

/// 日期 + 时长选择器。返回 (开始时间, 分钟数)；用户取消任一步骤返回 null。
Future<(DateTime, int?)?> pickScheduleTime(
  BuildContext context, {
  DateTime? initial,
}) async {
  final now = DateTime.now();
  final date = await showDatePicker(
    context: context,
    initialDate: initial ?? now,
    firstDate: now.subtract(const Duration(days: 1)),
    lastDate: now.add(const Duration(days: 365)),
  );
  if (date == null || !context.mounted) return null;

  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial ?? now.add(const Duration(hours: 1))),
  );
  if (time == null || !context.mounted) return null;

  final start = DateTime(date.year, date.month, date.day, time.hour, time.minute);
  final minutes = await _pickDuration(context);
  return (start, minutes);
}

Future<int?> _pickDuration(BuildContext context) async {
  const options = [15, 30, 45, 60, 90, 120];
  return showModalBottomSheet<int>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text('预计时长（可选）'),
            trailing: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('跳过'),
            ),
          ),
          for (final m in options)
            ListTile(
              dense: true,
              title: Text('$m 分钟'),
              onTap: () => Navigator.pop(context, m),
            ),
        ],
      ),
    ),
  );
}
