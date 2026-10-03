import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../application/overview_service.dart';
import '../../core/config/app_palette.dart';
import '../../core/motion/motion.dart';
import '../providers.dart';
import '../widgets/task_tile.dart';

/// 日历月视图（P7 遗留补全）。
///
/// [goalId] 非空 = 目标上下文（目标详情入口）；为空 = 全部目标（首页入口）。
/// 月历格子标记当日条目数，选中日下方列出任务（可完成/开始/取消）。
class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key, this.goalId, this.goalTitle});

  final String? goalId;
  final String? goalTitle;

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  late DateTime _month;
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selected = DateTime(now.year, now.month, now.day);
  }

  bool get _filterByGoal => widget.goalId != null;

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      final today = DateTime.now();
      final sameMonth =
          _month.year == today.year && _month.month == today.month;
      _selected = sameMonth
          ? DateTime(today.year, today.month, today.day)
          : DateTime(_month.year, _month.month, 1);
    });
  }

  Future<void> _onTaskChanged(bool complete, String taskId) async {
    if (!complete) return;
    final services = ref.read(servicesProvider);
    await services.planningService.completeTask(taskId);
    ref.invalidate(calendarProvider);
    invalidateAll(ref);
  }

  Future<void> _onTaskAction(String action, String taskId) async {
    final services = ref.read(servicesProvider);
    switch (action) {
      case 'start':
        await services.planningService.startTask(taskId);
      case 'complete':
        await services.planningService.completeTask(taskId);
      case 'cancel':
        await services.planningService.cancelTask(taskId);
      case 'postpone':
        await services.planningService.postponeTask(
          taskId,
          to: _selected.add(const Duration(days: 1)),
        );
      default:
        return;
    }
    if (!mounted) return;
    ref.invalidate(calendarProvider);
    invalidateAll(ref);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final monthAsync =
        ref.watch(calendarProvider((month: _month, goalId: widget.goalId)));
    final data = monthAsync.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: _filterByGoal
            ? Text('日程 · ${widget.goalTitle ?? ''}')
            : const Text('日程'),
      ),
      body: Column(
        children: [
          _monthBar(theme),
          _monthGrid(theme, data),
          const Divider(height: 1),
          Expanded(child: _dayList(theme, data)),
        ],
      ),
    );
  }

  Widget _monthBar(ThemeData theme) {
    final weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => _shiftMonth(-1),
                icon: const FaIcon(FontAwesomeIcons.chevronLeft, size: 15),
              ),
              Expanded(
                child: Text(
                  '${_month.year} 年 ${_month.month} 月',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppPalette.warmBrown,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _shiftMonth(1),
                icon: const FaIcon(FontAwesomeIcons.chevronRight, size: 15),
              ),
            ],
          ),
          Row(
            children: [
              for (final w in weekdays)
                Expanded(
                  child: Text(
                    w,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppPalette.warmBrown.withValues(alpha: 0.5),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _monthGrid(ThemeData theme, CalendarViewData? data) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final firstWeekday = DateTime(_month.year, _month.month, 1).weekday;
    final leadingBlanks = firstWeekday - 1; // 周一起始
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;

    return AnimatedSwitcher(
      duration: AppMotion.normal,
      switchInCurve: AppCurves.standard,
      switchOutCurve: AppCurves.standard,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: child,
      ),
      child: LayoutBuilder(
        key: ValueKey('${_month.year}-${_month.month}'),
        builder: (context, constraints) {
          // 格子高度跟随宽度但限制上下限，任何屏宽都不溢出。
          final cellWidth = constraints.maxWidth / 7;
          final cellHeight = cellWidth.clamp(34.0, 46.0);
          return GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: cellWidth / cellHeight,
            ),
            children: [
              for (var i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
              for (var day = 1; day <= daysInMonth; day++)
                _dayCell(theme, day, today, data?.itemsOf(day).length ?? 0),
            ],
          );
        },
      ),
    );
  }

  Widget _dayCell(ThemeData theme, int day, DateTime today, int marks) {
    final date = DateTime(_month.year, _month.month, day);
    final isSelected = date == _selected;
    final isToday = date == today;

    return GestureDetector(
      onTap: () => setState(() => _selected = date),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? AppPalette.sunsetOrange : Colors.transparent,
                border: isToday && !isSelected
                    ? Border.all(color: AppPalette.sunsetOrange, width: 1.5)
                    : null,
              ),
              child: Text(
                '$day',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isSelected
                      ? Colors.white
                      : AppPalette.warmBrown.withValues(alpha: 0.85),
                  fontWeight:
                      isSelected || isToday ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              height: 5,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (marks > 0)
                    Container(
                      width: marks > 2 ? 14 : 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppPalette.amber,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayList(ThemeData theme, CalendarViewData? data) {
    if (data == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppPalette.sunsetOrange),
      );
    }
    final items = data.itemsOf(_selected.day);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Text(
            '${_selected.month} 月 ${_selected.day} 日'
            '${items.isEmpty ? ' · 没有安排' : ' · ${items.length} 项'}',
            style: theme.textTheme.titleSmall?.copyWith(
              color: AppPalette.warmBrown,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                    '这一天没有日程或截止',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppPalette.warmBrown.withValues(alpha: 0.5),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  children: MotionEffects.staggerIn([
                    for (final item in items)
                      TaskTile(
                        task: item.task,
                        trailingTime: _timeLabel(item),
                        onChanged: (complete) =>
                            _onTaskChanged(complete, item.task.id),
                        onAction: (action) =>
                            _onTaskAction(action, item.task.id),
                      ),
                  ]),
                ),
        ),
      ],
    );
  }

  String? _timeLabel(TodayItem item) {
    final schedule = item.schedule;
    if (schedule != null) {
      final start =
          '${schedule.startAt.hour.toString().padLeft(2, '0')}:${schedule.startAt.minute.toString().padLeft(2, '0')}';
      return schedule.durationMinutes == null
          ? '$start 开始'
          : '$start · ${schedule.durationMinutes} 分钟';
    }
    return null;
  }
}
