import Foundation

struct SubscriptionSiteOption: Identifiable, Equatable {
    let id: String
    let label: String
    let host: String
    let pluginWord: String?
}

struct SubscriptionPlatform: Identifiable, Equatable {
    var id: String { agent }
    let agent: String
    let pid: String
    let name: String
    let subtitle: String
    let plans: String
    let keywords: String
    let risk: Bool
    let riskNote: String?
    let hint: String?
    let single: Bool
    let importable: Bool
    let importTitle: String?
    let importIntro: String?
    let supportsClaudeToken: Bool
    let supportsCodexDevice: Bool
    let supportsCopilotGHE: Bool
    let supportsExport: Bool
    let sites: [SubscriptionSiteOption]
    let plugin: RemotePluginSub?
    let movedToPlugin: Bool
    let pluginSpec: String?

    init(
        agent: String,
        pid: String,
        name: String,
        subtitle: String,
        plans: String,
        keywords: String,
        risk: Bool,
        riskNote: String?,
        hint: String?,
        single: Bool,
        importable: Bool,
        importTitle: String?,
        importIntro: String?,
        supportsClaudeToken: Bool,
        supportsCodexDevice: Bool,
        supportsCopilotGHE: Bool,
        supportsExport: Bool,
        sites: [SubscriptionSiteOption],
        plugin: RemotePluginSub?,
        movedToPlugin: Bool,
        pluginSpec: String? = nil
    ) {
        self.agent = agent
        self.pid = pid
        self.name = name
        self.subtitle = subtitle
        self.plans = plans
        self.keywords = keywords
        self.risk = risk
        self.riskNote = riskNote
        self.hint = hint
        self.single = single
        self.importable = importable
        self.importTitle = importTitle
        self.importIntro = importIntro
        self.supportsClaudeToken = supportsClaudeToken
        self.supportsCodexDevice = supportsCodexDevice
        self.supportsCopilotGHE = supportsCopilotGHE
        self.supportsExport = supportsExport
        self.sites = sites
        self.plugin = plugin
        self.movedToPlugin = movedToPlugin
        self.pluginSpec = pluginSpec
    }

    var isPluginBacked: Bool { plugin != nil }
}

