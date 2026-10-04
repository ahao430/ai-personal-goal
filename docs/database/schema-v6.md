# 数据库 Schema v6

> 事实源：`apps/mobile/lib/data/database/schema_migrations.dart`。
> v6 在 v5 基础上新增（[schema-v5](./schema-v5.md)）：目标激励与完成统计。

## goals — 新增列（ALTER TABLE）

| 列 | 类型 | 说明 |
| --- | --- | --- |
| reward | TEXT NULL | 达成目标后给自己的奖励（展示用文本，如「买一双跑鞋」）。完成目标时进度事件与详情页会提醒兑现 |
| completed_at | TEXT NULL | 完成时间（UTC ISO8601）。首页「本月/今年完成目标数」统计的唯一依据 |

### 回填规则（迁移内完成）

v6 之前的旧库里已 `status = 'completed'` 的目标没有完成时间，
迁移时用 `updated_at` 回填一个近似值：

```sql
UPDATE goals
SET completed_at = updated_at
WHERE status = 'completed' AND completed_at IS NULL
```

### 写入语义（GoalService）

- `completeGoal`：进入 completed 时写 `completed_at = now`；
- 重开 / 取消 / 归档（任何离开 completed 的迁移）：**清空** `completed_at`，
  避免「完成后又重开」污染统计；
- 统计查询走 `GoalRepository.countCompletedSince(from)`
  （`status = 'completed' AND completed_at IS NOT NULL AND completed_at >= from`），
  首页聚合为 `HomeView.completedThisMonth` / `completedThisYear`。

## 涉及面

| 层 | 变更 |
| --- | --- |
| domain | `Goal.reward` / `Goal.completedAt`（copyWith 用 `_keep` 哨兵保留置空语义） |
| data | `countCompletedSince` 查询；v6 迁移 |
| application | `createGoal(reward:)`；`_transition` 维护 completedAt；AI 工具 `create_goal` / `update_goal` 支持 reward |
| presentation | 目标表单「达成奖励」输入；详情概览卡奖励行（完成态高亮）；首页完成统计卡 |
