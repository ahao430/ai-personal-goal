# Changelog

本项目的所有显著变更都记录在此文件中。

## 版本策略

| 变更类型 | 版本变化 | 示例 |
| --- | --- | --- |
| 常规迭代（功能补全、修复、小优化） | 第三位 +1 | 0.0.1 → 0.0.2 |
| 较大的功能改动（新子系统、架构级变化） | 第二位 +1，第三位归零 | 0.0.x → 0.1.0 |
| V1 闭环正式发布 | 1.0.0 | 0.x.y → 1.0.0 |

规则：

- **monorepo 各 app 版本独立**：mobile 的版本事实源是
  `apps/mobile/pubspec.yaml` 的 `version`（格式 `x.y.z+build`，build 号随发版 +1）；
  根 `package.json` 是工作区自身版本，**不与任何 app 同步**；
  `packages/*` 与 `services/*` 各自维护。
- **mobile 每次交付必须**：更新 pubspec 版本 + 在本文件顶部新增条目
  （作用域前缀，如 `[mobile 1.0.1]`）。
- 云端打包与发版触发规则见 `.github/workflows/README.md`。

---

## [mobile 1.0.1] - 2026-10-03

修复真机 release 包无网络的问题。

- **Bug**：release APK 所有网络请求报
  `SocketException: failed host lookup, errno = -7`（DNS 解析失败）——
  Flutter 模板只在 debug/profile 清单声明 INTERNET 权限，
  main（release 合并源）没有。真机上配置 glm / deepseek / 自定义供应商
  后「获取模型列表」全部失败。已在 main manifest 显式声明
  `android.permission.INTERNET`。
  （测试全用 MockClient 且未在 release 真机跑过真实网络，故未拦截）
- 版本：`apps/mobile/pubspec.yaml` → `1.0.1+13`

---

## [workspace 0.1.0] - 2026-10-03

monorepo 版本与各 app 解耦 + CI 云端打包接入。

- 根 `package.json` version 从 1.0.0 回到 **0.1.0**（工作区自身版本，
  独立演进）；mobile 版本继续以 `apps/mobile/pubspec.yaml` 为唯一事实源
  （当前 1.0.0+12），`packages/*` 各共享包维持各自 0.1.0
- CI（`.github/workflows/mobile-ci.yml`）：push/PR 涉及 `apps/mobile/**`
  时触发 analyze + 全量测试 + release APK（split-per-abi）→ Artifacts
- 发版（`mobile-release.yml`）：tag `mobile-v*` 触发，APK 挂 GitHub
  Release（不进 git 仓库；当前 debug 签名仅侧载）
- 触发矩阵与新 app 接入指南：`.github/workflows/README.md`
  （后续 app 用各自路径过滤与 tag 前缀，互不干扰）

---

## [mobile 1.0.0] - 2026-10-03

**V1 正式发布**（plan §51 完成标准全部达成，P10 收官）。

### P10 · 测试与打磨

- **完整 Goal Loop E2E**（`test/application/goal_loop_e2e_test.dart`）：
  一条测试自动化 V1 验收全流程 —— 自然语言规划 → 提案（确认前不落库）→
  确认应用（目标+指标+阶段+任务+日程）→ 今天列表可见 → 提醒自动排 →
  通知按钮完成 → 向 AI 汇报（指标更新+事件）→ AI 分析 → 调整提案 →
  暂停二次确认 → 完成剩余任务 → 目标达成（100%）→ 会话全程可回放
  （含提案卡片挂载）
- E2E 抓出并修复一个真实 bug：`propose_action` 的提案 ID 未被
  AgentService 捕获，动作确认卡片不会挂到消息上（P6 引入）
- **AI Evaluation Cases**（`test/application/ai_evaluation_test.dart` ×7 +
  [docs/ai/evaluation.md](./docs/ai/evaluation.md)）：工具选择 /
  参数纠错回传 / 上下文质量 / 确认规则 / 供应商回退 的固定契约用例集，
  为真实模型跑分预留同套定义
- Release 构建链路验证通过（R8 代码收缩 + 资源收缩）

### V1 完成标准对照（plan §51）