enum SubscriptionCatalog {
    static let builtinPlatforms: [SubscriptionPlatform] = [
        SubscriptionPlatform(
            agent: "antigravity",
            pid: "antigravity",
            name: "Antigravity (谷歌反重力)",
            subtitle: "Google AI Pro / Ultra · Google OAuth",
            plans: "Google AI Pro · Ultra · free",
            keywords: "antigravity google 反重力 谷歌 gemini agy",
            risk: true,
            riskNote: "Google 可能封禁在 Antigravity 官方应用之外使用的账号，请使用可承受风险的账号。",
            hint: nil,
            single: false,
            importable: true,
            importTitle: "导入 Antigravity 账号",
            importIntro: "粘贴或导入 Antigravity Cockpit、Antigravity Manager 或 CLIProxyAPI 导出的 JSON / Refresh Token。",
            supportsClaudeToken: false,
            supportsCodexDevice: false,
            supportsCopilotGHE: false,
            supportsExport: false,
            sites: [],
            plugin: nil,
            movedToPlugin: false
        ),
        SubscriptionPlatform(
            agent: "codex",
            pid: "codex",
            name: "ChatGPT (Codex)",
            subtitle: "OpenAI OAuth / 设备码 · 多账号轮换",
            plans: "Plus · Pro · Business",
            keywords: "codex chatgpt openai gpt plus pro",
            risk: false,
            riskNote: nil,
            hint: nil,
            single: false,
            importable: true,
            importTitle: "导入 ChatGPT / Codex 账号",
            importIntro: "粘贴或选择 Codex auth.json、codexbar config.json，或 Cockpit Tools / CLIProxyAPI / Sub2API 导出内容。",
            supportsClaudeToken: false,
            supportsCodexDevice: true,
            supportsCopilotGHE: false,
            supportsExport: true,
            sites: [],
            plugin: nil,
            movedToPlugin: false
        ),
        SubscriptionPlatform(
            agent: "claude",
            pid: "claude",
            name: "Claude",
            subtitle: "Claude Code OAuth / Setup-Token · 多账号",
            plans: "Pro · Max · Team",
            keywords: "claude anthropic sonnet opus setup-token",
            risk: true,
            riskNote: "Anthropic 可能封禁在官方应用之外使用的 Claude 订阅账号，请自行评估风控风险。",
            hint: nil,
            single: false,
            importable: true,
            importTitle: "导入 Claude 账号",
            importIntro: "粘贴或选择 CLIProxyAPI 授权文件、Claude Code .credentials.json、claude-swap 导出内容或 setup-token。",
            supportsClaudeToken: true,
            supportsCodexDevice: false,
            supportsCopilotGHE: false,
            supportsExport: true,
            sites: [],
            plugin: nil,
            movedToPlugin: false
        ),
        SubscriptionPlatform(
            agent: "gemini",
            pid: "gemini",
            name: "Gemini CLI",
            subtitle: "Google Code Assist · Google OAuth",
            plans: "Code Assist Standard · Enterprise",
            keywords: "gemini google cli code assist",
            risk: false,
            riskNote: nil,
            hint: nil,
            single: false,
            importable: false,
            importTitle: nil,
            importIntro: nil,
            supportsClaudeToken: false,
            supportsCodexDevice: false,
            supportsCopilotGHE: false,
            supportsExport: false,
            sites: [],
            plugin: nil,
            movedToPlugin: false
        ),
        SubscriptionPlatform(
            agent: "chatgpt-api",
            pid: "chatgpt-api",
            name: "ChatGPT API",
            subtitle: "Sign in with ChatGPT · 直连 OpenAI API",
            plans: "Plus · Pro · Business",
            keywords: "chatgpt api openai sign in with chatgpt",
            risk: false,
            riskNote: nil,
            hint: "通过 OpenAI 官方 Sign in with ChatGPT 授权，直接以你配置的 Agent 指令请求 api.openai.com。",
            single: false,
            importable: false,
            importTitle: nil,
            importIntro: nil,
            supportsClaudeToken: false,
            supportsCodexDevice: false,
            supportsCopilotGHE: false,
            supportsExport: false,
            sites: [],
            plugin: nil,
            movedToPlugin: false
        ),
        SubscriptionPlatform(
            agent: "copilot",
            pid: "copilot",
            name: "GitHub Copilot",
            subtitle: "GitHub 设备码登录 · 支持 GHE.com 企业版",
            plans: "Free · Education · Pro · Pro+ · Max · Business · Enterprise",
            keywords: "copilot github ghe enterprise 设备码",
            risk: false,
            riskNote: nil,
            hint: nil,
            single: false,
            importable: false,
            importTitle: nil,
            importIntro: nil,
            supportsClaudeToken: false,
            supportsCodexDevice: false,
            supportsCopilotGHE: true,
            supportsExport: false,
            sites: [],
            plugin: nil,
            movedToPlugin: false
        ),
        SubscriptionPlatform(
            agent: "cursor",
            pid: "cursor",
            name: "Cursor",
            subtitle: "Cursor 订阅 OAuth",
            plans: "Pro · Ultra · Teams",
            keywords: "cursor pro ultra",
            risk: false,
            riskNote: nil,
            hint: nil,
            single: true,
            importable: false,
            importTitle: nil,
            importIntro: nil,
            supportsClaudeToken: false,
            supportsCodexDevice: false,
            supportsCopilotGHE: false,
            supportsExport: false,
            sites: [],
            plugin: nil,
            movedToPlugin: false
        ),
        SubscriptionPlatform(
            agent: "grok",
            pid: "grok",
            name: "Grok",
            subtitle: "xAI / Grok Build OAuth",
            plans: "SuperGrok · X Premium+",
            keywords: "grok xai twitter",
            risk: false,
            riskNote: nil,
            hint: nil,
            single: false,
            importable: false,
            importTitle: nil,
            importIntro: nil,
            supportsClaudeToken: false,
            supportsCodexDevice: false,
            supportsCopilotGHE: false,
            supportsExport: false,
            sites: [],
            plugin: nil,
            movedToPlugin: false
        ),
        SubscriptionPlatform(
            agent: "zcode",
            pid: "zcode",
            name: "ZCode (GLM Coding Plan)",
            subtitle: "Z.ai 国际站 / BigModel 智谱国内站",
            plans: "Lite · Pro · Max · Team",
            keywords: "zcode glm zhipu 智谱 bigmodel z.ai",
            risk: false,
            riskNote: nil,
            hint: nil,
            single: false,
            importable: false,
            importTitle: nil,
            importIntro: nil,
            supportsClaudeToken: false,
            supportsCodexDevice: false,
            supportsCopilotGHE: false,
            supportsExport: false,
            sites: [
                SubscriptionSiteOption(id: "zai", label: "Z.ai (国际站)", host: "z.ai", pluginWord: "Z.ai"),
                SubscriptionSiteOption(id: "bigmodel", label: "BigModel (智谱国内站)", host: "bigmodel.cn", pluginWord: "BigModel (智谱)")
            ],
            plugin: nil,
            movedToPlugin: false
        ),
        SubscriptionPlatform(
            agent: "kiro",
            pid: "kiro",
            name: "Kiro",
            subtitle: "AWS / Kiro OAuth",
            plans: "Free · Pro · Pro+ · Power",
            keywords: "kiro aws",
            risk: false,
            riskNote: nil,
            hint: nil,
            single: false,
            importable: false,
            importTitle: nil,
            importIntro: nil,
            supportsClaudeToken: false,
            supportsCodexDevice: false,
            supportsCopilotGHE: false,
            supportsExport: false,
            sites: [],
            plugin: nil,
            movedToPlugin: false
        ),
        SubscriptionPlatform(
            agent: "workbuddy",
            pid: "workbuddy",
            name: "WorkBuddy (CodeBuddy 国内版)",
            subtitle: "腾讯 CodeBuddy 国内版 · 每日签到/积分",
            plans: "Free · Pro",
            keywords: "workbuddy codebuddy 腾讯 国内",
            risk: true,
            riskNote: "腾讯可能对在官方 WorkBuddy 客户端外使用的账号进行风控封禁，请勿使用主力重要账号。",
            hint: nil,
            single: false,
            importable: false,
            importTitle: nil,
            importIntro: nil,
            supportsClaudeToken: false,
            supportsCodexDevice: false,
            supportsCopilotGHE: false,
            supportsExport: false,
            sites: [],
            plugin: nil,
            movedToPlugin: false
        ),
        SubscriptionPlatform(
            agent: "workbuddy-ai",
            pid: "workbuddy-ai",
            name: "WorkBuddy AI (国际版)",
            subtitle: "WorkBuddy 国际站 OAuth",
            plans: "Free · Pro",
            keywords: "workbuddy ai international 国际",
            risk: true,
            riskNote: "WorkBuddy AI 国际版对第三方客户端调用有严格风控，存在封号可能，请使用可承受风险的账号。",
            hint: nil,
            single: false,
            importable: false,
            importTitle: nil,
            importIntro: nil,
            supportsClaudeToken: false,
            supportsCodexDevice: false,
            supportsCopilotGHE: false,
            supportsExport: false,
            sites: [],
            plugin: nil,
            movedToPlugin: false
        ),
        SubscriptionPlatform(
            agent: "commandcode-plan",
            pid: "commandcode-plan",
            name: "Command Code",
            subtitle: "OAuth 授权 / Key 回退",
            plans: "Go · Pro · GOAT · Max · Ultra",
            keywords: "commandcode command code",
            risk: true,
            riskNote: "Go 套餐通过私有接口调用，可能被判定违反服务条款而封号；Pro/Max 等走官方 Provider API。",
            hint: nil,
            single: false,
            importable: false,
            importTitle: nil,
            importIntro: nil,
            supportsClaudeToken: false,
            supportsCodexDevice: false,
            supportsCopilotGHE: false,
            supportsExport: false,
            sites: [],
            plugin: nil,
            movedToPlugin: false
        ),
        SubscriptionPlatform(
            agent: "qoder",
            pid: "qoder",
            name: "Qoder (国际版)",
            subtitle: "qoder.com 账号授权",
            plans: "Pro",
            keywords: "qoder international 国际",
            risk: true,
            riskNote: "Qoder 无公开第三方接口，Magpie 以桌面客户端签名方式请求，存在第三方使用风控风险。",
            hint: "适用于 qoder.com 国际站账号。",
            single: false,
            importable: false,
            importTitle: nil,
            importIntro: nil,
            supportsClaudeToken: false,
            supportsCodexDevice: false,
            supportsCopilotGHE: false,
            supportsExport: false,
            sites: [],
            plugin: nil,
            movedToPlugin: false
        ),
        SubscriptionPlatform(
            agent: "qoder-cn",
            pid: "qoder-cn",
            name: "Qoder CN (国内版)",
            subtitle: "qoder.cn 阿里云 / 手机号登录",
            plans: "Pro",
            keywords: "qoder cn 国内 阿里云",
            risk: true,
            riskNote: "Qoder 无公开第三方接口，Magpie 以桌面客户端签名方式请求，存在第三方使用风控风险。",
            hint: "适用于 qoder.cn 国内站账号（支持阿里云账号或手机号登录）。",
            single: false,
            importable: false,
            importTitle: nil,
            importIntro: nil,
            supportsClaudeToken: false,
            supportsCodexDevice: false,
            supportsCopilotGHE: false,
            supportsExport: false,
            sites: [],
            plugin: nil,
            movedToPlugin: false
        ),
        SubscriptionPlatform(
            agent: "devin",
            pid: "devin",
            name: "Devin",
            subtitle: "Cognition Devin OAuth",
            plans: "Pro · Enterprise",
            keywords: "devin cognition",
            risk: false,
            riskNote: nil,
            hint: nil,
            single: false,
            importable: false,
            importTitle: nil,
            importIntro: nil,
            supportsClaudeToken: false,
            supportsCodexDevice: false,
            supportsCopilotGHE: false,
            supportsExport: false,
            sites: [],
            plugin: nil,
            movedToPlugin: false
        ),
        SubscriptionPlatform(
            agent: "zed",
            pid: "zed",
            name: "Zed",
            subtitle: "Zed Pro / Student / Business",
            plans: "Pro · Student · Business",
            keywords: "zed editor",
            risk: true,
            riskNote: "Zed 订阅仅面向其官方编辑器，第三方调用存在账号风控风险。",
            hint: nil,
            single: false,
            importable: false,
            importTitle: nil,
            importIntro: nil,
            supportsClaudeToken: false,
            supportsCodexDevice: false,
            supportsCopilotGHE: false,
            supportsExport: false,
            sites: [],
            plugin: nil,
            movedToPlugin: false
        ),
        SubscriptionPlatform(
            agent: "factory",
            pid: "factory",
            name: "Factory",
            subtitle: "OAuth 授权 / fk-... API Key 批量导入",
            plans: "Pro · Plus · Max",
            keywords: "factory droid fk-",
            risk: true,
            riskNote: "Factory 订阅仅供 Droid CLI 使用，第三方代理调用可能触发封控。",
            hint: nil,
            single: false,
            importable: true,
            importTitle: "通过 Factory API Key 添加账号",
            importIntro: "每行粘贴一个 Factory API Key (fk-...，取自 app.factory.ai/settings/api-keys) 或选择文本文件，逐个校验后入池。",
            supportsClaudeToken: false,
            supportsCodexDevice: false,
            supportsCopilotGHE: false,
            supportsExport: false,
            sites: [],
            plugin: nil,
            movedToPlugin: false
        ),
        SubscriptionPlatform(
            agent: "mimo-app",
            pid: "mimo-app",
            name: "Xiaomi MiMo (小米)",
            subtitle: "小米 MiMo App 账号授权",
            plans: "Free · Starter · Plus · Pro · Ultra",
            keywords: "mimo xiaomi 小米",
            risk: true,
            riskNote: "Xiaomi MiMo 订阅面向官方应用，第三方代理调用可能触发风控。",
            hint: nil,
            single: false,
            importable: false,
            importTitle: nil,
            importIntro: nil,
            supportsClaudeToken: false,
            supportsCodexDevice: false,
            supportsCopilotGHE: false,
            supportsExport: false,
            sites: [],
            plugin: nil,
            movedToPlugin: false
        )
    ]

