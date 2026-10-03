# 数据库 Schema v1

> 事实源：`apps/mobile/lib/data/database/schema_migrations.dart`。本文为对照文档。
> 约定：ID 为前缀 UUID 文本；时间列为毫秒精度 UTC ISO8601 文本；枚举存 snake_case 文本。

## goals — 目标

| 列 | 类型 | 说明 |
| --- | --- | --- |
| id | TEXT PK | `goal_<uuid>` |
| title | TEXT NOT NULL | |
| description | TEXT | |
| status | TEXT NOT NULL | active / paused / completed / cancelled / archived |
| start_date | TEXT | |
| target_date | TEXT | |
| overall_progress | REAL NOT NULL | 0~100，仅用于统一展示 |
| created_at / updated_at | TEXT NOT NULL | |

## phases — 阶段（Goal 的阶段性进展）

| 列 | 类型 | 说明 |
| --- | --- | --- |
| id | TEXT PK | `phase_<uuid>` |
| goal_id | TEXT NOT NULL → goals | ON DELETE CASCADE |
| title | TEXT NOT NULL | |
| description | TEXT | |
| status | TEXT NOT NULL | todo / in_progress / completed / cancelled |
| order_index | INTEGER NOT NULL | 同 Goal 内展示顺序 |
| created_at / updated_at | TEXT NOT NULL | |

索引：`idx_phases_goal(goal_id, order_index)`

## tasks — 任务（具体执行动作）

| 列 | 类型 | 说明 |
| --- | --- | --- |
| id | TEXT PK | `task_<uuid>` |
| title | TEXT NOT NULL | |
| description | TEXT | |
| phase_id | TEXT → phases | ON DELETE SET NULL |
| status | TEXT NOT NULL | todo / in_progress / completed / postponed / cancelled |
| priority | TEXT NOT NULL | low / medium / high |
| estimated_minutes | INTEGER | 预计耗时 |
| due_date | TEXT | 截止时间 |
| completed_at | TEXT | 仅 completed 时有值 |
| created_at / updated_at | TEXT NOT NULL | |

索引：`idx_tasks_phase(phase_id)`、`idx_tasks_due(due_date)`

## goal_tasks — Task ↔ Goal 多对多（跨目标共享任务）

| 列 | 类型 | 说明 |
| --- | --- | --- |
| goal_id | TEXT NOT NULL → goals | ON DELETE CASCADE |
| task_id | TEXT NOT NULL → tasks | ON DELETE CASCADE |
| is_primary | INTEGER NOT NULL | 主属目标标记 |
| created_at | TEXT NOT NULL | |

PK：(goal_id, task_id)。索引：`idx_goal_tasks_task(task_id)`

## schedules — 日程（什么时候做）

| 列 | 类型 | 说明 |
| --- | --- | --- |
| id | TEXT PK | `schedule_<uuid>` |
| task_id | TEXT NOT NULL → tasks | ON DELETE CASCADE |
| start_at | TEXT NOT NULL | |
| end_at | TEXT | 与 duration_minutes 至少其一 |
| duration_minutes | INTEGER | |
| status | TEXT NOT NULL | planned / completed / cancelled / missed |
| note | TEXT | |
| created_at / updated_at | TEXT NOT NULL | |

索引：`idx_schedules_task(task_id, start_at)`、`idx_schedules_start(start_at)`

重排不覆盖旧记录：新 Schedule 插入，旧的标记 cancelled —— 历史留给 AI 分析偏差。

## goal_metrics — 目标度量（可选，如体重 73.4kg → 70kg）

| 列 | 类型 | 说明 |
| --- | --- | --- |
| id | TEXT PK | `metric_<uuid>` |
| goal_id | TEXT NOT NULL → goals | ON DELETE CASCADE |
| name | TEXT NOT NULL | 体重 / 体脂 / 存款 … |
| unit | TEXT | kg / % / 元 … |
| kind | TEXT NOT NULL | numeric / percentage / count / duration / distance / score / category |
| current_value | REAL | 由最新 MetricValue 驱动 |
| target_value | REAL | |
| direction | TEXT NOT NULL | increase / decrease |
| created_at / updated_at | TEXT NOT NULL | |

索引：`idx_goal_metrics_goal(goal_id)`

## metric_values — 度量历史

| 列 | 类型 | 说明 |
| --- | --- | --- |
| id | TEXT PK | `metric_value_<uuid>` |
| metric_id | TEXT NOT NULL → goal_metrics | ON DELETE CASCADE |
| value | REAL NOT NULL | |
| recorded_at | TEXT NOT NULL | |
| source | TEXT | user / health / ai … |
| note | TEXT | |

索引：`idx_metric_values_metric(metric_id, recorded_at)`

## progress_events — 进度事件（不可变事实流）

| 列 | 类型 | 说明 |
| --- | --- | --- |
| id | TEXT PK | `event_<uuid>` |
| goal_id | TEXT | 可空（允许非目标事件） |
| task_id | TEXT | 可空 |
| type | TEXT NOT NULL | task_completed / task_started / task_postponed / task_cancelled / metric_updated / phase_completed / goal_updated / goal_paused / goal_resumed / schedule_changed / user_report |
| time | TEXT NOT NULL | 事件发生时间（≠写入时间） |
| source | TEXT NOT NULL | user / chat / system / health / location / calendar / ai / notification |
| message | TEXT | 用户可读描述 |
| data | TEXT | JSON 附加数据 |
| created_at | TEXT NOT NULL | 写入时间 |

索引：`idx_progress_events_goal(goal_id, time)`、`idx_progress_events_task(task_id, time)`

## 后续版本

- v2（已落地）：`ai_providers`、`ai_models`、`settings`，见 [schema-v2.md](./schema-v2.md)
- v3+（随 P4+ 落地）：`conversations`、`conversation_messages`、
  `ai_model_policies`、`data_sources`、`permissions`、`notifications`
- 云同步期（V4）：`sync_metadata`、`devices`、`remote_changes`
