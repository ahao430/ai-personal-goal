/// 数据库 Schema 迁移。
///
/// 规则：
/// - 每个版本对应一个 [SchemaMigration]，只追加、不修改已发布的版本。
/// - 升级路径 = 依次执行 version ∈ (from, to] 的迁移。
/// - 实体 ID 均为带前缀 UUID 字符串；时间列统一存 UTC ISO8601 文本。
class SchemaMigration {
  const SchemaMigration({required this.version, required this.statements});

  final int version;
  final List<String> statements;
}

/// Schema v1：V1 核心领域表（Goal / Phase / Task / Schedule /
/// ProgressEvent / GoalMetric）。
///
/// conversations、AI provider 配置、data sources、notifications 等表
/// 随后续 Phase（P3+）在 v2+ 迁移中追加 —— 架构支持未来，代码只实现当前。
const List<SchemaMigration> schemaMigrations = [
  SchemaMigration(version: 1, statements: [
    // ── goals ──────────────────────────────────────────────
    '''
    CREATE TABLE goals (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      description TEXT,
      status TEXT NOT NULL DEFAULT 'active',
      start_date TEXT,
      target_date TEXT,
      overall_progress REAL NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    // ── phases ─────────────────────────────────────────────
    '''
    CREATE TABLE phases (
      id TEXT PRIMARY KEY,
      goal_id TEXT NOT NULL REFERENCES goals(id) ON DELETE CASCADE,
      title TEXT NOT NULL,
      description TEXT,
      status TEXT NOT NULL DEFAULT 'todo',
      order_index INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    'CREATE INDEX idx_phases_goal ON phases(goal_id, order_index)',
    // ── tasks ──────────────────────────────────────────────
    '''
    CREATE TABLE tasks (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      description TEXT,
      phase_id TEXT REFERENCES phases(id) ON DELETE SET NULL,
      status TEXT NOT NULL DEFAULT 'todo',
      priority TEXT NOT NULL DEFAULT 'medium',
      estimated_minutes INTEGER,
      due_date TEXT,
      completed_at TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    'CREATE INDEX idx_tasks_phase ON tasks(phase_id)',
    'CREATE INDEX idx_tasks_due ON tasks(due_date)',
    // ── goal_tasks：Task 与 Goal 多对多（跨目标共享任务）──
    '''
    CREATE TABLE goal_tasks (
      goal_id TEXT NOT NULL REFERENCES goals(id) ON DELETE CASCADE,
      task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
      is_primary INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      PRIMARY KEY (goal_id, task_id)
    )
    ''',
    'CREATE INDEX idx_goal_tasks_task ON goal_tasks(task_id)',
    // ── schedules ──────────────────────────────────────────
    '''
    CREATE TABLE schedules (
      id TEXT PRIMARY KEY,
      task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
      start_at TEXT NOT NULL,
      end_at TEXT,
      duration_minutes INTEGER,
      status TEXT NOT NULL DEFAULT 'planned',
      note TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    'CREATE INDEX idx_schedules_task ON schedules(task_id, start_at)',
    'CREATE INDEX idx_schedules_start ON schedules(start_at)',
    // ── goal_metrics / metric_values ───────────────────────
    '''
    CREATE TABLE goal_metrics (
      id TEXT PRIMARY KEY,
      goal_id TEXT NOT NULL REFERENCES goals(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      unit TEXT,
      kind TEXT NOT NULL DEFAULT 'numeric',
      current_value REAL,
      target_value REAL,
      direction TEXT NOT NULL DEFAULT 'increase',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    'CREATE INDEX idx_goal_metrics_goal ON goal_metrics(goal_id)',
    '''
    CREATE TABLE metric_values (
      id TEXT PRIMARY KEY,
      metric_id TEXT NOT NULL REFERENCES goal_metrics(id) ON DELETE CASCADE,
      value REAL NOT NULL,
      recorded_at TEXT NOT NULL,
      source TEXT,
      note TEXT
    )
    ''',
    'CREATE INDEX idx_metric_values_metric ON metric_values(metric_id, recorded_at)',
    // ── progress_events ────────────────────────────────────
    '''
    CREATE TABLE progress_events (
      id TEXT PRIMARY KEY,
      goal_id TEXT,
      task_id TEXT,
      type TEXT NOT NULL,
      time TEXT NOT NULL,
      source TEXT NOT NULL,
      message TEXT,
      data TEXT,
      created_at TEXT NOT NULL
    )
    ''',
    'CREATE INDEX idx_progress_events_goal ON progress_events(goal_id, time)',
    'CREATE INDEX idx_progress_events_task ON progress_events(task_id, time)',
  ]),

  /// Schema v2：AI 供应商管理（P3 供应商部分）。
  ///
  /// - ai_providers：用户配置的多个供应商（模板预填或完全自定义）
  /// - ai_models：每供应商的模型缓存（一键拉取 + 手动补录）
  /// - settings：全局键值偏好（默认模型等）
  ///
  /// Model Policy / Fallback 表（ai_model_policies 等）随 P4+ 需要时再加。
  SchemaMigration(version: 2, statements: [
    '''
    CREATE TABLE ai_providers (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      api_style TEXT NOT NULL,
      base_url TEXT NOT NULL,
      api_key TEXT,
      enabled INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE ai_models (
      provider_id TEXT NOT NULL REFERENCES ai_providers(id) ON DELETE CASCADE,
      model_id TEXT NOT NULL,
      display_name TEXT,
      source TEXT NOT NULL DEFAULT 'fetched',
      updated_at TEXT NOT NULL,
      PRIMARY KEY (provider_id, model_id)
    )
    ''',
    'CREATE INDEX idx_ai_models_provider ON ai_models(provider_id)',
    '''
    CREATE TABLE settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
    ''',
  ]),

  /// Schema v3：AI 会话（P4）。
  ///
  /// 会话与消息仍是领域实体 —— 延续前缀 UUID 约定，为同步预留。
  SchemaMigration(version: 3, statements: [
    '''
    CREATE TABLE conversations (
      id TEXT PRIMARY KEY,
      goal_id TEXT,
      title TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    'CREATE INDEX idx_conversations_goal ON conversations(goal_id, updated_at)',
    '''
    CREATE TABLE conversation_messages (
      id TEXT PRIMARY KEY,
      conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
      role TEXT NOT NULL,
      content TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
    ''',
    'CREATE INDEX idx_conversation_messages_conv ON conversation_messages(conversation_id, created_at)',
  ]),

  /// Schema v4：AI Planning 提案（P5，plan §25「结构性变化先确认」）。
  ///
  /// - plan_proposals：AI 通过 propose_plan 产出的计划提案
  ///   （不直接写目标数据，用户确认后由 ProposalService 应用）。
  ///   变更内容整体存 payload_json，行内只保留定位与状态列。
  /// - conversation_messages.proposal_id：把确认卡片挂到具体消息上。
  SchemaMigration(version: 4, statements: [
    '''
    CREATE TABLE plan_proposals (
      id TEXT PRIMARY KEY,
      conversation_id TEXT,
      goal_id TEXT,
      kind TEXT NOT NULL,
      payload_json TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      created_at TEXT NOT NULL,
      applied_at TEXT
    )
    ''',
    'CREATE INDEX idx_plan_proposals_conv ON plan_proposals(conversation_id)',
    'CREATE INDEX idx_plan_proposals_status ON plan_proposals(status)',
    'ALTER TABLE conversation_messages ADD COLUMN proposal_id TEXT',
  ]),

  /// Schema v5：External Data 框架的权限层（P9，plan §49）。
  ///
  /// 每个外部数据源一行（source 即主键 —— 系统级配置，非同步实体）；
  /// 数据本身不落库，readContext 结果只进 AI 上下文。
  SchemaMigration(version: 5, statements: [
    '''
    CREATE TABLE data_source_permissions (
      source TEXT PRIMARY KEY,
      status TEXT NOT NULL DEFAULT 'not_requested',
      updated_at TEXT NOT NULL
    )
    ''',
  ]),

  /// Schema v6：目标激励与完成统计（用户需求：目标奖励 + 首页完成数）。
  ///
  /// - goals.reward：达成目标后给自己的奖励（展示用文本）。
  /// - goals.completed_at：完成时间，首页「本月/今年完成」统计的依据。
  ///   旧库里已 completed 的目标用 updated_at 回填一个近似值。
  SchemaMigration(version: 6, statements: [
    'ALTER TABLE goals ADD COLUMN reward TEXT',
    'ALTER TABLE goals ADD COLUMN completed_at TEXT',
    '''
    UPDATE goals
    SET completed_at = updated_at
    WHERE status = 'completed' AND completed_at IS NULL
    ''',
  ]),
];

/// 执行 (from, to] 范围内的迁移。from == 0 表示全新建库。
Future<void> runSchemaMigrations(
  Future<void> Function(String sql) execute, {
  required int from,
  required int to,
}) async {
  for (final migration in schemaMigrations) {
    if (migration.version > from && migration.version <= to) {
      for (final statement in migration.statements) {
        await execute(statement);
      }
    }
  }
}
