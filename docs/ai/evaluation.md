# AI Evaluation Cases（P10，plan §50）

> 固定评测用例集。当前以「系统 ↔ 模型行为契约」测试的形式落地
> （`test/application/ai_evaluation_test.dart`，给定模型响应序列断言系统行为）；
> 接真实模型跑分时复用同一批用例定义，人工/脚本判分。

## 用例表

| ID | 维度 | 用例 | 期望 | 代码位置 |
| --- | --- | --- | --- | --- |
| EV-1a | Tool Selection | 「我想学摄影」→ 模型调用 propose_plan | 结构性规划不直写 goal（确认前 goals 为空），提案挂消息 | ai_evaluation_test |
| EV-1b | Tool Selection | 「快走完成了」→ get_tasks → complete_task | 两步路由：先查再改；任务落库为 completed | ai_evaluation_test |
| EV-2a | Tool Arguments | propose_plan 缺 title（参数错误） | `{ok:false, error}` 原样回传模型；模型纠正后成功 | ai_evaluation_test |
| EV-2b | Tool Arguments | record_metric_value 引用不存在的指标 | 明确错误（含指标名），不静默 | ai_evaluation_test |
| EV-3 | Context Quality | 目标详情场景发消息 | 上下文含 scene/current_goal/open_tasks，紧凑（<6K 字符） | ai_evaluation_test |
| EV-4 | Confirmation Rules | propose_action(cancel_goal) | 确认前目标状态不变；确认后才 cancelled | ai_evaluation_test |
| EV-5 | Fallback | 首选模型 401 | 自动切换其它已启用供应商，fallbackNote 透出 | ai_evaluation_test |

## 端到端（完整 Goal Loop，plan §51 验收）

`test/application/goal_loop_e2e_test.dart` 自动化 V1 完成标准：

```text
自然语言规划 → 提案（不落库）→ 确认应用（目标+指标+阶段+任务+日程）
→ 今天列表可见 → 提醒已排 → 通知按钮完成 → 向 AI 汇报（指标更新）
→ AI 分析 → 调整提案 → 应用 → 暂停二次确认 → 确认后暂停
→ 完成剩余任务 → 目标达成（completed / 100%）→ 会话全程可回放
```

## 真实模型跑分（后续接入）

1. 用本表用例构造用户输入，调真实 AgentService（生产提示词 + 工具）
2. 判分维度：工具选择正确率 / 参数完整率（JSON Schema 校验）/
   确认规则遵守率（结构性变更是否走 propose_plan / propose_action）/
   引用率（搜索结论是否附来源）
3. 结果记入本文件附录，作为提示词迭代的回归基线