| 标准 | 状态 |
| --- | --- |
| 创建目标 | ✅ 手动 + AI 提案两路 |
| AI 理解（澄清）| ✅ 系统提示词 + 上下文 |
| AI 规划 | ✅ propose_plan → 确认卡片 |
| 查看路线 | ✅ 目标详情「路线」Tab + 日历月视图 |
| 查看今天任务 | ✅ 首页「今天」 |
| 收到提醒 | ✅ 本地通知（提前 10 分钟，重启恢复） |
| 完成任务 | ✅ UI 勾选 / 通知按钮 / AI 工具 |
| 向 AI 汇报 | ✅ 聊天（报告/指标/延期） |
| AI 更新进度 | ✅ 事件 + 进度重算 + 指标推进 |
| AI 调整后续计划 | ✅ analyze_progress → adjust 提案 |
| 全程不需要服务器 | ✅ SQLite 事实源；AI 走用户自配供应商 |

### 版本

- `apps/mobile/pubspec.yaml` → `1.0.0+12`；根 `package.json` → `1.0.0`
- 累计 152 个测试全绿；`flutter analyze` 零问题

---

## [0.7.0] - 2026-10-03

P9 External Data 基础框架完成：**DataProvider / Permission / Context Adapter
四组件齐备，天气源作为首个可跑实现**（plan §49，较大功能改动 → 0.7.0）。

### 新增 · External Data 框架

- **Schema v5**：`data_source_permissions` 表（source 主键 / status /
  updated_at）—— 权限层持久化
- **Domain**：`ExternalSource`（health / weather / location / calendar）、
  `PermissionStatus`（notRequested / requested / granted / denied）、
  `DataSourcePermission` + Repository 接口与 SQLite 实现
- **DataProvider 接口**（`core/external/data_provider.dart`）：
  checkPermission / requestPermission / readContext —— UI、Context Adapter
  只依赖接口，未来接 Health Connect 等实现无需改上层
- **WeatherDataProvider**（首个真实现）：Open-Meteo 免 key API（forecast +
  geocoding），城市配置存 settings（`weather.location`）；
  readContext 返回当前温度/体感/天气 + 今明两日温度与降水概率（WMO 码转中文）；
  未授权/未配城市/请求失败 → null 静默降级
- **PlaceholderDataProvider**：health / location / calendar 框架占位
  （可记录授权意向，readContext 恒 null）
- **ExternalDataService**（Context Adapter）：收集「已授权且可用」源片段
  拼进 AI 上下文 `external` 键，单源失败不影响其它源；ContextBuilder 集成
- **UI**：「我的 → 数据与权限」从写死预告改为动态渲染注册源 ——
  状态徽章（未开启/待版本开放/已授权）；天气可开启（输入城市自动 geocode）、
  换城市、关闭

### 测试

- 新增 8 个用例（累计 144 全绿）：迁移 2（v5 表 + 旧库升级）、权限存取 1、
  天气 3（geocode+forecast 请求形态与解析 / 三种 null 降级 / 找不到城市）、
  Context Adapter 3（已授权进上下文 / 全未授权跳过 / ContextBuilder 正向集成）

### 版本

- `apps/mobile/pubspec.yaml` → `0.7.0+11`；根 `package.json` → `0.7.0`

---

## [0.6.0] - 2026-10-03

P8 Web Search 完成：**AI 能查外部信息并给出引用来源**（较大功能改动 → 0.6.0）。

### 新增 · 联网搜索（plan §48）

- **SearchProvider 抽象**（`core/search/search_provider.dart`）：
  - `DuckDuckGoSearchProvider`：免 API key 默认来源（HTML 端点解析，
    uddg 重定向解码、HTML 实体转义、限流抛错）
  - `TavilySearchProvider`：可选高质量来源（Bearer 认证，
    key 存 settings 表 `search.tavily_key`）
- `SearchService`：来源链 —— 配置了 Tavily key 则 Tavily 优先
  （失败自动降级），否则 DuckDuckGo
- `PageFetcher`：网页抓取 → 去 script/style/标签、HTML 实体转义、
  折叠空白、截断 4000 字符（防撑爆上下文）；15 秒超时
- **工具 ×2**（累计 24 个）：
  - `web_search(query, maxResults?)`：返回 title/url/snippet + 引用要求
  - `fetch_web_page(url)`：抓取网页正文供模型精读
