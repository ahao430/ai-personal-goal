import '../time_codec.dart';

/// AI 会话（plan §36 conversations）。goalId 为空表示全局对话。
class Conversation {
  const Conversation({
    required this.id,
    this.goalId,
    this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String? goalId;
  final String? title;

  final DateTime createdAt;
  final DateTime updatedAt;

  Conversation copyWith({String? title, DateTime? updatedAt}) => Conversation(
        id: id,
        goalId: goalId,
        title: title ?? this.title,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'goal_id': goalId,
        'title': title,
        'created_at': encodeTime(createdAt),
        'updated_at': encodeTime(updatedAt),
      };

  factory Conversation.fromMap(Map<String, Object?> map) => Conversation(
        id: map['id']! as String,
        goalId: map['goal_id'] as String?,
        title: map['title'] as String?,
        createdAt: decodeTime(map['created_at']! as String),
        updatedAt: decodeTime(map['updated_at']! as String),
      );
}

/// 会话消息。role：user / assistant / activity（工具活动，仅本地展示，
/// 不回放给模型）。assistant 消息可挂 [proposalId]（P5 计划提案卡片）。
class ConversationMessage {
  const ConversationMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.proposalId,
  });

  final String id;
  final String conversationId;
  final String role;
  final String content;
  final DateTime createdAt;

  /// 关联的计划提案（渲染确认卡片用；不影响模型侧回放）。
  final String? proposalId;

  Map<String, Object?> toMap() => {
        'id': id,
        'conversation_id': conversationId,
        'role': role,
        'content': content,
        'proposal_id': proposalId,
        'created_at': encodeTime(createdAt),
      };

  factory ConversationMessage.fromMap(Map<String, Object?> map) =>
      ConversationMessage(
        id: map['id']! as String,
        conversationId: map['conversation_id']! as String,
        role: map['role']! as String,
        content: map['content']! as String,
        proposalId: map['proposal_id'] as String?,
        createdAt: decodeTime(map['created_at']! as String),
      );
}
