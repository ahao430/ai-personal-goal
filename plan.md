
# AI Goal App 项目总体规划

## 1. 项目定位

这是一个 **AI 驱动的个人目标管理 App**。

核心不是传统 Todo，而是：

> 用户提出目标 → AI 理解目标 → AI 制定计划 → 拆分阶段和任务 → 用户执行 → 用户反馈/系统数据产生进度 → AI 判断实际情况 → 调整计划 → 持续推进目标。

核心循环：

```text
Goal
 ↓
AI Clarification
 ↓
Plan
 ↓
Phase / Task / Schedule
 ↓
Execution
 ↓
User Report / System Data
 ↓
Progress Event
 ↓
AI Analysis
 ↓
Plan Adjustment
 ↓
Local Notification
 ↓
Continue
```

产品核心价值：

1. 帮用户把模糊目标变成可执行计划
2. 帮用户持续执行
3. 根据实际执行情况动态调整计划
4. 不要求用户维护复杂 Todo
5. 尽可能利用系统数据感知现实情况
6. AI 是目标管理 Agent，而不是单纯聊天机器人

---

# 2. 总体技术路线

## 2.1 V1

V1 完全 Local-first：

```text
Flutter App
│
├── SQLite
├── AI Provider
├── AI Agent
├── Web Search
├── Local Notification
├── Health / System Data Adapter
└── Repository
```

V1：

* 不需要登录
* 不需要账号
* 不需要后端
* 不需要云同步
* 不需要 Web
* 不需要 Desktop
* 不需要服务端推送
* 不需要服务端 Scheduler

AI 可以直接调用用户配置的模型 API。

---

# 3. 长期架构

未来逐步扩展：

```text
                         ┌──────────────┐
                         │   Web App    │
                         └──────┬───────┘
                                │
┌──────────────┐         ┌──────▼───────┐
│ Desktop App  │────────►│ Backend API  │
└──────────────┘         └──────┬───────┘
                                │
                         ┌──────▼───────┐
                         │ PostgreSQL   │
                         └──────────────┘
                                ▲
                                │ Sync
                                │
                         ┌──────┴───────┐
                         │ Flutter App  │
                         │   SQLite     │
                         └──────────────┘
```

长期原则：

> **Local-first, Cloud-optional**

即：

* 不连接服务器：App 正常使用
* 连接服务器：增加同步、备份、多设备、Web 等能力
* SQLite 始终是移动端本地事实来源
* 云端主要负责同步、备份、跨设备和 Web

不要设计成：

```text
App → Backend → 才能使用
```

---

# 4. Monorepo

使用 pnpm workspace 管理整个项目。

建议项目结构：

```text
ai-goal/
│
├── apps/
│   ├── mobile/
│   │   └── # Flutter App
│   │
│   ├── web/
│   │   └── # React / Next.js，未来
│   │
│   └── desktop/
│       └── # Tauri 2 + React，未来
│
├── packages/
│   ├── domain/
│   │   └── # Domain Model / 类型定义 / 业务概念
│   │
│   ├── contracts/
│   │   └── # API / Sync / AI Tool contracts
│   │
│   ├── ai/
│   │   └── # AI Agent / Prompt / Tool definitions
│   │
│   └── config/
│       └── # 公共配置
│
├── services/
│   └── api/
│       └── # Go Backend，未来
│
├── docs/
│   ├── product/
│   ├── architecture/
│   ├── ai/
│   ├── database/
│   └── roadmap/
│
├── scripts/
│
├── pnpm-workspace.yaml
├── package.json
├── README.md
└── .gitignore
```

注意：

**不要因为使用 pnpm monorepo 就强行让 Flutter 使用 TypeScript package。**

Flutter 仍然是独立 Dart 项目。

pnpm 主要负责：

* workspace
* docs
* Web
* Desktop
* shared contracts
* scripts
* future backend tooling

---

