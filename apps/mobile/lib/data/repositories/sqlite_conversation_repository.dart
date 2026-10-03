import 'package:sqflite/sqflite.dart';

import '../../domain/ai/conversation.dart';
import '../../domain/ai/conversation_repository.dart';
import '../../domain/entity_ids.dart';

class SqliteConversationRepository implements ConversationRepository {
  SqliteConversationRepository(this._db);

  final Database _db;

  @override
  Future<Conversation> create({String? goalId, String? title}) async {
    final now = DateTime.now();
    final conversation = Conversation(
      id: 'conv_${EntityIds.newGoalId().substring(5)}',
      goalId: goalId,
      title: title,
      createdAt: now,
      updatedAt: now,
    );
    await _db.insert('conversations', conversation.toMap());
    return conversation;
  }

  @override
  Future<Conversation?> findById(String id) async {
    final rows = await _db.query(
      'conversations',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Conversation.fromMap(rows.first);
  }

  @override
  Future<List<Conversation>> recent({int limit = 20}) async {
    final rows = await _db.query(
      'conversations',
      orderBy: 'updated_at DESC',
      limit: limit,
    );
    return rows.map(Conversation.fromMap).toList();
  }

  @override
  Future<void> appendMessage(
    String conversationId, {
    required String role,
    required String content,
    String? proposalId,
  }) async {
    final now = DateTime.now();
    await _db.transaction((txn) async {
      await txn.insert('conversation_messages', {
        'id': 'msg_${EntityIds.newGoalId().substring(5)}',
        'conversation_id': conversationId,
        'role': role,
        'content': content,
        'proposal_id': proposalId,
        'created_at': now.toUtc().toIso8601String(),
      });
      await txn.update(
        'conversations',
        {'updated_at': now.toUtc().toIso8601String()},
        where: 'id = ?',
        whereArgs: [conversationId],
      );
    });
  }

  @override
  Future<List<ConversationMessage>> messages(String conversationId,
      {int limit = 200}) async {
    final rows = await _db.query(
      'conversation_messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows.map(ConversationMessage.fromMap).toList();
  }

  @override
  Future<void> delete(String id) async {
    await _db.delete('conversations', where: 'id = ?', whereArgs: [id]);
  }
}
