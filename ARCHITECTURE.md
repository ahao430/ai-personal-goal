# 技术架构

> 事实源是 [plan.md](./plan.md)。本文说明 V1 已落地的架构与约定。

## 总体形态（V1）

**完全 Local-first**：无登录、无账号、无后端、无云同步。SQLite 是唯一事实源。
AI 通过用户自配的模型 API 直接调用。

## Monorepo

pnpm workspace 管理 `apps/*`、`packages/*`、`services/*`（未来 Go 后端）。

Flutter 是独立 Dart 项目，不依赖 TS packages。TS 侧（domain / contracts / ai /
config）目前是占位包，供 V5（Web）/ V6（Desktop）/ V4（Cloud Sync）使用 ——
**架构支持未来，代码只实现当前**。

## Mobile 分层（apps/mobile）

```text
presentation/   UI（Widget）
       ↓
application/    用例编排 + 组合根（AppServices）
       ↓
domain/         实体 / 枚举 / Repository 接口（纯 Dart，无 Flutter 依赖）
       ↑ 实现
data/           SQLite 实现：AppDatabase / SchemaMigrations / Sqlite*Repository
```

规则：

- UI 只依赖 **Repository 接口**（`domain/` 下的 abstract interface class），
  通过 `AppServices`（组合根）获取；不 import 任何 `data/` 类型
- domain 层不 import Flutter —— 可脱离 UI 测试
- 业务逻辑不写进 Widget
- 测试用 `sqflite_common_ffi` 内存库直接验证 Repository 行为

### 目录

```text
apps/mobile/lib/
├── core/
│   └── ai/             # AI 基础设施（model_list_client：一键获取模型列表）
├── domain/
│   ├── entity_ids.dart # 前缀 UUID 生成（goal_xxx / provider_xxx ...）
│   ├── time_codec.dart # 时间列编解码（毫秒精度 UTC ISO8601）
│   ├── goal/           # Goal + GoalMetric/MetricValue + Repository 接口
│   ├── phase/
│   ├── task/
│   ├── schedule/
│   ├── progress/       # ProgressEvent
│   ├── ai/             # AiProvider / 供应商模板 / 模型缓存 / 默认模型
│   └── settings/       # 全局键值偏好接口
├── data/
│   ├── database/       # AppDatabase（打开/迁移）+ schema_migrations
│   └── repositories/   # Sqlite*Repository
├── application/
│   ├── app_services.dart        # 组合根：装配全部 Repository
│   └── ai_provider_service.dart # 供应商/模型/默认模型用例编排
└── presentation/
    ├── app.dart
    ├── home/           # P0 占位首页（P2 替换为真首页）
    ├── settings/       # 设置（供应商管理 + 默认模型）
    └── widgets/        # 共享 UI（WarmCard：图片底暖色卡片）
```

## 视觉规范

- **配色**：暖色调（[app_palette.dart](./apps/mobile/lib/core/config/app_palette.dart)）——
  日落橙（主）/ 珊瑚红 / 琥珀金 / 蜜桃粉，奶油色页面底，暖棕文字；
  不同功能区块用不同暖色，避免整屏同色
- **图标**：Font Awesome 6 Free（font_awesome_flutter），
  供应商模板的图标映射在 presentation/settings/provider_icons.dart
- **插画**：AI 生成（gpt-image skill），资产在
  `apps/mobile/assets/images/`：logo / hero（首页主视觉）/ bg_home（页面背景）/
  card_bg_{orange,coral,amber}（WarmCard 底图，图上叠浅奶油蒙版保证文字可读，
  图片缺失时自动退化为暖色渐变）
- **App 图标**：由 logo.png 经 flutter_launcher_icons 生成
  （`dart run flutter_launcher_icons`，改动 logo 后需重跑）

## 动效体系（Motion Design System）

技术组合：**Flutter 原生动画（结构性：Hero / Tab / 隐式动画）
+ flutter_animate（UI 微动效：fade / slide / stagger）**；
Rive / Lottie 预留给未来的设计师资产（庆祝、空状态），不做主动画库。