    /// Built-ins whose upstream Magpie backend has migrated execution to community plugins when present.
    static let pluginServedBuiltins: Set<String> = [
        "antigravity", "cursor", "grok", "zcode", "kiro",
        "workbuddy", "workbuddy-ai", "commandcode-plan",
        "qoder", "qoder-cn", "devin", "zed", "factory", "mimo-app"
    ]

    static func isPriorityRouting(_ routing: String) -> Bool {
        let r = routing.lowercased()
        return r.isEmpty || r == "order" || r == "drain"
    }

    static func routingShortTag(_ routing: String) -> String {
        switch routing.lowercased() {
        case "": return "Smart 智能优先"
        case "order": return "Order 严格顺序"
        case "drain": return "Drain 用尽顺延"
        case "rotate": return "Rotate 逐轮轮询"
        case "weight": return "Weight 权重轮询"
        case "usage": return "Usage 最少已用"
        case "pace": return "Pace 速率均衡"
        case "fast": return "Fast 速度优先"
        case "free": return "Free 免费优先"
        default: return routing
        }
    }

    static let builtinCommunityListings: [RemotePluginListing] = [
        RemotePluginListing(
            package: "@magpie-community/opencode-agy-cli-auth",
            name: "Antigravity (local agy CLI)",
            icon: "antigravity-color",
            providers: ["agy-cli"],
            summary: ["zh": "通过本机 agy CLI 安全接入 Google Antigravity（替代已下架插件）。"]
        ),
        RemotePluginListing(
            package: "@magpie-community/opencode-zen-free-auth",
            name: "OpenCode Zen Free",
            icon: "opencode",
            providers: ["opencode-zen-free"],
            summary: ["zh": "使用 public 凭证接入 OpenCode Zen 免费模型，自动发现模型并支持原生流式协议。"]
        ),
        RemotePluginListing(
            package: "@magpie-community/opencode-qoder-auth",
            name: "Qoder & 千问办公 (QwenWork)",
            icon: "qoder",
            providers: ["qoder", "qoder-cn", "qwenwork", "qwenwork-enterprise"],
            replaces: "qoder",
            summary: ["zh": "接入 Qoder 国际/国内版，以及千问办公公有云与企业旗舰版。"]
        )
    ]