- **引用规则**（系统提示词）：考试/旅行/价格/最新资料等外部事实才搜，
  个人任务不搜；回复中的搜索结论必须附「参考来源：标题 (链接)」
- **设置 UI**：「我的 → AI 功能 → 联网搜索」——可配置/清除 Tavily Key，
  显示当前来源状态

### 测试

- 新增 13 个用例（累计 136 全绿）：DDG 解析 3（结果/uddg 解码/截断/
  限流报错）、Tavily 请求形态 1、PageFetcher 3（去标签转义/截断/异常）、
  SearchService 2（key 优先与降级链）、工具 4（web_search/fetch_web_page/
  错误回传/schema 暴露）

### 版本

- `apps/mobile/pubspec.yaml` → `0.6.0+10`；根 `package.json` → `0.6.0`

---

## [0.5.1] - 2026-10-03

P7 遗留补全：**日历月视图**（常规迭代 → 0.5.1）。

### 新增 · 日历月视图

- `CalendarPage`（`presentation/calendar/calendar_page.dart`）：
  月历网格（周一起始 / 今日描边 / 选中高亮 / 当日条目数圆点标记），
  月份切换带过渡动效；选中日下方列出任务（时间 · 时长，可直接完成/
  开始/取消），与动效规范一致（格子切换 fade、列表 stagger 入场）
- `OverviewService.calendarView(month, {goalId})` 聚合：月内 planned
  日程按日程落位（同任务多个日程都展示）、无日程但有截止的按截止日
  落位、已完成/已取消剔除、按目标过滤；服务层排序，UI 纯渲染
- 入口：首页「今天」区块标题右侧日历图标（全部目标）；目标详情 AppBar
  日历图标（该目标上下文，AppBar 显示目标名）

### 测试

- 新增 5 个用例（累计 123 全绿）：聚合 3（日程/截止/完成剔除/目标过滤/
  跨月/多日程排序）、日历页 widget 2（默认选中今天 + 切换日期联动、
  目标上下文过滤）

### 版本

- `apps/mobile/pubspec.yaml` → `0.5.1+9`；根 `package.json` → `0.5.1`

---

## [0.5.0] - 2026-10-03

P7 Notification 完成：**按计划时间提醒（App 重启仍生效）→ 通知直接完成/延后 →
点击深链目标详情**（较大功能改动 → 0.5.0）。

### 新增 · 本地通知（plan §47）

- `core/notifications/reminder_platform.dart`：`ReminderPlatform` 平台抽象
  （接口可注入 fake）+ `ReminderPlatformImpl`（flutter_local_notifications v22
  包装）：初始化时区、通知权限（Android 13+ POST_NOTIFICATIONS 运行时请求）、
  精确闹钟尽力而为（未授予自动降级 inexact）、通知按钮
  「完成了 / 延后 1 小时」、冷启动 launch 事件补发；
  全部平台调用异常防护 —— 测试/桌面环境静默降级 no-op
- `application/notification_scheduler.dart`：提醒调谐器 ——
  每任务一个通知 id（重排即覆盖）、取「最近一次未来日程」提前 10 分钟提醒；
  `syncTask`（任务/日程变化后重排）/ `syncGoal`（提案应用后批量）/
  `syncAll`（App 启动补排，设备重启后恢复提醒）/ 开关（关闭取消全部）
- **自动接线**：PlanningService 新增 `onTaskChanged` 钩子，全部任务/日程
  写操作（UI 手动 + AI 工具共用）自动重排提醒；ProposalService.apply 后
  整目标补排；通知按钮动作落地（完成 → completeTask、延后 → reschedule +1h）
- 深链：点击通知 → AppShell 订阅事件 → pushMotion 目标详情（plan §47）

### 配置

- Android 权限：POST_NOTIFICATIONS / SCHEDULE_EXACT_ALARM / VIBRATE
- Android 构建：开启 core library desugaring（flutter_local_notifications 要求，
  `desugar_jdk_libs 2.1.5`）
- 新依赖：flutter_local_notifications 22.3、timezone、flutter_timezone

### UI

- 「我的 → AI 功能」新增「任务提醒」开关（默认开；关闭取消全部通知，
  重新开启自动全量补排）

