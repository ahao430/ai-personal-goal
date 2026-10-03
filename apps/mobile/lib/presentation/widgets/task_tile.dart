import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/config/app_palette.dart';
import '../../core/motion/motion.dart';
import '../../domain/task/task.dart';

/// 任务行：完成勾选 + 标题/元信息 + 操作菜单。
class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.task,
    this.trailingTime,
    this.onChanged,
    required this.onAction,
  });

  final Task task;

  /// 左侧副标题附加信息（如日程时间「19:00 · 60 分钟」）。
  final String? trailingTime;

  /// 完成态切换回调（勾选 = 完成；已完成的勾选不提供反悔，用菜单恢复）。
  final void Function(bool complete)? onChanged;

  /// 菜单动作：start / postpone / cancel / schedule / reopen
  final void Function(String action) onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = task.status == TaskStatus.completed;
    final cancelled = task.status == TaskStatus.cancelled;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: InkWell(
        customBorder: const CircleBorder(),
        onTap: cancelled ? null : () => onChanged?.call(true),
        child: AnimatedScale(
          scale: done ? 1.08 : 1.0,
          duration: AppMotion.fast,
          curve: AppCurves.emphasized,
          child: AnimatedContainer(
            duration: AppMotion.fast,
            curve: AppCurves.standard,
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? AppPalette.amber : Colors.white,
              border: Border.all(
                color: done ? AppPalette.amber : const Color(0xFFE8C4AE),
                width: 2,
              ),
            ),
            child: done
                ? const Icon(Icons.check, size: 18, color: Colors.white)
                : null,
          ),
        ),
      ),
      title: AnimatedDefaultTextStyle(
        duration: AppMotion.fast,
        curve: AppCurves.standard,
        style: theme.textTheme.bodyLarge!.copyWith(
          color: done || cancelled
              ? AppPalette.warmBrown.withValues(alpha: 0.45)
              : AppPalette.warmBrown,
          decoration: done || cancelled ? TextDecoration.lineThrough : null,
          decorationColor: AppPalette.warmBrown.withValues(alpha: 0.4),
        ),
        child: Text(task.title),
      ),
      subtitle: (trailingTime != null || task.dueDate != null)
          ? Text(
              [
                ?trailingTime,
                if (task.dueDate case final due?)
                  '${due.month}/${due.day} 截止',
                if (task.estimatedMinutes != null)
                  '约 ${task.estimatedMinutes} 分钟',
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppPalette.warmBrown.withValues(alpha: 0.55),
              ),
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _statusChip(theme),
          PopupMenuButton<String>(
            icon: const FaIcon(
              FontAwesomeIcons.ellipsisVertical,
              size: 16,
              color: AppPalette.warmBrown,
            ),
            onSelected: onAction,
            itemBuilder: (_) => [
              if (!done && task.status != TaskStatus.inProgress)
                const PopupMenuItem(value: 'start', child: Text('开始')),
              if (!done) ...[
                const PopupMenuItem(value: 'complete', child: Text('完成')),
                const PopupMenuItem(value: 'postpone', child: Text('延期')),
                const PopupMenuItem(value: 'schedule', child: Text('安排时间')),
                const PopupMenuItem(value: 'cancel', child: Text('取消任务')),
              ],
              if (done || cancelled)
                const PopupMenuItem(value: 'reopen', child: Text('重新打开')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip(ThemeData theme) {
    if (task.status == TaskStatus.todo) return const SizedBox.shrink();
    final (label, color) = switch (task.status) {
      TaskStatus.inProgress => ('进行中', AppPalette.sunsetOrange),
      TaskStatus.completed => ('完成', AppPalette.amber),
      TaskStatus.postponed => ('延期', AppPalette.peach),
      TaskStatus.cancelled => ('取消', AppPalette.warmBrown),
      TaskStatus.todo => ('', AppPalette.warmBrown),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
