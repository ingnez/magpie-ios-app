# Magpie 原版网页端 (`yetone/magpie` / `usemagpie.ai`) vs 当前 iOS 版 (`magpie-ios-app`) 功能差距核对表

- **核对基准源码**：`https://github.com/yetone/magpie`（克隆路径：`/tmp/yetone-magpie`，Web UI 位于 `internal/gui/` 与 `plugins/`）及官方文档 `https://usemagpie.ai/docs/zh/start`
- **当前 iOS 源码**：`/home/rakazo/bots/cmwgouca0nk6rwbhk1swaxbi4/magpie-ios-app/Magpie/`（共 12 个 Swift 文件，3,668 行）

---

## 一、 原版 Magpie 网页端（`magpie web` / 桌面 GUI）真实架构与 11 大模块

原版 Magpie 远不止一个“单 URL 转发壳”，它由 **本机/服务端多协议网关（默认端口 `3425`）** 与 **完整 Web 管理控制台（默认端口 `3430`，带 `?k=` 密钥鉴权，接口位于 `internal/gui/api.go`）** 组成，包含 11 个一级页面：

1. **Providers（供应商与多账号/多 Key 号池）**：20+ 厂商预设、OAuth 订阅号池（Claude/ChatGPT/Copilot/Gemini/Antigravity 等）、自定义 OpenAI+Anthropic 双地址接入、单供应商多账号/多 Key 8 种轮询策略（`smart`/`order`/`drain`/`rotate`/`usage`/`pace`/`weight`/`fast`）、5 种会话粘性（`auto`/`session`/`turn`/`off`/`strict`）、429/余额耗尽自动退避休息（Cooldown）与备用模型故障转移。
2. **Routing Groups（跨供应商路由组与意图路由）**：同名模型自动成组（`auto/<model>`）、手动建组（`group/<id>`）、8 层嵌套路由组、9 种组路由策略（含按峰谷电价计算的 `cheap` 最便宜优先）、模型 ID 别名重映射、按 Token 长度/图片/推理强度/时段星期/意图分类模型（Intent Classifier）动态分流规则。
3. **Agents & Profiles（智能体与方案切换）**：管理客户端接入、推理强度（Effort）滑块、快速模式（`service_tier: priority` / `speed: fast`）、Claude 三档位（Opus/Sonnet/Haiku）独立映射、Profiles 方案一键保存与切换。
4. **Routing（实时路由追踪日志）**：实时展示每次请求命中了哪条规则、分配给哪个供应商与具体账号/Key、故障转移重试链路、首字耗时（TTFT）、流式吐字速度（tok/s）、按用途（对话/压缩/标题/子代理）过滤。
5. **Usage & Context（用量账单、套餐额度窗口与上下文透视）**：各订阅账号 5h/7d 额度窗口剩余百分比与重置倒计时（支持自动重置与定时 Warm-up 热身、平台每日签到）、按今天/7天/30天统计 Token/缓存命中/美元人民币花费、单次请求 Context 窗口占比拆解（系统提示词/MCP 工具/文件/历史对话）。
6. **Masking（隐私脱敏规则与左右对照观测）**：确定性规则（API Key/私钥/Token/邮箱/校验位银行卡与身份证/护照/IP 等）+ 自定义词表/正则 + 白名单（Never mask）+ 命中动作（脱敏/提醒/拦截）+ `{{TYPE_hash}}` 一致性占位符（支持流式与 Tool Call 参数实时还原）+ 在线「试一试」沙盒 + 左右对照观测记录。
7. **Gateway & Caller Keys（网关协议、局域网共享与下游 Key 限额）**：OpenAI Chat / Responses / Anthropic Messages / Gemini / Ollama 全协议**流式（SSE）+ 工具调用（Tool Calls）+ 思考块（Reasoning）**双向互转；支持签发多个下游 Caller Keys 并按日/周/月设置 Token 与金额预算上限。
8. **Network & Proxies（网络与命名代理池）**：管理多个 HTTP/HTTPS/SOCKS5 命名代理（保存、测速 `POST /api/proxies/test`），按上游/插件/更新分流代理；配置 IP 白名单、CORS、HTTPS/mTLS、以及连接**远程 Magpie（Remote Magpie）**。
9. **Alerts & Bark（告警与 iOS Bark 推送）**：额度不足告警、低余额告警、重置提醒、任务完成提醒，原生集成 **iOS Bark 推送（`/api/settings/bark`）** 与每日汇总。
10. **Sync & Backup（备份与多端云同步）**：加密备份导入导出，支持 **WebDAV（坚果云/Nextcloud）、S3、GitHub** 跨设备同步供应商、Key 与路由配置。
11. **Plugins & Middleware（插件与网关中间件）**：内置 New API 风格网关中间件（`param-override` 参数覆写、`model-map` 模型映射、`system-prompt` 注入、`word-guard` 敏感词过滤、`think-tags` 思考标签提取/剥离）及联网搜索（Tavily/Brave/Exa 等多 Key 轮询）。

---

## 二、 逐项核对：原版 Magpie Web vs 当前 iOS 版差距表