# 5. Mobile Flutter 架构

```text
apps/mobile/
│
├── lib/
│   ├── core/
│   │   ├── ai/
│   │   ├── database/
│   │   ├── notification/
│   │   ├── permissions/
│   │   ├── providers/
│   │   ├── external_data/
│   │   └── config/
│   │
│   ├── domain/
│   │   ├── goal/
│   │   ├── plan/
│   │   ├── phase/
│   │   ├── task/
│   │   ├── schedule/
│   │   ├── progress/
│   │   ├── metric/
│   │   ├── data_source/
│   │   └── user_context/
│   │
│   ├── data/
│   │   ├── database/
│   │   ├── repositories/
│   │   ├── local/
│   │   └── external/
│   │
│   ├── application/
│   │   ├── goal/
│   │   ├── planning/
│   │   ├── progress/
│   │   ├── scheduling/
│   │   └── ai/
│   │
│   └── presentation/
│       ├── home/
│       ├── goals/
│       ├── goal_detail/
│       ├── chat/
│       ├── settings/
│       └── widgets/
│
├── test/
└── pubspec.yaml
```

核心原则：

```text
UI
 ↓
Application / UseCase
 ↓
Repository
 ↓
LocalDataSource
```

不要把业务逻辑写进 Widget。

---

# 6. 核心 Domain Model

## 6.1 Goal

```text
Goal
├── id
├── title
├── description
├── status
├── startDate
├── targetDate
├── overallProgress
├── createdAt
└── updatedAt
```

状态：

```text
active
paused
completed
cancelled
archived
```

---

# 7. Goal Progress Model

不要把 Goal 设计成只有一个 percentage。

统一采用：

```text
Goal
│
├── Outcome
│   └── Metrics
│
└── Process
    ├── Phases
    └── Tasks
        └── Schedule
```

一个 Goal 可以有：

### 7.1 Overall Progress

用于统一展示。

### 7.2 Goal Metrics

适合可量化目标。

例如：

```text
体重
73.4kg → 70kg

体脂
23.5% → 18%
```

数据结构：

```text
GoalMetric
├── id
├── goalId
├── name
├── unit
├── currentValue
├── targetValue
├── direction
└── history
```

支持：

```text
numeric
percentage
count
duration
distance
score
enum
```

不要强制所有 Goal 都必须有 Metric。

---

# 8. Phase

Goal 可以拆成多个阶段。

例如：

```text
做出 AI Goal App

Phase 1 产品设计 ✓
Phase 2 MVP UI ●
Phase 3 App 开发 ○
Phase 4 AI Agent ○
Phase 5 测试发布 ○
```

Phase 是：

> Goal 的阶段性进展

不是简单 Todo 分组。

---

# 9. Task

Task 是具体执行动作。

```text
Task
├── id
├── title
├── description
├── phaseId
├── status
├── priority
├── estimatedDuration
├── dueDate
└── createdAt
```

状态：

```text
todo
in_progress
completed
postponed
cancelled
```

---

# 10. Schedule

Schedule 表示：

> 什么时候做。

不要把 Task 和 Schedule 混成一个东西。

例如：

```text
Task:
完成目标详情页

Schedule:
2026-10-03 20:00
预计 60 分钟
```

未来同一个 Task 可以重新安排多次。

---

# 11. ProgressEvent

ProgressEvent 是非常核心的数据模型。

不要只依赖：

```text
task.status
```

而应该记录真实变化：

```json
{
  "id": "event_xxx",
  "goalId": "goal_xxx",
  "taskId": "task_xxx",
  "type": "completed",
  "time": "2026-10-03T08:30:00",
  "source": "chat",
  "message": "昨天的英语跟读完成了"
}
```

事件来源：

```text
user
chat
system
health
location
calendar
ai
notification
```

事件类型可以包括：

```text
task_completed
task_started
task_postponed
task_cancelled
metric_updated
phase_completed
goal_updated
goal_paused
goal_resumed
schedule_changed
user_report
```

