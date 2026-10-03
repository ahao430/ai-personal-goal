# 页面导航地图

> V1 使用 `pushMotion`（MotionPageRoute）+ IndexedStack 底部导航。
> 页面继续增多或需要深链（P7 通知）时再评估 go_router。

## 已实现（0.5.1）

| 路由 | 页面 | 文件 | 入口 | 说明 |
| --- | --- | --- | --- | --- |
| `/` | 底部导航外壳 | `presentation/app_shell.dart` | App 启动 | 首页 / 目标 / 我的（IndexedStack 保状态） |
| `/` Tab1 | 首页 | `presentation/home/home_page.dart` | 启动默认 | 今天 / **每日 AI 回顾卡（P6）** / 当前目标 / 需要处理 + 「和 AI 聊聊」入口 |
| `/` Tab2 | 目标列表 | `presentation/goals/goals_page.dart` | 底部导航 | 状态过滤芯片 + 循环暖色卡片 |
| `/` Tab3 | 我的 | `presentation/profile/profile_page.dart` | 底部导航 | 设置入口 / **AI 功能开关（每日回顾，P6）** / 数据源预告 / 版本与隐私 |
| `/chat` | 全局对话 | `presentation/chat/chat_page.dart` | 首页主视觉卡「和 AI 聊聊」 | Agent 工具循环；活动胶囊；恢复最近会话；计划提案卡片 + **动作确认卡片（P6）** |
| `/goals/new` | 创建目标 | `presentation/goals/goal_edit_page.dart` | 列表 FAB / + | 标题/描述/目标日期 + 可选初始 Metric |
| `/goals/:id` | 目标详情 | `presentation/goal_detail/goal_detail_page.dart` | 点击目标卡片 / 首页「查看目标」 | 路线 / 任务 / 动态 三 Tab |
| `/goals/:id/chat` | 目标上下文对话 | `presentation/chat/chat_page.dart`（goalId） | 详情 AppBar 评论图标 | 上下文自动带入该目标；提案默认关联该目标 |
| `/calendar` | 日历月视图 | `presentation/calendar/calendar_page.dart` | 首页「今天」区块图标 / 目标详情 AppBar 图标（goalId） | 月历 + 选中日任务列表（0.5.1） |
| `/goals/:id/edit` | 编辑目标 | `presentation/goal_edit_page.dart`（existing） | 详情菜单 | |
| `/settings` | 设置 | `presentation/settings/settings_page.dart` | 首页齿轮 / 我的 | 分区：AI 供应商管理 / 默认模型 |
| `/settings/provider-edit` | 供应商编辑 | `presentation/settings/provider_edit_page.dart` | 设置页「+」/ 供应商卡片 / 菜单 | 新增带模板；编辑 Key 留空 = 保留 |

> 计划提案卡片（`plan_proposal_card.dart`）与动作确认卡片
> （`action_confirm_card.dart`）不是独立路由：它们挂在 `/chat` 与
> `/goals/:id/chat` 的 assistant 消息下方，确认后原地转只读徽章。

## 规划中

| 路由 | 页面 | 阶段 | 说明 |
| --- | --- | --- | --- |
| `/goals/:id/calendar` | 日历月视图 | P7 | 完整月历 + 提醒配置（当前以日程列表呈现） |
| `/settings/permissions` | 数据源权限 | P9 | Health / Location / Calendar / Weather 授权开关 |

## 导航约定

- 不设 Chat Tab（plan §28/32）：对话入口分散在首页与目标详情的上下文位置。
- 写操作后统一 `invalidateAll(ref)` 刷新 Riverpod providers（含 AI 改数据后）。
- 从本地通知进入的深链：`/goals/:id` —— AppShell 订阅提醒事件流
  （`ReminderAction.open`）→ `pushMotion` 目标详情（0.5.0 已实现）。
