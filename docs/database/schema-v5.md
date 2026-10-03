# 数据库 Schema v5

> 事实源：`apps/mobile/lib/data/database/schema_migrations.dart`。
> v5 在 v4 基础上新增（[schema-v4](./schema-v4.md)）。

## data_source_permissions — 外部数据源授权（P9，plan §49）

External Data 框架的权限层持久化。每个外部数据源一行；
**数据本身不落库**（readContext 结果只进 AI 上下文，不存储）。

| 列 | 类型 | 说明 |
| --- | --- | --- |
| source | TEXT PK | `health` / `weather` / `location` / `calendar`（枚举主键 —— 系统级配置，非同步实体，不适用前缀 UUID 约定） |
| status | TEXT NOT NULL DEFAULT 'not_requested' | not_requested / requested（已表达意向）/ granted / denied |
| updated_at | TEXT NOT NULL | |

## 框架组件与数据流（plan §49）

```text
DataProvider（core/external/data_provider.dart）
  ├─ WeatherDataProvider      Open-Meteo 免 key（forecast + geocoding）
  │                           城市配置存 settings `weather.location`
  ├─ PlaceholderDataProvider  health / location / calendar（占位，可记录意向）
  └─ 外部数据不落库：readContext 只产生 AI 上下文片段

ExternalDataService（application，Context Adapter）
  └─ buildExternalContext()：收集「已授权且可用」源 → ContextBuilder
     写入上下文 JSON 的 `external` 键（单源失败静默跳过）
```

## 上下文示例（external 键）

```json
{
  "external": {
    "weather": {
      "location": "上海",
      "current": {"temperature": 22.5, "feelsLike": 23.1, "condition": "多云"},
      "today": {"maxTemp": 25.0, "minTemp": 18.0, "precipitationChance": 10},
      "tomorrow": {"maxTemp": 24.0, "minTemp": 17.5, "precipitationChance": 60}
    }
  }
}
```

AI 据此外部事实给户外目标建议（如降水概率高 → 建议室内替代或调整日程）。
