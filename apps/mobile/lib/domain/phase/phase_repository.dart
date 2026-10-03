import 'phase.dart';

abstract interface class PhaseRepository {
  Future<Phase> insert(Phase phase);
  Future<Phase> update(Phase phase);
  Future<Phase?> findById(String id);

  /// 按 orderIndex 升序返回某 Goal 的全部阶段。
  Future<List<Phase>> findByGoal(String goalId);

  /// 同一 Goal 内下一个可用的 orderIndex。
  Future<int> nextOrderIndex(String goalId);

  Future<void> delete(String id);
}
