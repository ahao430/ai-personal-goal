# CI / 云端打包 —— 触发矩阵与接入指南

> 原则：**一个 app 一套 workflow，用路径过滤互不干扰；版本号各自独立。**

## 触发矩阵

| 变更路径 | 触发的 workflow | 动作 |
| --- | --- | --- |
| `apps/mobile/**`、`.github/workflows/mobile-ci.yml` | **mobile-ci**（push main / PR） | flutter analyze + 全量测试 → 打 release APK（split-per-abi）→ Artifacts（14 天） |
| 推送 tag `mobile-v*` | **mobile-release** | 构建 → APK 挂到 GitHub Release（不进 git 仓库） |
| `packages/**` | （预留）packages-ci | TS 契约包检查；接入时复制 mobile-ci 改 paths 与命令 |
| `services/**` | （预留）api-ci | Go 服务端测试 + 镜像构建；tag `api-v*` 发版 |
| `docs/**`、根 `*.md`、根配置 | 无 | 文档变更不触发打包 |

规则说明：

- **CI 与发版分文件**：GitHub 的 `paths` 过滤同样作用于 tag 事件——
  如果发版和 CI 写在同一个 workflow，tag 指向的提交若不含
  `apps/mobile/**` 变更，发版会被静默跳过。因此 release workflow
  只认 tag，不配 paths。
- **tag 前缀 = app 作用域**：`mobile-v1.0.1` 只发 mobile；
  将来 `api-v0.1.0` 发服务端。各 app 版本互不相干（见下方版本规则）。

## 版本号规则（monorepo 各 app 独立）

| 位置 | 版本含义 | 事实源 |
| --- | --- | --- |
| `apps/mobile/pubspec.yaml` | mobile app 版本（`x.y.z+build`） | 唯一事实源，发版改这里 |
| 根 `package.json` | monorepo 工作区自身版本 | 独立演进，**不与任何 app 同步** |
| `packages/*/package.json` | 各共享包版本 | 各自维护（当前占位 0.1.0） |
| `services/api` | 服务端版本（V4 落地时定） | Go module / tag |

## 新 app 接入 CI（3 步）

1. 复制 `mobile-ci.yml` → `<app>-ci.yml`，改三处：
   - `paths`（指向新 app 目录）
   - `defaults.run.working-directory`
   - 构建/测试命令与 SDK setup
2. 复制 `mobile-release.yml` → `<app>-release.yml`，改 tag 前缀与产物路径
3. 在上方触发矩阵登记一行

## 发版操作（mobile 示例）

```bash
# 1. bump 版本：apps/mobile/pubspec.yaml 的 version，更新 CHANGELOG
# 2. 提交并打 tag
git add -A && git commit -m "mobile: release v1.0.1"
git tag mobile-v1.0.1
git push origin main mobile-v1.0.1
# 3. Actions 跑完，APK 出现在仓库 Release 页面
```

## 注意事项

- **产物不进 git**：APK 只存在于 Artifacts / GitHub Release，仓库保持轻量
- **正式签名（已接入）**：keystore 与密码存 GitHub Secrets
  （`AI_GOAL_KEYSTORE_BASE64` / `AI_GOAL_STORE_PASSWORD` /
  `AI_GOAL_KEY_ALIAS` / `AI_GOAL_KEY_PASSWORD`），release workflow 注入，
  所有云端 release 包签名一致，可直接覆盖安装升级。
  本地构建同签名包：
  ```bash
  cd apps/mobile
  export AI_GOAL_KEYSTORE_PATH=~/.keystores/ai-goal-release.jks
  export AI_GOAL_STORE_PASSWORD=$(cat ~/.keystores/ai-goal-password.txt)
  export AI_GOAL_KEY_ALIAS=ai-goal
  export AI_GOAL_KEY_PASSWORD=$AI_GOAL_STORE_PASSWORD
  flutter build apk --release --split-per-abi
  ```
- **keystore 保管**：`~/.keystores/ai-goal-release.jks`（不进仓库）。
  丢失 = 无法再出同签名包，用户只能卸载重装；建议离线备份一份
- Flutter 版本 pin 在 `3.38.9`（与开发机一致），升级时改两个文件的
  `FLUTTER_VERSION`
- 免费额度：public 仓库无限；private 2000 分钟/月
  （一次 CI 约 8-12 分钟，一次发版约 6 分钟）