### 测试

- 新增 8 个用例（累计 118 全绿）：调度（未来日程/过去日程/完成任务/
  开关/改期）、通知按钮动作（snooze 改期 +1h、complete 完成任务）、
  提案应用补排、装配钩子自动同步（fake 平台记录调用，不触系统）

### 版本

- `apps/mobile/pubspec.yaml` → `0.5.0+8`；根 `package.json` → `0.5.0`

---

## [0.4.0] - 2026-10-03

P6 Progress Loop 完成：**AI 能看见偏差（分析）、能提出目标级操作（二次确认）、
App 打开时给一句今日指引（每日回顾）**（较大功能改动 → 0.4.0）。

### 新增 · 进度分析（plan §46）

- `AnalysisService`：目标执行聚合事实 —— 有效任务数（剔除取消）、完成率、
  逾期数、近 14 天延期/完成频次与延期率、指标趋势（窗口首尾值 / delta /
  是否朝目标方向前进）、近期事件时间线、`hasSignals` 偏差信号
- `analyze_progress` 工具（第 21 个）：把聚合事实交给模型，
  系统提示词要求「先拿事实再诊断；hasSignals=false 不建议调整」，
  确需调整给至多 2 个选项走 propose_plan

### 新增 · 目标级操作二次确认（plan §25）

- `ProposalKind.action` + `ProposalActions`（pause / resume / cancel /
  archive 白名单）；`propose_action` 工具（第 22 个）生成是/否确认卡片
- `ActionConfirmCard`：取消类操作红色警示、确认后转「已执行」徽章
- ProposalService.apply 分发到 GoalService 对应用例；dismiss 回执
  「已放弃 XX」；action 提案自动回填目标标题

### 新增 · 每日 AI 回顾

- `DailyReviewService`：App 打开时基于今日日程 + 昨日未完成 + 活跃目标
  生成 1-3 句行动指引；每天只生成一次（settings 按日期键缓存并清理昨日键）；
  供应商沿用模型链（默认 → 回退）；失败静默降级（首页不显示卡片）
- 首页回顾卡（WarmCard + 点击进入对话）；「我的 → AI 功能」开关
  （settings `feature.daily_review`）
- `modelChain()` 从 AgentService 下沉到 AiProviderService（对话与回顾共用）

### 变更

- `ChatClient.complete` 的 `tools` 参数改为可选（每日回顾不传工具）
- 系统提示词新增「进度分析」「目标级操作（二次确认）」两节；
  docs/ai/prompts.md §2 progress.analysis / daily.review 标记 ✅ 并说明落地形态

### 测试

- 新增 18 个用例（累计 110 全绿）：分析服务 5（完成率/逾期/延期频次/
  指标趋势/无信号）、提案 action 4（暂停执行/校验/放弃回执/取消目标）、
  工具 3（analyze_progress 聚合 / propose_action 挂会话 / 非法操作报错）、
  每日回顾 6（未配置/开关关闭/按日缓存/供应商回退/空响应/开关切换）

### 版本

- `apps/mobile/pubspec.yaml` → `0.4.0+7`；根 `package.json` → `0.4.0`

---

## [0.3.0] - 2026-10-03

P5 AI Planning 完成：**自然语言 → 澄清 → 计划提案 → 确认卡片 → 一键应用**
的核心产品链路打通（较大功能改动 → 0.3.0）。

### 新增 · 计划提案（结构性变更先确认，plan §25）

- **Domain**：`PlanProposal`（kind：create 新目标全套计划 / adjust 结构调整；
  status：pending / applied / dismissed / superseded）+
  `PlanProposalRepository` 接口与 SQLite 实现（`prop_` 前缀 ID）
- **Schema v4**：`plan_proposals` 表（payload_json 存完整提案内容）+
  `conversation_messages.proposal_id` 列（确认卡片挂到具体消息）
- **`propose_plan` 工具**（第 20 个）：新目标规划与结构性调整
  （重新规划/缩小/延期超 7 天/批量删任务）一律走提案，不直接写目标数据；
  参数含 metric（量化指标）、phases（阶段+任务+可选排期 startAt）、
  removePhaseIds / removeTaskIds（减法清单）、reason（现状 vs 建议）