| 功能模块 | 原版 Magpie 网页端 (`yetone/magpie`) | 当前 iOS 版 (`magpie-ios-app`) | 差距判定 | 具体缺失内容 |
| :--- | :--- | :--- | :--- | :--- |
| **1. 远程 Magpie 网页/服务端对接** | 支持直连远程 `magpie web`（`3430` 端口 `?k=` 鉴权）及调用 `/api/state`、`/api/providers`、`/api/groups` 等 100+ 管理 API | **完全未对接**（仅把填入的 URL 当作普通 OpenAI/Claude 上游发推理请求） | **严重缺失** | 填入部署在服务器/NAS 上的 Magpie 地址后，无法读取或管理远端 Magpie 的供应商、路由组、额度、日志，也无法直接渲染远端 `magpie web` 控制台 |
| **2. 号池管理与多 Key 轮询** | 单供应商支持挂多个 API Key 与多个订阅账号；内置 `smart`/`order`/`drain`/`rotate`/`usage`/`pace`/`weight`/`fast` 8 种轮询策略 + 5 种会话保持 + 429/报错自动退避切号 | 仅支持 `1 个 Profile = 1 个 URL + 1 个 API Key`，无多 Key 池，无自动切号 | **严重缺失** | 缺单供应商多 Key/多账号池、缺 8 种轮询调度算法、缺会话粘性保持、缺 429/5xx 自动故障转移（Failover）与冷却恢复（Cooldown） |
| **3. 厂商预设与订阅额度监控** | 内置 20+ 厂商预设（DeepSeek/Kimi/GLM/OpenRouter 等）；实时监控各账号余额、5h/7d 额度窗口、重置倒计时、每日签到与定时 Warm-up | 仅 4 个手写模板按钮，无余额/额度窗口查询，无签到与热身 | **严重缺失** | 缺 20+ 预设厂商库、缺账号余额/套餐额度窗口（Allowances）看板、缺重置倒计时与自动签到/Warm-up |
| **4. 路由组与模型切换 (`group/<id>`)** | 支持 `auto/<model>` 自动成组、手动跨供应商建组 `group/<id>`、模型 ID 别名重映射、推理强度（Effort）与快速模式（Priority）、按 Token/图片/时段/意图规则分流 | 仅能拉取单个上游的 `/v1/models` 列表并选 1 个默认模型名 | **严重缺失** | 缺跨供应商路由组（`group/<id>`）、缺模型 ID 映射（`model-map`）、缺按条件/时段/长度/意图路由规则、缺推理强度与快速模式开关 |
| **5. 网关核心转发能力（流式 / 工具 / 中间件）** | 支持 OpenAI Chat/Responses、Anthropic、Gemini、Ollama 全协议 **SSE 流式输出**、**Tool Calls**、**Reasoning 思考块**互转；支持 `param-override`/`system-prompt`/`think-tags` 中间件 | 仅支持**非流式（一次性 JSON）**纯文本互转；不支持 SSE 流式，不支持 Tool Calls，无中间件 | **核心缺陷** | 酒馆（SillyTavern）或编程客户端开流式（`stream: true`）或带工具/思考块时会退化或丢失；缺 `param-override`、`system-prompt`、`think-tags` 中间件 |
| **6. 请求日志、路由追踪与用量统计** | **Routing 页**展示每次请求命中的规则、具体回答的账号/Key、重试链路、TTFT 首字延迟、tok/s 速度；**Usage 页**统计 Token、缓存命中、花费与 Context 窗口占比 | 仅记录简单内存日志（时间、路径、状态码、总耗时、160字预览），重启即丢，无 Token/费用统计 | **差距较大** | 缺路由决策溯源、缺 TTFT 与流式 tok/s 测速、缺 Token 与美元/人民币账单统计、缺 Context 上下文窗口构成分析、缺日志持久化与导出 |
| **7. 隐私脱敏规则与对照观测** | 机密/PII 细分类型开关（含银行卡 Luhn 校验、身份证校验位、私钥、护照、IP 等）+ 自定义词/正则 + 白名单（Never mask）+ 动作（脱敏/提醒/拦截）+ `{{TYPE_hash}}` 一致性流式还原 + **可编辑「试一试」预览沙盒** + **左右对照观测页** | 仅 3 类固定正则开关（`maskAPIKeys` API Key / `maskEmails` 邮箱 / `maskPhones` 手机号）+ 逗号分隔自定义敏感词（`customKeywordsText`）+ 基于固定示例文本（`sampleInput`）的只读脱敏预览 | **差距较大** | 缺银行卡/身份证/私钥/IP 等确定性规则、缺自定义正则表达式、缺白名单（Never mask）、缺「脱敏/仅提醒/拦截」动作策略、缺用户可自行输入测试文本的交互式「试一试」沙盒、缺真实请求脱敏前后左右对照详情页 |
| **8. 代理配置、局域网共享、Bark 推送与同步** | 支持 HTTP/HTTPS/SOCKS5 命名代理池与测速；支持局域网共享与 Caller Keys 预算限额；原生支持 **iOS Bark 推送**；支持 **WebDAV/S3/备份文件** 同步 | 本地网关写死绑定 `127.0.0.1:3425`；无上游代理配置；无 Caller Keys；无 Bark 推送；无备份同步 | **完全缺失** | 缺上游 HTTP/SOCKS5 代理配置与测速、缺局域网 `0.0.0.0` 共享与下游 Key 限额、缺 iOS Bark 推送通知、缺配置导入导出与 WebDAV 同步 |