未来：

```text
Progress Events
 ↓
Goal Progress
 ↓
AI Analysis
```

---

# 12. External Data Source

为了支持运动、天气、定位、日历等能力，从 V1 就预留：

```text
DataSource
```

例如：

```text
Health
Location
Weather
Calendar
Device
```

架构：

```text
External Data Provider
 ↓
Data Source Adapter
 ↓
Normalized Data
 ↓
Context Builder
 ↓
AI
```

不要让 AI 直接调用系统 API。

---

# 13. Health Data

运动类目标支持读取系统健康数据。

可能的数据：

```text
steps
distance
exercise
exerciseDuration
calories
heartRate
sleep
weight
bodyFat
```

平台：

```text
iOS
→ Apple Health

Android
→ Health Connect
```

V1 可以先实现基础能力：

```text
steps
distance
exercise
weight
```

其他数据预留。

---

# 14. Location

定位作为外部环境数据源。

```text
Location
├── latitude
├── longitude
├── city
└── timestamp
```

不要默认持续后台定位。

优先：

```text
用户打开 App
↓
需要环境信息
↓
获取当前位置
```

如果未来需要运动轨迹，再单独增加运动期间定位能力。

---

# 15. Weather

天气作为外部 Data Provider。

例如：

```text
Weather
├── temperature
├── condition
├── precipitationProbability
├── wind
├── airQuality
└── forecast
```

典型用途：

```text
跑步
骑行
户外学习
旅行
```

例如：

```text
今天 18:00 跑步
        ↓
天气数据
        ↓
暴雨
        ↓
AI 建议改为室内运动
```

---

# 16. Calendar

Calendar 是后续非常重要的数据源。

用于：

```text
工作时间
会议
空闲时间
日程冲突
```

例如：

```text
目标：
每天学习 1 小时

Calendar：
19:00 - 20:00 空闲

AI：
安排 19:00 学习
```

V1 可以先设计接口，后续实现。

---

# 17. Permission

所有系统数据都经过权限层。

```text
Permission
 ↓
Data Source
 ↓
Context Builder
 ↓
AI
```

用户应该可以控制：

```text
健康数据     已授权
定位         未授权
日历         已授权
```

并允许关闭。

原则：

> 能不用的数据不要读取。

---

# 18. AI Agent

AI 不是一个聊天接口，而是 Agent。

```text
AI Agent
│
├── Goal Tools
├── Plan Tools
├── Task Tools
├── Progress Tools
├── Schedule Tools
├── Metric Tools
├── External Data Tools
└── Web Search
```

---

# 19. AI Tools

至少设计：

```text
get_goal
get_goals
create_goal
update_goal
pause_goal
resume_goal
cancel_goal

get_plan
create_plan
update_plan

get_phases
create_phase
update_phase

get_tasks
create_task
update_task
complete_task
postpone_task
reschedule_task

get_progress
create_progress_event

get_metrics
update_metric

get_schedule
create_schedule
update_schedule

get_external_data

web_search
fetch_web_page
```

AI 应通过 Tool 操作数据。

不要让 AI 输出任意 JSON 后由 App 猜测 AI 想做什么。

---

# 20. AI Context

Context Builder：

```text
AI Context
├── User Context
├── Current Goal
├── Current Phase
├── Current Tasks
├── Today's Schedule
├── Recent Progress
├── Goal Metrics
├── Relevant External Data
├── Recent Conversation
└── Agent Rules
```

不要把整个数据库全部塞给模型。

根据当前任务动态构建 Context。

---

# 21. AI Model Provider

统一抽象：

```text
AI Provider
├── Official Service
├── OpenAI
├── Anthropic
├── 智谱
└── Custom OpenAI Compatible
```

用户可以配置多个 Provider。

---

# 22. Model Policy

不要直接在业务代码中写：

