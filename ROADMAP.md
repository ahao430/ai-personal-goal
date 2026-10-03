# ROADMAP — 路线图

> 总体规划的事实源是 [plan.md](./plan.md)；本文跟踪执行进度与后续方向。
> 版本策略见 [CHANGELOG.md](./CHANGELOG.md) 头部。

## 当前状态（v1.0.0 · V1 已发布）

- ✅ P0 工程初始化 · ✅ P1 本地数据层 · ✅ P2 核心 UI
- ✅ P3 AI Provider（含模板/一键取模型/默认模型/对话调用/回退链）
- ✅ P4 AI Agent 核心（Context Builder / Tool Registry / Tool Calling /
  会话持久化 / 聊天入口）
- ✅ P5 AI Planning（propose_plan 提案 → 确认卡片 → 一键应用）
- ✅ P6 Progress Loop（analyze_progress 分析 / propose_action 二次确认 /
  每日 AI 回顾）
- ✅ P7 Notification（本地通知 + 通知动作 + 深链 + 日历月视图）
- ✅ P8 Web Search（web_search / fetch_web_page + 引用来源 + Tavily 可配）
- ✅ P9 External Data 框架（DataProvider / Permission / Context Adapter + 天气源）
- ✅ P10 测试打磨（完整 Goal Loop E2E + AI Evaluation Cases）
- 🎉 **V1 发布（1.0.0）**：plan §51 完成标准全部达成，全程无需服务器
- 后续：V2 起的长期路线（见下文）

---

# V1 阶段路线图

## P0 项目初始化 ✅（0.0.1）

- [x] pnpm monorepo / Flutter App / 分层架构 / Domain Models
- [x] SQLite + Migration 框架 / Repository 接口与实现
- [x] 基础测试 / README / ARCHITECTURE / docs

## P1 本地数据层 ✅（0.0.2）

- [x] Application 用例（GoalService / PlanningService / ProgressService）
- [x] Goal 进度计算（未取消任务完成比例；跨 Goal 联动）
- [x] 事件自动记录（状态变化 → ProgressEvent；阶段自动完成）

## P2 核心 UI ✅（0.1.0）

- [x] 底部导航：首页 / 目标 / 我的（Riverpod）
- [x] 首页（今天 / 当前目标 / 需要处理）
- [x] Goal List（状态过滤 + 暖色卡片）/ Goal Detail（路线 / 任务 / 动态）
- [x] 目标创建 / 编辑（含可选初始 Metric）；设置页
- [x] 状态管理选型：Riverpod
- [ ] 日历月视图（完整月历随 P7 提醒一起做；当前以日程列表呈现）

## 动效体系 ✅（0.1.1）

- [x] core/motion 统一时长/曲线/预设/页面过渡；Hero 共享过渡；
  列表错位入场；任务完成微动效；进度数字滚动（规范见 AGENTS.md）

## P3 AI Provider ✅（0.0.1 部分 + 0.2.0 收尾）

- [x] Provider / Model / API Key 存储（schema v2）
- [x] 供应商模板（智谱/OpenAI/Claude/DeepSeek/Kimi/通义/自定义）
- [x] 一键获取模型列表（双协议；fetched 缓存 + manual 补录）
- [x] 供应商与默认模型分开配置
- [x] 对话调用客户端（OpenAI 兼容 + Anthropic 双协议，含 Tool Calling）
- [x] Fallback：默认模型失败 → 其他已启用供应商自动切换（0.2.0）
- [ ] Model Policy（Task Type → 模型映射表）：V1 简化为「默认模型 + 回退链」，
      Policy 表随实际需求再加（plan §22 的接口位保留）

## P4 AI Agent + Tools ✅（0.2.0）

- [x] Context Builder（按场景动态组装，不倾倒全库；docs/ai/prompts.md §3）
- [x] Tool Registry + 首批 18 个工具：goal/phase/task/schedule/progress/metric
      （工具包装 P1 用例，统一 `{ok, data|error}` 返回）
- [x] Tool Calling 循环（最多 8 轮，工具活动实时透出 UI）
- [x] Structured Output（工具调用即结构化输出；不解析自由 JSON）
- [x] Conversation 持久化（schema v3：conversations / conversation_messages）
- [x] 聊天入口：首页「和 AI 聊聊」+ 目标详情「讨论这个目标」

