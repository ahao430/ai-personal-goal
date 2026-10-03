import 'conversation.dart';

abstract interface class ConversationRepository {
  Future<Conversation> create({String? goalId, String? title});

  Future<Conversation?> findById(String id);

  /// 最近会话（按更新时间倒序）。
  Future<List<Conversation>> recent({int limit = 20});

  Future<void> appendMessage(
    String conversationId, {
    required String role,
    required String content,
    String? proposalId,
  });

  /// 全量消息（含 activity），按时间升序 —— UI 展示用。
  Future<List<ConversationMessage>> messages(String conversationId,
      {int limit = 200});

  Future<void> delete(String id);
}