```text
if task == xxx:
    use claude
```

使用：

```text
Task Type
 ↓
Model Policy
 ↓
Preferred Model
 ↓
Fallback Model
```

Task Type：

```text
goal.create
goal.update
plan.create
plan.update
progress.report
progress.analysis
chat
task.complete
task.reschedule
daily.review
weekly.review
```

初始策略：

```text
Planning / Analysis
→ 强模型

Chat
→ 普通模型

Quick Actions
→ 快速模型
```

---

# 23. Model Fallback

如果指定模型不可用：

```text
Preferred Model
 ↓ unavailable
Fallback Model
 ↓ unavailable
Default Model
 ↓ unavailable
Error
```

用户继续操作，不应该因为单个模型故障导致整个 App 不可用。

同时记录：

```json
{
  "requestedModel": "xxx",
  "actualModel": "xxx",
  "fallback": true,
  "fallbackReason": "unavailable"
}
```

界面只轻量提示：

> 当前模型暂时不可用，已自动切换到 XXX。

---

# 24. Web Search

V1 支持 Web Search。

Search 也是 Agent Tool。

```text
AI Agent
│
└── Web Search
    ├── search
    └── fetch page
```

Search Provider 也抽象：

```text
Search Provider
├── Official Service
├── Exa / Tavily
└── Custom API
```

搜索模式：

```text
智能判断
始终关闭
始终开启
```

智能判断：

```text
个人任务 / 当前计划
→ 不搜索

旅行 / 考试 / 最新信息 / 调研
→ 搜索
```

计划中保留来源：

```text
参考来源
- xxx
- xxx
```

---

# 25. AI 操作规则

AI 可以自动执行简单操作：

```text
完成任务
延期任务
调整时间
记录进度
更新 Metric
```

重大结构变化需要确认：

```text
拆分 Goal
合并 Goal
大幅调整 Plan
删除大量任务
修改目标方向
```

例如：

```text
AI：

当前计划可能过于复杂。

建议调整：

产品设计 3 天
开发 7 天
测试 3 天

共 13 天

[应用计划]
[修改]
```

---

# 26. Goal Split / Merge

支持 AI 识别：

### Goal Split

```text
做一个 AI Goal App

→ 产品设计
→ App 开发
→ AI Agent
→ 测试
→ 发布
```

### Goal Merge

```text
学习 Flutter
做一个 Flutter App
学习 Flutter 状态管理

→ AI 建议合并
```

必须用户确认。

---

# 27. Cross Goal Task

Task 不强制只能属于一个 Goal。

建议：

```text
Goal
Task
GoalTask
```

例如：

```text
学习 Riverpod

→ Goal A：做 AI Goal App
→ Goal B：学习 Flutter
```

V1 可以支持多个 Goal 关联。

复杂的依赖图暂时不要实现。

---

# 28. Home 首页

底部：

```text
首页
目标
我的
```

不单独设置 Chat Tab。

首页重点回答：

> 今天应该做什么？当前目标进展如何？有什么需要处理？

结构：

```text
早上好
10月3日 · 星期六

今天
████████████░░ 70%

✓ 完成需求分析
✓ 确定页面结构
○ 设计目标详情页
○ 整理开发任务

当前目标
🚀 做出 AI Goal App
MVP UI
██████████░░ 60%

下一步：
设计目标详情页

需要处理
⚠️ 计划出现偏差

最近目标
[英语]
[健身]

✨ 告诉 AI 今天发生了什么
```

不要把首页做成复杂 Dashboard。

---

# 29. Goal List

Goal Card：

```text
Title
Overall Progress
Current Phase
Next Step
Expected Completion
```

但是不同类型 Goal 可以使用不同 Card。

例如：

```text
减重
73.4kg
↓ 0.8kg
目标 70kg
```

而：

```text
App 开发
72%
当前阶段：MVP UI
下一步：目标详情页
```