- **ProposalService**：`apply`（create：目标+指标+阶段+任务+日程一次落库；
  adjust：改期/取消任务/取消阶段/新增阶段）、`dismiss`；
  同一会话新提案自动取代旧 pending 提案；
  应用/忽略都会在会话里留 activity 消息，`plan_applied` 事件进目标动态

### 变更

- **工具运行上下文**（`ToolRunContext`）：AgentService 注入
  goalId / conversationId，全部 20 个工具统一双参签名
  （跨端契约单源，为 V4 服务端 MCP 铺路）
- **PlanningService.cancelPhase**：取消阶段（先取消其未完成任务，
  再置 cancelled，幂等）；新增 `phase_cancelled` / `plan_applied` 事件类型
- **系统提示词**（docs/ai/prompts.md §1 同步）：规划方法落到 propose_plan，
  「修改」流程（旧提案自动被取代，AI 基于上一版调整重新提案）

### UI

- **确认卡片**（`presentation/widgets/plan_proposal_card.dart`）：
  指标 chip（72.5 → 67.5 kg）、阶段列表 stagger 入场（动效规范）、
  减法清单、pending 态 [应用计划] [修改] 双按钮，
  应用后变只读徽章（已应用 / 已忽略 / 已有新版本提案）
- **ChatPage 集成**：发送完成后统一重读会话（消息+提案）；
  [应用计划] 落库后 SnackBar 汇总 + invalidateAll 刷新全部列表；
  [修改] 预填输入并聚焦（不忽略旧提案，AI 重新提案时自动取代）

### 测试

- 新增 14 个用例（累计 92 全绿）：提案服务 6（create/adjust 落库、
  取代、重复应用、忽略、校验）、迁移 2（v4 表/列 + 旧库升级）、
  工具 2（propose_plan 存 pending 提案挂会话 / 错误回传）、
  Agent 闭环 1（提案挂到 assistant 消息 → 确认后应用）、卡片 UI 4

### 版本

- `apps/mobile/pubspec.yaml` → `0.3.0+6`；根 `package.json` → `0.3.0`

---

## [0.2.0] - 2026-10-03

P3 收尾 + P4 AI Agent 核心完成：**用户自然语言 → AI → 工具 → SQLite → UI 刷新**
的链路已打通（较大功能改动 → 0.2.0）。

### 新增 · 对话客户端（P3 收尾）

- `core/ai/chat_client.dart`：OpenAI 兼容（`/chat/completions`）与
  Anthropic（`/v1/messages`）双协议对话调用，完整支持 Tool Calling
  （请求构造 / tool_calls 解析 / 工具结果回传，Anthropic 连续
  tool_result 自动合并为单条 user 消息）
- 供应商回退链：默认模型失败 → 其他已启用供应商自动切换，
  切换提示经 UI 轻量透出（plan §23）

### 新增 · AI Agent（P4）

- **Tool Registry**（`application/tool_registry.dart`）+ 首批 19 个工具
  （`application/ai_tools.dart`）：goal 6 个 / phase 2 个 / task 5 个 /
  schedule 2 个 / progress 2 个 / metric 2 个；
  工具全部包装 P1 用例（不直碰 Repository），统一 `{ok, data|error}` 返回，
  错误原样交回模型自行纠正
- **Context Builder**（`application/context_builder.dart`）：按场景动态组装
  紧凑 JSON 上下文（目标摘要 / 开放任务 / 指标 / 最近事件），不倾倒全库
- **AgentService**（`application/agent_service.dart`）：工具循环（≤8 轮）+
  活动实时回调（「正在创建目标…」）+ 会话历史回放（user/assistant 最近 10 条）；
  未配置供应商抛可恢复的 AgentNotConfiguredException 引导去设置
- 系统提示词常量（`core/ai/goal_agent_prompts.dart`，对齐 docs/ai/prompts.md）
- Schema v3：conversations / conversation_messages（含 v1→v3 升级迁移测试）

### 新增 · 聊天 UI

- 聊天页：用户气泡 / AI 卡片气泡 / 工具活动胶囊 / 输入中指示；
  恢复最近会话；发送后 invalidateAll 刷新首页与目标列表
- 入口：首页主视觉卡「和 AI 聊聊」+ 目标详情「讨论这个目标」（带 goalId 上下文）

