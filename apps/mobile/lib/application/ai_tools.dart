import '../domain/goal/goal.dart';
import '../domain/goal/goal_metric.dart';
import '../domain/phase/phase.dart';
import '../domain/planning/plan_proposal.dart';
import '../domain/progress/progress_event.dart';
import '../domain/task/task.dart';
import 'app_services.dart';
import 'tool_registry.dart';

// ── schema / 参数辅助 ────────────────────────────────────

Map<String, Object?> _obj(
  Map<String, Object?> properties, [
  List<String> required = const [],
]) =>
    {
      'type': 'object',
      'properties': properties,
      if (required.isNotEmpty) 'required': required,
    };

Map<String, Object?> _arr(
  Map<String, Object?> items, [
  String? desc,
]) =>
    {'type': 'array', 'items': items, 'description': ?desc};

Map<String, Object?> _s([String? desc]) =>
    {'type': 'string', 'description': ?desc};
Map<String, Object?> _num([String? desc]) =>
    {'type': 'number', 'description': ?desc};
Map<String, Object?> _int([String? desc]) =>
    {'type': 'integer', 'description': ?desc};

String? _str(Map args, String key) {
  final v = args[key];
  if (v is String && v.trim().isNotEmpty) return v.trim();
  return null;
}

double? _numV(Map args, String key) {
  final v = args[key];
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

int? _intV(Map args, String key) {
  final v = args[key];
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

DateTime? _dateV(Map args, String key) {
  final s = _str(args, key);
  return s == null ? null : DateTime.tryParse(s)?.toLocal();
}

DateTime _reqDate(Map args, String key) {
  final d = _dateV(args, key);
  if (d == null) {
    throw ArgumentError('$key 需要是合法时间（ISO 8601，如 2026-10-04T19:00:00）');
  }
  return d;
}

String _req(Map args, String key) {
  final v = _str(args, key);
  if (v == null) throw ArgumentError('$key 不能为空');
  return v;
}

// ── 领域序列化（保持上下文紧凑） ────────────────────────

Map<String, Object?> _goalJson(Goal g) => {
      'id': g.id,
      'title': g.title,
      'status': g.status.name,
      'progress': g.overallProgress.round(),
      'description': ?g.description,
      'targetDate': ?g.targetDate?.toIso8601String(),
    };

Map<String, Object?> _phaseJson(Phase p) => {
      'id': p.id,
      'goalId': p.goalId,
      'title': p.title,
      'status': p.status.name,
      'orderIndex': p.orderIndex,
    };

Map<String, Object?> _taskJson(Task t) => {
      'id': t.id,
      'title': t.title,
      'status': t.status.name,
      'phaseId': ?t.phaseId,
      'dueDate': ?t.dueDate?.toIso8601String(),
      'estimatedMinutes': ?t.estimatedMinutes,
    };

Map<String, Object?> _metricJson(GoalMetric m) => {
      'id': m.id,
      'goalId': m.goalId,
      'name': m.name,
      'currentValue': m.currentValue,
      'targetValue': m.targetValue,
      'unit': ?m.unit,
      'direction': m.direction.name,
    };

Map<String, Object?> _eventJson(ProgressEvent e) => {
      'type': e.type.columnName,
      'source': e.source.name,
      'time': e.time.toIso8601String(),
      'message': ?e.message,
    };

/// 首批 Agent 工具（plan §19）：Goal / Phase / Task / Schedule / Progress / Metric。
/// 全部包装 P1 的 Application 用例 —— 工具不直接碰 Repository。
ToolRegistry buildGoalTools(AppServices s) => ToolRegistry([
      // ── Goal ─────────────────────────────────────────
      AgentTool(
        name: 'get_goals',
        description: '获取用户的目标列表（可选状态过滤 active/paused/completed/cancelled/archived）',
        parametersSchema: _obj({'status': _s('目标状态，缺省返回全部')}),
        handler: (args, ctx) async {
          final status = _str(args, 'status');
          final goals = await s.goals.findAll();
          return {
            'goals': [
              for (final g in goals)
                if (status == null || g.status.name == status) _goalJson(g),
            ],
          };
        },
      ),
      AgentTool(
        name: 'create_goal',
        description: '创建目标。title 必填；targetDate 用 ISO 8601',
        parametersSchema: _obj({
          'title': _s('目标标题'),
          'description': _s('补充描述'),
          'targetDate': _s('目标日期，如 2026-12-31'),
        }, ['title']),
        handler: (args, ctx) async {
          final goal = await s.goalService.createGoal(
            title: _req(args, 'title'),
            description: _str(args, 'description'),
            targetDate: _dateV(args, 'targetDate'),
          );
          return {'goal': _goalJson(goal)};
        },
      ),
      AgentTool(
        name: 'update_goal',
        description: '更新目标字段（只传需要修改的）',
        parametersSchema: _obj({
          'goalId': _s('目标 ID'),
          'title': _s('新标题'),
          'description': _s('新描述，传空字符串可清除'),
          'targetDate': _s('新目标日期'),
        }, ['goalId']),
        handler: (args, ctx) async {
          final goal = await s.goalService.updateGoal(
            args['goalId'] as String,
            (g) => g.copyWith(
              title: _str(args, 'title') ?? g.title,
              description: args['description'] is String &&
                      (args['description'] as String).isEmpty
                  ? null
                  : (_str(args, 'description') ?? g.description),
              targetDate: _dateV(args, 'targetDate') ?? g.targetDate,
            ),
          );
          return {'goal': _goalJson(goal)};
        },
      ),
      AgentTool(
        name: 'pause_goal',
        description: '暂停目标',
        parametersSchema: _obj({
          'goalId': _s('目标 ID'),
          'reason': _s('暂停原因'),
        }, ['goalId']),
        handler: (args, ctx) async {
          final g = await s.goalService.pauseGoal(
            args['goalId'] as String,
            reason: _str(args, 'reason'),
          );
          return {'goal': _goalJson(g)};
        },
      ),
      AgentTool(
        name: 'resume_goal',
        description: '恢复已暂停的目标',
        parametersSchema: _obj({'goalId': _s('目标 ID')}, ['goalId']),
        handler: (args, ctx) async =>
            {'goal': _goalJson(await s.goalService.resumeGoal(args['goalId'] as String))},
      ),
      AgentTool(
        name: 'complete_goal',
        description: '标记目标完成（重大操作，仅在用户明确表达后调用）',
        parametersSchema: _obj({'goalId': _s('目标 ID')}, ['goalId']),
        handler: (args, ctx) async =>
            {'goal': _goalJson(await s.goalService.completeGoal(args['goalId'] as String))},
      ),

      // ── Phase ────────────────────────────────────────
      AgentTool(
        name: 'get_phases',
        description: '获取某目标的阶段列表（按顺序）',
        parametersSchema: _obj({'goalId': _s('目标 ID')}, ['goalId']),
        handler: (args, ctx) async => {
              'phases': [
                for (final p
                    in await s.phases.findByGoal(args['goalId'] as String))
                  _phaseJson(p),
              ],
            },
      ),
      AgentTool(
        name: 'create_phase',
        description: '为目标追加阶段（自动排到末尾）',
        parametersSchema: _obj({
          'goalId': _s('目标 ID'),
          'title': _s('阶段名'),
          'description': _s('阶段说明'),
        }, ['goalId', 'title']),
        handler: (args, ctx) async {
          final phase = await s.planningService.createPhase(
            goalId: args['goalId'] as String,
            title: _req(args, 'title'),
            description: _str(args, 'description'),
          );
          return {'phase': _phaseJson(phase)};
        },
      ),

      // ── Task ─────────────────────────────────────────
      AgentTool(
        name: 'get_tasks',
        description: '获取目标下（或全部）的未完成任务，含今日日程',
        parametersSchema: _obj({
          'goalId': _s('目标 ID，缺省查全部目标'),
        }),
        handler: (args, ctx) async {
          final goalId = _str(args, 'goalId');
          final tasks = goalId == null
              ? (await s.overview.homeView()).today.items.map((i) => i.task).toList()
              : await s.tasks.findByGoal(goalId);
          final open = tasks
              .where((t) =>
                  t.status != TaskStatus.completed &&
                  t.status != TaskStatus.cancelled)
              .take(20);
          return {'tasks': [for (final t in open) _taskJson(t)]};
        },
      ),
      AgentTool(
        name: 'create_task',
        description: '创建任务。给了 phaseId 自动归属该阶段；否则给 goalId',
        parametersSchema: _obj({
          'title': _s('任务标题'),
          'goalId': _s('目标 ID（无 phaseId 时必填）'),
          'phaseId': _s('阶段 ID'),
          'description': _s('任务说明'),
          'dueDate': _s('截止时间，ISO 8601'),
          'estimatedMinutes': _int('预计分钟数'),
        }, ['title']),
        handler: (args, ctx) async {
          final task = await s.planningService.createTask(
            title: _req(args, 'title'),
            goalId: _str(args, 'goalId'),
            phaseId: _str(args, 'phaseId'),
            description: _str(args, 'description'),
            dueDate: _dateV(args, 'dueDate'),
            estimatedMinutes: _intV(args, 'estimatedMinutes'),
          );
          return {'task': _taskJson(task)};
        },
      ),
      AgentTool(
        name: 'complete_task',
        description: '完成任务（自动记录完成时间并更新目标进度）',
        parametersSchema: _obj({'taskId': _s('任务 ID')}, ['taskId']),
        handler: (args, ctx) async =>
            {'task': _taskJson(await s.planningService.completeTask(args['taskId'] as String))},
      ),
      AgentTool(
        name: 'postpone_task',
        description: '延期任务，可选给新时间',
        parametersSchema: _obj({
          'taskId': _s('任务 ID'),
          'to': _s('新的时间，ISO 8601，如 2026-10-04T19:00:00'),
        }, ['taskId']),
        handler: (args, ctx) async => {
              'task': _taskJson(await s.planningService.postponeTask(
                args['taskId'] as String,
                to: _dateV(args, 'to'),
              )),
            },
      ),
      AgentTool(
        name: 'cancel_task',
        description: '取消任务（进度分母会剔除）',
        parametersSchema: _obj({'taskId': _s('任务 ID')}, ['taskId']),
        handler: (args, ctx) async =>
            {'task': _taskJson(await s.planningService.cancelTask(args['taskId'] as String))},
      ),

      // ── Schedule ─────────────────────────────────────
      AgentTool(
        name: 'schedule_task',
        description: '给任务安排开始时间（可带预计时长）',
        parametersSchema: _obj({
          'taskId': _s('任务 ID'),
          'startAt': _s('开始时间，ISO 8601，如 2026-10-04T19:00:00'),
          'durationMinutes': _int('预计分钟数'),
        }, ['taskId', 'startAt']),
        handler: (args, ctx) async {
          final schedule = await s.planningService.scheduleTask(
            args['taskId'] as String,
            startAt: _reqDate(args, 'startAt'),
            durationMinutes: _intV(args, 'durationMinutes'),
          );
          return {'schedule': {
            'id': schedule.id,
            'startAt': schedule.startAt.toIso8601String(),
            if (schedule.durationMinutes != null)
              'durationMinutes': schedule.durationMinutes,
          }};
        },
      ),
      AgentTool(
        name: 'reschedule_task',
        description: '改期：取消旧安排并落新时间',
        parametersSchema: _obj({
          'taskId': _s('任务 ID'),
          'newStartAt': _s('新的开始时间，ISO 8601'),
          'durationMinutes': _int('预计分钟数'),
        }, ['taskId', 'newStartAt']),
        handler: (args, ctx) async {
          final schedule = await s.planningService.rescheduleTask(
            args['taskId'] as String,
            newStartAt: _reqDate(args, 'newStartAt'),
            durationMinutes: _intV(args, 'durationMinutes'),
          );
          return {'schedule': {
            'id': schedule.id,
            'startAt': schedule.startAt.toIso8601String(),
          }};
        },
      ),

      // ── Progress ─────────────────────────────────────
      AgentTool(
        name: 'get_progress',
        description: '获取某目标（或全局）最近的进度事件',
        parametersSchema: _obj({'goalId': _s('目标 ID，缺省查全局')}),
        handler: (args, ctx) async {
          final goalId = _str(args, 'goalId');
          final events = goalId == null
              ? await s.progressEvents.recent(limit: 10)
              : await s.progressEvents.findByGoal(goalId, limit: 10);
          return {'events': [for (final e in events) _eventJson(e)]};
        },
      ),
      AgentTool(
        name: 'user_report',
        description: '记录用户的自由汇报（如「今天快走完成了」）',
        parametersSchema: _obj({
          'goalId': _s('目标 ID'),
          'message': _s('汇报内容'),
          'taskId': _s('相关任务 ID（可选）'),
        }, ['message']),
        handler: (args, ctx) async {
          final goalId = _str(args, 'goalId');
          final event = await s.planningService.recordUserReport(
            goalId ?? '',
            _req(args, 'message'),
            taskId: _str(args, 'taskId'),
          );
          return {'recorded': true, 'eventId': event.id};
        },
      ),

      // ── Metric ───────────────────────────────────────
      AgentTool(
        name: 'get_metrics',
        description: '获取某目标的量化指标（如体重）',
        parametersSchema: _obj({'goalId': _s('目标 ID')}, ['goalId']),
        handler: (args, ctx) async => {
              'metrics': [
                for (final m
                    in await s.metrics.findByGoal(args['goalId'] as String))
                  _metricJson(m),
              ],
            },
      ),
      AgentTool(
        name: 'record_metric_value',
        description: '记录指标的新数值（如当前体重），会推进当前值',
        parametersSchema: _obj({
          'goalId': _s('目标 ID'),
          'metricName': _s('指标名，如「体重」'),
          'value': _num('新数值'),
        }, ['goalId', 'metricName', 'value']),
        handler: (args, ctx) async {
          final goalId = args['goalId'] as String;
          final name = _req(args, 'metricName');
          final value = _numV(args, 'value');
          if (value == null) throw ArgumentError('value 需要是数字');
          final metrics = await s.metrics.findByGoal(goalId);
          final metric = metrics.where((m) => m.name == name).firstOrNull;
          if (metric == null) {
            throw ArgumentError('目标下没有名为「$name」的指标，可先用 get_metrics 查看或提示用户创建');
          }
          final updated = await s.goalService.recordMetricValue(metric.id, value);
          return {'metricName': name, 'currentValue': updated};
        },
      ),

      // ── Progress Analysis（P6）─────────────────────────
      AgentTool(
        name: 'analyze_progress',
        description: '聚合分析某目标的执行情况：完成率、近 14 天延期/完成频次、'
            '逾期任务数、指标趋势、近期事件。用户问近况 / 进度 / 是否落后 / '
            '要不要调整计划时，先用本工具拿事实，再做偏差诊断。',
        parametersSchema: _obj({'goalId': _s('目标 ID')}, ['goalId']),
        handler: (args, ctx) async {
          final goalId = _str(args, 'goalId') ?? ctx.goalId;
          if (goalId == null) throw ArgumentError('需要 goalId');
          final a = await s.analysisService.analyze(goalId);
          return {
            'goal': {
              'id': a.goal.id,
              'title': a.goal.title,
              'status': a.goal.status.name,
              'progress': a.goal.overallProgress.round(),
              if (a.goal.targetDate != null)
                'targetDate': a.goal.targetDate!.toIso8601String(),
            },
            'taskStats': {
              'total': a.tasksTotal,
              'completed': a.tasksCompleted,
              'cancelled': a.tasksCancelled,
              'overdue': a.tasksOverdue,
              if (a.completionRate != null) 'completionRate': a.completionRate,
              'postponedLast14d': a.postponedRecent,
              'completedLast14d': a.completedRecent,
              if (a.postponeRate != null) 'postponeRate': a.postponeRate,
            },
            'metricTrends': [
              for (final t in a.metricTrends)
                {
                  'name': t.name,
                  'current': t.current,
                  'target': t.target,
                  if (t.unit != null) 'unit': t.unit,
                  'samplesLast14d': t.samples,
                  if (t.delta != null) 'delta': t.delta,
                  'improving': t.improved,
                },
            ],
            'recentEvents': [
              for (final e in a.recentEvents)
                {'type': e.type.columnName, 'time': e.time.toIso8601String(), 'message': e.message},
            ],
            'hasSignals': a.hasSignals,
          };
        },
      ),

      // ── Plan Proposal（P5）─────────────────────────────
      AgentTool(
        name: 'propose_plan',
        description: '生成计划提案（不写库，等用户在确认卡片上点「应用计划」后才生效）。'
            '新目标的全套规划（Goal+指标+Phase+Task+Schedule）和结构性调整'
            '（重新规划/缩小目标/延期超过 7 天/阶段大改/批量删任务）都必须走本工具，'
            '不要用 create_goal + create_phase + create_task 逐个拼。',
        parametersSchema: _obj({
          'kind': _s('create=规划新目标；adjust=调整现有目标'),
          'goalId': _s('adjust 必填的目标 ID'),
          'title': _s('目标标题（create 必填）'),
          'description': _s('目标描述'),
          'targetDate': _s('目标日期 ISO 8601（adjust 中表示新的截止日期）'),
          'metric': _obj({
            'name': _s('指标名，如 体重'),
            'unit': _s('单位，如 kg'),
            'startValue': _num('当前值'),
            'targetValue': _num('目标值'),
            'direction': _s('increase（越高越好）或 decrease（越低越好）'),
          }),
          'phases': _arr(_obj({
            'title': _s('阶段名'),
            'description': _s('阶段完成判据'),
            'tasks': _arr(_obj({
              'title': _s('任务标题，用户当天能做完的具体动作'),
              'estimatedMinutes': _int('预计分钟数'),
              'dueDate': _s('截止时间 ISO 8601'),
              'startAt': _s('日程开始时间 ISO 8601（需要排进日程时给）'),
              'durationMinutes': _int('日程时长分钟数'),
            }), '阶段下展开的任务（只展开当前阶段，后续阶段留空即可）'),
          }), '阶段列表，3-6 个，每个有明确完成判据'),
          'removePhaseIds': _arr(
            {'type': 'string'},
            'adjust：要取消的阶段 ID 列表（其未完成任务一并取消）',
          ),
          'removeTaskIds': _arr(
            {'type': 'string'},
            'adjust：要取消的任务 ID 列表',
          ),
          'reason': _s('调整理由（现状 vs 建议），会展示给用户'),
        }, ['kind']),
        handler: (args, ctx) async {
          final kind = ProposalKind.parse(_req(args, 'kind'));
          final metric = args['metric'] is Map ? args['metric'] as Map : null;
          final phases = <ProposalPhaseDraft>[
            for (final p in (args['phases'] as List? ?? const []))
              ProposalPhaseDraft(
                title: (p as Map)['title'] as String? ?? '',
                description: p['description'] as String?,
                tasks: [
                  for (final t in (p['tasks'] as List? ?? const []))
                    ProposalTaskDraft(
                      title: (t as Map)['title'] as String? ?? '',
                      description: t['description'] as String?,
                      estimatedMinutes: _intV(t, 'estimatedMinutes'),
                      dueDate: _dateV(t, 'dueDate'),
                      scheduleStartAt: _dateV(t, 'startAt'),
                      scheduleMinutes: _intV(t, 'durationMinutes'),
                    ),
                ],
              ),
          ].where((p) => p.title.trim().isNotEmpty).toList();

          final proposal = await s.proposalService.create(
            conversationId: ctx.conversationId,
            goalId: _str(args, 'goalId') ?? ctx.goalId,
            kind: kind,
            goalTitle: _str(args, 'title'),
            goalDescription: _str(args, 'description'),
            targetDate: _dateV(args, 'targetDate'),
            metricName: metric == null ? null : _str(metric, 'name'),
            metricUnit: metric == null ? null : _str(metric, 'unit'),
            metricStartValue: metric == null ? null : _numV(metric, 'startValue'),
            metricTargetValue: metric == null ? null : _numV(metric, 'targetValue'),
            metricDecrease:
                metric != null && _str(metric, 'direction') == 'decrease',
            phases: phases,
            removePhaseIds: [
              for (final v in (args['removePhaseIds'] as List? ?? const []))
                v as String,
            ],
            removeTaskIds: [
              for (final v in (args['removeTaskIds'] as List? ?? const []))
                v as String,
            ],
            reason: _str(args, 'reason'),
          );
          return {
            'proposalId': proposal.id,
            'status': proposal.status.name,
            'hint': '提案已生成并展示为确认卡片，等待用户选择「应用计划」或「修改」；'
                '在用户确认前不要重复创建',
          };
        },
      ),

      // ── Action Confirmation（P6）──────────────────────
      AgentTool(
        name: 'propose_action',
        description: '提出需要二次确认的目标级操作（暂停/恢复/取消/归档目标），'
            '生成是/否确认卡片，用户点确认后才执行。用户表达「不想做了 / 太累了 / '
            '先放一放 / 做完了收尾」等意图时走本工具，不要直接调用 pause_goal 等。',
        parametersSchema: _obj({
          'action': _s('pause_goal=暂停 / resume_goal=恢复 / cancel_goal=取消 / archive_goal=归档'),
          'goalId': _s('目标 ID'),
          'reason': _s('原因或说明，展示在确认卡片上'),
        }, ['action', 'goalId']),
        handler: (args, ctx) async {
          final goalId = _str(args, 'goalId') ?? ctx.goalId;
          if (goalId == null) throw ArgumentError('需要 goalId');
          final proposal = await s.proposalService.create(
            conversationId: ctx.conversationId,
            goalId: goalId,
            kind: ProposalKind.action,
            action: _str(args, 'action'),
            reason: _str(args, 'reason'),
          );
          return {
            'proposalId': proposal.id,
            'status': proposal.status.name,
            'hint': '确认卡片已生成，等待用户点「确认」或「取消」',
          };
        },
      ),

      // ── Web Search（P8）────────────────────────────────
      AgentTool(
        name: 'web_search',
        description: '联网搜索（需要外部信息时用：考试时间 / 旅行信息 / 最新资料 / '
            '价格政策等）。个人任务、不需要外部事实的请求不要调用。'
            '回复中引用搜索结论时必须列出来源（标题 + 链接）。',
        parametersSchema: _obj({
          'query': _s('搜索关键词（具体、含关键实体，如「2026 年 12 月 N2 考试时间」）'),
          'maxResults': _int('返回条数，默认 5，最多 8'),
        }, ['query']),
        handler: (args, ctx) async {
          final query = _req(args, 'query');
          final maxResults = (_intV(args, 'maxResults') ?? 5).clamp(1, 8);
          final (results, provider) =
              await s.searchService.search(query, maxResults: maxResults);
          return {
            'provider': provider,
            'results': [for (final r in results) r.toJson()],
            'hint': '引用这些结论时在回复末尾列出「参考来源：标题 (URL)」；'
                '需要更详细内容可用 fetch_web_page 抓取具体链接',
          };
        },
      ),
      AgentTool(
        name: 'fetch_web_page',
        description: '抓取网页正文（去标签纯文本，截断到 4000 字符）。'
            '在 web_search 结果需要更详细内容时使用，或用户明确给了链接时。',
        parametersSchema: _obj({
          'url': _s('网页 URL（http/https）'),
        }, ['url']),
        handler: (args, ctx) async {
          final url = _req(args, 'url');
          final content = await s.searchService.fetchPage(url);
          return {'url': url, 'content': content};
        },
      ),
    ]);