不要强制所有 Goal 使用同一种卡片。

---

# 30. Goal Detail

核心思想：

> Goal Detail 不是 Todo List，而是目标进展页面。

结构：

```text
Goal Overview

Metrics（可选）

Progress Visualization

[路线] [日历] [任务]

Phase Roadmap

Current Phase Tasks

Recent Changes

AI
```

默认：

```text
路线
```

---

# 31. Goal Visualization

根据 Goal 类型自动决定展示方式。

### 健康目标

```text
体重趋势
73.4kg → 70kg

本周运动
48,320 步
4 次运动
```

### 存钱

```text
¥12,000 / ¥30,000
```

### 跑步

```text
配速
里程
训练次数
```

### 考试

```text
当前分数
目标分数
各科能力
```

### 软件开发

```text
Phase Roadmap
Task Progress
```

不要强迫用户自己设计 Dashboard。

AI 根据 Goal 自动判断：

> 这个 Goal 是否需要 Metric，以及应该使用什么可视化。

---

# 32. Chat

没有独立 Chat Tab。

在不同页面提供上下文入口：

```text
首页
✨ 告诉 AI 今天发生了什么

Goal List
✨ 创建 / 管理目标

Goal Detail
✨ 和 AI 讨论这个目标
```

Chat 可以：

```text
创建 Goal
修改 Goal
创建 Plan
调整 Plan
报告进度
完成任务
延期任务
修改截止日期
减少目标范围
暂停 Goal
恢复 Goal
```

---

# 33. Local Notification

V1 使用系统 Local Notification。

App 关闭后：

```text
OS Scheduler
 ↓
Notification
```

不要依赖 App 常驻后台。

例如：

```text
🎯 AI Goal

今天的计划：
完成目标详情页

预计：
60 分钟

[开始]
[延后 30 分钟]
[调整计划]
```

简单 Action 可以直接修改 SQLite。

重大调整进入 App，由 AI 处理。

---

# 34. App 关闭时的 AI 边界

必须明确：

> App 关闭时，AI 不知道现实世界发生了什么。

例如：

```text
App 关闭
↓
系统按最后确认的 Schedule 发通知
```

App 再次打开：

```text
读取实际数据
↓
Progress Event
↓
AI 分析
↓
重新规划
```

不要设计依赖长期后台运行的 Agent。

---

# 35. V1 AI 触发机制

AI 不需要每分钟运行。

只在有意义的事件触发：

```text
Goal 创建
Goal 修改
Plan 创建
Plan 修改
用户聊天
用户报告进度
用户要求调整
App 打开后的 Review
```

系统数据发生变化也可以触发相关分析，但不要持续调用模型。

---

# 36. V1 数据库

建议至少：

```text
goals
phases
tasks
goal_tasks
schedules
progress_events
goal_metrics
metric_values
conversations
conversation_messages

ai_providers
ai_models
ai_model_policies

data_sources
permissions

notifications
```

未来：

```text
sync_metadata
devices
remote_changes
```

暂时不实现。

---

# 37. UUID

所有实体从 V1 开始使用 UUID：

```text
goal_xxx
phase_xxx
task_xxx
event_xxx
```

不要使用数据库自增 ID 作为跨设备唯一标识。

原因：

未来云同步时可以直接复用。

---

# 38. Repository

所有数据访问经过 Repository：

```text
GoalRepository
PhaseRepository
TaskRepository
ScheduleRepository
ProgressRepository
MetricRepository
ConversationRepository
```

V1：

```text
Repository
 ↓
SQLite
```

未来：

```text
Repository
 ↓
LocalDataSource
 ↓
SQLite

SyncService
 ↓
RemoteDataSource
 ↓
Backend
```

UI 不允许直接操作 SQLite。

---

# 39. V1 不做什么

为了避免项目失控，V1 明确不做：

