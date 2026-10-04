import 'dart:async';

import 'package:http/http.dart' as http;

import '../core/ai/model_list_client.dart';
import '../core/external/data_provider.dart';
import '../core/notifications/reminder_platform.dart';
import '../data/database/app_database.dart';
import '../data/repositories/sqlite_ai_provider_repository.dart';
import '../data/repositories/sqlite_conversation_repository.dart';
import '../data/repositories/sqlite_data_source_permission_repository.dart';
import '../data/repositories/sqlite_goal_repository.dart';
import '../data/repositories/sqlite_phase_repository.dart';
import '../data/repositories/sqlite_plan_proposal_repository.dart';
import '../data/repositories/sqlite_progress_event_repository.dart';
import '../data/repositories/sqlite_schedule_repository.dart';
import '../data/repositories/sqlite_settings_repository.dart';
import '../data/repositories/sqlite_task_repository.dart';
import '../domain/ai/ai_provider_repository.dart';
import '../domain/ai/conversation_repository.dart';
import '../domain/external/data_source.dart';
import '../domain/goal/goal_repository.dart';
import '../domain/phase/phase_repository.dart';
import '../domain/planning/plan_proposal_repository.dart';
import '../domain/progress/progress_event_repository.dart';
import '../domain/schedule/schedule_repository.dart';
import '../domain/settings/app_settings.dart';
import '../domain/task/task_repository.dart';
import 'agent_service.dart';
import 'ai_provider_service.dart';
import 'analysis_service.dart';
import 'context_builder.dart';
import 'daily_review_service.dart';
import 'external_data_service.dart';
import 'goal_service.dart';
import 'notification_scheduler.dart';
import 'overview_service.dart';
import 'planning_service.dart';
import 'progress_service.dart';
import 'proposal_service.dart';
import 'search_service.dart';
import 'update_service.dart';

/// 组合根：打开数据库并装配全部 Repository。
///
/// P0 阶段用最朴素的手工装配；P2（核心 UI）再决定是否引入 Provider/Riverpod。
/// UI 层只从这里拿 Repository 接口，不接触任何 SQLite 类型。
class AppServices {
  AppServices._(this.db, {ReminderPlatform? reminderPlatform, http.Client? searchClient})
      : _reminderPlatform = reminderPlatform,
        _searchClient = searchClient;

  final AppDatabase db;

  /// 可注入的通知平台实现（测试用 fake；生产用 flutter_local_notifications）。
  final ReminderPlatform? _reminderPlatform;

  /// 可注入的搜索 HTTP 客户端（测试用 MockClient）。
  final http.Client? _searchClient;

  /// 当前数据库 schema 版本（透出给展示层，避免其接触 data 层类型）。
  int get schemaVersion => AppDatabase.schemaVersion;

  late final GoalRepository goals = SqliteGoalRepository(db.database);
  late final GoalMetricRepository metrics = SqliteGoalMetricRepository(
    db.database,
  );
  late final PhaseRepository phases = SqlitePhaseRepository(db.database);
  late final TaskRepository tasks = SqliteTaskRepository(db.database);
  late final ScheduleRepository schedules = SqliteScheduleRepository(
    db.database,
  );
  late final ProgressEventRepository progressEvents =
      SqliteProgressEventRepository(db.database);

  // ── 目标域用例（P1） ──────────────────────────────────
  late final ProgressService progressService = ProgressService(
    goals,
    phases,
    tasks,
    progressEvents,
  );
  late final GoalService goalService = GoalService(
    goals,
    metrics,
    progressService,
  );
  late final NotificationScheduler notificationScheduler =
      NotificationScheduler(this, _reminderPlatform ?? ReminderPlatformImpl());
  late final PlanningService planningService = PlanningService(
    phases,
    tasks,
    schedules,
    progressService,
    // 任务/日程变化 → 自动重排该任务的提醒（AI 工具与 UI 写操作共用）。
    onTaskChanged: (taskId) =>
        unawaited(notificationScheduler.syncTask(taskId)),
  );
  late final OverviewService overview = OverviewService(
    goals,
    phases,
    tasks,
    schedules,
    metrics,
    progressEvents,
  );

  // ── AI 供应商（P3） ────────────────────────────────────
  late final AiProviderRepository aiProviders =
      SqliteAiProviderRepository(db.database);
  late final AppSettingsRepository settings =
      SqliteAppSettingsRepository(db.database);
  late final AiProviderService aiProviderService = AiProviderService(
    aiProviders,
    settings,
    modelListClient: ModelListClient(),
  );

  // ── AI Agent（P4） ─────────────────────────────────────
  late final ConversationRepository conversations =
      SqliteConversationRepository(db.database);
  late final ContextBuilder contextBuilder = ContextBuilder(this);
  late final AgentService agentService = AgentService(this);

  // ── AI Planning 提案（P5） ────────────────────────────
  late final PlanProposalRepository proposals =
      SqlitePlanProposalRepository(db.database);
  late final ProposalService proposalService = ProposalService(this, proposals);

  // ── Progress Loop（P6） ───────────────────────────────
  late final AnalysisService analysisService = AnalysisService(this);
  late final DailyReviewService dailyReviewService = DailyReviewService(this);

  // ── Web Search（P8） ──────────────────────────────────
  late final SearchService searchService =
      SearchService(settings, client: _searchClient);

  // ── 检查更新 ─────────────────────────────────────────
  late final UpdateService updateService =
      UpdateService(settings, client: _searchClient);

  // ── External Data 框架（P9） ──────────────────────────
  late final DataSourcePermissionRepository dataSourcePermissions =
      SqliteDataSourcePermissionRepository(db.database);
  late final ExternalDataService externalService = ExternalDataService(
    dataSourcePermissions,
    [
      WeatherDataProvider(
        settings: settings,
        permissions: dataSourcePermissions,
        client: _searchClient,
      ),
      PlaceholderDataProvider(
        source: ExternalSource.health,
        permissions: dataSourcePermissions,
      ),
      PlaceholderDataProvider(
        source: ExternalSource.location,
        permissions: dataSourcePermissions,
      ),
      PlaceholderDataProvider(
        source: ExternalSource.calendar,
        permissions: dataSourcePermissions,
      ),
    ],
  );

  /// 打开默认位置的数据库。测试请直接使用 [AppDatabase.open] 注入工厂。
  static Future<AppServices> bootstrap() async =>
      AppServices._(await AppDatabase.open());

  /// 基于已打开的数据库装配（测试 / 预览场景使用）。
  factory AppServices.of(
    AppDatabase database, {
    ReminderPlatform? reminderPlatform,
    http.Client? searchClient,
  }) =>
      AppServices._(
        database,
        reminderPlatform: reminderPlatform,
        searchClient: searchClient,
      );

  Future<void> close() => db.close();
}
