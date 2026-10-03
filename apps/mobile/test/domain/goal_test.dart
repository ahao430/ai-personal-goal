import 'package:flutter_test/flutter_test.dart';

import 'package:ai_goal/domain/entity_ids.dart';
import 'package:ai_goal/domain/goal/goal.dart';
import 'package:ai_goal/domain/progress/progress_event.dart';

void main() {
  group('EntityIds', () {
    test('生成带前缀的 UUID', () {
      final id = EntityIds.newGoalId();
      expect(id.startsWith('goal_'), isTrue);
      expect(id.length > 'goal_'.length + 30, isTrue);

      expect(EntityIds.newTaskId().startsWith('task_'), isTrue);
      expect(EntityIds.newProgressEventId().startsWith('event_'), isTrue);
    });

    test('不重复', () {
      expect(EntityIds.newGoalId(), isNot(EntityIds.newGoalId()));
    });
  });

  group('Goal', () {
    final createdAt = DateTime(2026, 10, 3, 8, 30);

    Goal build() => Goal(
          id: 'goal_t1',
          title: '三个月减掉 5kg',
          description: '从 73.4kg 到 68.4kg',
          startDate: DateTime(2026, 10, 1),
          targetDate: DateTime(2026, 12, 31),
          overallProgress: 12.5,
          createdAt: createdAt,
          updatedAt: createdAt,
        );

    test('toMap/fromMap 往返保持字段', () {
      final goal = build();
      final restored = Goal.fromMap(goal.toMap());

      expect(restored.id, goal.id);
      expect(restored.title, goal.title);
      expect(restored.description, goal.description);
      expect(restored.status, GoalStatus.active);
      expect(restored.overallProgress, 12.5);
      expect(restored.startDate!.isAtSameMomentAs(goal.startDate!), isTrue);
      expect(restored.targetDate!.isAtSameMomentAs(goal.targetDate!), isTrue);
      expect(restored.createdAt.isAtSameMomentAs(createdAt), isTrue);
    });

    test('时间列编码为固定宽度 UTC 字符串（可按字典序比较）', () {
      final utcGoal = Goal(
        id: 'goal_utc',
        title: '时区无关',
        createdAt: DateTime.utc(2026, 10, 3, 0, 30),
        updatedAt: DateTime.utc(2026, 10, 3, 0, 30),
      );
      expect(utcGoal.toMap()['created_at'], '2026-10-03T00:30:00.000Z');
    });

    test('copyWith 可更新字段，未指定字段保持不变', () {
      final goal = build();
      final updated = goal.copyWith(
        title: '三个月减掉 6kg',
        overallProgress: 30,
        updatedAt: DateTime(2026, 10, 5),
      );

      expect(updated.title, '三个月减掉 6kg');
      expect(updated.overallProgress, 30);
      expect(updated.description, goal.description);
      expect(updated.startDate!.isAtSameMomentAs(goal.startDate!), isTrue);
      expect(updated.id, goal.id);
      expect(updated.createdAt.isAtSameMomentAs(createdAt), isTrue);
    });

    test('copyWith 传 null 可以清空可空字段', () {
      final goal = build();
      final cleared = goal.copyWith(description: null, targetDate: null);

      expect(cleared.description, isNull);
      expect(cleared.targetDate, isNull);
    });

    test('overallProgress 超出 0-100 会断言失败', () {
      expect(
        () => Goal(
          id: 'goal_bad',
          title: 'x',
          overallProgress: 120,
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('GoalStatus 解析非法值抛错', () {
      expect(() => GoalStatus.parse('bogus'), throwsArgumentError);
    });
  });

  group('ProgressEvent', () {
    test('data 字段 JSON 编解码往返', () {
      final time = DateTime(2026, 10, 3, 20, 0);
      final event = ProgressEvent(
        id: 'event_t1',
        goalId: 'goal_t1',
        taskId: 'task_t1',
        type: ProgressEventType.taskCompleted,
        time: time,
        source: ProgressSource.chat,
        message: '昨天的英语跟读完成了',
        data: {'from': 73.4, 'to': 72.9, 'unit': 'kg'},
      );

      final restored = ProgressEvent.fromMap(event.toMap());
      expect(restored.type, ProgressEventType.taskCompleted);
      expect(restored.source, ProgressSource.chat);
      expect(restored.data?['to'], 72.9);
      expect(restored.data?['unit'], 'kg');
      expect(restored.createdAt.isAtSameMomentAs(time), isTrue);
    });

    test('事件类型列名与计划中的 snake_case 契约一致', () {
      expect(ProgressEventType.taskCompleted.columnName, 'task_completed');
      expect(ProgressEventType.userReport.columnName, 'user_report');
      expect(ProgressEventType.scheduleChanged.columnName, 'schedule_changed');
      expect(
        ProgressEventType.fromColumnName('phase_completed'),
        ProgressEventType.phaseCompleted,
      );
    });
  });
}