```text
❌ 登录
❌ 注册
❌ 云同步
❌ 后端
❌ Web
❌ Desktop
❌ 多设备同步
❌ 社交
❌ 分享
❌ 社区
❌ 服务端推送
❌ 服务端 Scheduler
❌ 复杂依赖图
❌ Gantt
❌ 复杂 Dashboard 编辑器
❌ Fine-tuning
❌ 自建模型
❌ 后台持续运行 Agent
```

但是：

```text
✅ Web Search
✅ AI Agent
✅ Tool Calling
✅ Local SQLite
✅ Local Notification
✅ Model Provider
✅ Model Fallback
✅ Goal Metrics
✅ Progress Event
✅ DataSource 抽象
```

---

# 40. V1 开发阶段

## P0：项目初始化

目标：

> 跑起来一个干净的 Flutter App + pnpm monorepo。

完成：

```text
pnpm workspace
Flutter App
基础 CI
代码格式化
Lint
测试框架
环境配置
```

建立：

```text
apps/mobile
packages/domain
packages/contracts
packages/ai
docs
```

---

# 41. P1：本地数据层

完成：

```text
SQLite
Repository
Goal
Phase
Task
Schedule
ProgressEvent
Metric
```

实现：

```text
创建 Goal
编辑 Goal
创建 Phase
创建 Task
完成 Task
延期 Task
调整 Schedule
记录 Progress Event
```

这一步暂时不接 AI。

---

# 42. P2：核心 UI

完成：

```text
首页
Goal List
Goal Detail
Settings
```

完成：

```text
Goal 创建
Goal 编辑
Phase
Task
Schedule
Progress
```

先让用户不用 AI 也能完整使用。

---

# 43. P3：AI Provider

完成：

```text
Provider
Model
API Key
Model Policy
Fallback
```

至少支持：

```text
OpenAI Compatible
Anthropic
智谱
Custom OpenAI Compatible
```

Provider 必须可扩展。

---

# 44. P4：AI Agent

实现：

```text
Context Builder
Tool Registry
Tool Calling
Structured Output
Conversation
```

第一批 Tool：

```text
Goal
Plan
Phase
Task
Schedule
Progress
Metric
```

完成：

```text
用户自然语言
 ↓
AI
 ↓
Tool
 ↓
SQLite
 ↓
UI 更新
```

---

# 45. P5：AI Planning

完成核心产品能力：

```text
用户：

我想三个月减掉5kg

↓

AI 澄清

↓

Goal

↓

Plan

↓

Phase

↓

Tasks

↓

Schedule
```

同时支持：

```text
重新规划
缩小目标
延期
暂停
恢复
```

---

# 46. P6：Progress Loop

完成：

```text
用户报告
 ↓
ProgressEvent
 ↓
AI 分析
 ↓
Goal Progress
 ↓
Plan Adjustment
```

重点测试：

```text
“首页做完了”
→ complete_task

“今天不做，明天再做”
→ reschedule_task

“这个目标太大了”
→ propose_plan_adjustment

“我不想做了”
→ pause/cancel
```

---

# 47. P7：Notification

实现：

```text
Schedule
 ↓
Local Notification
```

支持：

```text
开始
延后
无法完成
调整计划
```

App 关闭后仍然可以根据最后计划提醒。

---

# 48. P8：Web Search

完成：

```text
Search Provider
Search Tool
Fetch Page
Citation
```

测试：

```text
旅游目标
考试目标
学习目标
最新资料目标
```

确认：

```text
需要搜索
→ Search

不需要
→ 不搜索
```

---

# 49. P9：External Data 基础框架

V1 后期先实现框架，不追求所有数据源。

```text
DataSource
DataProvider
Permission
Context Adapter
```

优先：

```text
Health
Weather
Location
```

Calendar 可以随后加入。

---

# 50. P10：测试与打磨

重点不是单纯 Unit Test 数量，而是测试完整 Goal Loop。

测试案例：

