import '../time_codec.dart';

/// 提案类型：create = 新目标 + 全套计划；adjust = 调整现有目标结构；
/// action = 需要二次确认的目标级操作（暂停/恢复/取消/归档）。
enum ProposalKind {
  create,
  adjust,
  action;

  static ProposalKind parse(String value) => values.firstWhere(
        (v) => v.name == value,
        orElse: () => throw ArgumentError('未知的提案类型: $value'),
      );
}

/// action 提案支持的操作（与 GoalService 用例一一对应）。
abstract final class ProposalActions {
  static const pause = 'pause_goal';
  static const resume = 'resume_goal';
  static const cancel = 'cancel_goal';
  static const archive = 'archive_goal';

  static const all = {pause, resume, cancel, archive};

  static bool isValid(String? v) => v != null && all.contains(v);

  /// 用户可读的操作名（确认卡片标题用）。
  static String label(String action) => switch (action) {
        pause => '暂停目标',
        resume => '恢复目标',
        cancel => '取消目标',
        archive => '归档目标',
        _ => '操作',
      };
}

/// 提案状态：pending 等待确认；applied 已应用；dismissed 用户忽略；
/// superseded 被同会话更新的提案取代。
enum ProposalStatus {
  pending,
  applied,
  dismissed,
  superseded;

  static ProposalStatus parse(String value) => values.firstWhere(
        (v) => v.name == value,
        orElse: () => throw ArgumentError('未知的提案状态: $value'),
      );
}

/// 提案中的任务草稿（应用时创建 Task，可带日程）。
class ProposalTaskDraft {
  const ProposalTaskDraft({
    required this.title,
    this.description,
    this.estimatedMinutes,
    this.dueDate,
    this.scheduleStartAt,
    this.scheduleMinutes,
  });

  final String title;
  final String? description;
  final int? estimatedMinutes;
  final DateTime? dueDate;

  /// 非空则应用后立即给任务排日程。
  final DateTime? scheduleStartAt;
  final int? scheduleMinutes;

  Map<String, Object?> toMap() => {
        'title': title,
        'description': description,
        'estimatedMinutes': estimatedMinutes,
        'dueDate': encodeTimeOrNull(dueDate),
        'scheduleStartAt': encodeTimeOrNull(scheduleStartAt),
        'scheduleMinutes': scheduleMinutes,
      };

  factory ProposalTaskDraft.fromMap(Map<String, Object?> map) =>
      ProposalTaskDraft(
        title: map['title']! as String,
        description: map['description'] as String?,
        estimatedMinutes: map['estimatedMinutes'] as int?,
        dueDate: _optTime(map['dueDate']),
        scheduleStartAt: _optTime(map['scheduleStartAt']),
        scheduleMinutes: map['scheduleMinutes'] as int?,
      );

  static DateTime? _optTime(Object? v) =>
      v is String && v.isNotEmpty ? decodeTime(v) : null;
}

/// 提案中的阶段草稿（应用时创建 Phase + 其下任务）。
class ProposalPhaseDraft {
  const ProposalPhaseDraft({
    required this.title,
    this.description,
    this.tasks = const [],
  });

  final String title;
  final String? description;
  final List<ProposalTaskDraft> tasks;

  Map<String, Object?> toMap() => {
        'title': title,
        'description': description,
        'tasks': [for (final t in tasks) t.toMap()],
      };

  factory ProposalPhaseDraft.fromMap(Map<String, Object?> map) =>
      ProposalPhaseDraft(
        title: map['title']! as String,
        description: map['description'] as String?,
        tasks: [
          for (final t in (map['tasks'] as List? ?? const []))
            ProposalTaskDraft.fromMap(t as Map<String, Object?>),
        ],
      );
}

/// 计划提案（plan §25「结构性变化先确认」）。
///
/// AI 通过 propose_plan 工具产出提案（不直接写目标数据），
/// 用户在确认卡片上 [应用计划] / [修改]（docs/ai/prompts.md §4）。
class PlanProposal {
  const PlanProposal({
    required this.id,
    this.conversationId,
    this.goalId,
    required this.kind,
    this.goalTitle,
    this.goalDescription,
    this.targetDate,
    this.metricName,
    this.metricUnit,
    this.metricStartValue,
    this.metricTargetValue,
    this.metricDecrease = false,
    this.phases = const [],
    this.removePhaseIds = const [],
    this.removeTaskIds = const [],
    this.reason,
    this.action,
    this.status = ProposalStatus.pending,
    required this.createdAt,
    this.appliedAt,
  });