统一入口 `lib/core/motion/`（硬性规范见 AGENTS.md，页面禁止裸写 duration/curve）：

```text
motion/
├── app_motion.dart       # 时长：instant 100 / fast 160 / normal 240 / slow 360 / page 300ms
├── app_curves.dart       # 曲线：standard easeOutCubic / emphasized easeOutBack / exit / count
├── motion_effects.dart   # flutter_animate 预设：entrance / staggerIn / popIn
└── motion_transition.dart# MotionPageRoute（淡入+上滑页面过渡）+ pushMotion()
```

已落地的动效语言：

| 场景 | 动效 |
| --- | --- |
| 页面切换 | MotionPageRoute 淡入 + 3.5% 上滑（全局统一） |
| 目标卡片 → 详情 | Hero 共享过渡（卡片容器连续飞行「展开」） |
| 首页/详情/列表入场 | staggerIn 逐项错位淡入上移 |
| 任务完成 | 勾选徽章 easeOutBack 弹跳 + 标题颜色/删除线平滑过渡 |
| 进度更新 | AnimatedProgressBar 增长 + AnimatedPercent 数字滚动（72→73 连续变化） |

## 领域模型

```text
Goal（聚合根）
├── Outcome:  GoalMetric → MetricValue（历史）
└── Process:  Phase → Task ── GoalTask（多对多，跨目标共享）
                    └── Schedule（什么时候做；同 Task 可重排多次）

ProgressEvent：一切重要变化的不可变事实（AI 分析的依据）
```

关键决策：

| 决策 | 理由 |
| --- | --- |
| ID = 前缀 + UUID 字符串 | 为云同步预留跨设备唯一标识，不用自增 ID |
| 时间列 = 毫秒精度 UTC ISO8601 文本 | 固定宽度 → 字符串比较/排序与时间序一致；统一 UTC 便于同步 |
| 枚举存 TEXT（snake_case） | 可读、可调试、同步友好 |
| Task 与 Goal 通过 goal_tasks 关联 | Task 可属于多个 Goal；不实现复杂依赖图 |
| Schedule 独立于 Task | 「做什么」与「什么时候做」分离；重排保留历史供 AI 分析 |
| Metric 可选 | 不强制所有 Goal 可量化；是否需要由 AI 判断 |
| ProgressEvent 不可变 | 状态会被覆盖，事件不会；它是进度分析的事实依据 |

## 数据库

- 引擎：sqflite（iOS/Android），测试注入 sqflite_common_ffi 内存库
- 版本化迁移：`schema_migrations.dart` 中每个版本一个 `SchemaMigration`，
  只追加不修改；`onCreate`/`onUpgrade` 统一走 `runSchemaMigrations`
- 外键：每次连接 `PRAGMA foreign_keys = ON`；删除 Goal 级联删 Phase/Metric，
  删除 Phase 将 Task 的 `phase_id` 置空，删除供应商级联删模型缓存
- 当前 schema v2（v1 目标域 + v2 AI 供应商域），表结构见
  [docs/database/schema-v1.md](./docs/database/schema-v1.md) /
  [docs/database/schema-v2.md](./docs/database/schema-v2.md)
- conversations / data_sources / permissions / notifications 等表随后续迁移版本追加

## AI 供应商与 Agent（P3/P4/P5 已落地）

- 用户可配置多个供应商：内置模板（智谱 / OpenAI / Claude 官方 / DeepSeek /
  Kimi / 通义）快速预填，或完全自定义 Base URL + API Key + 协议风格
- 一键获取模型列表：OpenAI 兼容（`GET {base}/models` + Bearer）与
  Anthropic（`GET {base}/v1/models` + x-api-key）双协议；结果缓存于
  ai_models（fetched 全量替换、manual 手动补录且优先）
- 默认模型与供应商分开配置（settings 表 `ai.default_model` 键），
  删除供应商时自动清除指向它的默认模型
- `core/ai/chat_client.dart`：双协议对话调用（含 Tool Calling 全链路），
  Agent 复用同一客户端
