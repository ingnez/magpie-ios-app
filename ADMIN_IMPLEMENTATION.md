# Magpie iOS 管理控制台全量还原实现说明

本项目将 `yetone/magpie` 网页端管理控制台（`internal/gui/*.go` 下全部 378 条 `HandleFunc` 路由与 `GET /`、`POST /_magpie/sign-in`）完整还原至 iOS 客户端，完整路由映射表见 [`ROUTE_INVENTORY.md`](ROUTE_INVENTORY.md)。

## 一、 原生 SwiftUI 管理工作台（可编辑 · 可保存 · 实时写回 `/api/*`）

| 模块范围 | 原生交互与写接口覆盖 | 入口 / 源码文件 |
|---|---|---|
| **总览与网关控制** | 实时路由流（`/api/gateway/trace`）、按日历史（`/api/gateway/history`）、单次载荷详情（`/api/gateway/call`）、重启网关（`POST /api/gateway/restart`）、接管网关（`POST /api/gateway/take-over`）、暂停/恢复监听（`POST /api/gateway/pause`）、解除限流冷却（`POST /api/gateway/unrest`） | 总览；`DashboardView.swift` |
| **供应商与多 Key 号池** | 官方预设添加与自定义双模式（`POST /api/provider/save`）、排序调整（`POST /api/providers/arrange`）、启停/测连/拉模型/查余额、多 Key 号池增删改/批量导入/优先使用/权重/协议/限定模型（`POST /api/keys/*`）、调度策略与粘性（`POST /api/provider/route`、`affinity`、`sink`、`usefirst`、`standin`） | 供应商 → 管理；`ProvidersView.swift`、`ProviderDetailSheet.swift` |
| **模型能力与自定义定价** | 模型勾选、别名（`POST /api/provider/name`）、推理档位（`efforts`）、图片能力（`images`）、模型自定义单价查询与保存（`GET/POST /api/model-price`，严格按 `input`/`output`/`cache_read`/`cache_write` 字段提交） | 供应商 → 定价 / 管理；`SettingsWorkspacesView.swift` (`ModelPriceEditorView`) |
| **跨供应商路由组** | 新建/编辑/复制/删除（`POST /api/groups/save`、`copy`、`delete`）、上下排序（`arrange`）、从模板创建（`template`）、导入与分享（`import`、`share`）、全局默认超时与沉底（`defaults`）、同名自动归组（`found`）、手动成员切换（`pick`）、保留高级条件 `where` | 供应商 → 路由组；`ProvidersView.swift`、`GroupEditorSheet.swift`、`CopyGroupSheet.swift` |
| **Agents 与 Profiles** | 服务器客户端扫描（`POST /api/agents/rescan`）、接入/断开/重应用/保留（`POST /api/agents/{action}/{id}`）、模型字段绑定（`POST /api/set`）、Fast/Ultrafast 开关（`POST /api/agent-fast`）、可见模型筛选（`GET/POST /api/agent-models/{id}`）、遥测开关与桌面端重启、Profiles 方案保存/应用/改名/删除（`POST /api/profile/{action}`） | 总览 → Agents 与方案；`AgentsView.swift` |
| **Caller Keys 与预算** | 下游调用密钥签发、改名、启停、轮换、删除、模型范围限制、只读权限、日/周/月 Token 与美元预算上限（`POST /api/caller-keys/{action}`，严格先设 `limit-key` 后开 `access-key`） | 隐私与设置 → Caller Keys 管理（列表行也可直接点按进入）；`CallerKeysView.swift` |
| **隐私脱敏与对照恢复** | 凭据/个人信息/保形假密钥开关（`redact`/`redactPersonal`/`redactShape`）、自定义前缀与 RE2 正则规则（`POST /api/settings/redact-rules`）、命中动作（脱敏/提醒/拦截 `POST /api/settings/redact-actions`）、敏感词与大小写/整词匹配、白名单（`POST /api/settings/redact-allow`）、在线预览（`POST /api/masking/preview`）、近 7 日记录与脱敏前后原文显式对照（`GET /api/masking/sent`、`POST /api/masking/values`） | 隐私与设置；`LogsPrivacyView.swift`、`MaskingEditors.swift` |
| **代理池与网络配置** | 上游请求代理（`proxy`）、插件下载代理（`pluginProxy`）、应用更新代理（`updateProxy`）分流保存；命名代理池增删改与测速（`POST /api/proxies/save`、`delete`、`test`）；网关端口修改（`POST /api/settings/port`）、无前缀裸模型 ID（`POST /api/settings/bare-ids`）、局域网共享（`POST /api/settings/lan`）、IP 白名单（`allowips`）、CORS 域名（`cors`）、GitHub Token（`github-token`）、Bark 推送与测试（`POST /api/settings/bark`、`/api/bark/test`） | 隐私与设置 → 代理池与网络配置；`SettingsWorkspacesView.swift` (`ProxiesManagerView`) |
| **备份与 WebDAV/S3/GitHub 云同步** | 跨端云同步配置保存与立即同步（`GET /api/davsync`、`POST /api/davsync/save`、`now`、`auto`、`follow-server`、`restore`、`upload`、`off`）；服务端定时自动备份策略、立即备份与历史恢复（`GET /api/autobackup`、`POST /api/autobackup/set`、`now`、`restore`）；加密备份导出与 Base64 导入恢复（`POST /api/backup/export`、`import`） | 隐私与设置 → 备份与云同步管理；`SettingsWorkspacesView.swift` (`BackupSyncView`) |
| **上下文与缓存调优** | 会话回放压缩阈值与缓存 TTL 智能建议查询、一键应用、接管与撤销还原（`GET /api/tune`、`POST /api/tune/apply`、`takeover`、`undo`）；Claude Code 主对话/子代理缓存 TTL（`POST /api/settings/claude-cache`）与 `Co-Authored-By` 签名开关（`claude-attribution`）；长对话自动压缩（`POST /api/settings/full-context`）、全局最大上下文限制（`context-cap`、`context-cap-mode`）、Codex 后台异步压缩（`codex-async-compact`） | 隐私与设置 / 用量 → 上下文与缓存调优；`SettingsWorkspacesView.swift` (`ContextTuneView`) |
| **系统通用、告警、搜索与隐私模型** | 主题外观、语言、账单/汇总币种、每日起点、中文万/亿单位、Web 网关模式（`POST /api/settings/gateway-mode`）、简洁模型名（`plain-names`）；剩余/已用额度切换（`quota-left`）、读取时机（`quota-reads`）、额度/低余额/重置/任务完成/脱敏告警阈值；高负载模型后置（`busy-load`）、禁用模型（`disabled-models`）、联网搜索兜底与搜索服务商 Key 配置（`search-all`、`search-count`、`search-api`）、Codex 服务档位与多代理协议；隐私转交模型（`redact-route`）、本地 AI 隐私识别模型（`GET/POST /api/privacy-model`）、全局遥测关闭（`agent-telemetry`）、请求归档开关（`POST /api/settings/archive`）、更新通道与 GitHub 镜像（`update-mirror`） | 隐私与设置 → 系统通用与告警设置；`SettingsWorkspacesView.swift` (`SystemSettingsEditorView`) |
| **用量趋势与签到热身** | `today`/`7d`/`30d`/`all` 周期切换、请求/Token/费用交互柱状图、5h/7d 订阅额度窗口刷新、清空当前统计视图（`POST /api/usage/clear`）、WorkBuddy/Trae/MiniMax/Qoder/插件每日签到与自动签到、Claude/Codex 账号热身（`POST /api/warm-all`） | 用量；`UsageView.swift`、`UsageTools.swift` |

## 二、 App 内嵌原版 Web 控制台（`RemoteConsoleView.swift`）

针对跨客户端会话全文检索（`Sessions`）、MCP Servers/Skills/Memory 资源库（`Library`）、插件市场与动态 Schema 页面（`Plugins`），以及需要查看服务器原版 Web 界面的场景，提供 `RemoteConsoleView`（基于独立非持久化 `WKWebView` 自动注入 `magpie_web_<port>` HttpOnly 会话 Cookie，URL 不拼接密钥 `k`）。
