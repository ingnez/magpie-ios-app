# yetone/magpie 网页端控制台 (`internal/gui/*.go`) 全量路由清点与 iOS 端还原映射表

- **清点范围**：`/tmp/yetone-magpie/internal/gui/*.go` 全部非测试源码文件（共检出 **378** 处 `HandleFunc` 路由注册，外加 `api.go:1213` 根页面 `GET /` 与 `web.go` 登录表单 `POST /_magpie/sign-in`）。
- **iOS 还原策略**：
  1. **原生页 (SwiftUI)**：所有核心管理动作类接口（`providers` / `keys` / `groups` / `agents` / `agent-models` / `profile` / `caller-keys` / `masking` / `settings` / `proxies` / `backup` / `autobackup` / `davsync` / `tune` / `model-price` / `privacy-model` / `gateway` 控制 / `usage` / `quotas` / `checkin` / `warm`）均提供可编辑、可保存、可提交的原生 SwiftUI 界面。
  2. **内嵌原版控制台 (WKWebView)**：复杂桌面会话检索（`Sessions`）、MCP/Skills 资源库（`Library`）、插件市场与动态 schema 页面（`Plugins`）通过 `RemoteConsoleView` 自动注入 `HttpOnly` 会话 Cookie 承载。
  3. **无需页面（桌面宿主/内部协议）**：macOS/Windows 托盘窗口缩放、打开宿主机本地 Finder 文件夹、桌面端自卸载等仅适用于桌面 GUI 宿主的路由。