```text
创建目标
→ AI 规划
→ 执行
→ 报告
→ AI 调整
→ 通知
→ 完成
```

AI Evaluation：

```text
Tool Selection
Tool Arguments
Context Quality
Plan Quality
Confirmation Rules
Fallback
```

建立一套固定 Evaluation Cases。

---

# 51. V1 完成标准

用户第一次打开 App，可以完成：

```text
创建目标
 ↓
AI 理解
 ↓
AI 制定计划
 ↓
查看路线
 ↓
查看今天任务
 ↓
收到提醒
 ↓
完成任务
 ↓
向 AI 汇报
 ↓
AI 更新进度
 ↓
AI 调整后续计划
```

整个过程不需要服务器。

这才是 V1 的真正完成标准。

---

# 52. V2：智能现实世界数据

V2 重点：

```text
Health
Location
Weather
Calendar
```

形成：

```text
Goal
 ↓
Plan
 ↓
Real World Data
 ↓
Progress
 ↓
AI
```

例如：

```text
跑步目标

计划：
每天 18:00 跑步

现实：
下雨

↓

AI：
建议改为室内训练
```

或者：

```text
学习目标

Calendar：
今天会议很多

↓

AI：
自动减少今天学习量
```

---

# 53. V3：AI Long-term Context

建立：

```text
User Context
```

包括：

```text
可用时间
工作时间
长期目标
习惯
偏好
约束
```

例如：

```text
用户通常晚上学习
工作日只能学习 1 小时
周末可以学习 3 小时
```

AI 制定计划时自动考虑这些约束。

---

# 54. V4：Cloud Sync

增加：

```text
Go Backend
PostgreSQL
Authentication
Sync
```

架构：

```text
Flutter
 ↓
SQLite
 ↓
Sync Engine
 ↓
Go API
 ↓
PostgreSQL
```

重点：

> 不改变现有 Domain / Repository / UI。

只是增加：

```text
RemoteDataSource
SyncService
```

---

# 55. V5：Web

Web 使用：

```text
React / Next.js
```

主要用途：

```text
查看目标
查看计划
查看进度
编辑 Goal
AI Chat
数据分析
```

Web 不需要复制整个 Mobile UI。

---

# 56. V6：Desktop

使用：

```text
Tauri 2
+
React
```

重点能力：

```text
全局快捷键
快速记录
Clipboard
截图
桌面通知
Tray
快速向 AI 汇报
```

Desktop 更适合作为：

> 快速捕获 / AI 工作台

而不是简单复制手机 App。

---

# 57. V7：智能 Goal Network

后续可以建立：

```text
Goal
├── Sub Goal
├── Related Goal
├── Dependency
├── Conflict
└── Shared Task
```

例如：

```text
减重
↕
健身
↕
睡眠
```

AI 可以识别不同目标之间：

```text
时间冲突
资源冲突
任务复用
目标协同
```

但不要在 V1 实现复杂图结构。

---

# 58. 长期产品架构

最终形成：

```text
                         AI Agent
                            │
       ┌────────────────────┼────────────────────┐
       │                    │                    │
   Goal System         User Context       World Context
       │                    │                    │
       │                    │             ┌──────┼──────┐
       │                    │             │      │      │
      Goal              Preferences     Health Weather Calendar
       │
      Plan
       │
      Phase
       │
      Task
       │
   Schedule
       │
Progress Event
       │
   Goal Metrics
       │
   Visualization
```

最终产品不是：

> AI Todo List

而是：

> **AI Personal Goal Operating System**

---

# 59. Claude Code 执行顺序

Claude Code 不要一次性实现全部功能。

严格按以下顺序：

```text
Phase 0
项目初始化
↓
Phase 1
Domain + SQLite + Repository
↓
Phase 2
核心 UI
↓
Phase 3
AI Provider
↓
Phase 4
AI Agent + Tools
↓
Phase 5
AI Planning
↓
Phase 6
Progress Loop
↓
Phase 7
Notification
↓
Phase 8
Web Search
↓
Phase 9
External Data
↓
Phase 10
测试 + V1 Release
```

