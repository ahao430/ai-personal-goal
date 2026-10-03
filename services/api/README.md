# services/api（占位）

V4 落地的 Go 服务端：REST/Sync API + **MCP Server**。

- 契约来源：`packages/contracts`（与 App 内 AI Agent 共用同一套 Tool 语义）
- 形态：单二进制 + PostgreSQL，可自托管
- MCP：streamable HTTP + Bearer（用户级 API Key），
  支持 workuddy / Claude Code / Cursor 等外部 agent 直接做计划、管计划

设计见 [docs/roadmap/long-term.md](../../docs/roadmap/long-term.md)。