  final String id;
  final String? conversationId;

  /// adjust 提案指向的目标；create 提案为空。
  final String? goalId;
  final ProposalKind kind;

  // ── Goal 字段（create 全用；adjust 中可选更新） ────────
  final String? goalTitle;
  final String? goalDescription;
  final DateTime? targetDate;

  // ── 可选量化指标（如体重 72.5 → 67.5 kg） ──────────────
  final String? metricName;
  final String? metricUnit;
  final double? metricStartValue;
  final double? metricTargetValue;
  final bool metricDecrease;

  /// 新增的阶段（含任务草稿）。
  final List<ProposalPhaseDraft> phases;

  /// adjust：要取消的阶段（其未完成任务一并取消）。
  final List<String> removePhaseIds;

  /// adjust：要取消的单个任务。
  final List<String> removeTaskIds;

  /// 调整理由（现状 vs 建议），展示在确认卡片上。
  final String? reason;

  /// action 提案要执行的操作（ProposalActions）。
  final String? action;

  final ProposalStatus status;
  final DateTime createdAt;
  final DateTime? appliedAt;

  int get taskCount => phases.fold(0, (sum, p) => sum + p.tasks.length);

  PlanProposal copyWith({
    ProposalStatus? status,
    DateTime? appliedAt,
  }) =>
      PlanProposal(
        id: id,
        conversationId: conversationId,
        goalId: goalId,
        kind: kind,
        goalTitle: goalTitle,
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
        status: status ?? this.status,
        createdAt: createdAt,
        appliedAt: appliedAt ?? this.appliedAt,
      );

  /// 行数据（不含 payload —— 由 Repository 组装 payloadJson）。
  Map<String, Object?> toRow() => {
        'id': id,
        'conversation_id': conversationId,
        'goal_id': goalId,
        'kind': kind.name,
        'status': status.name,
        'created_at': encodeTime(createdAt),
        'applied_at': encodeTimeOrNull(appliedAt),
      };

  /// payload 部分：会随提案演进变化的内容，整体存 JSON。
  Map<String, Object?> toPayload() => {
        'goalTitle': goalTitle,
        'goalDescription': goalDescription,
        'targetDate': encodeTimeOrNull(targetDate),
        'metricName': metricName,
        'metricUnit': metricUnit,
        'metricStartValue': metricStartValue,
        'metricTargetValue': metricTargetValue,
        'metricDecrease': metricDecrease,
        'phases': [for (final p in phases) p.toMap()],
        'removePhaseIds': removePhaseIds,
        'removeTaskIds': removeTaskIds,
        'reason': reason,
        'action': action,
      };

  factory PlanProposal.fromStorage(
    Map<String, Object?> row,
    Map<String, Object?> payload,
  ) =>
      PlanProposal(
        id: row['id']! as String,
        conversationId: row['conversation_id'] as String?,
        goalId: row['goal_id'] as String?,
        kind: ProposalKind.parse(row['kind']! as String),
        goalTitle: payload['goalTitle'] as String?,
        goalDescription: payload['goalDescription'] as String?,
        targetDate: _optTime(payload['targetDate']),
        metricName: payload['metricName'] as String?,
        metricUnit: payload['metricUnit'] as String?,
        metricStartValue: (payload['metricStartValue'] as num?)?.toDouble(),
        metricTargetValue: (payload['metricTargetValue'] as num?)?.toDouble(),
        metricDecrease: payload['metricDecrease'] == true,
        phases: [
          for (final p in (payload['phases'] as List? ?? const []))
            ProposalPhaseDraft.fromMap(p as Map<String, Object?>),
        ],
        removePhaseIds: [
          for (final v in (payload['removePhaseIds'] as List? ?? const []))
            v as String,
        ],
        removeTaskIds: [
          for (final v in (payload['removeTaskIds'] as List? ?? const []))
            v as String,
        ],
        reason: payload['reason'] as String?,
        action: payload['action'] as String?,
        status: ProposalStatus.parse(row['status']! as String),
        createdAt: decodeTime(row['created_at']! as String),
        appliedAt: _optTime(row['applied_at']),
      );

  static DateTime? _optTime(Object? v) =>
      v is String && v.isNotEmpty ? decodeTime(v) : null;
}
