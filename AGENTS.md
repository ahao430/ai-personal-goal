# AGENTS.md — 本仓库的 AI 协作规范

给在此仓库工作的 AI 编码 agent（Claude Code / ZCode / Cursor 等）的操作约定。
人类开发者同样适用。

## 项目是什么

AI 驱动的个人目标管理 App。核心循环：**目标 → AI 澄清 → 计划 → 阶段/任务/日程 →
执行 → 进度事件 → AI 分析 → 调整计划**。V1 完全 Local-first（SQLite 事实源，
无账号无后端），服务端能力是后期增量。

动手前先读：

| 文档 | 内容 |
| --- | --- |
| [plan.md](./plan.md) | 产品与技术总体规划（**事实源**，勿随意改写） |
| [ARCHITECTURE.md](./ARCHITECTURE.md) | 分层架构、领域模型、数据库约定 |
| [CHANGELOG.md](./CHANGELOG.md) | 版本记录（每次交付必更新） |
| [ROADMAP.md](./ROADMAP.md) | 路线图：V1 阶段进度 + 长期方向（完成阶段必勾选） |
| [docs/architecture/routes.md](./docs/architecture/routes.md) | 页面导航地图（改页面/加页面必更新） |
| [docs/ai/prompts.md](./docs/ai/prompts.md) | AI Agent 提示词与确认规则 |
| [docs/ai/evaluation.md](./docs/ai/evaluation.md) | AI Evaluation 固定用例集 |
| [docs/database/](./docs/database/) | schema 文档（随迁移更新） |

## 常用命令

```bash
# Node 侧（目前只有占位包）
pnpm install

# Flutter（在 apps/mobile 下，或用根目录 pnpm 脚本）
cd apps/mobile
flutter pub get
flutter analyze          # 静态检查，必须零 issue
flutter test             # 全部测试，必须全绿
flutter run              # 运行

# 重新生成 App 图标（改了 assets/images/logo.png 之后）
dart run flutter_launcher_icons
```

交付前最低标准：`flutter analyze` 零问题 + `flutter test` 全绿 +
`flutter build bundle --debug --target-platform android-arm` 成功。

## 架构红线（违反 = 返工）

1. **分层**：`presentation → application → domain ← data`。
   UI 不 import 任何 `data/` 类型，只通过 `AppServices` 拿 Repository 接口
   或 Application 服务；domain 层不 import Flutter。
2. **数据库迁移只追加**：已发布的 `SchemaMigration` 不许修改；
   新表/新列加新版本号，并同步更新 `docs/database/` 文档与
   `AppDatabase.schemaVersion`。
3. **ID 与时间约定**：实体 ID 用 `EntityIds.newXxxId()`（前缀 UUID）；
   时间列一律走 `domain/time_codec.dart`（毫秒 UTC ISO8601），
   不要在 Repository 里手写日期转换。
4. **AI 不直接改状态**：AI 通过 Tool 修改业务（P4 起），
   不解析任意 JSON 猜意图。重大结构变化必须走用户确认（规则见
   docs/ai/prompts.md）。
5. **V1 不做的事**（plan.md §39）：登录/注册/云同步/后端/Web/Desktop/
   社交/服务端推送/复杂依赖图/Gantt/Fine-tuning。需求再像也不要顺手实现。
6. **不过度工程化**：没有实际需求不引入 Redis/MQ/微服务/DI 框架；
   状态管理库等 P2 真正需要时再定。

## UI / 视觉约定

- 配色只用 [app_palette.dart](./apps/mobile/lib/core/config/app_palette.dart)
  的暖色调（日落橙/珊瑚/琥珀/蜜桃 + 奶油底 + 暖棕字），不同区块用不同暖色。
- 图标用 Font Awesome（font_awesome_flutter），不用 Material Icons 做新图标。
- 卡片底图类视觉用 `WarmCard`（自带蒙版与图缺兜底）；所有 `Image.asset`
  必须带 `errorBuilder` 兜底。
- 新插画用 gpt-image skill 生成，提示词风格保持一致
  （flat vector、暖色、no text），产出后做 256 色量化压缩再入库。

## 动效约定（硬性规范）

> **所有 UI 动效必须通过统一的 `core/motion/` 体系实现，
> 不允许各页面自行定义 duration / curve。**

- 时长只用 `AppMotion`（instant/fast/normal/slow/page），曲线只用
  `AppCurves`（standard/emphasized/exit/count）——禁止页面里出现裸
  `Duration(milliseconds: ...)` 与任意 `Curves.xxx`。
- 入场/错位/弹出统一用 `MotionEffects`（entrance / staggerIn / popIn），
  基于 flutter_animate。
- 页面跳转统一 `pushMotion(context, page)`（MotionPageRoute：淡入 + 轻微上滑），
  不再直接使用 MaterialPageRoute。
- 进度条与百分比用 `AnimatedProgressBar` / `AnimatedPercent`（值变化平滑联动）。
- 结构性动画（Hero 共享过渡、Tab 切换）优先 Flutter 原生；
  Rive / Lottie 仅用于未来设计师资产（庆祝动画等），不引入「全家桶」。

## 版本与发布流程（monorepo 各 app 版本独立）

1. **版本互不同步**：mobile 的版本事实源是
   `apps/mobile/pubspec.yaml`（`x.y.z+build`）；根 `package.json` 是
   monorepo 工作区自身版本（独立演进）；`packages/*` 各共享包、
   `services/*` 服务端各自维护自己的版本。
2. mobile 发版：常规改动第三位 +1，大功能（新子系统/架构级）第二位 +1；
   bump pubspec 后更新 `CHANGELOG.md`（新条目放最上面，条目名带作用域
   如 `[mobile 1.0.1]`），打 tag `mobile-v<版本>` 触发云端打包发 Release
   （触发矩阵见 [.github/workflows/README.md](./.github/workflows/README.md)）。
3. 后续新 app 接入 CI：复制 `mobile-ci.yml` / `mobile-release.yml` 改
   paths 与命令，tag 用自己的前缀（如 `api-v*`）。
4. 改 `logo.png` 后重跑 `flutter_launcher_icons`。

## 测试要求

- 数据层（Repository / 迁移 / Service）：用 `test/helpers/test_database.dart`
  的内存 SQLite 写真实行为测试，不 mock 数据库。
- HTTP 客户端：注入 `http.Client`（MockClient）测协议解析与错误路径。
- Widget 测试注意：FakeAsync 环境下 ffi 真实异步要用 `tester.runAsync`
  等待（先例见 test/presentation/home_page_test.dart）。
- 涉及 AI Tool 的功能（P4+）：每个 Tool 至少一个正例 + 一个越权/确认例。
