# 数据库 Schema v4

> 事实源：`apps/mobile/lib/data/database/schema_migrations.dart`。
> v4 在 v3 基础上新增（[schema-v3](./schema-v3.md)）。

## plan_proposals — 计划提案（P5，plan §25「结构性变化先确认」）

AI 通过 `propose_plan` 工具产出的计划提案。提案本身**不写目标数据**；
用户在确认卡片上点 [应用计划] 后由 `ProposalService.apply` 落库。

| 列 | 类型 | 说明 |
| --- | --- | --- |
| id | TEXT PK | `prop_<uuid>` |
| conversation_id | TEXT | 来源会话；提案通过消息列挂进聊天流 |
| goal_id | TEXT | kind=adjust 时指向被调整的目标；create 为空 |
| kind | TEXT NOT NULL | `create`（新目标全套计划）/ `adjust`（结构调整） |
| payload_json | TEXT NOT NULL | 完整提案内容（见下） |
| status | TEXT NOT NULL DEFAULT 'pending' | pending / applied / dismissed / superseded |
| created_at | TEXT NOT NULL | |
| applied_at | TEXT | 应用时间 |

索引：`idx_plan_proposals_conv(conversation_id)`、
`idx_plan_proposals_status(status)`

### payload_json 结构

```json
{
  "goalTitle": "三个月减掉 5kg",
  "goalDescription": null,
  "targetDate": "2026-12-31T00:00:00.000Z",
  "metricName": "体重", "metricUnit": "kg",
  "metricStartValue": 72.5, "metricTargetValue": 67.5,
  "metricDecrease": true,
  "phases": [
    {
      "title": "适应期", "description": "建立运动习惯",
      "tasks": [
        {
          "title": "晚间快走 30 分钟", "estimatedMinutes": 30,
          "dueDate": null,
          "scheduleStartAt": "2026-10-05T19:00:00.000Z",
          "scheduleMinutes": 30
        }
      ]
    }
  ],
  "removePhaseIds": ["phase_xxx"],
  "removeTaskIds": ["task_xxx"],
  "reason": "现状 vs 建议的调整理由（展示在确认卡片）"
}
```

### 状态机

```text
pending ──apply──→ applied（落库，plan_applied 事件）
pending ──dismiss──→ dismissed
pending ──同会话出现更新的提案──→ superseded
```

## conversation_messages.proposal_id（新列）

| 列 | 类型 | 说明 |
| --- | --- | --- |
| proposal_id | TEXT | assistant 消息可挂一个提案；UI 在该消息下渲染确认卡片。模型侧历史回放忽略此列 |

## 应用语义（ProposalService.apply）

- **create**：GoalService.createGoal → addMetric（可选）→ createPhase×N →
  createTask×M → scheduleTask（带 startAt 的任务）
- **adjust**：updateGoal（targetDate/描述）→ cancelTask×N（removeTaskIds）→
  cancelPhase×N（removePhaseIds，连带取消其未完成任务）→ 新增 phases
- 应用 / 忽略都会向来源会话追加一条 activity 消息（本地可见，不回放模型）