    static func routingCategorySummary(_ routing: String) -> String {
        switch routing.lowercased() {
        case "order":
            return "优先级模式 · 严格按 #1→#2→#3 顺序，耗尽或冷却才顺延"
        case "drain":
            return "优先级模式 · 单号用尽再顺延下一顺位，不主动回切"
        case "rotate":
            return "轮询模式 · 每轮用户消息在已启用账号间轮流分发"
        case "weight":
            return "轮询模式 · 按账号权重比例平滑分流"
        case "usage":
            return "均衡模式 · 优先分配当前已用量比例最低的账号"
        case "pace":
            return "均衡模式 · 优先消耗距重置前单位时间余量最充裕的账号"
        case "fast":
            return "速度模式 · 按近期响应速度优先分配"
        case "free":
            return "免费模式 · 优先调用不消耗付费配额的免费额度"
        default:
            return "智能优先级 · 优先即将重置的可用账号，快耗尽或异常时切换"
        }
    }

    static func resolve(
        agent: String,
        plugins: [RemotePluginSub],
        onPlugins: [String],
        movable: [String] = []
    ) -> SubscriptionPlatform {
        let builtin = builtinPlatforms.first(where: { $0.agent == agent })
        let plugin = plugins.first(where: { $0.id == agent || $0.pid == agent })
        let moved = onPlugins.contains(agent)
        let shouldUsePlugin = moved || movable.contains(agent) || pluginServedBuiltins.contains(agent)

        if let b = builtin, let pl = plugin, shouldUsePlugin {
            return SubscriptionPlatform(
                agent: b.agent,
                pid: pl.pid,
                name: b.name,
                subtitle: "\(b.subtitle) · 插件通道",
                plans: b.plans,
                keywords: "\(b.keywords) \(pl.name) \(pl.spec)",
                risk: b.risk,
                riskNote: b.riskNote,
                hint: b.hint,
                single: pl.single || b.single,
                importable: b.importable || pl.importable,
                importTitle: b.importTitle,
                importIntro: b.importIntro ?? pl.importFroms["zh"] ?? pl.importFrom,
                supportsClaudeToken: b.supportsClaudeToken,
                supportsCodexDevice: b.supportsCodexDevice,
                supportsCopilotGHE: b.supportsCopilotGHE,
                supportsExport: b.supportsExport,
                sites: b.sites,
                plugin: pl,
                movedToPlugin: moved,
                pluginSpec: pl.spec.isEmpty ? nil : pl.spec
            )
        }
        if let b = builtin {
            return b
        }
        if let pl = plugin {
            return SubscriptionPlatform(
                agent: pl.id,
                pid: pl.pid,
                name: pl.name,
                subtitle: "插件订阅 · \(pl.spec)",
                plans: pl.spec.isEmpty ? "Plugin" : pl.spec,
                keywords: "\(pl.id) \(pl.pid) \(pl.name) \(pl.spec) plugin",
                risk: false,
                riskNote: nil,
                hint: nil,
                single: pl.single,
                importable: pl.importable,
                importTitle: "导入 \(pl.name) 账号",
                importIntro: pl.importFroms["zh"] ?? pl.importFroms["zh-CN"] ?? pl.importFrom ?? "粘贴或选择导出文件。",
                supportsClaudeToken: false,
                supportsCodexDevice: false,
                supportsCopilotGHE: false,
                supportsExport: false,
                sites: [],
                plugin: pl,
                movedToPlugin: false
            )
        }
        return SubscriptionPlatform(
            agent: agent,
            pid: agent,
            name: agent,
            subtitle: "订阅账号",
            plans: "Subscription",
            keywords: agent,
            risk: false,
            riskNote: nil,
            hint: nil,
            single: false,
            importable: false,
            importTitle: nil,
            importIntro: nil,
            supportsClaudeToken: false,
            supportsCodexDevice: false,
            supportsCopilotGHE: false,
            supportsExport: false,
            sites: [],
            plugin: nil,
            movedToPlugin: false
        )
    }