## P5 AI Planning ✅（0.3.0）

- [x] 自然语言 → 澄清 → 提案 → 确认 → Goal/Phase/Task/Schedule 完整流
- [x] `propose_plan` 工具（schema v4 `plan_proposals` 表）：结构性变更
      只产出提案不直接落库，挂到会话消息上
- [x] 确认卡片（[应用计划] [修改]，docs/ai/prompts.md §4）：
      阶段/任务/指标/减法清单可视化，应用后变只读徽章；
      新提案自动取代旧 pending 提案
- [x] 调整提案：重新规划 / 缩小目标（取消阶段/任务）/ 延期（改目标日期）；
      暂停/恢复/单任务延期仍走简单工具直接执行
- [x] 工具运行上下文（ToolRunContext：goalId / conversationId）；
      `phase_cancelled` / `plan_applied` 事件类型

## P6 Progress Loop ✅（0.4.0）

- [x] 用户报告 → ProgressEvent → AI 分析 → 进度更新 → 计划调整
      （「首页做完了」→ complete_task、「明天再做」→ reschedule、
      「目标太大了」→ propose_plan 调整提案，P4/P5 已通）
- [x] `analyze_progress` 工具：完成率 / 近 14 天延期率 / 逾期数 /
      指标趋势 / 事件时间线 / hasSignals 聚合事实（AnalysisService）；
      系统提示词要求「先拿事实再诊断，无偏差证据不建议调整」
- [x] `propose_action` 工具：暂停 / 恢复 / 取消 / 归档目标走
      是/否确认卡片（ActionConfirmCard），用户点确认才执行（plan §25）
- [x] 每日 AI 回顾：DailyReviewService（每天生成一次、settings 按日期
      缓存、模型链回退、失败静默降级）+ 首页回顾卡 + 「我的 → AI 功能」开关

## P7 Notification ✅（0.5.0，日历月视图待做）

- [x] Schedule → Local Notification（提前 10 分钟；App 关闭仍可提醒，
      App 启动自动补排）
- [x] 通知动作：完成了 → complete_task；延后 1 小时 → reschedule_task
- [x] 通知点击深链 → 目标详情
- [x] PlanningService 钩子自动重排（UI 手动与 AI 工具写操作共用链路）；
      「我的 → AI 功能」开关
- [x] 日历月视图（月历网格 + 当日条目标记 + 选中日任务列表；
      首页与目标详情双入口，0.5.1）

## P8 Web Search ✅（0.6.0）

- [x] SearchProvider 抽象：DuckDuckGo（免 key 默认）+ Tavily（可选配置，
      失败自动降级）；SearchService 来源链
- [x] `web_search` / `fetch_web_page` 工具（累计 24 个）；
      PageFetcher 去标签截断
- [x] Citation：系统提示词要求搜索结论附「参考来源：标题 (链接)」，
      时效性信息无来源不断言
- [x] 智能判断是否需要搜索（旅行/考试/最新信息 → 搜；个人任务 → 不搜）；
      「我的 → AI 功能」可配置 Tavily Key

## P9 External Data 框架 ✅（0.7.0）

- [x] 框架四组件：DataSource（ExternalSource 枚举）/ DataProvider 接口 /
      Permission（schema v5 + 授权状态）/ Context Adapter（ExternalDataService
      → ContextBuilder `external` 键）
- [x] 天气源首个真实现：Open-Meteo 免 key + 城市配置（geocoding），
      今明温度/降水进 AI 上下文，可换城市/关闭
- [x] Health / Location / Calendar：占位 Provider（可记录授权意向），
      真实系统权限接入随版本开放（Health Connect / CoreLocation / EventKit）

## P10 测试 + V1 Release ✅（1.0.0）

- [x] 完整 Goal Loop 端到端测试（goal_loop_e2e_test：规划→确认→提醒→
      通知完成→汇报→分析→调整→二次确认→达成，全程同一会话可回放）
