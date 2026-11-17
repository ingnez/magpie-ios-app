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

    static func resolve(
        agent: String,
        plugins: [RemotePluginSub],
        onPlugins: [String]
    ) -> SubscriptionPlatform {
        let builtin = builtinPlatforms.first(where: { $0.agent == agent })
        let plugin = plugins.first(where: { $0.id == agent || $0.pid == agent })
        let moved = onPlugins.contains(agent)

        if let b = builtin, let pl = plugin, moved {
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
                movedToPlugin: true
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
        onPlugins: [String]
    ) -> (builtins: [SubscriptionPlatform], extraPlugins: [SubscriptionPlatform]) {
        let builtins = builtinPlatforms.map { resolve(agent: $0.agent, plugins: plugins, onPlugins: onPlugins) }
        let builtinIDs = Set(builtinPlatforms.map(\.agent))
        let extras = plugins
            .filter { pl in !builtinIDs.contains(pl.id) && !(onPlugins.contains(pl.id)) }
            .map { pl in resolve(agent: pl.id, plugins: plugins, onPlugins: onPlugins) }
        return (builtins, extras)
    }
}
