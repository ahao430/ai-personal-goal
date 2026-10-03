import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../domain/planning/plan_proposal.dart';
import '../../domain/planning/plan_proposal_repository.dart';
import '../../domain/time_codec.dart';

class SqlitePlanProposalRepository implements PlanProposalRepository {
  SqlitePlanProposalRepository(this._db);

  final Database _db;

  PlanProposal _fromRow(Map<String, Object?> row) => PlanProposal.fromStorage(
        row,
        (jsonDecode(row['payload_json']! as String) as Map)
            .cast<String, Object?>(),
      );

  @override
  Future<PlanProposal> insert(PlanProposal proposal) async {
    await _db.insert('plan_proposals', {
      ...proposal.toRow(),
      'payload_json': jsonEncode(proposal.toPayload()),
    });
    return proposal;
  }

  @override
  Future<PlanProposal?> findById(String id) async {
    final rows = await _db.query(
      'plan_proposals',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  @override
  Future<List<PlanProposal>> findByConversation(String conversationId) async {
    final rows = await _db.query(
      'plan_proposals',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'created_at DESC',
    );
    return [for (final r in rows) _fromRow(r)];
  }

  @override
  Future<List<PlanProposal>> pending() async {
    final rows = await _db.query(
      'plan_proposals',
      where: 'status = ?',
      whereArgs: [ProposalStatus.pending.name],
      orderBy: 'created_at DESC',
    );
    return [for (final r in rows) _fromRow(r)];
  }

  @override
  Future<void> updateStatus(
    String id,
    ProposalStatus status, {
    DateTime? appliedAt,
  }) async {
    await _db.update(
      'plan_proposals',
      {
        'status': status.name,
        'applied_at': appliedAt == null ? null : encodeTime(appliedAt),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