### 变更 · 文档结构

- 路线图文件更名为根目录 **ROADMAP.md**（合并原 docs/roadmap/ 两份文档）
- 原页面导航地图移至 `docs/architecture/routes.md`

### 测试

- 新增 19 个用例：ChatClient 双协议 8 个、Agent 闭环 6 个（含回退/超限/
  历史回放）、工具执行 6 个、v3 迁移扩展；累计 78 用例全绿
- 修复测试基建：MockClient 响应需显式 UTF-8 content-type（http 包默认 Latin-1）

---

## [0.1.1] - 2026-10-03

动效体系（Motion Design System）落地，全 App 动画语言统一。

### 新增 · 统一动效系统（硬性规范）

- `core/motion/`：AppMotion 时长（100/160/240/360/300ms）+
  AppCurves 曲线（standard/emphasized/exit/count）+
  MotionEffects 预设（entrance / staggerIn / popIn，flutter_animate）+
  MotionPageRoute 页面过渡与 pushMotion() 全局跳转入口
- 规范写入 AGENTS.md：页面禁止自行定义 duration / curve
- 技术组合：Flutter 原生（结构性动画）+ flutter_animate（UI 微动效）；
  Rive / Lottie 预留给设计师资产，不做主动画库

### 新增 · 动效语言

| 场景 | 动效 |
| --- | --- |
| 页面切换 | 全局统一淡入 + 3.5% 上滑（替换所有 MaterialPageRoute） |
| 目标卡片 → 详情 | Hero 共享过渡，卡片「展开」成详情概览卡 |
| 首页区块 / 详情路线 / 目标列表 | 逐项错位淡入（stagger，切换过滤器时重放） |
| 任务完成 | 勾选徽章 easeOutBack 弹跳放大 + 标题颜色/删除线平滑过渡 |
| 进度更新 | AnimatedProgressBar 平滑增长 + AnimatedPercent 数字滚动（72→73） |

---

## [0.1.0] - 2026-10-03

P2 核心 UI 完成：**不用 AI 也能完整使用 App**（较大功能改动 → 0.1.0）。

### 新增 · 导航与状态管理

- 底部导航外壳：首页 / 目标 / 我的（不设 Chat Tab，plan §28）
- 状态管理选型 **Riverpod**（flutter_riverpod）：servicesProvider 在 main 注入，
  homeView / goalsList / goalDetail 三组 FutureProvider，
  写操作后统一 `invalidateAll` 刷新

### 新增 · 首页（真数据）

- 「今天」：今日日程（时间 + 时长）+ 今日截止任务（已排期的去重），
  可直接勾选完成 / 开始 / 延期 / 取消 / 安排时间
- 「当前目标」：最近更新的活跃目标，进度条 + 当前阶段 + 下一步
- 「需要处理」：过期未完成任务（有才显示）
- 保留暖色视觉（logo / 主视觉 / 背景 / WarmCard）

### 新增 · 目标列表与详情

- 目标列表：状态过滤芯片（进行中/已暂停/已完成/已归档/已取消）+
  循环暖色卡片（标题 / 进度条 / 目标日）
- 目标详情三 Tab：
  - **路线**：概览卡（状态/进度/描述/目标日）+ Metric 卡（记录值）+
    阶段时间线（完成态 / 任务计数 / 内嵌前 3 任务 / 添加阶段 / 重命名）
  - **任务**：按阶段分组，TaskTile 全操作（开始/完成/延期/安排时间/取消/重新打开）
  - **动态**：ProgressEvent 时间线（类型图标 + 来源）
- 目标菜单：编辑 / 暂停 / 恢复 / 完成 / 取消 / 归档 / 删除（确认对话框）
- 创建目标：标题 / 描述 / 目标日期 + 可选初始 Metric（名称/单位/当前值/目标值/方向）

### 新增 · 其他

- 「我的」页：AI 供应商设置入口、数据源权限预告（P9）、版本与隐私说明
- OverviewService：首页/详情聚合查询（TodayItem 任务+日程联查，
  消除 UI 层 n+1 与 Tile 内 FutureBuilder）
- pickScheduleTime：日期 + 时间 + 时长三步选择器（全流程可取消）

