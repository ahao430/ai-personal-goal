import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/config/app_palette.dart';
import '../../core/motion/motion.dart';
import '../../domain/planning/plan_proposal.dart';

/// 计划提案确认卡片（plan §25「结构性变化先确认」）。
///
/// pending：展示 [应用计划] [修改]；applied / dismissed / superseded：
/// 只读徽章。阶段列表按动效规范 stagger 入场。
class PlanProposalCard extends StatelessWidget {
  const PlanProposalCard({
    super.key,
    required this.proposal,
    this.onApply,
    this.onEdit,
    this.busy = false,
  });

  final PlanProposal proposal;
  final VoidCallback? onApply;
  final VoidCallback? onEdit;

  /// 应用中（防重复点击）。
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10, right: 24),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18)
            .copyWith(bottomLeft: const Radius.circular(6)),
        border: Border.all(color: AppPalette.peach.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: AppPalette.peach.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(theme),
          if (proposal.reason != null && proposal.reason!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              proposal.reason!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppPalette.warmBrown.withValues(alpha: 0.75),
                height: 1.6,
              ),
            ),
          ],
          const SizedBox(height: 10),
          if (proposal.metricName != null) ...[
            _metricChip(theme),
            const SizedBox(height: 8),
          ],
          ...MotionEffects.staggerIn([
            for (var i = 0; i < proposal.phases.length; i++)
              _phaseRow(theme, proposal.phases[i], i),
            if (proposal.removePhaseIds.isNotEmpty ||
                proposal.removeTaskIds.isNotEmpty)
              _removalRow(theme),
          ]),
          if (proposal.targetDate != null) ...[
            const SizedBox(height: 6),
            _dateRow(theme),
          ],
          const SizedBox(height: 6),
          _footer(theme),
        ],
      ),
    );
  }

  Widget _header(ThemeData theme) {
    return Row(
      children: [
        const FaIcon(FontAwesomeIcons.route,
            size: 15, color: AppPalette.sunsetOrange),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            proposal.kind == ProposalKind.create
                ? '计划提案：${proposal.goalTitle ?? ''}'
                : '调整提案',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              color: AppPalette.warmBrown,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _metricChip(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1E0),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const FaIcon(FontAwesomeIcons.bullseye,
              size: 11, color: AppPalette.amber),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '${proposal.metricName}：'
              '${_fmtNum(proposal.metricStartValue)} → '
              '${_fmtNum(proposal.metricTargetValue)}'
              '${proposal.metricUnit ?? ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppPalette.warmBrown,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _phaseRow(ThemeData theme, ProposalPhaseDraft phase, int index) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppPalette.sunsetOrange,
              shape: BoxShape.circle,
            ),
            child: Text(
              '${index + 1}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  phase.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppPalette.warmBrown,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                for (final task in phase.tasks.take(4))
                  Padding(
                    padding: const EdgeInsets.only(top: 2, left: 2),
                    child: Row(
                      children: [
                        const FaIcon(FontAwesomeIcons.circleDot,
                            size: 8, color: AppPalette.peach),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            task.title +
                                (task.scheduleStartAt != null
                                    ? '（${_short(task.scheduleStartAt!)}）'
                                    : ''),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppPalette.warmBrown.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (phase.tasks.length > 4)
                  Text(
                    '…及另外 ${phase.tasks.length - 4} 个任务',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppPalette.warmBrown.withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _removalRow(ThemeData theme) {
    final parts = <String>[
      if (proposal.removePhaseIds.isNotEmpty)
        '取消 ${proposal.removePhaseIds.length} 个阶段',
      if (proposal.removeTaskIds.isNotEmpty)
        '取消 ${proposal.removeTaskIds.length} 个任务',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          const FaIcon(FontAwesomeIcons.minus,
              size: 12, color: AppPalette.coral),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              parts.join('，'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppPalette.coral,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateRow(ThemeData theme) {
    final date = proposal.targetDate!;
    return Row(
      children: [
        const FaIcon(FontAwesomeIcons.flagCheckered,
            size: 12, color: AppPalette.warmBrown),
        const SizedBox(width: 6),
        Text(
          proposal.kind == ProposalKind.create ? '目标日期' : '新的截止日期',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppPalette.warmBrown.withValues(alpha: 0.75),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppPalette.warmBrown,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _footer(ThemeData theme) {
    switch (proposal.status) {
      case ProposalStatus.applied:
        return _badge(
          theme,
          icon: FontAwesomeIcons.circleCheck,
          text: '已应用',
          color: const Color(0xFF3E8E5A),
        );
      case ProposalStatus.dismissed:
        return _badge(
          theme,
          icon: FontAwesomeIcons.circleXmark,
          text: '已忽略',
          color: AppPalette.warmBrown.withValues(alpha: 0.5),
        );
      case ProposalStatus.superseded:
        return _badge(
          theme,
          icon: FontAwesomeIcons.clockRotateLeft,
          text: '已有新版本提案',
          color: AppPalette.warmBrown.withValues(alpha: 0.5),
        );
      case ProposalStatus.pending:
        return Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppPalette.sunsetOrange,
                  disabledBackgroundColor: const Color(0xFFFFD9C2),
                ),
                onPressed: busy ? null : onApply,
                icon: busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const FaIcon(FontAwesomeIcons.wandMagicSparkles, size: 13),
                label: const Text('应用计划'),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppPalette.warmBrown,
                side: BorderSide(
                    color: AppPalette.warmBrown.withValues(alpha: 0.35)),
              ),
              onPressed: busy ? null : onEdit,
              child: const Text('修改'),
            ),
          ],
        );
    }
  }

  Widget _badge(ThemeData theme,
      {required IconData icon, required String text, required Color color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FaIcon(icon, size: 13, color: color),
        const SizedBox(width: 6),
        Text(
          text,
          style: theme.textTheme.labelMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  static String _fmtNum(double? v) => v == null
      ? '—'
      : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());

  static String _short(DateTime t) =>
      '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