然后才：

```text
V2 Health / Weather / Calendar
↓
V3 User Context
↓
V4 Cloud Sync
↓
V5 Web
↓
V6 Desktop
↓
V7 Goal Network
```

---

# 60. Claude Code 第一阶段任务

当前不要直接开始实现所有功能。

第一步只执行：

```text
1. 创建 pnpm monorepo

2. 创建：
   apps/mobile
   packages/domain
   packages/contracts
   packages/ai
   docs

3. 初始化 Flutter App

4. 建立 Flutter 分层架构

5. 建立 SQLite

6. 建立 Repository Interface

7. 建立基础 Domain Model：
   Goal
   Phase
   Task
   Schedule
   ProgressEvent
   GoalMetric

8. 创建基础数据库 Migration

9. 创建基础测试

10. 创建 README / ARCHITECTURE.md

11. 确保：
    pnpm install
    Flutter build
    Flutter test
    全部可以正常运行
```

**第一阶段不要实现 AI、Web Search、Health、Weather、Cloud Sync。**

先把基础工程和 Domain 打稳。

---

# 61. 开发原则

### 原则 1：Local-first

SQLite 是 V1 事实源。

### 原则 2：Repository 隔离

UI 不直接访问数据库。

### 原则 3：AI Tool 化

AI 通过 Tool 修改业务状态。

### 原则 4：Progress Event 化

重要状态变化都产生 Event。

### 原则 5：External Data Provider 化

Health / Weather / Location / Calendar 都通过 Provider 接入。

### 原则 6：AI Context 动态化

不要把整个数据库发送给模型。

### 原则 7：计划可变

计划不是静态 Gantt：

```text
Plan
 ↓
Execution
 ↓
Reality
 ↓
Adjustment
 ↓
New Plan
```

### 原则 8：重大变化需要确认

AI 可以自动完成简单动作，但结构性改变需要用户确认。

### 原则 9：不要过度工程化

V1 不引入：

```text
Redis
Kubernetes
Microservices
Message Queue
API Gateway
```

没有实际需求之前都不要做。

### 原则 10：为未来留接口，不为未来提前实现

这是整个项目最重要的原则：

> **架构支持未来，代码只实现当前。**

---

# 62. 最终 V1 架构图

```text
┌──────────────────────────────────────────────┐
│                Flutter Mobile                │
│                                              │
│  Home │ Goals │ Goal Detail │ Settings       │
│                       │                      │
│                       ▼                      │
│                 Application                 │
│                       │                      │
│          ┌────────────┴────────────┐         │
│          ▼                         ▼         │
│     Goal System               AI Agent       │
│          │                         │         │
│          ▼                         ▼         │
│      Repository               AI Provider   │
│          │                         │         │
│          ▼                    Web Search     │
│       SQLite                             │
│                                             │
│  External Data                              │
│   ├── Health                                │
│   ├── Weather                               │
│   └── Location                              │
│                                             │
│  Local Notification                         │
└──────────────────────────────────────────────┘
```

---

# 63. 最终目标

V1 不追求“功能很多”。

只验证一个事情：

> **AI 能不能真正帮助一个人持续完成一个目标。**

完整闭环：

```text
“我想完成一个目标”
        ↓
AI 理解
        ↓
AI 规划
        ↓
今天该做什么
        ↓
提醒
        ↓
执行
        ↓
用户汇报 / 系统数据
        ↓
记录真实进度
        ↓
AI 判断偏差
        ↓
调整计划
        ↓
继续执行
        ↓
目标完成
```

只要这个闭环成立，后面的：

```text
Health
Weather
Calendar
Cloud
Web
Desktop
Goal Network
```

都是在这个核心系统上继续增强，而不是重新做一个产品。