    static func allPlatforms(
        plugins: [RemotePluginSub],
        onPlugins: [String],
        movable: [String] = []
    ) -> (builtins: [SubscriptionPlatform], extraPlugins: [SubscriptionPlatform]) {
        let builtins = builtinPlatforms.map { resolve(agent: $0.agent, plugins: plugins, onPlugins: onPlugins, movable: movable) }
        let builtinIDs = Set(builtinPlatforms.map(\.agent))
        let extras = plugins
            .filter { pl in !builtinIDs.contains(pl.id) && !builtinIDs.contains(pl.pid) && !(onPlugins.contains(pl.id)) }
            .map { pl in resolve(agent: pl.id, plugins: plugins, onPlugins: onPlugins, movable: movable) }
        return (builtins, extras)
    }

    static func communityMarketPlatforms(
        plugins: [RemotePluginSub],
        onPlugins: [String],
        listings: [RemotePluginListing]
    ) -> [SubscriptionPlatform] {
        let installedIDs = Set(plugins.flatMap { [$0.id, $0.pid] })
        let builtinIDs = Set(builtinPlatforms.map(\.agent))
        let merged = listings.isEmpty ? builtinCommunityListings : (
            listings + builtinCommunityListings.filter { def in
                !listings.contains(where: { $0.package == def.package })
            }
        )
        var seenAgents = Set<String>()
        var result: [SubscriptionPlatform] = []
        for item in merged {
            if let kind = item.kind, !kind.isEmpty { continue }
            for pid in item.providers {
                if builtinIDs.contains(pid) || installedIDs.contains(pid) || onPlugins.contains(pid) || seenAgents.contains(pid) {
                    continue
                }
                seenAgents.insert(pid)
                let title: String
                switch pid {
                case "agy-cli": title = "Antigravity (local agy CLI)"
                case "opencode-zen-free": title = "OpenCode Zen Free"
                case "qwenwork": title = "千问办公 (QwenWork 公有云)"
                case "qwenwork-enterprise": title = "千问办公企业旗舰版"
                default: title = item.providers.count > 1 ? "\(item.name) · \(pid)" : item.name
                }
                let summary = item.localizedSummary.isEmpty ? "社区插件 · 需安装 \(item.package)" : item.localizedSummary
                result.append(SubscriptionPlatform(
                    agent: pid,
                    pid: pid,
                    name: title,
                    subtitle: summary,
                    plans: item.package,
                    keywords: "\(pid) \(item.name) \(item.package) \(summary)",
                    risk: false,
                    riskNote: nil,
                    hint: summary,
                    single: false,
                    importable: false,
                    importTitle: nil,
                    importIntro: nil,
                    supportsClaudeToken: false,
                    supportsCodexDevice: false,
                    supportsCopilotGHE: false,
                    supportsExport: false,
                    sites: [],
                    plugin: nil,
                    movedToPlugin: false,
                    pluginSpec: item.package
                ))
            }
        }
        return result
    }
}
