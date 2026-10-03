import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/config/app_palette.dart';
import '../../core/motion/motion.dart';
import '../../domain/goal/goal.dart';
import '../widgets/animated_progress.dart';
import '../goal_detail/goal_detail_page.dart';
import '../providers.dart';
import '../widgets/warm_card.dart';
import 'goal_edit_page.dart';

/// 目标列表：状态过滤 + 差异化卡片（有 Metric 的目标展示指标卡）。
class GoalsPage extends ConsumerStatefulWidget {
  const GoalsPage({super.key});

  @override
  ConsumerState<GoalsPage> createState() => _GoalsPageState();
}

class _GoalsPageState extends ConsumerState<GoalsPage> {
  GoalStatus _filter = GoalStatus.active;

  static const _filters = [
    (GoalStatus.active, '进行中'),
    (GoalStatus.paused, '已暂停'),
    (GoalStatus.completed, '已完成'),
    (GoalStatus.archived, '已归档'),
    (GoalStatus.cancelled, '已取消'),
  ];

  @override
  Widget build(BuildContext context) {
    final goalsAsync = ref.watch(goalsListProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('目标'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton.filledTonal(
              tooltip: '新建目标',
              onPressed: () => _create(),
              icon: const FaIcon(FontAwesomeIcons.plus, size: 16),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppPalette.sunsetOrange,
        foregroundColor: Colors.white,
        onPressed: _create,
        child: const FaIcon(FontAwesomeIcons.plus, size: 18),
      ),
      body: goalsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (allGoals) {
          final goals =
              allGoals.where((g) => g.status == _filter).toList();
          return Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Row(
                  children: [
                    for (final (status, label) in _filters)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(label),
                          selected: _filter == status,
                          showCheckmark: false,
                          onSelected: (_) => setState(() => _filter = status),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: goals.isEmpty
                    ? _emptyState(theme)
                    : RefreshIndicator(
                        onRefresh: () async {
                          ref.invalidate(goalsListProvider);
                          await ref.read(goalsListProvider.future);
                        },
                        child: ListView.builder(
                          // 切换过滤时重放错位入场
                          key: ValueKey('goals-$_filter'),
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 88),
                          itemCount: goals.length,
                          itemBuilder: (_, i) => MotionEffects.entrance(
                            _goalCard(theme, goals[i], i),
                            delay: Duration(
                              milliseconds:
                                  56 * (i > 8 ? 8 : i),
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _create() async {
    await pushMotion<bool>(context, const GoalEditPage());
    invalidateAll(ref);
  }

  Widget _emptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const FaIcon(FontAwesomeIcons.bullseye,
                size: 44, color: AppPalette.peach),
            const SizedBox(height: 12),
            Text(
              _filter == GoalStatus.active ? '还没有进行中的目标' : '该状态下暂无目标',
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: AppPalette.warmBrown),
            ),
            const SizedBox(height: 4),
            Text(
              '点右下角 + 创建目标：写下想完成的事，\nP5 之后 AI 会帮你拆解成阶段和任务',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppPalette.warmBrown.withValues(alpha: 0.6),
                height: 1.7,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _cardBgs = [
    AppPalette.cardBgOrange,
    AppPalette.cardBgCoral,
    AppPalette.cardBgAmber,
  ];

  Widget _goalCard(ThemeData theme, Goal goal, int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Hero(
        tag: 'goal-card-${goal.id}',
        child: WarmCard(
          background: _cardBgs[index % _cardBgs.length],
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => pushMotion(context, GoalDetailPage(goalId: goal.id)),
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
                AnimatedProgressBar(value: goal.overallProgress, height: 7),
                const SizedBox(height: 10),
                Text(
                  [
                    if (goal.targetDate != null)
                      '目标日 ${goal.targetDate!.year}/${goal.targetDate!.month}/${goal.targetDate!.day}',
                    '更新于 ${goal.updatedAt.month}/${goal.updatedAt.day}',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppPalette.warmBrown.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
