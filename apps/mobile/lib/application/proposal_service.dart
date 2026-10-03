import 'dart:async';

import '../domain/entity_ids.dart';
import '../domain/goal/goal_metric.dart';
import '../domain/phase/phase.dart';
import '../domain/planning/plan_proposal.dart';
import '../domain/planning/plan_proposal_repository.dart';
import '../domain/progress/progress_event.dart';
import '../domain/task/task.dart';
import 'app_services.dart';
import 'goal_service.dart';
import 'planning_service.dart';

/// 应用计划提案的结果（用于 UI 反馈）。
class ProposalApplyResult {
  const ProposalApplyResult({
    required this.goalId,
    this.phasesCreated = 0,
    this.tasksCreated = 0,
    this.schedulesCreated = 0,
  });

  final String goalId;
  final int phasesCreated;
  final int tasksCreated;
  final int schedulesCreated;
}

/// 计划提案用例（P5，plan §25「结构性变化先确认」）。
///
/// AI 只产出提案（pending），用户在确认卡片上操作：
/// - [apply]：按提案落库（新目标全套计划 / 结构调整）
/// - [dismiss]：忽略
/// - 同一会话出现新提案时，旧的 pending 自动被取代（superseded）。
class ProposalService {
  ProposalService(this._services, this._proposals);

  final AppServices _services;
  final PlanProposalRepository _proposals;

  GoalService get _goals => _services.goalService;
  PlanningService get _planning => _services.planningService;

  /// 创建提案（propose_plan / propose_action 工具入口）。create 需要
  /// goalTitle 且至少一个阶段；adjust 需要存在的 goalId 且至少一项变更；
  /// action 需要白名单内的操作与存在的目标。
  Future<PlanProposal> create({
    String? conversationId,
    String? goalId,
    required ProposalKind kind,
    String? goalTitle,
    String? goalDescription,
    DateTime? targetDate,
    String? metricName,
    String? metricUnit,
    double? metricStartValue,
    double? metricTargetValue,
    bool metricDecrease = false,
    List<ProposalPhaseDraft> phases = const [],
    List<String> removePhaseIds = const [],
    List<String> removeTaskIds = const [],
    String? reason,
    String? action,
  }) async {
    final goalExists =
        goalId != null && await _services.goals.findById(goalId) != null;
    if (kind == ProposalKind.create) {
      if (goalTitle == null || goalTitle.trim().isEmpty) {
        throw ArgumentError('create 提案需要 goalTitle');
      }
      if (phases.isEmpty) {
        throw ArgumentError('create 提案至少需要一个阶段');
      }
    } else if (kind == ProposalKind.action) {
      if (!goalExists) {
        throw ArgumentError('action 提案指向的目标不存在: $goalId');
      }
      if (!ProposalActions.isValid(action)) {
        throw ArgumentError('不支持的操作: $action（可选 '
            '${ProposalActions.all.join(' / ')}）');
      }
    } else {
      if (!goalExists) {
        throw ArgumentError('adjust 提案指向的目标不存在: $goalId');
      }
      final hasChange = targetDate != null ||
          phases.isNotEmpty ||
          removePhaseIds.isNotEmpty ||
          removeTaskIds.isNotEmpty;
      if (!hasChange) {
        throw ArgumentError('adjust 提案没有任何变更内容');
      }
    }

    // 同一会话旧的 pending 提案被本提案取代。
    if (conversationId != null) {
      for (final old in await _proposals.findByConversation(conversationId)) {
        if (old.status == ProposalStatus.pending) {
          await _proposals.updateStatus(old.id, ProposalStatus.superseded);
        }
      }
    }

    // action 提案自动带上目标标题（确认卡片渲染用）。
    if (kind == ProposalKind.action && goalExists) {
      final goal = await _services.goals.findById(goalId);
      goalTitle ??= goal!.title;
    }

    final now = DateTime.now();
    return _proposals.insert(PlanProposal(
      id: EntityIds.newProposalId(),
      conversationId: conversationId,
      goalId: goalId,
      kind: kind,
      goalTitle: goalTitle?.trim(),
      goalDescription: goalDescription,
      targetDate: targetDate,
      metricName: metricName,
      metricUnit: metricUnit,
      metricStartValue: metricStartValue,
      metricTargetValue: metricTargetValue,
      metricDecrease: metricDecrease,
      phases: phases,
      removePhaseIds: removePhaseIds,
      removeTaskIds: removeTaskIds,
      reason: reason,
      action: action,
      createdAt: now,
    ));
  }