- [x] AI Evaluation Cases（ai_evaluation_test ×7 + docs/ai/evaluation.md：
      Tool 选择 / 参数纠错 / 上下文质量 / 确认规则 / Fallback）
- [x] E2E 修出真实 bug：propose_action 提案未挂载消息（P6 引入）
- [x] Release 构建链路验证（R8 + 资源收缩）

## V1 完成标准（plan §51）

创建目标 → AI 理解 → AI 规划 → 查看路线 → 查看今天任务 → 收到提醒 →
完成任务 → 向 AI 汇报 → AI 更新进度 → AI 调整后续计划。全程不需要服务器。

---

# 长期路线（V2 → V7）

> 核心不变量：**Local-first** —— SQLite 始终是移动端事实源，服务端是可选增强。

## 总览

```text
V2  智能现实数据（Health / Weather / Calendar / Location）
V3  AI 长期用户上下文（User Context）
V4  Cloud Sync + 服务端 + MCP 网关        ← MCP 是服务端的一等能力
V5  Web（Next.js）
V6  Desktop（Tauri 2 + React）
V7  智能 Goal Network（子目标/依赖/冲突/协同）
```

## V4：服务端与 MCP（重点方向）

服务端不只是一个同步后端，而是把「目标管理」开放为一等能力：

```text
┌─────────────┐   MCP (streamable HTTP)   ┌──────────────────┐
│ 外部 Agent   │ ────────────────────────► │  Go 服务端        │
│ workuddy /   │   tools: plan.* / task.*  │  ├ MCP Server     │
│ Claude Code /│ ◄──────────────────────── │  ├ REST/Sync API  │
│ Cursor 等    │   计划与任务数据            │  └ PostgreSQL     │
└─────────────┘                            └────────┬─────────┘
                                                    │ Sync
                                           ┌────────▼─────────┐
                                           │  Flutter App      │
                                           │  SQLite（事实源）  │
                                           └──────────────────┘
```

### 场景：在编程 agent 里直接管理计划

用户在 workuddy（或其他支持 MCP 的 agent）里说「帮我把这个功能拆成开发计划，
安排到接下来两周」→ agent 调 `goal.create` / `plan.create` / `task.schedule` →
手机 App 同步后即见计划与提醒 → 执行产生 ProgressEvent 回流 →
外部 agent 下次读取真实进度继续调整。

### MCP 要点

1. **契约单源**：工具 schema 定义在 `packages/contracts`，App 内 Agent（Dart）
   与服务端 MCP（Go）同源生成/校验，行为语义完全一致。
2. **同一确认规则**：docs/ai/prompts.md §4 的确认阈值对 MCP 调用同样生效，
   由服务端强制执行（结构性变更返回「待确认」，App 内点确认）。
3. **鉴权**：用户级 API Key；MCP transport 用 streamable HTTP + Bearer。
4. **冲突**：SQLite 为准；MCP 写入同样产生带来源的 ProgressEvent（source=ai）。

### 服务端形态

Go + PostgreSQL（`services/api/`），MCP 与 REST/Sync 同进程；单二进制可自托管。

## V2 智能现实数据

Health（Apple Health / Health Connect）、Weather、Location、Calendar 经
Permission → DataProvider → Context Builder 进入 AI（雨天改室内、会议日减量）。

## V3 AI 长期用户上下文

沉淀可用时间 / 工作时段 / 偏好 / 约束，规划时自动注入 User Context。

## V5 Web（Next.js）

查看/编辑目标与计划 + AI Chat + 数据分析；复用 packages/domain + contracts。

## V6 Desktop（Tauri 2 + React）

快速捕获工作台：全局快捷键、快速记录、截图、Tray、快速汇报。

## V7 智能 Goal Network

子目标 / 关联 / 依赖 / 冲突 / 协同；AI 识别时间冲突与任务复用。

## 版本与里程碑对照（预期，非承诺）

| 产品版本 | 内容 |
| --- | --- |
| 0.x | V1 阶段迭代（大功能 0.x.0，常规 0.x.y） |
| 1.0.0 | V1 完整闭环（plan §51 验收标准） |
| 1.1+ | V2 现实数据 |
| 2.0.0 | V4 服务端 + MCP 上线（架构级变化 → 主版本） |
