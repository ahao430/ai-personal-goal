# AI Goal App

[![mobile-ci](https://github.com/ahao430/ai-personal-goal/actions/workflows/mobile-ci.yml/badge.svg)](https://github.com/ahao430/ai-personal-goal/actions/workflows/mobile-ci.yml)

AI 驱动的个人目标管理 App。核心不是 Todo，而是：

> 用户提出目标 → AI 理解目标 → AI 制定计划 → 拆分阶段和任务 → 用户执行 →
> 用户反馈 / 系统数据产生进度 → AI 判断实际情况 → 调整计划 → 持续推进目标

完整产品与技术规划见 [plan.md](./plan.md)。

## 当前状态

**v1.0.0**（2026-10-03）—— **V1 正式发布**：
**规划 → 执行 → 提醒 → 汇报 → 分析 → 调整** 全闭环，
plan §51 完成标准全部达成，全程无需服务器。

- pnpm monorepo；Flutter App（`apps/mobile`，iOS / Android）
- 分层架构（domain / data / application / presentation）
- 核心领域模型：Goal / Phase / Task / Schedule / ProgressEvent / GoalMetric
- SQLite（schema v5）+ Migration 框架；Repository 接口 + SQLite 实现
- 核心 UI：首页（含每日 AI 回顾卡）/ 目标列表与详情 / 聊天 / 设置；
  统一动效体系（core/motion）
- AI 供应商：模板快速添加、一键获取模型列表、供应商与默认模型分开配置、
  失败自动回退
- AI Agent：22 个工具；结构性变更走 `propose_plan` 提案 + 确认卡片；
  目标级操作走 `propose_action` 是/否确认；`analyze_progress` 提供聚合事实
- 本地通知：按计划提前 10 分钟提醒、通知直接完成/延后、点击深链目标详情
- 日历月视图：月历 + 选中日任务列表（首页 / 目标详情双入口）
- 联网搜索：web_search / fetch_web_page 工具，结论附引用来源；
  免 key 默认可用，可选配 Tavily Key
- External Data 框架：DataProvider / 授权 / Context Adapter；
  天气源已接入（Open-Meteo 免 key，户外目标建议）
- 测试 152 个用例全通过（含完整 Goal Loop E2E 与 AI Evaluation Cases）

详细变更见 [CHANGELOG.md](./CHANGELOG.md)；路线图见 [ROADMAP.md](./ROADMAP.md)
（V1 阶段进度 + V2-V7 长期方向，含服务端 MCP：支持 workuddy 等外部 agent
做计划、管计划）。

## 版本策略与 CI

**monorepo 各 app 版本独立**：mobile 的版本事实源是
`apps/mobile/pubspec.yaml`（常规 +0.0.1 / 大功能 +0.1.0）；
根 `package.json` 是工作区自身版本，**不与任何 app 同步**。

云端打包（[.github/workflows/README.md](./.github/workflows/README.md)）：

- push / PR 涉及 `apps/mobile/**` → 自动 analyze + 152 测试 + 打 APK
- tag `mobile-v*` → APK 挂 GitHub Release（安装包不进 git 仓库）
- 后续其他 app 用各自路径过滤与 tag 前缀接入，互不干扰

## 文档索引

| 文档 | 内容 |
| --- | --- |
| [plan.md](./plan.md) | 产品与技术总体规划（事实源） |
| [ARCHITECTURE.md](./ARCHITECTURE.md) | 分层架构 / 领域模型 / 数据库约定 / 视觉规范 |
| [AGENTS.md](./AGENTS.md) | 仓库协作规范（AI agent 与人类通用：命令/红线/约定） |
| [CHANGELOG.md](./CHANGELOG.md) | 版本记录与版本策略 |
| [ROADMAP.md](./ROADMAP.md) | 路线图（V1 阶段进度 + V2-V7 长期方向 / MCP 服务端） |
| [docs/ai/prompts.md](./docs/ai/prompts.md) | AI Agent 提示词、上下文组装、确认规则 |
| [docs/database/](./docs/database/) | SQLite schema 文档（v1 - v5） |
| [docs/architecture/routes.md](./docs/architecture/routes.md) | 页面导航地图（已实现 + 规划） |

## 仓库结构

```text
ai-personal-goal/
├── apps/
│   └── mobile/          # Flutter App（V1 主战场）
├── packages/
│   ├── domain/          # TS 领域模型（未来 Web/Desktop 共享，占位）
│   ├── contracts/       # API / Sync / AI Tool 契约（MCP/App 共用，占位）
│   ├── ai/              # TS 侧 AI 定义（占位）
│   └── config/          # 公共配置（占位）
├── services/
│   └── api/             # Go 服务端 + MCP Server（V4，占位）
├── docs/
│   ├── product/         # 产品文档
│   ├── architecture/    # 架构文档（含 routes.md 页面导航地图）
│   ├── ai/              # AI Agent / Prompt / Tools 设计
│   └── database/        # 数据库 schema 文档
├── plan.md / ARCHITECTURE.md / AGENTS.md / CHANGELOG.md / ROADMAP.md / README.md
└── pnpm-workspace.yaml
```

注意：**Flutter 是独立的 Dart 项目**，pnpm 只负责 workspace 层面管理，
不强行让 Flutter 使用 TypeScript package。

## 快速开始

前置要求：Flutter 3.38+ / Dart 3.10+、Node 20+、pnpm 9+。

```bash
# 安装 Node 侧依赖（目前只有占位包）
pnpm install

# Flutter 依赖
cd apps/mobile && flutter pub get

# 静态检查 / 测试
flutter analyze
flutter test

# 运行（连接设备或模拟器）
flutter run
```

根目录也提供快捷脚本：`pnpm mobile:analyze`、`pnpm mobile:test`、`pnpm mobile:run`。

## 核心原则

1. **Local-first**：SQLite 是 V1 事实源，不连服务器也能完整使用
2. **Repository 隔离**：UI 不直接访问数据库
3. **AI Tool 化**：AI 通过 Tool 修改业务状态，不输出任意 JSON 让 App 猜
4. **Progress Event 化**：重要状态变化都产生事件
5. **架构支持未来，代码只实现当前**

详见 [ARCHITECTURE.md](./ARCHITECTURE.md)。
