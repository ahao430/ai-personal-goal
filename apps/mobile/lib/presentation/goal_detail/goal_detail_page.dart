import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../application/overview_service.dart';
import '../../core/config/app_palette.dart';
import '../../core/motion/motion.dart';
import '../../domain/goal/goal.dart';
import '../../domain/goal/goal_metric.dart';
import '../../domain/phase/phase.dart';
import '../../domain/progress/progress_event.dart';
import '../../domain/task/task.dart';
import '../calendar/calendar_page.dart';
import '../chat/chat_page.dart';
import '../goals/goal_edit_page.dart';
import '../home/home_page.dart' show pickScheduleTime;
import '../providers.dart';
import '../widgets/animated_progress.dart';
import '../widgets/task_tile.dart';

/// 目标详情：路线 / 任务 / 动态三个视图，默认路线（plan §30）。
class GoalDetailPage extends ConsumerWidget {
  const GoalDetailPage({super.key, required this.goalId});

  final String goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(goalDetailProvider(goalId));

    return detailAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('加载失败：$e')),
      ),
      data: (detail) => DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              detail.goal.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              IconButton(
                tooltip: '日历视图',
                icon: const FaIcon(FontAwesomeIcons.calendarDays, size: 17),
                onPressed: () => pushMotion(
                  context,
                  CalendarPage(goalId: goalId, goalTitle: detail.goal.title),
                ),
              ),
              IconButton(
                tooltip: '和 AI 讨论这个目标',
                icon: const FaIcon(FontAwesomeIcons.commentDots, size: 18),
                onPressed: () => pushMotion(
                  context,
                  ChatPage(goalId: goalId),
                ),
              ),
              IconButton(
                tooltip: '编辑',
                icon: const FaIcon(FontAwesomeIcons.penToSquare, size: 16),
                onPressed: () async {
                  await pushMotion<bool>(
                    context,
                    GoalEditPage(existing: detail.goal),
                  );
                  ref.invalidate(goalDetailProvider(goalId));
                },
              ),
              _goalMenu(context, ref, detail.goal),
            ],
            bottom: TabBar(
              labelColor: AppPalette.sunsetOrange,
              unselectedLabelColor: AppPalette.warmBrown.withValues(alpha: 0.5),
              indicatorColor: AppPalette.sunsetOrange,
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: '路线'),
                Tab(text: '任务'),
                Tab(text: '动态'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _RoadmapTab(goalId: goalId, detail: detail),
              _TasksTab(goalId: goalId, detail: detail),
              _EventsTab(goalId: goalId),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            backgroundColor: AppPalette.sunsetOrange,
            foregroundColor: Colors.white,
            onPressed: () => _addTask(context, ref, detail.phases),
            child: const FaIcon(FontAwesomeIcons.plus, size: 18),
          ),
        ),
      ),
    );
  }

  // ── AppBar 菜单 ───────────────────────────────────────

  Widget _goalMenu(BuildContext context, WidgetRef ref, Goal goal) {
    final services = ref.read(servicesProvider);
    return PopupMenuButton<String>(
      icon: const FaIcon(FontAwesomeIcons.ellipsisVertical, size: 16),
      onSelected: (action) async {
        switch (action) {
          case 'pause':
            await services.goalService.pauseGoal(goal.id);
          case 'resume':
            await services.goalService.resumeGoal(goal.id);
          case 'complete':
            final ok = await _confirm(
              context,
              '完成目标「${goal.title}」？',
              '完成后可在「已完成」分类中查看。',
            );
            if (ok == true) {
              await services.goalService.completeGoal(goal.id);
            }
          case 'cancel':
            final ok = await _confirm(
              context,
              '取消目标「${goal.title}」？',
              '已完成的任务记录会保留。',
            );
            if (ok == true) {
              await services.goalService.cancelGoal(goal.id);
            }
          case 'archive':
            await services.goalService.archiveGoal(goal.id);
          case 'delete':
            final ok = await _confirm(
              context,
              '彻底删除「${goal.title}」？',
              '阶段、任务、日程与进度事件将一并删除，不可恢复。',
            );
            if (ok == true) {
              await services.goals.delete(goal.id);
              invalidateAll(ref);
              if (context.mounted) Navigator.of(context).pop();
              return;
            }
        }
        invalidateAll(ref);
      },
      itemBuilder: (_) => [
        if (goal.status == GoalStatus.active)
          const PopupMenuItem(value: 'pause', child: Text('暂停目标')),
        if (goal.status == GoalStatus.paused)
          const PopupMenuItem(value: 'resume', child: Text('恢复目标')),
        if (goal.status != GoalStatus.completed)
          const PopupMenuItem(value: 'complete', child: Text('完成目标')),
        if (goal.status == GoalStatus.active ||
            goal.status == GoalStatus.paused)
          const PopupMenuItem(value: 'cancel', child: Text('取消目标')),
        const PopupMenuItem(value: 'archive', child: Text('归档')),
        const PopupMenuItem(value: 'delete', child: Text('删除（不可恢复）')),
      ],
    );
  }

  Future<bool?> _confirm(BuildContext context, String title, String body) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('再想想'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  Future<void> _addTask(
    BuildContext context,
    WidgetRef ref,
    List<Phase> phases,
  ) async {
    final services = ref.read(servicesProvider);
    final controller = TextEditingController();
    final now = DateTime.now();

    final result = await showModalBottomSheet<(String, String?, DateTime?)>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20, 16, 20, 20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: StatefulBuilder(
          builder: (context, setState) {
            String? phaseId = phases.isNotEmpty ? phases.first.id : null;
            DateTime? due;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('添加任务', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '任务标题'),
                ),
                if (phases.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: phaseId,
                    decoration: const InputDecoration(labelText: '所属阶段'),
                    items: [
                      for (final p in phases)
                        DropdownMenuItem(
                          value: p.id,
                          child: Text(p.title,
                              overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => phaseId = v,
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    TextButton.icon(
                      icon: const FaIcon(FontAwesomeIcons.calendarDay, size: 14),
                      label: Builder(
                        builder: (_) {
                          final d = due;
                          return Text(d == null
                              ? '截止日期（可选）'
                              : '${d.month}/${d.day} 截止');
                        },
                      ),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: now.add(const Duration(days: 1)),
                          firstDate: now,
                          lastDate: now.add(const Duration(days: 365)),
                        );
                        if (picked != null) setState(() => due = picked);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppPalette.sunsetOrange,
                    ),
                    icon: const FaIcon(FontAwesomeIcons.check, size: 14),
                    label: const Text('添加'),
                    onPressed: () {
                      final title = controller.text.trim();
                      if (title.isEmpty) return;
                      Navigator.pop(context, (title, phaseId, due));
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );

    if (result == null) return;
    final (title, phaseId, due) = result;
    await services.planningService.createTask(
      title: title,
      phaseId: phaseId,
      goalId: phaseId == null ? goalId : null,
      dueDate: due == null
          ? null
          : DateTime(due.year, due.month, due.day, 23, 59),
    );
    invalidateAll(ref);
  }
}

// ── 路线 Tab ─────────────────────────────────────────────

class _RoadmapTab extends ConsumerWidget {
  const _RoadmapTab({required this.goalId, required this.detail});

  final String goalId;
  final GoalDetailData detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final goal = detail.goal;
    final phases = detail.phases;
    final metrics = detail.metrics;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 88),
      children: MotionEffects.staggerIn([
        // 概览卡（与列表卡片 Hero 共享过渡）
        Hero(
          tag: 'goal-card-${goal.id}',
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _statusBadge(theme, goal.status),
                      const Spacer(),
                      AnimatedPercent(
                        value: goal.overallProgress,
                        style: theme.textTheme.headlineSmall,
                      ),
                    ],
                  ),
                  if (goal.description != null &&
                      goal.description!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      goal.description!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppPalette.warmBrown.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  AnimatedProgressBar(
                    value: goal.overallProgress,
                    trackColor: const Color(0xFFFFE8DA),
                  ),
                  if (goal.targetDate != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '目标日 ${goal.targetDate!.year}/${goal.targetDate!.month}/${goal.targetDate!.day}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppPalette.warmBrown.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),

        // Metrics
        if (metrics.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final m in metrics) _metricCard(context, ref, m),
        ],

        // 阶段路线
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text('阶段路线', style: theme.textTheme.titleMedium),
            ),
            TextButton.icon(
              icon: const FaIcon(FontAwesomeIcons.plus, size: 13),
              label: const Text('阶段'),
              onPressed: () => _addPhase(context, ref),
            ),
          ],
        ),
        if (phases.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '还没有阶段。把目标拆成 2-5 个阶段（如「适应期 / 强化期 / 巩固期」）。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppPalette.warmBrown.withValues(alpha: 0.6),
                ),
              ),
            ),
          )
        else
          for (final phase in phases) _phaseTimelineTile(context, ref, phase),
      ]),
    );
  }

  Widget _metricCard(BuildContext context, WidgetRef ref, GoalMetric metric) {
    final theme = Theme.of(context);
    final decreasing = metric.direction == MetricDirection.decrease;
    final direction = decreasing ? '↓' : '↑';
    return Card(
      child: ListTile(
        leading: FaIcon(
          decreasing
              ? FontAwesomeIcons.arrowTrendDown
              : FontAwesomeIcons.arrowTrendUp,
          color: AppPalette.amber,
        ),
        title: Text(metric.name,
            style: theme.textTheme.titleSmall
                ?.copyWith(color: AppPalette.warmBrown)),
        subtitle: Text(
          '${_fmt(metric.currentValue)} → ${_fmt(metric.targetValue)}'
          '${metric.unit ?? ''} $direction',
        ),
        trailing: TextButton(
          onPressed: () => _recordMetric(context, ref, metric),
          child: const Text('记录'),
        ),
      ),
    );
  }

  static String _fmt(dynamic v) => v == null ? '—' : v.toString();

  Future<void> _recordMetric(
    BuildContext context,
    WidgetRef ref,
    GoalMetric metric,
  ) async {
    final services = ref.read(servicesProvider);
    final controller = TextEditingController();
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('记录 ${metric.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: '当前值（${metric.unit ?? '数值'}）',
            hintText: metric.currentValue?.toString(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(controller.text.trim())),
            child: const Text('记录'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    await services.goalService.recordMetricValue(metric.id, value);
    invalidateAll(ref);
  }

  Widget _phaseTimelineTile(
    BuildContext context,
    WidgetRef ref,
    Phase phase,
  ) {
    final theme = Theme.of(context);
    final services = ref.read(servicesProvider);
    final tasks = detail.tasksByPhase[phase.id] ?? const <Task>[];
    final effective =
        tasks.where((t) => t.status != TaskStatus.cancelled).toList();
    final done = effective
        .where((t) => t.status == TaskStatus.completed).length;
    final finished = phase.status == PhaseStatus.completed;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: finished ? AppPalette.amber : Colors.white,
                  border: Border.all(
                    color: finished ? AppPalette.amber : const Color(0xFFE8C4AE),
                    width: 2,
                  ),
                ),
                child: finished
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : Center(
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppPalette.sunsetOrange,
                          ),
                        ),
                      ),
              ),
              Expanded(
                child: Container(width: 2, color: const Color(0xFFFFD9C2)),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          phase.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: AppPalette.warmBrown,
                            decoration: finished ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                      Text(
                        '$done/${effective.length}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: AppPalette.warmBrown.withValues(alpha: 0.6),
                        ),
                      ),
                      if (!finished)
                        PopupMenuButton<String>(
                          icon: const FaIcon(FontAwesomeIcons.ellipsisVertical,
                              size: 14),
                          onSelected: (action) async {
                            if (action == 'complete') {
                              await services.planningService
                                  .completePhase(phase.id);
                              invalidateAll(ref);
                            } else if (action == 'rename') {
                              await _renamePhase(context, ref, phase);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                                value: 'complete', child: Text('标记完成')),
                            PopupMenuItem(value: 'rename', child: Text('重命名')),
                          ],
                        ),
                    ],
                  ),
                  if (phase.description?.isNotEmpty == true)
                    Text(
                      phase.description!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppPalette.warmBrown.withValues(alpha: 0.6),
                      ),
                    ),
                  const SizedBox(height: 4),
                  for (final task in tasks.take(3))
                    Row(
                      children: [
                        FaIcon(
                          task.status == TaskStatus.completed
                              ? FontAwesomeIcons.circleCheck
                              : FontAwesomeIcons.circle,
                          size: 12,
                          color: task.status == TaskStatus.completed
                              ? AppPalette.amber
                              : AppPalette.warmBrown.withValues(alpha: 0.3),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            task.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppPalette.warmBrown.withValues(alpha: 0.75),
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (tasks.length > 3)
                    Text(
                      '…共 ${tasks.length} 个任务，见「任务」页',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppPalette.warmBrown.withValues(alpha: 0.5),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addPhase(BuildContext context, WidgetRef ref) async {
    final services = ref.read(servicesProvider);
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加阶段'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: '阶段名', hintText: '如：适应期'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.isEmpty) return;
    await services.planningService.createPhase(goalId: goalId, title: title);
    invalidateAll(ref);
  }

  Future<void> _renamePhase(
    BuildContext context,
    WidgetRef ref,
    Phase phase,
  ) async {
    final services = ref.read(servicesProvider);
    final controller = TextEditingController(text: phase.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名阶段'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.isEmpty) return;
    await services.planningService
        .updatePhase(phase.id, (p) => p.copyWith(title: title));
    invalidateAll(ref);
  }

  Widget _statusBadge(ThemeData theme, GoalStatus status) {
    final (label, color) = switch (status) {
      GoalStatus.active => ('进行中', AppPalette.sunsetOrange),
      GoalStatus.paused => ('已暂停', AppPalette.peach),
      GoalStatus.completed => ('已完成', AppPalette.amber),
      GoalStatus.cancelled => ('已取消', AppPalette.warmBrown),
      GoalStatus.archived => ('已归档', AppPalette.warmBrown),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: theme.textTheme.labelMedium?.copyWith(color: color)),
    );
  }
}

// ── 任务 Tab ─────────────────────────────────────────────

class _TasksTab extends ConsumerWidget {
  const _TasksTab({required this.goalId, required this.detail});

  final String goalId;
  final GoalDetailData detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final phases = detail.phases;
    final tasksByPhase = detail.tasksByPhase;
    final unphased = detail.unphasedTasks;

    final sections = <Widget>[
      for (final phase in phases)
        _section(
          context,
          ref,
          header: phase.title,
          tasks: tasksByPhase[phase.id] ?? const [],
        ),
      if (unphased.isNotEmpty)
        _section(context, ref, header: '未分组', tasks: unphased),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 88),
      children: sections.isEmpty
          ? [
              Padding(
                padding: const EdgeInsets.only(top: 60),
                child: Center(
                  child: Text(
                    '还没有任务，点右下角 + 添加',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppPalette.warmBrown.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
            ]
          : sections,
    );
  }

  Widget _section(
    BuildContext context,
    WidgetRef ref, {
    required String header,
    required List<Task> tasks,
  }) {
    final theme = Theme.of(context);
    if (tasks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(header,
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: AppPalette.warmBrown)),
        ),
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Column(
              children: [
                for (final task in tasks) _taskTile(context, ref, task),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _taskTile(BuildContext context, WidgetRef ref, Task task) {
    final services = ref.read(servicesProvider);
    return TaskTile(
      task: task,
      onChanged: (_) async {
        await services.planningService.completeTask(task.id);
        invalidateAll(ref);
      },
      onAction: (action) async {
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
              final picked = await pickScheduleTime(context,
                  initial: task.dueDate);
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
      },
    );
  }
}

// ── 动态 Tab ─────────────────────────────────────────────

class _EventsTab extends ConsumerWidget {
  const _EventsTab({required this.goalId});

  final String goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(goalDetailProvider(goalId));
    return detailAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败：$e')),
      data: (detail) => ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 88),
        itemCount: detail.recentEvents.length,
        itemBuilder: (_, i) {
          final event = detail.recentEvents[i];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: FaIcon(_eventIcon(event.type),
                size: 16, color: AppPalette.sunsetOrange),
            title: Text(event.message ?? event.type.name),
            subtitle: Text(
              '${event.time.month}/${event.time.day} '
              '${event.time.hour.toString().padLeft(2, '0')}:'
              '${event.time.minute.toString().padLeft(2, '0')} · '
              '${_sourceLabel(event.source)}',
            ),
          );
        },
      ),
    );
  }

  static String _sourceLabel(ProgressSource source) {
    return switch (source) {
      ProgressSource.user => '我',
      ProgressSource.system => '自动',
      ProgressSource.chat => '对话',
      _ => source.name,
    };
  }

  static IconData _eventIcon(ProgressEventType type) {
    return switch (type) {
      ProgressEventType.taskCompleted =>
        FontAwesomeIcons.circleCheck,
      ProgressEventType.taskStarted => FontAwesomeIcons.play,
      ProgressEventType.taskPostponed => FontAwesomeIcons.clockRotateLeft,
      ProgressEventType.taskCancelled => FontAwesomeIcons.ban,
      ProgressEventType.metricUpdated => FontAwesomeIcons.chartLine,
      ProgressEventType.phaseCompleted => FontAwesomeIcons.flagCheckered,
      ProgressEventType.goalPaused => FontAwesomeIcons.pause,
      ProgressEventType.goalResumed => FontAwesomeIcons.play,
      _ => FontAwesomeIcons.heart,
    };
  }
}
