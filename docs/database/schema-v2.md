# 数据库 Schema v2

> 事实源：`apps/mobile/lib/data/database/schema_migrations.dart`。
> v2 在 v1 基础上新增（[schema-v1](./schema-v1.md)）。

## ai_providers — AI 供应商（可配置多个）

| 列 | 类型 | 说明 |
| --- | --- | --- |
| id | TEXT PK | `provider_<uuid>` |
| name | TEXT NOT NULL | 展示名（模板预填或自定） |
| api_style | TEXT NOT NULL | openai_compatible / anthropic |
| base_url | TEXT NOT NULL | API 根地址（模板预填或完全自定义） |
| api_key | TEXT | V1 明文存本机（无后端不上传；UI 脱敏展示） |
| enabled | INTEGER NOT NULL | 启停开关 |
| created_at / updated_at | TEXT NOT NULL | |

内置模板（`domain/ai/ai_provider_template.dart`）：智谱官方 / OpenAI 官方 /
Claude 官方（Anthropic）/ DeepSeek 官方 / Kimi / 通义千问 / 自定义。

## ai_models — 模型缓存（按供应商）

| 列 | 类型 | 说明 |
| --- | --- | --- |
| provider_id | TEXT NOT NULL → ai_providers | ON DELETE CASCADE |
| model_id | TEXT NOT NULL | 调用 API 用的模型标识（如 glm-4.6） |
| display_name | TEXT | 供应商返回的展示名 |
| source | TEXT NOT NULL | fetched（一键拉取，可整体替换）/ manual（手动补录，长期保留） |
| updated_at | TEXT NOT NULL | |

PK：(provider_id, model_id)。索引：`idx_ai_models_provider(provider_id)`

刷新语义：一键获取时只替换该供应商的 fetched 条目；manual 条目保留，
与 fetched 同名时 manual 优先 —— 兼容部分中转站 /models 列表不全的情况。

## settings — 全局键值偏好

| 列 | 类型 | 说明 |
| --- | --- | --- |
| key | TEXT PK | |
| value | TEXT NOT NULL | 通常是 JSON |

已用键：

- `ai.default_model` → `{"providerId":"...","modelId":"..."}` 默认模型
  （供应商与模型分开配置后的全局选择；删除对应供应商时自动清除）

## 一键获取模型列表的协议约定

- OpenAI 兼容：`GET {base_url}/models`，`Authorization: Bearer <key>`
- Anthropic：`GET {base_url}/v1/models`，`x-api-key` + `anthropic-version: 2023-06-01`

解析兼容三种返回形态：`{"data":[...]}`（OpenAI/Anthropic）、裸数组、
条目里的 `id`（必需）与 `display_name|displayName|name`（可选展示名）。
