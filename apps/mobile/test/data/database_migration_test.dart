import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ai_goal/data/database/app_database.dart';
import 'package:ai_goal/data/database/schema_migrations.dart';
import 'package:ai_goal/domain/goal/goal.dart';
import 'package:ai_goal/domain/phase/phase.dart';

import '../helpers/test_database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = await openTestDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  Future<Set<String>> tableNames() async {
    final rows = await db.database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    return rows.map((r) => r['name']! as String).toSet();
  }

  test('全新建库：schema v1 的核心表全部存在', () async {
    const expectedTables = {
      'goals',
      'phases',
      'tasks',
      'goal_tasks',
      'schedules',
      'goal_metrics',
      'metric_values',
      'progress_events',
    };
    final tables = await tableNames();
    for (final t in expectedTables) {
      expect(tables, contains(t), reason: '缺少表 $t');
    }
  });

  test('外键级联：删除 Goal 连带删除 Phase 与关联', () async {
    await db.database.insert('goals', {
      'id': 'goal_c1',
      'title': '减重',
      'status': 'active',
      'overall_progress': 0.0,
      'created_at': '2026-10-03T00:00:00.000Z',
      'updated_at': '2026-10-03T00:00:00.000Z',
    });
    await db.database.insert('phases', {
      'id': 'phase_c1',
      'goal_id': 'goal_c1',
      'title': '适应期',
      'status': 'todo',
      'order_index': 0,
      'created_at': '2026-10-03T00:00:00.000Z',
      'updated_at': '2026-10-03T00:00:00.000Z',
    });

    await db.database.delete('goals', where: 'id = ?', whereArgs: ['goal_c1']);

    final phases = await db.database.query('phases');
    expect(phases, isEmpty);
  });

  test('删除 Phase 后 Task 的 phase_id 置空（SET NULL）', () async {
    final t = '2026-10-03T00:00:00.000Z';
    await db.database.insert('goals', {
      'id': 'goal_s',
      'title': 'x',
      'status': 'active',
      'overall_progress': 0.0,
      'created_at': t,
      'updated_at': t,
    });
    await db.database.insert('phases', {
      'id': 'phase_s',
      'goal_id': 'goal_s',
      'title': '阶段一',
      'status': 'todo',
      'order_index': 0,
      'created_at': t,
      'updated_at': t,
    });
    await db.database.insert('tasks', {
      'id': 'task_s',
      'title': '做任务',
      'phase_id': 'phase_s',
      'status': 'todo',
      'priority': 'medium',
      'created_at': t,
      'updated_at': t,
    });

    await db.database.delete('phases', where: 'id = ?', whereArgs: ['phase_s']);

    final tasks = await db.database.query('tasks');
    expect(tasks.single['phase_id'], isNull);
  });

  test('schema 版本常量与迁移列表一致', () {
    expect(AppDatabase.schemaVersion, 6);
    expect(schemaMigrations.last.version, AppDatabase.schemaVersion);
  });

  test('v6：goals 的 reward / completed_at 列存在', () async {
    final columns = await db.database.rawQuery('PRAGMA table_info(goals)');
    expect(
      columns.map((c) => c['name']),
      containsAll(['reward', 'completed_at']),
    );
  });

  test('v6 升级回填：旧库已完成目标用 updated_at 填 completed_at', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('ai_goal_v6');
    final path = '${dir.path}/v6.db';

    // 以 v5 建库，写入一条已完成目标（v5 没有 completed_at 列）。
    final v5 = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 5,
        onCreate: (db, version) =>
            runSchemaMigrations(db.execute, from: 0, to: 5),
      ),
    );
    await v5.insert('goals', {
      'id': 'goal_done',
      'title': '旧版本完成的目标',
      'status': 'completed',
      'overall_progress': 100.0,
      'created_at': '2026-08-01T00:00:00.000Z',
      'updated_at': '2026-09-15T00:00:00.000Z',
    });
    await v5.insert('goals', {
      'id': 'goal_alive',
      'title': '进行中的目标',
      'status': 'active',
      'overall_progress': 30.0,
      'created_at': '2026-08-01T00:00:00.000Z',
      'updated_at': '2026-09-15T00:00:00.000Z',
    });
    await v5.close();

    final upgraded = await AppDatabase.open(
      path: path,
      factory: databaseFactoryFfi,
    );
    try {
      final rows = await upgraded.database.query('goals');
      final byId = {for (final r in rows) r['id']! as String: r};
      // 已完成 → completed_at 回填为 updated_at；进行中 → 保持 NULL。
      expect(byId['goal_done']!['completed_at'], '2026-09-15T00:00:00.000Z');
      expect(byId['goal_alive']!['completed_at'], isNull);

      final goal = Goal.fromMap(byId['goal_done']!);
      expect(goal.completedAt, isNotNull);
      expect(goal.reward, isNull);
    } finally {
      await upgraded.close();
      await dir.delete(recursive: true);
    }
  });

  test('v5：data_source_permissions 表存在', () async {
    final tables = await tableNames();
    expect(tables, contains('data_source_permissions'));
  });

  test('v4：plan_proposals 表与 conversation_messages.proposal_id 列存在', () async {
    final tables = await tableNames();
    expect(tables, contains('plan_proposals'));

    final columns = await db.database.rawQuery(
      'PRAGMA table_info(conversation_messages)',
    );
    expect(
      columns.map((c) => c['name']),
      containsAll(['proposal_id']),
    );
  });

  test('v1 旧库升级到最新：数据保留，v2/v3/v4 新表可用', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('ai_goal_upgrade');
    final path = '${dir.path}/upgrade.db';

    // 以 v1 建库并写入一条目标数据（模拟老版本用户）。
    final v1 = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) =>
            runSchemaMigrations(db.execute, from: 0, to: 1),
      ),
    );
    await v1.insert('goals', {
      'id': 'goal_old',
      'title': '升级前创建的目标',
      'status': 'active',
      'overall_progress': 0.0,
      'created_at': '2026-09-01T00:00:00.000Z',
      'updated_at': '2026-09-01T00:00:00.000Z',
    });
    await v1.close();

    // 用当前版本（v2）打开 → 触发 onUpgrade。
    final upgraded = await AppDatabase.open(
      path: path,
      factory: databaseFactoryFfi,
    );
    try {
      // 旧数据完好
      final goals = await upgraded.database.query('goals');
      expect(Goal.fromMap(goals.single).title, '升级前创建的目标');

      // 新表可写
      await upgraded.database.insert('ai_providers', {
        'id': 'provider_up',
        'name': '智谱官方',
        'api_style': 'openai_compatible',
        'base_url': 'https://open.bigmodel.cn/api/paas/v4',
        'api_key': null,
        'enabled': 1,
        'created_at': '2026-10-03T00:00:00.000Z',
        'updated_at': '2026-10-03T00:00:00.000Z',
      });
      await upgraded.database.insert('settings', {
        'key': 'ai.default_model',
        'value': '{"providerId":"provider_up","modelId":"glm-4.6"}',
      });

      final providers = await upgraded.database.query('ai_providers');
      expect(providers, hasLength(1));
      final settingsRows = await upgraded.database.query('settings');
      expect(settingsRows.single['key'], 'ai.default_model');

      // v3 会话表可写
      await upgraded.database.insert('conversations', {
        'id': 'conv_up',
        'goal_id': null,
        'title': '升级后的会话',
        'created_at': '2026-10-03T00:00:00.000Z',
        'updated_at': '2026-10-03T00:00:00.000Z',
      });
      await upgraded.database.insert('conversation_messages', {
        'id': 'msg_up',
        'conversation_id': 'conv_up',
        'role': 'user',
        'content': '你好',
        'created_at': '2026-10-03T00:00:00.000Z',
      });
      final convMessages =
          await upgraded.database.query('conversation_messages');
      expect(convMessages.single['role'], 'user');

      // v4 提案表可写，消息可挂 proposal_id
      await upgraded.database.insert('plan_proposals', {
        'id': 'prop_up',
        'conversation_id': 'conv_up',
        'goal_id': null,
        'kind': 'create',
        'payload_json': '{"phases":[]}',
        'status': 'pending',
        'created_at': '2026-10-03T00:00:00.000Z',
        'applied_at': null,
      });
      await upgraded.database.insert('conversation_messages', {
        'id': 'msg_prop',
        'conversation_id': 'conv_up',
        'role': 'assistant',
        'content': '给你一个计划提案',
        'proposal_id': 'prop_up',
        'created_at': '2026-10-03T00:00:01.000Z',
      });
      final proposals = await upgraded.database.query('plan_proposals');
      expect(proposals.single['status'], 'pending');
      final withProposal = await upgraded.database.query(
        'conversation_messages',
        where: 'proposal_id IS NOT NULL',
      );
      expect(withProposal.single['proposal_id'], 'prop_up');

      // v5 权限表可写
      await upgraded.database.insert('data_source_permissions', {
        'source': 'weather',
        'status': 'granted',
        'updated_at': '2026-10-03T00:00:00.000Z',
      });
      final perms =
          await upgraded.database.query('data_source_permissions');
      expect(perms.single['status'], 'granted');
    } finally {
      await upgraded.close();
      await dir.delete(recursive: true);
    }
  });

  test('Goal 默认状态与状态机取值可往返', () async {
    final t = DateTime(2026, 10, 3);
    await db.database.insert(
      'goals',
      Goal(
        id: 'goal_d',
        title: '默认状态',
        createdAt: t,
        updatedAt: t,
      ).toMap(),
    );
    final rows = await db.database.query('goals');
    expect(Goal.fromMap(rows.single).status, GoalStatus.active);
    expect(PhaseStatus.fromColumnName('in_progress'), PhaseStatus.inProgress);
  });
}
