import 'dart:convert';

import '../domain/goal/goal_repository.dart';
import '../domain/phase/phase_repository.dart';
import '../domain/task/task_repository.dart';
import 'app_services.dart';

/// 按需构建 AI 上下文（plan §20 / docs/ai/prompts.md §3）。
///
/// 不倾倒全库：全局场景给目标摘要；目标场景给该目标的
/// 开放任务 / 指标 / 最近事件。输出紧凑 JSON 字符串。
class ContextBuilder {
  ContextBuilder(this._services);

  final AppServices _services;

  GoalRepository get _goals => _services.goals;
  PhaseRepository get _phases => _services.phases;
  TaskRepository get _tasks => _services.tasks;

  Future<String> build({String? goalId, String scene = 'chat'}) async {
    final now = DateTime.now();
    final map = <String, Object?>{
      'now': now.toIso8601String(),
      'scene': scene,
    };

    // Context Adapter（P9）：已授权外部源的上下文片段（天气等），
    // 失败/未授权静默跳过。
    final external = await _services.externalService.buildExternalContext(
      now: now,
    );
    if (external != null) map['external'] = external;

    final active = await _goals.findAll(); // 按 updated_at DESC
    final activeGoals = active.where((g) => g.status.name == 'active').take(5);
    map['goals'] = [
      for (final g in activeGoals)
        {
          'id': g.id,
          'title': g.title,
          'progress': g.overallProgress.round(),
          if (g.targetDate != null) 'targetDate': g.targetDate!.toIso8601String(),
        },
    ];

    if (goalId != null) {
      final goal = active.where((g) => g.id == goalId).firstOrNull ??
          await _goals.findById(goalId);
      if (goal != null) {
        map['current_goal'] = {
          'id': goal.id,
          'title': goal.title,
          'status': goal.status.name,
          'progress': goal.overallProgress.round(),
          if (goal.description != null) 'description': goal.description,
          if (goal.targetDate != null)
            'targetDate': goal.targetDate!.toIso8601String(),
        };

        final phases = await _phases.findByGoal(goalId);
        map['phases'] = [
          for (final p in phases.take(8))
            {
              'id': p.id,
              'title': p.title,
              'status': p.status.name,
            },
        ];

        final tasks = await _tasks.findByGoal(goalId);
        final open = tasks
            .where((t) =>
                t.status.name != 'completed' && t.status.name != 'cancelled')
            .take(10);
        map['open_tasks'] = [
          for (final t in open)
            {
              'id': t.id,
              'title': t.title,
              'status': t.status.name,
              if (t.dueDate != null) 'due': t.dueDate!.toIso8601String(),
            },
        ];

        map['metrics'] = [
          for (final m in await _services.metrics.findByGoal(goalId))
            {
              'name': m.name,
              'current': m.currentValue,
              'target': m.targetValue,
              if (m.unit != null) 'unit': m.unit,
            },
        ];

        map['recent_events'] = [
          for (final e
              in await _services.progressEvents.findByGoal(goalId, limit: 5))
            {'type': e.type.columnName, 'message': e.message},
        ];
      }
    }

    return jsonEncode(map);
  }
}
