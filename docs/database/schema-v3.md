# 数据库 Schema v3

> 事实源：`apps/mobile/lib/data/database/schema_migrations.dart`。
> v3 在 v2 基础上新增（[schema-v2](./schema-v2.md)）。

## conversations — AI 会话（P4）

| 列 | 类型 | 说明 |
| --- | --- | --- |
| id | TEXT PK | `conv_<uuid>` |
| goal_id | TEXT | 为空 = 全局对话；非空 = 「讨论这个目标」上下文 |
| title | TEXT | 取首条用户消息前 24 字 |
| created_at / updated_at | TEXT NOT NULL | 每条消息追加时刷新 updated_at |

索引：`idx_conversations_goal(goal_id, updated_at)`

## conversation_messages — 会话消息

| 列 | 类型 | 说明 |
| --- | --- | --- |
| id | TEXT PK | `msg_<uuid>` |
| conversation_id | TEXT NOT NULL → conversations | ON DELETE CASCADE |
| role | TEXT NOT NULL | user / assistant / **activity**（工具活动与回退提示，仅本地展示，不回放给模型） |
| content | TEXT NOT NULL | |
| created_at | TEXT NOT NULL | |

索引：`idx_conversation_messages_conv(conversation_id, created_at)`

## 模型回放约定

发给模型的对话历史只包含 `user` / `assistant` 文本消息（最近 10 条）；
`activity` 是给用户看的「正在创建目标…」过程记录，不进入上下文。