  /// 应用提案：按类型落库并置为 applied（非 pending 直接拒绝）。
  Future<ProposalApplyResult> apply(String id) async {
    final proposal = await _proposals.findById(id);
    if (proposal == null) {
      throw StateError('提案不存在: $id');
    }
    if (proposal.status != ProposalStatus.pending) {
      throw StateError('提案当前状态是 ${proposal.status.name}，不能应用');
    }

    final String goalId;
    var phasesCreated = 0;
    var tasksCreated = 0;
    var schedulesCreated = 0;

    switch (proposal.kind) {
      case ProposalKind.action:
        goalId = proposal.goalId!;
        final reason = proposal.reason;
        switch (proposal.action) {
          case ProposalActions.pause:
            await _goals.pauseGoal(goalId, reason: reason);
          case ProposalActions.resume:
            await _goals.resumeGoal(goalId);
          case ProposalActions.cancel:
            await _goals.cancelGoal(goalId, reason: reason);
          case ProposalActions.archive:
            await _goals.archiveGoal(goalId);
          default:
            throw StateError('不支持的操作: ${proposal.action}');
        }
        await _proposals.updateStatus(
          id,
          ProposalStatus.applied,
          appliedAt: DateTime.now(),
        );
        await _noteInConversation(
            proposal, '已${_actionDoneLabel(proposal.action!)}');
        return ProposalApplyResult(goalId: goalId);

      case ProposalKind.create:
        final goal = await _goals.createGoal(
          title: proposal.goalTitle!,
          description: proposal.goalDescription,
          targetDate: proposal.targetDate,
        );
        goalId = goal.id;

        if (proposal.metricName != null && proposal.metricTargetValue != null) {
          await _goals.addMetric(
            goalId,
            name: proposal.metricName!,
            unit: proposal.metricUnit,
            direction: proposal.metricDecrease
                ? MetricDirection.decrease
                : MetricDirection.increase,
            initialValue: proposal.metricStartValue,
            targetValue: proposal.metricTargetValue,
          );
        }

      case ProposalKind.adjust:
        goalId = proposal.goalId!;
        // 延期 / 缩小：更新目标日期或描述。
        if (proposal.targetDate != null || proposal.goalDescription != null) {
          await _goals.updateGoal(goalId, (g) => g.copyWith(
                targetDate: proposal.targetDate ?? g.targetDate,
                description: proposal.goalDescription ?? g.description,
              ));
        }
        // 先做减法（取消任务 → 取消阶段），再补新增，顺序与用户直觉一致。
        for (final taskId in proposal.removeTaskIds) {
          final task = await _services.tasks.findById(taskId);
          if (task != null &&
              task.status != TaskStatus.completed &&
              task.status != TaskStatus.cancelled) {
            await _planning.cancelTask(taskId);
          }
        }
        for (final phaseId in proposal.removePhaseIds) {
          final phase = await _services.phases.findById(phaseId);
          if (phase != null && phase.status != PhaseStatus.completed) {
            await _planning.cancelPhase(phaseId);
          }
        }
    }

    // 新增阶段与任务（两种类型共用）。
    for (final phaseDraft in proposal.phases) {
      final phase = await _planning.createPhase(
        goalId: goalId,
        title: phaseDraft.title,
        description: phaseDraft.description,
      );
      phasesCreated++;
      for (final taskDraft in phaseDraft.tasks) {
        final task = await _planning.createTask(
          title: taskDraft.title,
          description: taskDraft.description,
          goalId: goalId,
          phaseId: phase.id,
          estimatedMinutes: taskDraft.estimatedMinutes,
          dueDate: taskDraft.dueDate,
        );
        tasksCreated++;
        if (taskDraft.scheduleStartAt != null) {
          await _planning.scheduleTask(
            task.id,
            startAt: taskDraft.scheduleStartAt!,
            durationMinutes: taskDraft.scheduleMinutes ??
                taskDraft.estimatedMinutes,
          );
          schedulesCreated++;
        }
      }
    }

    await _services.progressService.emit(
      ProgressEventType.planApplied,
      goalId: goalId,
      message: proposal.kind == ProposalKind.create
          ? '应用 AI 计划，创建目标「${proposal.goalTitle}」'
          : '应用 AI 调整建议',
      data: {'proposalId': id},
    );
    await _proposals.updateStatus(
      id,
      ProposalStatus.applied,
      appliedAt: DateTime.now(),
    );
    await _noteInConversation(proposal, '已应用计划');
    // 提案可能带来一批新日程：整目标重排提醒。
    unawaited(_services.notificationScheduler.syncGoal(goalId));
    return ProposalApplyResult(
      goalId: goalId,
      phasesCreated: phasesCreated,
      tasksCreated: tasksCreated,
      schedulesCreated: schedulesCreated,
    );
  }

  /// 忽略提案（用户点 [修改] 后另行提出，或直接放弃）。
  Future<void> dismiss(String id, {String note = '已忽略该计划'}) async {
    final proposal = await _proposals.findById(id);
    if (proposal == null) {
      throw StateError('提案不存在: $id');
    }
    if (proposal.status != ProposalStatus.pending) return;
    await _proposals.updateStatus(id, ProposalStatus.dismissed);
    await _noteInConversation(
        proposal,
        proposal.kind == ProposalKind.action
            ? '已放弃${ProposalActions.label(proposal.action ?? '')}'
            : note);
  }

  /// action 应用后的会话回执文案。
  static String _actionDoneLabel(String action) => switch (action) {
        ProposalActions.pause => '暂停该目标',
        ProposalActions.resume => '恢复该目标',
        ProposalActions.cancel => '取消该目标',
        ProposalActions.archive => '归档该目标',
        _ => '执行操作',
      };

  /// 在来源会话里追加一条 activity 消息，让历史可见。
  Future<void> _noteInConversation(PlanProposal proposal, String note) async {
    final convId = proposal.conversationId;
    if (convId == null) return;
    if (await _services.conversations.findById(convId) == null) return;
    await _services.conversations.appendMessage(
      convId,
      role: 'activity',
      content: note,
    );
  }
}
