import 'package:sqflite/sqflite.dart';

import '../../domain/ai/ai_model_info.dart';
import '../../domain/ai/ai_provider.dart';
import '../../domain/ai/ai_provider_repository.dart';

class SqliteAiProviderRepository implements AiProviderRepository {
  SqliteAiProviderRepository(this._db);

  final Database _db;

  @override
  Future<AiProvider> insert(AiProvider provider) async {
    await _db.insert('ai_providers', provider.toMap());
    return provider;
  }

  @override
  Future<AiProvider> update(AiProvider provider) async {
    final updated = provider.copyWith(updatedAt: DateTime.now());
    final count = await _db.update(
      'ai_providers',
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [provider.id],
    );
    if (count == 0) {
      throw StateError('AiProvider 不存在: ${provider.id}');
    }
    return updated;
  }

  @override
  Future<AiProvider?> findById(String id) async {
    final rows = await _db.query(
      'ai_providers',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : AiProvider.fromMap(rows.first);
  }

  @override
  Future<List<AiProvider>> findAll({bool? enabled}) async {
    final rows = await _db.query(
      'ai_providers',
      where: enabled == null ? null : 'enabled = ?',
      whereArgs: enabled == null ? null : [enabled ? 1 : 0],
      orderBy: 'created_at ASC',
    );
    return rows.map(AiProvider.fromMap).toList();
  }

  @override
  Future<void> delete(String id) async {
    // ai_models 经外键级联删除。
    await _db.delete('ai_providers', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<List<AiModelInfo>> replaceFetchedModels(
    String providerId,
    List<AiModelInfo> fetched,
  ) async {
    await _db.transaction((txn) async {
      // 只清掉上一次拉取的结果；manual 条目保留。
      await txn.delete(
        'ai_models',
        where: 'provider_id = ? AND source = ?',
        whereArgs: [providerId, AiModelSource.fetched.name],
      );
      for (final model in fetched) {
        // 同名 manual 条目已存在时忽略插入（manual 优先）。
        await txn.insert(
          'ai_models',
          model.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
    return modelsOfProvider(providerId);
  }

  @override
  Future<List<AiModelInfo>> modelsOfProvider(String providerId) async {
    final rows = await _db.query(
      'ai_models',
      where: 'provider_id = ?',
      whereArgs: [providerId],
      orderBy: 'source DESC, model_id ASC',
    );
    return rows.map(AiModelInfo.fromMap).toList();
  }

  @override
  Future<AiModelInfo> addManualModel(AiModelInfo model) async {
    await _db.insert(
      'ai_models',
      model.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return model;
  }

  @override
  Future<void> deleteModel(String providerId, String modelId) async {
    await _db.delete(
      'ai_models',
      where: 'provider_id = ? AND model_id = ?',
      whereArgs: [providerId, modelId],
    );
  }
}