- `application/agent_service.dart`：Goal Agent ——
  Context Builder（按场景紧凑组装）→ 工具循环（≤8 轮，22 个工具包装 P1 用例）→
  回答；供应商失败自动回退到其他已启用供应商（fallbackNote 轻提示）；
  工具统一携带 ToolRunContext（goalId / conversationId）执行
- 会话持久化：schema v3 conversations / conversation_messages；
  模型回放只取 user/assistant 最近 10 条，activity 仅供本地展示
- **计划提案（P5，plan §25）**：结构性变更（新目标规划 / 重新规划 / 缩小 /
  延期超 7 天）不直接落库，走 `propose_plan` 工具产出 PlanProposal
  （schema v4），挂到 assistant 消息上渲染确认卡片；
  [应用计划] 由 ProposalService.apply 一次性落库（目标+指标+阶段+任务+日程
  或 调整减法），[修改] 让用户继续对话、AI 重新提案（旧 pending 自动取代）
- **Progress Loop（P6，plan §46）**：`analyze_progress` 工具返回
  AnalysisService 聚合事实（完成率 / 延期率 / 逾期 / 指标趋势 / hasSignals），
  模型据此诊断并给出至多 2 个调整选项（走 propose_plan）；
  暂停/恢复/取消/归档目标走 `propose_action` 生成是/否确认卡片，
  用户点确认才执行；每日 AI 回顾（DailyReviewService）在 App 打开时
  生成一句行动指引（每日缓存、模型链回退、失败静默、设置可关）
- **本地通知（P7，plan §47）**：`core/notifications/reminder_platform.dart`
  平台抽象（可注入 fake）+ flutter_local_notifications 实现；
  `NotificationScheduler` 按「最近一次未来日程」提前 10 分钟提醒，
  PlanningService `onTaskChanged` 钩子让全部写操作（UI + AI 工具）自动重排；
  通知按钮「完成了/延后 1 小时」直接落库；点击通知深链目标详情；
  App 启动 `syncAll` 补排（设备重启后恢复提醒）；全部入口静默容错
- **联网搜索（P8，plan §48）**：`core/search/` —— SearchProvider 抽象 +
  DuckDuckGo（免 key 默认）/ Tavily（可选 key，settings 表）双实现，
  SearchService 来源链（Tavily 优先失败降级）；PageFetcher 抓网页正文
  （去标签、实体转义、截断 4000 字符）；`web_search` / `fetch_web_page`
  工具进 Agent；引用规则由系统提示词承载（结论必须附来源）
- **External Data 框架（P9，plan §49）**：DataProvider 接口
  （checkPermission / requestPermission / readContext）+
  schema v5 `data_source_permissions` 授权层 + ExternalDataService
  （Context Adapter：已授权源片段 → ContextBuilder `external` 键，
  单源失败静默跳过）；天气源首个真实现（Open-Meteo 免 key + 城市配置），
  health/location/calendar 占位待版本开放
- API Key V1 明文存本机 SQLite（无后端不上传），UI 脱敏展示

## AI 接入（P3+ 预告，尚未实现）

- AI 是 Agent 而非聊天接口：通过 Tool Registry 操作 Goal/Plan/Task/Progress/Metric
- Provider 抽象（OpenAI Compatible / Anthropic / 智谱 / Custom）+ Model Policy + Fallback
- Context Builder 按需构建上下文，不倾倒全库
- 重大结构变化（拆分/合并 Goal、大幅调整 Plan）需要用户确认
- Web Search 也是 Tool；External Data（Health/Weather/Location/Calendar）经
  Permission 层 → Adapter → Context Builder，AI 不直接调用系统 API

## 长期演进（不改变现有分层）

```text
V4 Cloud Sync:  Repository 之下增加 RemoteDataSource + SyncService
V5 Web:         packages/domain + contracts 供给 Next.js
V6 Desktop:     Tauri 2 + React
```

SQLite 始终是移动端本地事实源；云端只做同步、备份、跨设备与 Web。