| 序号 | 后端文件:行号 | 路由 (Method & Pattern) | 网页端对应交互功能 | iOS 侧实现方式 | iOS 对应源码文件 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 0a | `web.go:404` | `POST /_magpie/sign-in` | 密钥 `k` 表单换取 `magpie_web_<port>` HttpOnly 会话 Cookie | 原生鉴权管道 (URLSession) | `MagpieWebClient.swift` |
| 0b | `api.go:1213` | `GET /` | Web 控制台主页面 HTML 容器与 `?mode=window&view=...` 路由 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift` / `ConsoleDestination.swift` |
| 1 | `admin.go:112` | `ar.pattern` | Admin API (/v1/magpie/admin/*) 代理复用 /api/* 管理处理器 | 原生页 (SwiftUI 直接调用 /api/* 同源处理器) | `MagpieWebClient*.swift` |
| 2 | `admin.go:131` | `GET /routing-groups/{id...}` | Admin API 路由组读写接口 | 原生页 (SwiftUI 调用 /api/groups/*) | `GroupEditorSheet.swift / ProvidersView.swift` |
| 3 | `admin.go:139` | `POST /routing-groups/create` | Admin API 路由组读写接口 | 原生页 (SwiftUI 调用 /api/groups/*) | `GroupEditorSheet.swift / ProvidersView.swift` |
| 4 | `admin.go:140` | `POST /routing-groups/update` | Admin API 路由组读写接口 | 原生页 (SwiftUI 调用 /api/groups/*) | `GroupEditorSheet.swift / ProvidersView.swift` |
| 5 | `admin.go:144` | `POST /signin` | Admin API OAuth 登录回调转发 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift` |
| 6 | `agent_models.go:252` | `POST /api/agent-fast` | Agents 页切换 Fast / Ultrafast 推理速度档位 | 原生页 (SwiftUI) | `AgentsView.swift` |
| 7 | `agent_models.go:274` | `GET /api/agent-models/{id}` | Agents 页读取与保存客户端可见模型列表 | 原生页 (SwiftUI) | `AgentsView.swift` |
| 8 | `agent_models.go:302` | `POST /api/agent-models/{id}` | Agents 页读取与保存客户端可见模型列表 | 原生页 (SwiftUI) | `AgentsView.swift` |
| 9 | `api.go:110` | `POST /api/cli-behind/quiet` | 桌面宿主窗口控制、托盘退出、本机 Finder 目录打开或 Web 引导脚本 | 无需页面（桌面宿主/内部协议） | `-` |
| 10 | `api.go:123` | `GET /api/cli` | 桌面宿主窗口控制、托盘退出、本机 Finder 目录打开或 Web 引导脚本 | 无需页面（桌面宿主/内部协议） | `-` |
| 11 | `api.go:128` | `GET /api/notices` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 12 | `api.go:131` | `POST /api/cli` | 桌面宿主窗口控制、托盘退出、本机 Finder 目录打开或 Web 引导脚本 | 无需页面（桌面宿主/内部协议） | `-` |
| 13 | `api.go:1225` | `POST /api/page-away` | 桌面宿主窗口控制、托盘退出、本机 Finder 目录打开或 Web 引导脚本 | 无需页面（桌面宿主/内部协议） | `-` |
| 14 | `api.go:1231` | `GET /boot.js` | 桌面宿主窗口控制、托盘退出、本机 Finder 目录打开或 Web 引导脚本 | 无需页面（桌面宿主/内部协议） | `-` |
| 15 | `api.go:1353` | `GET /api/omarchy` | 桌面宿主窗口控制、托盘退出、本机 Finder 目录打开或 Web 引导脚本 | 无需页面（桌面宿主/内部协议） | `-` |
| 16 | `api.go:1362` | `GET /api/state` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 17 | `api.go:1382` | `POST /api/set` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 18 | `api.go:1416` | `GET /api/drift` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 19 | `api.go:1430` | `POST /api/agents/rescan` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 20 | `api.go:1434` | `GET /api/agents/cli` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 21 | `api.go:1440` | `GET /api/agents/install` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 22 | `api.go:1444` | `POST /api/agents/stage/{id}` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 23 | `api.go:1472` | `POST /api/agents/cli/{id}` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 24 | `api.go:1489` | `POST /api/settings/desktop-isolated` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 25 | `api.go:1504` | `POST /api/settings/desktop-isolated-claude` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 26 | `api.go:1518` | `POST /api/agents/telemetry/{id}` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 27 | `api.go:1535` | `POST /api/agents/restart/{id}` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 28 | `api.go:1552` | `GET /api/agents/preview/{id}` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 29 | `api.go:1579` | `POST /api/agents/disconnect-offline/{id}` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 30 | `api.go:1613` | `POST /api/agents/{action}/{id}` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 31 | `api.go:1649` | `POST /api/profile/{action}` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 32 | `api.go:1692` | `POST /api/sync` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 33 | `api.go:1730` | `GET /api/settings` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 34 | `api.go:1734` | `POST /api/settings` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 35 | `api.go:1791` | `POST /api/settings/quota-left` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 36 | `api.go:1811` | `POST /api/settings/quota-reads` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 37 | `api.go:1829` | `POST /api/settings/search-all` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 38 | `api.go:1848` | `POST /api/settings/search-count` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 39 | `api.go:1867` | `POST /api/settings/agent-telemetry` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 40 | `api.go:1891` | `POST /api/settings/account-discovery` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 41 | `api.go:1910` | `POST /api/settings/update-skip` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 42 | `api.go:1933` | `POST /api/settings/plain-names` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 43 | `api.go:1957` | `POST /api/settings/bare-ids` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 44 | `api.go:1971` | `POST /api/settings/busy-load` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 45 | `api.go:1989` | `POST /api/settings/codex-agents-v1` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 46 | `api.go:2002` | `POST /api/settings/guide` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 47 | `api.go:2018` | `POST /api/settings/desktop-longest` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 48 | `api.go:2041` | `POST /api/settings/full-context` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 49 | `api.go:2064` | `POST /api/settings/context-cap` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 50 | `api.go:2078` | `POST /api/settings/context-cap-mode` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 51 | `api.go:2092` | `POST /api/settings/agent-compact` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 52 | `api.go:2114` | `POST /api/settings/agent-contexts` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 53 | `api.go:2136` | `POST /api/settings/agent-suffix` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 54 | `api.go:2155` | `POST /api/settings/codex-compact-held/drop` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 55 | `api.go:2165` | `POST /api/settings/codex-async-compact` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 56 | `api.go:2187` | `POST /api/settings/codex-descriptions` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 57 | `api.go:2210` | `POST /api/settings/codex-predictions` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 58 | `api.go:2233` | `POST /api/settings/codex-suggestions` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 59 | `api.go:2257` | `POST /api/settings/disabled-models` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 60 | `api.go:2271` | `POST /api/proxy/check` | 系统设置读写：通用外观、语言币种、额度告警、代理分流、端口、LAN、IP白名单、CORS、Bark推送、脱敏规则、联网搜索、Codex专项等 | 原生页 (SwiftUI) | `LogsPrivacyView.swift / MaskingEditors.swift / SettingsWorkspacesView.swift` |
| 61 | `api.go:2273` | `POST /api/pipelines/check` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 62 | `api.go:2274` | `POST /api/settings/codex-titles` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 63 | `api.go:2298` | `POST /api/settings/redact-route` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 64 | `api.go:2319` | `POST /api/settings/codex-auto-review` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 65 | `api.go:2343` | `POST /api/settings/codex-service-tier` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 66 | `api.go:2357` | `POST /api/settings/codex-client` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 67 | `api.go:2371` | `POST /api/settings/codex-open` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 68 | `api.go:2385` | `POST /api/warm-now` | Claude / Codex 订阅账号立即热身与批量热身 | 原生页 (SwiftUI) | `UsageTools.swift` |
| 69 | `api.go:2399` | `POST /api/warm-all` | Claude / Codex 订阅账号立即热身与批量热身 | 原生页 (SwiftUI) | `UsageTools.swift` |
| 70 | `api.go:2416` | `POST /api/settings/codex-warm-at` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 71 | `api.go:2430` | `POST /api/settings/codex-auto-reset` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 72 | `api.go:2456` | `POST /api/settings/codex-reset-lead` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 73 | `api.go:2471` | `POST /api/settings/codex-credits` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 74 | `api.go:2508` | `POST /api/settings/workbuddy-checkin` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 75 | `api.go:2523` | `POST /api/settings/trae-checkin` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 76 | `api.go:2538` | `POST /api/settings/minimax-checkin` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 77 | `api.go:2553` | `POST /api/settings/qoder-checkin` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 78 | `api.go:2568` | `POST /api/settings/plugin-checkin` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 79 | `api.go:2595` | `POST /api/settings/plugin-option` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 80 | `api.go:2632` | `POST /api/settings/checkin-account` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 81 | `api.go:2663` | `POST /api/settings/text-size` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 82 | `api.go:2682` | `POST /api/settings/panel-shortcut` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 83 | `api.go:2716` | `POST /api/agents/arrange` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 84 | `api.go:2732` | `POST /api/agents/here` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 85 | `api.go:2766` | `POST /api/usage/arrange` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 86 | `api.go:2814` | `POST /api/settings/login` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 87 | `api.go:2828` | `POST /api/settings/lan` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 88 | `api.go:2855` | `POST /api/settings/cors` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 89 | `api.go:2879` | `POST /api/settings/allowips` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 90 | `api.go:2912` | `POST /api/settings/port` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 91 | `api.go:2927` | `POST /api/settings/redact-rules` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 92 | `api.go:2944` | `POST /api/settings/redact-rule` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 93 | `api.go:2969` | `POST /api/settings/redact-actions` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 94 | `api.go:2986` | `POST /api/settings/redact-allow` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 95 | `api.go:3004` | `POST /api/settings/github-token` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 96 | `api.go:3028` | `POST /api/settings/bark` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 97 | `api.go:3059` | `POST /api/bark/test` | 系统设置读写：通用外观、语言币种、额度告警、代理分流、端口、LAN、IP白名单、CORS、Bark推送、脱敏规则、联网搜索、Codex专项等 | 原生页 (SwiftUI) | `LogsPrivacyView.swift / MaskingEditors.swift / SettingsWorkspacesView.swift` |
| 98 | `api.go:3078` | `POST /api/settings/update-mirror` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 99 | `api.go:3105` | `POST /api/settings/search-api` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 100 | `api.go:3146` | `POST /api/settings/search-keys` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 101 | `api.go:3179` | `POST /api/settings/search-key` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 102 | `api.go:3204` | `POST /api/settings/search-quota` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 103 | `api.go:3226` | `POST /api/settings/reveal` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 104 | `api.go:3235` | `POST /api/settings/log/reveal` | 全局状态握手、Agents 客户端扫描/接入/字段绑定/遥测/重启、Profiles 方案切换与同步 | 原生页 (SwiftUI) | `DashboardView.swift / AgentsView.swift / BackupSyncView` |
| 105 | `api.go:3249` | `POST /api/gateway/held/reveal` | 桌面宿主窗口控制、托盘退出、本机 Finder 目录打开或 Web 引导脚本 | 无需页面（桌面宿主/内部协议） | `-` |
| 106 | `api.go:3262` | `GET /api/quit` | 桌面宿主窗口控制、托盘退出、本机 Finder 目录打开或 Web 引导脚本 | 无需页面（桌面宿主/内部协议） | `-` |
| 107 | `api.go:3267` | `POST /api/quit/disconnect` | 桌面宿主窗口控制、托盘退出、本机 Finder 目录打开或 Web 引导脚本 | 无需页面（桌面宿主/内部协议） | `-` |
| 108 | `api.go:3274` | `POST /api/window/{action}` | 桌面宿主窗口控制、托盘退出、本机 Finder 目录打开或 Web 引导脚本 | 无需页面（桌面宿主/内部协议） | `-` |
| 109 | `appearance.go:347` | `GET /api/appearance/css` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 110 | `appearance.go:351` | `GET /api/appearance/wallpaper` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 111 | `appearance.go:369` | `POST /api/appearance/wallpaper` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 112 | `apppage.go:289` | `GET /api/web-page` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 113 | `apppage.go:292` | `POST /api/web-page` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 114 | `archive.go:109` | `POST /api/settings/archive` | 设置 → 隐私：网关请求/响应归档开关 | 原生页 (SwiftUI) | `SettingsWorkspacesView.swift (SystemSettingsEditorView)` |
| 115 | `archive.go:127` | `GET /api/archive` | 路由/用量页：读取或下载已归档单次请求原始载荷 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift` |
| 116 | `archive.go:158` | `GET /api/archive/file` | 路由/用量页：读取或下载已归档单次请求原始载荷 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift` |
| 117 | `archive.go:173` | `POST /api/archive/export` | 路由/用量页：读取或下载已归档单次请求原始载荷 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift` |
| 118 | `backup.go:25` | `POST /api/backup/export` | 设置 → 同步与备份：加密备份导出与 Base64 导入恢复 | 原生页 (SwiftUI) + 内嵌控制台双支持 | `SettingsWorkspacesView.swift (BackupSyncView)` |
| 119 | `backup.go:75` | `POST /api/backup/import` | 设置 → 同步与备份：加密备份导出与 Base64 导入恢复 | 原生页 (SwiftUI) + 内嵌控制台双支持 | `SettingsWorkspacesView.swift (BackupSyncView)` |
| 120 | `backup.go:113` | `GET /api/autobackup` | 设置 → 同步与备份：服务端定时自动备份策略与恢复 | 原生页 (SwiftUI) + 内嵌控制台双支持 | `SettingsWorkspacesView.swift (BackupSyncView)` |
| 121 | `backup.go:116` | `POST /api/autobackup/{action}` | 设置 → 同步与备份：服务端定时自动备份策略与恢复 | 原生页 (SwiftUI) + 内嵌控制台双支持 | `SettingsWorkspacesView.swift (BackupSyncView)` |
| 122 | `backup.go:196` | `GET /api/davsync` | 设置 → 同步与备份：WebDAV/S3/GitHub 跨端云同步读写与控制 | 原生页 (SwiftUI) + 内嵌控制台双支持 | `SettingsWorkspacesView.swift (BackupSyncView)` |
| 123 | `backup.go:199` | `POST /api/davsync/{action}` | 设置 → 同步与备份：WebDAV/S3/GitHub 跨端云同步读写与控制 | 原生页 (SwiftUI) + 内嵌控制台双支持 | `SettingsWorkspacesView.swift (BackupSyncView)` |
| 124 | `browser.go:140` | `GET /api/library/browser` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 125 | `browser.go:148` | `POST /api/library/browser/extension` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 126 | `browser.go:177` | `POST /api/library/browser/setup` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 127 | `browser.go:194` | `POST /api/library/browser/drag` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 128 | `builtins.go:151` | `GET /api/plugins/builtin` | Plugins 插件中心：内置网关中间件与第三方插件安装、升级、配置与独立插件页 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.plugins)` |
| 129 | `builtins.go:154` | `POST /api/plugins/builtin` | Plugins 插件中心：内置网关中间件与第三方插件安装、升级、配置与独立插件页 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.plugins)` |
| 130 | `caller_keys.go:70` | `GET /api/caller-keys` | 网关 → Caller Keys：下游调用密钥签发、改名、启停、轮换、模型范围与日/周/月预算限额 | 原生页 (SwiftUI) | `CallerKeysView.swift` |
| 131 | `caller_keys.go:84` | `GET /api/caller-keys/account-windows` | 网关 → Caller Keys：下游调用密钥签发、改名、启停、轮换、模型范围与日/周/月预算限额 | 原生页 (SwiftUI) | `CallerKeysView.swift` |
| 132 | `caller_keys.go:97` | `GET /api/caller-keys/models` | 网关 → Caller Keys：下游调用密钥签发、改名、启停、轮换、模型范围与日/周/月预算限额 | 原生页 (SwiftUI) | `CallerKeysView.swift` |
| 133 | `caller_keys.go:209` | `GET /api/caller-keys/mcp` | 网关 → Caller Keys：下游调用密钥签发、改名、启停、轮换、模型范围与日/周/月预算限额 | 原生页 (SwiftUI) | `CallerKeysView.swift` |
| 134 | `caller_keys.go:228` | `POST /api/caller-keys/{action}` | 网关 → Caller Keys：下游调用密钥签发、改名、启停、轮换、模型范围与日/周/月预算限额 | 原生页 (SwiftUI) | `CallerKeysView.swift` |
| 135 | `caller_keys.go:251` | `GET /api/account-groups` | 网关 → Caller Keys：下游调用密钥签发、改名、启停、轮换、模型范围与日/周/月预算限额 | 原生页 (SwiftUI) | `CallerKeysView.swift` |
| 136 | `caller_keys.go:260` | `POST /api/account-groups/{action}` | 网关 → Caller Keys：下游调用密钥签发、改名、启停、轮换、模型范围与日/周/月预算限额 | 原生页 (SwiftUI) | `CallerKeysView.swift` |
| 137 | `catalog_models.go:74` | `GET /api/catalog/models` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 138 | `config_repair.go:97` | `POST /api/config/repair` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 139 | `context.go:1036` | `GET /api/context/session` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 140 | `context.go:1047` | `GET /api/context` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 141 | `context.go:1059` | `GET /api/context/text` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 142 | `context_archive.go:204` | `GET /api/context/reply` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 143 | `datafolder.go:64` | `GET /api/datafolder` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 144 | `datafolder.go:67` | `POST /api/datafolder/{action}` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 145 | `dev_on.go:83` | `GET /api/dev/wait` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 146 | `dev_on.go:93` | `POST /api/dev/import` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 147 | `dev_on.go:96` | `GET /dev.js` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 148 | `dev_on.go:283` | `POST /{op}` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 149 | `feedback.go:93` | `GET /api/feedback` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 150 | `fonts.go:35` | `GET /api/fonts` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 151 | `gateway_takeover.go:52` | `POST /api/gateway/take-over` | 网关服务控制：接管端口、重启网关、暂停/恢复监听、切换 Web 网关模式 | 原生页 (SwiftUI) | `DashboardView.swift / SettingsWorkspacesView.swift` |
| 152 | `gateway_takeover.go:55` | `POST /api/gateway/restart` | 网关服务控制：接管端口、重启网关、暂停/恢复监听、切换 Web 网关模式 | 原生页 (SwiftUI) | `DashboardView.swift / SettingsWorkspacesView.swift` |
| 153 | `gatewaymode.go:68` | `POST /api/settings/gateway-mode` | 网关服务控制：接管端口、重启网关、暂停/恢复监听、切换 Web 网关模式 | 原生页 (SwiftUI) | `DashboardView.swift / SettingsWorkspacesView.swift` |
| 154 | `gatewaypause.go:228` | `POST /api/gateway/pause` | 网关服务控制：接管端口、重启网关、暂停/恢复监听、切换 Web 网关模式 | 原生页 (SwiftUI) | `DashboardView.swift / SettingsWorkspacesView.swift` |
| 155 | `groups.go:557` | `GET /api/groups` | 路由组（group/*）：列表、新建、编辑、复制、删除、排序、模板、导入/分享与全局默认超时 | 原生页 (SwiftUI) | `ProvidersView.swift / GroupEditorSheet.swift / CopyGroupSheet.swift` |
| 156 | `groups.go:560` | `POST /api/groups/{action}` | 路由组（group/*）：列表、新建、编辑、复制、删除、排序、模板、导入/分享与全局默认超时 | 原生页 (SwiftUI) | `ProvidersView.swift / GroupEditorSheet.swift / CopyGroupSheet.swift` |
| 157 | `https.go:62` | `GET /api/settings/https` | 设置 → 网络安全：HTTPS 证书导入与 mTLS 客户端证书签发/吊销 | 原生状态展示 + 内嵌原版控制台 (WKWebView) | `LogsPrivacyView.swift / RemoteConsoleView.swift (.network)` |
| 158 | `https.go:68` | `POST /api/settings/https` | 设置 → 网络安全：HTTPS 证书导入与 mTLS 客户端证书签发/吊销 | 原生状态展示 + 内嵌原版控制台 (WKWebView) | `LogsPrivacyView.swift / RemoteConsoleView.swift (.network)` |
| 159 | `https.go:97` | `POST /api/settings/https/import` | 设置 → 网络安全：HTTPS 证书导入与 mTLS 客户端证书签发/吊销 | 原生状态展示 + 内嵌原版控制台 (WKWebView) | `LogsPrivacyView.swift / RemoteConsoleView.swift (.network)` |
| 160 | `https.go:113` | `POST /api/settings/https/remove` | 设置 → 网络安全：HTTPS 证书导入与 mTLS 客户端证书签发/吊销 | 原生状态展示 + 内嵌原版控制台 (WKWebView) | `LogsPrivacyView.swift / RemoteConsoleView.swift (.network)` |
| 161 | `https.go:121` | `POST /api/settings/https/ca` | 设置 → 网络安全：HTTPS 证书导入与 mTLS 客户端证书签发/吊销 | 原生状态展示 + 内嵌原版控制台 (WKWebView) | `LogsPrivacyView.swift / RemoteConsoleView.swift (.network)` |
| 162 | `importapps.go:30` | `GET /api/importapps/discovery` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 163 | `importapps.go:48` | `GET /api/importapps` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 164 | `importapps.go:70` | `POST /api/importapps` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 165 | `importlink.go:61` | `GET /api/import/{id}` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 166 | `importlink.go:80` | `POST /api/import/icon` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 167 | `join.go:17` | `POST /api/settings/join` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 168 | `library.go:181` | `GET /api/library` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 169 | `library.go:189` | `GET /api/library/skill` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 170 | `library.go:199` | `GET /api/library/market/servers` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 171 | `library.go:209` | `GET /api/library/market/skills` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 172 | `library.go:213` | `GET /api/library/market/pi` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 173 | `library.go:217` | `POST /api/library/market/about` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 174 | `library.go:228` | `GET /api/library/icon` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 175 | `library.go:239` | `POST /api/library/skills/probe` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 176 | `library.go:254` | `POST /api/library/plugins/probe` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 177 | `library.go:269` | `POST /api/library/subagents/probe` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 178 | `library.go:284` | `POST /api/library/commands/probe` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 179 | `library.go:294` | `POST /api/library/skills/check` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 180 | `library.go:308` | `POST /api/library/skills/regroup` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 181 | `library.go:327` | `GET /api/library/pi` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 182 | `library.go:330` | `POST /api/library/pi` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 183 | `library.go:355` | `POST /api/library/pi/copy` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 184 | `library.go:370` | `POST /api/library/pi/install` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 185 | `library.go:383` | `POST /api/library/pi/remove` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 186 | `library.go:398` | `GET /api/library/rtk` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 187 | `library.go:419` | `POST /api/library/rtk` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 188 | `library.go:435` | `POST /api/library/rtk/upgrade` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 189 | `library.go:444` | `POST /api/library/rtk/path` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 190 | `library.go:453` | `POST /api/library/rtk/install` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 191 | `library.go:475` | `GET /api/library/bili` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 192 | `library.go:478` | `POST /api/library/bili` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 193 | `library.go:497` | `GET /api/library/bili/settings` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 194 | `library.go:505` | `POST /api/library/bili/settings` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 195 | `library.go:518` | `POST /api/library/bili/install` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 196 | `library.go:527` | `POST /api/library/projects/choose` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 197 | `library.go:535` | `POST /api/library/reveal` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 198 | `library.go:570` | `POST /api/library/mcp-signin` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 199 | `library.go:593` | `GET /api/library/mcp-signin/{id}` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 200 | `library.go:601` | `POST /api/library/mcp-signin/{id}/cancel` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 201 | `library.go:608` | `POST /api/library/mcp-account` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 202 | `library.go:644` | `POST /api/library/mcp-signout` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 203 | `library.go:663` | `POST /api/library/mcp/check` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 204 | `library.go:681` | `POST /api/library/mcp/config` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 205 | `library.go:698` | `POST /api/library/{what}/{action}` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 206 | `localhosts.go:20` | `POST /api/local-hosts` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 207 | `masking.go:86` | `POST /api/masking/allow` | 隐私脱敏：在线试测预览、近7日统计、命中记录、上游发送体与显式原值对照恢复、清空记录 | 原生页 (SwiftUI) | `LogsPrivacyView.swift / MaskingEditors.swift` |
| 208 | `masking.go:119` | `POST /api/masking/preview` | 隐私脱敏：在线试测预览、近7日统计、命中记录、上游发送体与显式原值对照恢复、清空记录 | 原生页 (SwiftUI) | `LogsPrivacyView.swift / MaskingEditors.swift` |
| 209 | `masking.go:145` | `POST /api/masking/clear` | 隐私脱敏：在线试测预览、近7日统计、命中记录、上游发送体与显式原值对照恢复、清空记录 | 原生页 (SwiftUI) | `LogsPrivacyView.swift / MaskingEditors.swift` |
| 210 | `masking.go:152` | `GET /api/masking/summary` | 隐私脱敏：在线试测预览、近7日统计、命中记录、上游发送体与显式原值对照恢复、清空记录 | 原生页 (SwiftUI) | `LogsPrivacyView.swift / MaskingEditors.swift` |
| 211 | `masking.go:156` | `GET /api/masking/records` | 隐私脱敏：在线试测预览、近7日统计、命中记录、上游发送体与显式原值对照恢复、清空记录 | 原生页 (SwiftUI) | `LogsPrivacyView.swift / MaskingEditors.swift` |
| 212 | `masking.go:168` | `GET /api/masking/record` | 隐私脱敏：在线试测预览、近7日统计、命中记录、上游发送体与显式原值对照恢复、清空记录 | 原生页 (SwiftUI) | `LogsPrivacyView.swift / MaskingEditors.swift` |
| 213 | `masking.go:178` | `GET /api/masking/value` | 隐私脱敏：在线试测预览、近7日统计、命中记录、上游发送体与显式原值对照恢复、清空记录 | 原生页 (SwiftUI) | `LogsPrivacyView.swift / MaskingEditors.swift` |
| 214 | `masking.go:192` | `GET /api/masking/sent` | 隐私脱敏：在线试测预览、近7日统计、命中记录、上游发送体与显式原值对照恢复、清空记录 | 原生页 (SwiftUI) | `LogsPrivacyView.swift / MaskingEditors.swift` |
| 215 | `masking.go:202` | `POST /api/masking/values` | 隐私脱敏：在线试测预览、近7日统计、命中记录、上游发送体与显式原值对照恢复、清空记录 | 原生页 (SwiftUI) | `LogsPrivacyView.swift / MaskingEditors.swift` |
| 216 | `memory.go:71` | `GET /api/memory` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 217 | `memory.go:80` | `POST /api/memory` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 218 | `memory.go:101` | `POST /api/memory/remove` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 219 | `memory.go:121` | `POST /api/memory/status` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 220 | `memory.go:142` | `POST /api/memory/promote` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 221 | `memory.go:156` | `POST /api/memory/skill` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 222 | `memory.go:170` | `POST /api/memory/decline` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 223 | `memory.go:184` | `POST /api/memory/digest` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 224 | `memory_distill.go:161` | `GET /api/memory/distill` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 225 | `memory_distill.go:173` | `POST /api/memory/distill` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 226 | `memory_distill.go:220` | `POST /api/memory/distill/run` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 227 | `memory_distill.go:230` | `POST /api/memory/distill/stop` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 228 | `memory_distill.go:240` | `POST /api/memory/dream` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 229 | `memory_distill.go:259` | `POST /api/memory/dream/run` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 230 | `memory_distill.go:269` | `POST /api/memory/dream/undo` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 231 | `memory_semantic.go:19` | `GET /api/memory/semantic` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 232 | `memory_semantic.go:24` | `POST /api/memory/semantic` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 233 | `memory_semantic.go:41` | `POST /api/memory/rank` | Library 资源库：MCP Servers、Skills、Prompts、Subagents 与 Memory 知识库管理 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.library)` |
| 234 | `modelprice.go:53` | `GET /api/model-price` | 模型自定义单价（input/output/cache_read/cache_write）查询与保存 | 原生页 (SwiftUI) | `SettingsWorkspacesView.swift (ModelPriceEditorView)` |
| 235 | `modelprice.go:61` | `POST /api/model-price` | 模型自定义单价（input/output/cache_read/cache_write）查询与保存 | 原生页 (SwiftUI) | `SettingsWorkspacesView.swift (ModelPriceEditorView)` |
| 236 | `mtls.go:58` | `POST /api/settings/mtls` | 设置 → 网络安全：HTTPS 证书导入与 mTLS 客户端证书签发/吊销 | 原生状态展示 + 内嵌原版控制台 (WKWebView) | `LogsPrivacyView.swift / RemoteConsoleView.swift (.network)` |
| 237 | `mtls.go:82` | `POST /api/settings/mtls/issue` | 设置 → 网络安全：HTTPS 证书导入与 mTLS 客户端证书签发/吊销 | 原生状态展示 + 内嵌原版控制台 (WKWebView) | `LogsPrivacyView.swift / RemoteConsoleView.swift (.network)` |
| 238 | `mtls.go:108` | `POST /api/settings/mtls/revoke` | 设置 → 网络安全：HTTPS 证书导入与 mTLS 客户端证书签发/吊销 | 原生状态展示 + 内嵌原版控制台 (WKWebView) | `LogsPrivacyView.swift / RemoteConsoleView.swift (.network)` |
| 239 | `omarchy.go:44` | `GET /api/omarchy/widget` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 240 | `omarchy.go:47` | `POST /api/omarchy/widget` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 241 | `pageimage.go:114` | `POST /api/plugin-pages/image` | Plugins 插件中心：内置网关中间件与第三方插件安装、升级、配置与独立插件页 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.plugins)` |
| 242 | `pluginpage.go:470` | `pluginPagePrefix` | Plugins 插件中心：内置网关中间件与第三方插件安装、升级、配置与独立插件页 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.plugins)` |
| 243 | `pluginpage.go:473` | `GET /api/plugin-pages` | Plugins 插件中心：内置网关中间件与第三方插件安装、升级、配置与独立插件页 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.plugins)` |
| 244 | `pluginpage.go:500` | `POST /api/plugin-pages/arrange` | Plugins 插件中心：内置网关中间件与第三方插件安装、升级、配置与独立插件页 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.plugins)` |
| 245 | `pluginpage.go:518` | `GET /api/plugin-panels` | Plugins 插件中心：内置网关中间件与第三方插件安装、升级、配置与独立插件页 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.plugins)` |
| 246 | `pluginpage.go:527` | `POST /api/plugin-pages/read` | Plugins 插件中心：内置网关中间件与第三方插件安装、升级、配置与独立插件页 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.plugins)` |
| 247 | `pluginpage.go:557` | `POST /api/plugin-pages/options` | Plugins 插件中心：内置网关中间件与第三方插件安装、升级、配置与独立插件页 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.plugins)` |
| 248 | `plugins.go:610` | `GET /api/plugins/updates` | Plugins 插件中心：内置网关中间件与第三方插件安装、升级、配置与独立插件页 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.plugins)` |
| 249 | `plugins.go:615` | `GET /api/plugins/listings` | Plugins 插件中心：内置网关中间件与第三方插件安装、升级、配置与独立插件页 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.plugins)` |
| 250 | `plugins.go:620` | `GET /api/plugins/agents` | Plugins 插件中心：内置网关中间件与第三方插件安装、升级、配置与独立插件页 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.plugins)` |
| 251 | `plugins.go:625` | `GET /api/plugins/github` | Plugins 插件中心：内置网关中间件与第三方插件安装、升级、配置与独立插件页 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.plugins)` |
| 252 | `plugins.go:662` | `GET /api/plugins/git` | Plugins 插件中心：内置网关中间件与第三方插件安装、升级、配置与独立插件页 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.plugins)` |
| 253 | `plugins.go:667` | `GET /api/plugins/npm` | Plugins 插件中心：内置网关中间件与第三方插件安装、升级、配置与独立插件页 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.plugins)` |
| 254 | `plugins.go:687` | `GET /api/plugins/market` | Plugins 插件中心：内置网关中间件与第三方插件安装、升级、配置与独立插件页 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.plugins)` |
| 255 | `plugins.go:692` | `GET /api/plugins/search` | Plugins 插件中心：内置网关中间件与第三方插件安装、升级、配置与独立插件页 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.plugins)` |
| 256 | `plugins.go:700` | `GET /api/plugins/page` | Plugins 插件中心：内置网关中间件与第三方插件安装、升级、配置与独立插件页 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.plugins)` |
| 257 | `plugins.go:708` | `GET /api/plugins` | Plugins 插件中心：内置网关中间件与第三方插件安装、升级、配置与独立插件页 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.plugins)` |
| 258 | `plugins.go:715` | `POST /api/plugins/choose` | Plugins 插件中心：内置网关中间件与第三方插件安装、升级、配置与独立插件页 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.plugins)` |
| 259 | `plugins.go:725` | `POST /api/plugins/check` | Plugins 插件中心：内置网关中间件与第三方插件安装、升级、配置与独立插件页 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.plugins)` |
| 260 | `plugins.go:733` | `POST /api/plugins/mirror` | Plugins 插件中心：内置网关中间件与第三方插件安装、升级、配置与独立插件页 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.plugins)` |
| 261 | `plugins.go:747` | `POST /api/plugins/registry` | Plugins 插件中心：内置网关中间件与第三方插件安装、升级、配置与独立插件页 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.plugins)` |
| 262 | `plugins.go:760` | `POST /api/plugins/{op}` | Plugins 插件中心：内置网关中间件与第三方插件安装、升级、配置与独立插件页 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.plugins)` |
| 263 | `plugins.go:814` | `POST /api/plugin-signin/prompt` | Plugins 插件中心：内置网关中间件与第三方插件安装、升级、配置与独立插件页 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.plugins)` |
| 264 | `plugins.go:850` | `POST /api/plugin-signin` | Plugins 插件中心：内置网关中间件与第三方插件安装、升级、配置与独立插件页 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.plugins)` |
| 265 | `plugins_counts.go:82` | `GET /api/plugins/counts` | Plugins 插件中心：内置网关中间件与第三方插件安装、升级、配置与独立插件页 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.plugins)` |
| 266 | `plugins_counts.go:95` | `POST /api/plugins/like` | Plugins 插件中心：内置网关中间件与第三方插件安装、升级、配置与独立插件页 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.plugins)` |
| 267 | `privacymodel.go:54` | `GET /api/privacy-model` | 设置 → 隐私：本地 AI 隐私识别模型启停、切换与阈值配置 | 原生页 (SwiftUI) | `SettingsWorkspacesView.swift (SystemSettingsEditorView)` |
| 268 | `privacymodel.go:57` | `POST /api/privacy-model` | 设置 → 隐私：本地 AI 隐私识别模型启停、切换与阈值配置 | 原生页 (SwiftUI) | `SettingsWorkspacesView.swift (SystemSettingsEditorView)` |
| 269 | `providers.go:1676` | `GET /api/lanes` | 供应商图标、辅助复制与外部链接打开 | 原生页 / 无需单独页面 | `ProvidersView.swift` |
| 270 | `providers.go:1691` | `GET /api/upstream` | 供应商图标、辅助复制与外部链接打开 | 原生页 / 无需单独页面 | `ProvidersView.swift` |
| 271 | `providers.go:1704` | `GET /api/providers` | 供应商与多 Key 号池：预设/自定义增删改、测连、拉模型、查余额、多 Key 权重/协议/限定模型、路由与粘性策略 | 原生页 (SwiftUI) | `ProvidersView.swift / ProviderDetailSheet.swift` |
| 272 | `providers.go:1731` | `GET /api/gateway/call` | 实时路由流：查看单次请求/响应完整载荷详情 | 原生页 (SwiftUI) | `DashboardView.swift (RouteDetailSheet)` |
| 273 | `providers.go:1758` | `POST /api/providers/arrange` | 供应商与多 Key 号池：预设/自定义增删改、测连、拉模型、查余额、多 Key 权重/协议/限定模型、路由与粘性策略 | 原生页 (SwiftUI) | `ProvidersView.swift / ProviderDetailSheet.swift` |
| 274 | `providers.go:1776` | `POST /api/providers/delete` | 供应商与多 Key 号池：预设/自定义增删改、测连、拉模型、查余额、多 Key 权重/协议/限定模型、路由与粘性策略 | 原生页 (SwiftUI) | `ProvidersView.swift / ProviderDetailSheet.swift` |
| 275 | `providers.go:1822` | `POST /api/icons` | 供应商图标、辅助复制与外部链接打开 | 原生页 / 无需单独页面 | `ProvidersView.swift` |
| 276 | `providers.go:1847` | `POST /api/icons/favicon` | 供应商图标、辅助复制与外部链接打开 | 原生页 / 无需单独页面 | `ProvidersView.swift` |
| 277 | `providers.go:1862` | `POST /api/icons/url` | 供应商图标、辅助复制与外部链接打开 | 原生页 / 无需单独页面 | `ProvidersView.swift` |
| 278 | `providers.go:1875` | `GET /api/icons/{name}` | 供应商图标、辅助复制与外部链接打开 | 原生页 / 无需单独页面 | `ProvidersView.swift` |
| 279 | `providers.go:1893` | `POST /api/provider/{action}` | 供应商与多 Key 号池：预设/自定义增删改、测连、拉模型、查余额、多 Key 权重/协议/限定模型、路由与粘性策略 | 原生页 (SwiftUI) | `ProvidersView.swift / ProviderDetailSheet.swift` |
| 280 | `providers.go:3303` | `GET /api/login/usage` | 供应商 OAuth / 订阅账号扫码与网页登录授权流 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift` |
| 281 | `providers.go:3312` | `POST /api/login/{action}` | 供应商 OAuth / 订阅账号扫码与网页登录授权流 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift` |
| 282 | `providers.go:3360` | `GET /api/claude/mode` | 供应商图标、辅助复制与外部链接打开 | 原生页 / 无需单独页面 | `ProvidersView.swift` |
| 283 | `providers.go:3367` | `POST /api/codex/daemon/{action}` | 供应商图标、辅助复制与外部链接打开 | 原生页 / 无需单独页面 | `ProvidersView.swift` |
| 284 | `providers.go:3400` | `POST /api/codex/app/reopen` | 供应商图标、辅助复制与外部链接打开 | 原生页 / 无需单独页面 | `ProvidersView.swift` |
| 285 | `providers.go:3415` | `POST /api/keys/{action}` | 供应商与多 Key 号池：预设/自定义增删改、测连、拉模型、查余额、多 Key 权重/协议/限定模型、路由与粘性策略 | 原生页 (SwiftUI) | `ProvidersView.swift / ProviderDetailSheet.swift` |
| 286 | `providers.go:3496` | `POST /api/signin` | 供应商 OAuth / 订阅账号扫码与网页登录授权流 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift` |
| 287 | `providers.go:3520` | `GET /api/signin/{id}` | 供应商 OAuth / 订阅账号扫码与网页登录授权流 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift` |
| 288 | `providers.go:3528` | `POST /api/signin/{id}/cancel` | 供应商 OAuth / 订阅账号扫码与网页登录授权流 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift` |
| 289 | `providers.go:3532` | `POST /api/signin/{id}/callback` | 供应商 OAuth / 订阅账号扫码与网页登录授权流 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift` |
| 290 | `providers.go:3547` | `POST /api/signin/claude-token` | 供应商 OAuth / 订阅账号扫码与网页登录授权流 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift` |
| 291 | `providers.go:3564` | `POST /api/signin/import` | 供应商 OAuth / 订阅账号扫码与网页登录授权流 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift` |
| 292 | `providers.go:3623` | `POST /api/signin/export` | 供应商 OAuth / 订阅账号扫码与网页登录授权流 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift` |
| 293 | `providers.go:3679` | `POST /api/stepfun/{id}/session` | 供应商 OAuth / 订阅账号扫码与网页登录授权流 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift` |
| 294 | `providers.go:3697` | `POST /api/stepfun/{id}/signout` | 供应商 OAuth / 订阅账号扫码与网页登录授权流 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift` |
| 295 | `providers.go:3718` | `POST /api/qianfan/{id}/session` | 供应商 OAuth / 订阅账号扫码与网页登录授权流 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift` |
| 296 | `providers.go:3736` | `POST /api/qianfan/{id}/signout` | 供应商 OAuth / 订阅账号扫码与网页登录授权流 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift` |
| 297 | `providers.go:3757` | `POST /api/qianwen/{id}/signin` | 供应商 OAuth / 订阅账号扫码与网页登录授权流 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift` |
| 298 | `providers.go:3773` | `GET /api/qianwen/{id}/signin` | 供应商 OAuth / 订阅账号扫码与网页登录授权流 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift` |
| 299 | `providers.go:3784` | `POST /api/qianwen/{id}/signin/cancel` | 供应商 OAuth / 订阅账号扫码与网页登录授权流 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift` |
| 300 | `providers.go:3792` | `POST /api/qianwen/{id}/signout` | 供应商 OAuth / 订阅账号扫码与网页登录授权流 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift` |
| 301 | `providers.go:3805` | `POST /api/copy` | 供应商图标、辅助复制与外部链接打开 | 原生页 / 无需单独页面 | `ProvidersView.swift` |
| 302 | `providers.go:3817` | `POST /api/partner` | 供应商图标、辅助复制与外部链接打开 | 原生页 / 无需单独页面 | `ProvidersView.swift` |
| 303 | `providers.go:3831` | `POST /api/open` | 供应商图标、辅助复制与外部链接打开 | 原生页 / 无需单独页面 | `ProvidersView.swift` |
| 304 | `proxies.go:247` | `POST /api/proxies/save` | 设置 → 网络与共享：命名代理池保存、删除与连通性测速 | 原生页 (SwiftUI) + 内嵌控制台双支持 | `SettingsWorkspacesView.swift (ProxiesManagerView)` |
| 305 | `proxies.go:248` | `POST /api/proxies/delete` | 设置 → 网络与共享：命名代理池保存、删除与连通性测速 | 原生页 (SwiftUI) + 内嵌控制台双支持 | `SettingsWorkspacesView.swift (ProxiesManagerView)` |
| 306 | `proxies.go:249` | `POST /api/proxies/test` | 设置 → 网络与共享：命名代理池保存、删除与连通性测速 | 原生页 (SwiftUI) + 内嵌控制台双支持 | `SettingsWorkspacesView.swift (ProxiesManagerView)` |
| 307 | `remote.go:203` | `GET /api/remote` | 远程 Magpie 实例连接管理（iOS 端已作为原生多实例切换器核心实现） | 原生页 (SwiftUI) | `LogsPrivacyView.swift / ServerEditorSheet.swift` |
| 308 | `remote.go:211` | `POST /api/remote` | 远程 Magpie 实例连接管理（iOS 端已作为原生多实例切换器核心实现） | 原生页 (SwiftUI) | `LogsPrivacyView.swift / ServerEditorSheet.swift` |
| 309 | `remote.go:259` | `POST /api/remote/forget` | 远程 Magpie 实例连接管理（iOS 端已作为原生多实例切换器核心实现） | 原生页 (SwiftUI) | `LogsPrivacyView.swift / ServerEditorSheet.swift` |
| 310 | `sessions.go:116` | `GET /api/sessions` | Sessions 会话浏览器：跨客户端对话记录检索、Markdown 导出、删除与恢复 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.sessions)` |
| 311 | `sessions.go:229` | `GET /api/sessions/stats` | Sessions 会话浏览器：跨客户端对话记录检索、Markdown 导出、删除与恢复 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.sessions)` |
| 312 | `sessions.go:270` | `GET /api/sessions/overview` | Sessions 会话浏览器：跨客户端对话记录检索、Markdown 导出、删除与恢复 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.sessions)` |
| 313 | `sessions.go:278` | `GET /api/sessions/progress` | Sessions 会话浏览器：跨客户端对话记录检索、Markdown 导出、删除与恢复 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.sessions)` |
| 314 | `sessions.go:283` | `GET /api/sessions/one` | Sessions 会话浏览器：跨客户端对话记录检索、Markdown 导出、删除与恢复 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.sessions)` |
| 315 | `sessions.go:321` | `GET /api/sessions/transcript` | Sessions 会话浏览器：跨客户端对话记录检索、Markdown 导出、删除与恢复 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.sessions)` |
| 316 | `sessions.go:359` | `GET /api/sessions/markdown` | Sessions 会话浏览器：跨客户端对话记录检索、Markdown 导出、删除与恢复 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.sessions)` |
| 317 | `sessions.go:370` | `POST /api/sessions/export` | Sessions 会话浏览器：跨客户端对话记录检索、Markdown 导出、删除与恢复 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.sessions)` |
| 318 | `sessions.go:387` | `POST /api/sessions/terminal` | Sessions 会话浏览器：跨客户端对话记录检索、Markdown 导出、删除与恢复 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.sessions)` |
| 319 | `sessions.go:423` | `POST /api/agents/open` | Sessions 会话浏览器：跨客户端对话记录检索、Markdown 导出、删除与恢复 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.sessions)` |
| 320 | `sessions.go:471` | `POST /api/sessions/carry` | Sessions 会话浏览器：跨客户端对话记录检索、Markdown 导出、删除与恢复 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.sessions)` |
| 321 | `sessions_manage.go:102` | `POST /api/sessions/relocate-claude` | Sessions 会话浏览器：跨客户端对话记录检索、Markdown 导出、删除与恢复 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.sessions)` |
| 322 | `sessions_manage.go:118` | `POST /api/sessions/recording` | Sessions 会话浏览器：跨客户端对话记录检索、Markdown 导出、删除与恢复 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.sessions)` |
| 323 | `sessions_manage.go:137` | `GET /api/speeds` | Sessions 会话浏览器：跨客户端对话记录检索、Markdown 导出、删除与恢复 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.sessions)` |
| 324 | `sessions_manage.go:146` | `GET /api/sessions/manage` | Sessions 会话浏览器：跨客户端对话记录检索、Markdown 导出、删除与恢复 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.sessions)` |
| 325 | `sessions_manage.go:286` | `GET /api/sessions/search` | Sessions 会话浏览器：跨客户端对话记录检索、Markdown 导出、删除与恢复 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.sessions)` |
| 326 | `sessions_manage.go:293` | `GET /api/sessions/said` | Sessions 会话浏览器：跨客户端对话记录检索、Markdown 导出、删除与恢复 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.sessions)` |
| 327 | `sessions_manage.go:306` | `POST /api/sessions/delete` | Sessions 会话浏览器：跨客户端对话记录检索、Markdown 导出、删除与恢复 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.sessions)` |
| 328 | `sessions_manage.go:357` | `POST /api/sessions/codex-provider` | Sessions 会话浏览器：跨客户端对话记录检索、Markdown 导出、删除与恢复 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.sessions)` |
| 329 | `sessions_manage.go:398` | `POST /api/sessions/restore` | Sessions 会话浏览器：跨客户端对话记录检索、Markdown 导出、删除与恢复 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.sessions)` |
| 330 | `sessions_manage.go:417` | `POST /api/sessions/purge` | Sessions 会话浏览器：跨客户端对话记录检索、Markdown 导出、删除与恢复 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.sessions)` |
| 331 | `sessions_reads.go:68` | `GET /api/sessions/reads` | Sessions 会话浏览器：跨客户端对话记录检索、Markdown 导出、删除与恢复 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.sessions)` |
| 332 | `sessions_reads.go:74` | `POST /api/sessions/reads` | Sessions 会话浏览器：跨客户端对话记录检索、Markdown 导出、删除与恢复 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift (.sessions)` |
| 333 | `speeds.go:43` | `GET /api/model-speeds` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 334 | `speeds.go:51` | `GET /api/model-loads` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 335 | `trace.go:442` | `POST /api/gateway/session-titles` | 路由流会话标题解析与挂起请求诊断报告 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift` |
| 336 | `trace.go:499` | `GET /api/gateway/route` | 总览 → 请求路由流：实时长轮询追踪与按日历史记录回放 | 原生页 (SwiftUI) | `DashboardView.swift` |
| 337 | `trace.go:524` | `GET /api/gateway/trace` | 总览 → 请求路由流：实时长轮询追踪与按日历史记录回放 | 原生页 (SwiftUI) | `DashboardView.swift` |
| 338 | `trace.go:547` | `GET /api/gateway/history` | 总览 → 请求路由流：实时长轮询追踪与按日历史记录回放 | 原生页 (SwiftUI) | `DashboardView.swift` |
| 339 | `trace.go:564` | `GET /api/gateway/held/{name}` | 路由流会话标题解析与挂起请求诊断报告 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift` |
| 340 | `trace.go:575` | `POST /api/gateway/unrest` | 网关：手动解除供应商或 Key 的限流冷却状态 | 原生页 (SwiftUI) | `DashboardView.swift` |
| 341 | `tune.go:339` | `GET /api/tune` | 用量 → 上下文调优：回放 Token 压缩/缓存 TTL 建议、应用、接管与还原 | 原生页 (SwiftUI) + 内嵌控制台双支持 | `SettingsWorkspacesView.swift (ContextTuneView)` |
| 342 | `tune.go:362` | `POST /api/tune/apply` | 用量 → 上下文调优：回放 Token 压缩/缓存 TTL 建议、应用、接管与还原 | 原生页 (SwiftUI) + 内嵌控制台双支持 | `SettingsWorkspacesView.swift (ContextTuneView)` |
| 343 | `tune.go:381` | `POST /api/settings/claude-cache` | 用量 → 上下文调优：回放 Token 压缩/缓存 TTL 建议、应用、接管与还原 | 原生页 (SwiftUI) + 内嵌控制台双支持 | `SettingsWorkspacesView.swift (ContextTuneView)` |
| 344 | `tune.go:396` | `POST /api/settings/claude-attribution` | 用量 → 上下文调优：回放 Token 压缩/缓存 TTL 建议、应用、接管与还原 | 原生页 (SwiftUI) + 内嵌控制台双支持 | `SettingsWorkspacesView.swift (ContextTuneView)` |
| 345 | `tune.go:410` | `POST /api/tune/takeover` | 用量 → 上下文调优：回放 Token 压缩/缓存 TTL 建议、应用、接管与还原 | 原生页 (SwiftUI) + 内嵌控制台双支持 | `SettingsWorkspacesView.swift (ContextTuneView)` |
| 346 | `tune.go:427` | `POST /api/tune/undo` | 用量 → 上下文调优：回放 Token 压缩/缓存 TTL 建议、应用、接管与还原 | 原生页 (SwiftUI) + 内嵌控制台双支持 | `SettingsWorkspacesView.swift (ContextTuneView)` |
| 347 | `uninstall.go:35` | `POST /api/uninstall` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 348 | `uninstall.go:49` | `POST /api/uninstall/finish` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 349 | `update.go:933` | `POST /api/update/using` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 350 | `update.go:941` | `GET /api/update` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 351 | `update.go:956` | `GET /api/update/notes` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 352 | `update.go:984` | `POST /api/update/check` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 353 | `update.go:994` | `POST /api/update/install` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 354 | `usage.go:104` | `GET /api/usage` | 用量与额度：今日/7d/30d/all 汇总与交互趋势图、5h/7d 额度窗口刷新、平台每日签到、清空统计与重置卡 | 原生页 (SwiftUI) | `UsageView.swift / UsageTools.swift` |
| 355 | `usage.go:110` | `GET /api/usage/deleted/into` | 用量明细 CSV 导出、热力图与历史额度曲线 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift` |
| 356 | `usage.go:141` | `POST /api/usage/clear` | 用量与额度：今日/7d/30d/all 汇总与交互趋势图、5h/7d 额度窗口刷新、平台每日签到、清空统计与重置卡 | 原生页 (SwiftUI) | `UsageView.swift / UsageTools.swift` |
| 357 | `usage.go:157` | `POST /api/usage/deleted` | 用量明细 CSV 导出、热力图与历史额度曲线 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift` |
| 358 | `usage.go:182` | `GET /api/usage/requests` | 用量明细 CSV 导出、热力图与历史额度曲线 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift` |
| 359 | `usage.go:191` | `GET /api/usage/traffic` | 用量明细 CSV 导出、热力图与历史额度曲线 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift` |
| 360 | `usage.go:196` | `GET /api/usage/heatmap` | 用量明细 CSV 导出、热力图与历史额度曲线 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift` |
| 361 | `usage.go:202` | `GET /api/usage/requests/content` | 用量明细 CSV 导出、热力图与历史额度曲线 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift` |
| 362 | `usage.go:219` | `GET /api/usage/requests.csv` | 用量明细 CSV 导出、热力图与历史额度曲线 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift` |
| 363 | `usage.go:232` | `POST /api/usage/requests/export` | 用量明细 CSV 导出、热力图与历史额度曲线 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift` |
| 364 | `usage.go:271` | `GET /api/usage/quotas` | 用量与额度：今日/7d/30d/all 汇总与交互趋势图、5h/7d 额度窗口刷新、平台每日签到、清空统计与重置卡 | 原生页 (SwiftUI) | `UsageView.swift / UsageTools.swift` |
| 365 | `usage.go:306` | `POST /api/usage/quotas/refresh` | 用量与额度：今日/7d/30d/all 汇总与交互趋势图、5h/7d 额度窗口刷新、平台每日签到、清空统计与重置卡 | 原生页 (SwiftUI) | `UsageView.swift / UsageTools.swift` |
| 366 | `usage.go:320` | `POST /api/usage/workbuddy-checkin` | 用量与额度：今日/7d/30d/all 汇总与交互趋势图、5h/7d 额度窗口刷新、平台每日签到、清空统计与重置卡 | 原生页 (SwiftUI) | `UsageView.swift / UsageTools.swift` |
| 367 | `usage.go:330` | `POST /api/usage/trae-checkin` | 用量与额度：今日/7d/30d/all 汇总与交互趋势图、5h/7d 额度窗口刷新、平台每日签到、清空统计与重置卡 | 原生页 (SwiftUI) | `UsageView.swift / UsageTools.swift` |
| 368 | `usage.go:340` | `POST /api/usage/minimax-checkin` | 用量与额度：今日/7d/30d/all 汇总与交互趋势图、5h/7d 额度窗口刷新、平台每日签到、清空统计与重置卡 | 原生页 (SwiftUI) | `UsageView.swift / UsageTools.swift` |
| 369 | `usage.go:350` | `POST /api/usage/qoder-checkin` | 用量与额度：今日/7d/30d/all 汇总与交互趋势图、5h/7d 额度窗口刷新、平台每日签到、清空统计与重置卡 | 原生页 (SwiftUI) | `UsageView.swift / UsageTools.swift` |
| 370 | `usage.go:360` | `POST /api/usage/plugin-checkin` | 用量与额度：今日/7d/30d/all 汇总与交互趋势图、5h/7d 额度窗口刷新、平台每日签到、清空统计与重置卡 | 原生页 (SwiftUI) | `UsageView.swift / UsageTools.swift` |
| 371 | `usage.go:377` | `POST /api/usage/checkin-account` | 用量与额度：今日/7d/30d/all 汇总与交互趋势图、5h/7d 额度窗口刷新、平台每日签到、清空统计与重置卡 | 原生页 (SwiftUI) | `UsageView.swift / UsageTools.swift` |
| 372 | `usage.go:395` | `GET /api/usage/checkins/off` | 用量与额度：今日/7d/30d/all 汇总与交互趋势图、5h/7d 额度窗口刷新、平台每日签到、清空统计与重置卡 | 原生页 (SwiftUI) | `UsageView.swift / UsageTools.swift` |
| 373 | `usage.go:404` | `GET /api/usage/quotas/history` | 用量明细 CSV 导出、热力图与历史额度曲线 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift` |
| 374 | `usage.go:414` | `GET /api/usage/quotas/history/holds` | 用量明细 CSV 导出、热力图与历史额度曲线 | 内嵌原版控制台 (WKWebView) | `RemoteConsoleView.swift` |
| 375 | `usage.go:431` | `POST /api/usage/codex-reset` | 用量与额度：今日/7d/30d/all 汇总与交互趋势图、5h/7d 额度窗口刷新、平台每日签到、清空统计与重置卡 | 原生页 (SwiftUI) | `UsageView.swift / UsageTools.swift` |
| 376 | `whatsnew.go:431` | `GET /api/whatsnew` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 377 | `whatsnew.go:447` | `POST /api/whatsnew/seen` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
| 378 | `whatsnew.go:452` | `POST /api/whatsnew/today` | 辅助状态查询或桌面宿主专用接口 | 内嵌原版控制台 / 无需单独页面 | `RemoteConsoleView.swift` |