### 测试

- Widget 冒烟重写：AppShell + 底部导航 + 空状态 + 创建目标后首页渲染
  （目标标题 / 今日任务 / 下一步提示），累计 59 用例全绿

---

## [0.0.2] - 2026-10-03

P1 本地数据层完成：不接 AI 也能完整管理目标。

### 新增 · Application 层用例（P1）

- `GoalService`：创建/编辑目标（mapper 式更新，保留「置空 vs 不变」语义）、
  暂停/恢复/完成/取消/归档（同状态幂等，不重复发事件）、
  Metric 建立（初值直接入历史）与记录（推进 currentValue + metric_updated 事件）
- `PlanningService`：创建 Phase（orderIndex 自增）/ Task（给 phaseId 自动
  关联 Goal）；startTask（阶段随之 in_progress）、completeTask（幂等：
  completedAt + 完成 planned 日程 + 事件 + 进度重算）、
  postponeTask（可带新时间，顺带重排日程）、cancelTask（分母剔除）、
  scheduleTask / rescheduleTask（保留历史日程；改期使延期任务恢复 todo）、
  recordUserReport（用户自由汇报 → user_report 事件）
- `ProgressService` 进度引擎：统一事件发射；
  overallProgress = 未取消任务完成比例（四舍五入，无任务归 0，未变化不写库）；
  阶段全部任务完成时自动完成并发 phase_completed 事件（source=system）；
  跨 Goal 任务一次完成联动更新所有关联目标

### 测试

- 新增 13 个用例（goal_loop_test.dart）：目标生命周期幂等、事件完整性、
  进度计算（1/3→33、2/3→67、取消剔除分母）、阶段自动完成、
  延期/改期状态机、跨目标联动、P1 完整闭环

---

## [0.0.1] - 2026-10-03

首个工程版本：V1 基础工程 + AI 供应商管理 + 视觉体系。

### 新增 · 工程基础（P0）

- pnpm monorepo（apps / packages / docs / scripts）
- Flutter App（`apps/mobile`，iOS / Android，org `dev.aigoal`）
- 分层架构：presentation → application → domain ← data，UI 不接触 SQLite
- Domain Models：Goal / Phase / Task / Schedule / ProgressEvent /
  GoalMetric（前缀 UUID、毫秒 UTC ISO8601 时间列、snake_case 枚举列）
- SQLite（sqflite）+ 版本化 Migration 框架，schema v1（8 张目标域表，外键级联）
- Repository 接口（domain）+ SQLite 实现（data），
  goal_tasks 支持 Task 跨 Goal 多对多
- AppServices 组合根；首页占位（数据库状态展示）

### 新增 · AI 供应商管理（P3 部分）

- Schema v2：ai_providers / ai_models / settings（含 v1→v2 升级迁移）
- 供应商模板快速选择：智谱官方 / OpenAI 官方 / Claude 官方（Anthropic）/
  DeepSeek / Kimi / 通义千问 / 完全自定义（任意 Base URL + Key + 协议风格）
- 一键获取模型列表：OpenAI 兼容与 Anthropic 双协议；
  fetched 全量替换 + manual 手动补录（manual 优先）
- 供应商与默认模型分开配置；删除供应商自动清除默认模型
- API Key 本地明文存储（V1 无后端不上传），UI 脱敏展示

### 新增 · 视觉体系

- 暖色调 Material 3 主题（日落橙 / 珊瑚红 / 琥珀金 / 蜜桃粉 + 奶油底）
- Font Awesome 6 Free 图标（供应商模板专属图标映射）
- AI 生成插画资产：logo / hero（首页主视觉）/ bg_home / 三张暖色卡片底图
  （量化压缩：8.1MB → 2.2MB）
- WarmCard 组件：图片底 + 奶油蒙版，图缺时退化为暖色渐变
- flutter_launcher_icons 从 logo 生成 iOS / Android 应用图标

### 工程约定

- Android 只支持最新版：minSdk 35，release 开启 R8 + 资源收缩
- 版本策略（见上）与 CHANGELOG 流程建立
- 文档体系：README / AGENTS / CHANGELOG / ROUTES / ARCHITECTURE / plan.md /
  docs/{product,architecture,ai,database,roadmap}
