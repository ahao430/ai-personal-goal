import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_goal/domain/planning/plan_proposal.dart';
import 'package:ai_goal/presentation/widgets/plan_proposal_card.dart';

PlanProposal _proposal({ProposalStatus status = ProposalStatus.pending}) =>
    PlanProposal(
      id: 'prop_1',
      conversationId: 'conv_1',
      kind: ProposalKind.create,
      goalTitle: '三个月减掉 5kg',
      targetDate: DateTime(2026, 12, 31),
      metricName: '体重',
      metricUnit: 'kg',
      metricStartValue: 72.5,
      metricTargetValue: 67.5,
      metricDecrease: true,
      phases: [
        ProposalPhaseDraft(title: '适应期', tasks: [
          ProposalTaskDraft(title: '晚间快走 30 分钟'),
        ]),
        ProposalPhaseDraft(title: '提升期'),
      ],
      reason: '每周约 0.4kg，安全节奏',
      status: status,
      createdAt: DateTime(2026, 10, 3),
    );

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('pending：展示阶段/指标/理由与两个操作按钮，点击触发回调', (tester) async {
    var applied = 0;
    var edited = 0;
    await tester.pumpWidget(_wrap(PlanProposalCard(
      proposal: _proposal(),
      onApply: () => applied++,
      onEdit: () => edited++,
    )));
    await tester.pumpAndSettle();

    expect(find.text('计划提案：三个月减掉 5kg'), findsOneWidget);
    expect(find.text('适应期'), findsOneWidget);
    expect(find.text('提升期'), findsOneWidget);
    expect(find.text('晚间快走 30 分钟'), findsOneWidget);
    expect(find.textContaining('体重：72.5'), findsOneWidget);
    expect(find.textContaining('每周约 0.4kg'), findsOneWidget);
    expect(find.text('应用计划'), findsOneWidget);
    expect(find.text('修改'), findsOneWidget);

    await tester.tap(find.text('应用计划'));
    await tester.pump();
    expect(applied, 1);

    await tester.tap(find.text('修改'));
    await tester.pump();
    expect(edited, 1);
  });

  testWidgets('applied：显示已应用徽章，没有操作按钮', (tester) async {
    await tester.pumpWidget(_wrap(PlanProposalCard(
      proposal: _proposal(status: ProposalStatus.applied),
    )));
    await tester.pumpAndSettle();

    expect(find.text('已应用'), findsOneWidget);
    expect(find.text('应用计划'), findsNothing);
    expect(find.text('修改'), findsNothing);
  });

  testWidgets('superseded：显示取代提示', (tester) async {
    await tester.pumpWidget(_wrap(PlanProposalCard(
      proposal: _proposal(status: ProposalStatus.superseded),
    )));
    await tester.pumpAndSettle();
    expect(find.text('已有新版本提案'), findsOneWidget);
  });

  testWidgets('adjust：展示取消阶段/任务的减法行', (tester) async {
    await tester.pumpWidget(_wrap(PlanProposalCard(
      proposal: PlanProposal(
        id: 'prop_2',
        goalId: 'goal_1',
        kind: ProposalKind.adjust,
        targetDate: DateTime(2027, 1, 31),
        removePhaseIds: const ['phase_1', 'phase_2'],
        removeTaskIds: const ['task_1'],
        phases: [ProposalPhaseDraft(title: '口语期')],
        reason: '缩小范围',
        createdAt: DateTime(2026, 10, 3),
      ),
    )));
    await tester.pumpAndSettle();

    expect(find.text('调整提案'), findsOneWidget);
    expect(find.text('取消 2 个阶段，取消 1 个任务'), findsOneWidget);
    expect(find.text('口语期'), findsOneWidget);
  });
}
