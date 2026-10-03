import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/config/app_palette.dart';
import '../../core/motion/motion.dart';
import '../../domain/planning/plan_proposal.dart';

/// 目标级操作的二次确认卡片（plan §25：暂停/恢复/取消/归档 = 是/否确认）。
///
/// pending：[确认] [取消]；其余状态只读徽章。
class ActionConfirmCard extends StatelessWidget {
  const ActionConfirmCard({
    super.key,
    required this.proposal,
    this.onConfirm,
    this.onCancel,
    this.busy = false,
  });

  final PlanProposal proposal;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final action = proposal.action ?? '';
    final isCancel = action == ProposalActions.cancel;
    return Container(
      margin: const EdgeInsets.only(bottom: 10, right: 24),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16)
            .copyWith(bottomLeft: const Radius.circular(6)),
        border: Border.all(
          color: (isCancel ? AppPalette.coral : AppPalette.peach)
              .withValues(alpha: 0.6),
        ),
        boxShadow: [
          BoxShadow(
            color: AppPalette.peach.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: MotionEffects.entrance(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                FaIcon(_icon(action),
                    size: 15,
                    color: isCancel ? AppPalette.coral : AppPalette.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${ProposalActions.label(action)}「${proposal.goalTitle ?? ''}」',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: AppPalette.warmBrown,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            if (proposal.reason != null && proposal.reason!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                proposal.reason!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppPalette.warmBrown.withValues(alpha: 0.75),
                  height: 1.6,
                ),
              ),
            ],
            const SizedBox(height: 10),
            _footer(theme, isCancel),
          ],
        ),
      ),
    );
  }

  Widget _footer(ThemeData theme, bool isCancel) {
    switch (proposal.status) {
      case ProposalStatus.applied:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const FaIcon(FontAwesomeIcons.circleCheck,
                size: 13, color: Color(0xFF3E8E5A)),
            const SizedBox(width: 6),
            Text('已执行',
                style: theme.textTheme.labelMedium?.copyWith(
                    color: const Color(0xFF3E8E5A),
                    fontWeight: FontWeight.w700)),
          ],
        );
      case ProposalStatus.dismissed:
      case ProposalStatus.superseded:
        return Text(
          proposal.status == ProposalStatus.dismissed ? '已取消' : '已有新版本提案',
          style: theme.textTheme.labelMedium?.copyWith(
            color: AppPalette.warmBrown.withValues(alpha: 0.5),
            fontWeight: FontWeight.w700,
          ),
        );
      case ProposalStatus.pending:
        return Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor:
                      isCancel ? AppPalette.coral : AppPalette.sunsetOrange,
                  disabledBackgroundColor: const Color(0xFFFFD9C2),
                ),
                onPressed: busy ? null : onConfirm,
                icon: busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const FaIcon(FontAwesomeIcons.check, size: 13),
                label: const Text('确认'),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppPalette.warmBrown,
                side: BorderSide(
                    color: AppPalette.warmBrown.withValues(alpha: 0.35)),
              ),
              onPressed: busy ? null : onCancel,
              child: const Text('取消'),
            ),
          ],
        );
    }
  }

  static IconData _icon(String action) => switch (action) {
        ProposalActions.pause => FontAwesomeIcons.pause,
        ProposalActions.resume => FontAwesomeIcons.play,
        ProposalActions.cancel => FontAwesomeIcons.ban,
        ProposalActions.archive => FontAwesomeIcons.boxArchive,
        _ => FontAwesomeIcons.circleQuestion,
      };
}
