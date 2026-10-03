import 'plan_proposal.dart';

abstract interface class PlanProposalRepository {
  Future<PlanProposal> insert(PlanProposal proposal);

  Future<PlanProposal?> findById(String id);

  /// 某会话下的全部提案（时间倒序）—— 聊天确认卡片渲染用。
  Future<List<PlanProposal>> findByConversation(String conversationId);

  /// 未处理的提案（全局）。
  Future<List<PlanProposal>> pending();

  /// 更新状态（应用 / 忽略 / 取代）。
  Future<void> updateStatus(String id, ProposalStatus status, {DateTime? appliedAt});
}
