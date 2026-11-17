import Foundation

// MARK: - /api/state, /api/agents/*, /api/profile/* & /api/settings

struct RemoteStateResponse: Decodable {
    let agents: [RemoteAgent]
    let clients: [RemoteClient]
    let profiles: [RemoteProfile]
    let served: Int
    let notice: String?
    let settings: RemoteSettingsState
    let fx: RemoteFXRate?
    let gatewayOther: RemoteGatewaySkew?
    let gatewayHeld: RemotePortHeld?

    enum CodingKeys: String, CodingKey {
        case agents, clients, profiles, served, notice, settings, fx
        case gatewayOther, gatewayHeld
        case optionLists, options
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawAgents = try c.decodeIfPresent([RemoteAgent].self, forKey: .agents) ?? []
        let optionLists = try c.decodeIfPresent([[Int]].self, forKey: .optionLists) ?? []
        let sharedOptions = try c.decodeIfPresent([RemoteAgentOption].self, forKey: .options) ?? []

        // Unpack shared `optionLists` (1-based `field.list`) per `internal/gui/statewrite.go`.
        if !optionLists.isEmpty && !sharedOptions.isEmpty {
            agents = rawAgents.map { agent in
                agent.unpackingSharedOptions(optionLists: optionLists, sharedOptions: sharedOptions)
            }
        } else {
            agents = rawAgents
        }

        clients = try c.decodeIfPresent([RemoteClient].self, forKey: .clients) ?? []
        profiles = try c.decodeIfPresent([RemoteProfile].self, forKey: .profiles) ?? []
        served = try c.decodeIfPresent(Int.self, forKey: .served) ?? 0
        notice = try c.decodeIfPresent(String.self, forKey: .notice)
        settings = try c.decodeIfPresent(RemoteSettingsState.self, forKey: .settings) ?? RemoteSettingsState()
        fx = try c.decodeIfPresent(RemoteFXRate.self, forKey: .fx)
        gatewayOther = try c.decodeIfPresent(RemoteGatewaySkew.self, forKey: .gatewayOther)
        gatewayHeld = try c.decodeIfPresent(RemotePortHeld.self, forKey: .gatewayHeld)
    }
}

struct RemoteClient: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
}

struct RemoteAgentOption: Decodable, Identifiable, Equatable {
    var id: String { "\(value)|\(group ?? "")|\(label ?? "")" }
    let value: String
    let label: String?
    let note: String
    let icon: String?
    let icons: [String]
    let group: String?
    let ref: String?
    let free: Bool
    let zero: Bool
    let rate: Double?
    let rateWas: Double?
    let context: Int?
    let takes: String?
    let direct: String?
    let via: Bool
    let same: Bool
    let served: Bool
    let alias: String?
    let fastFor: String?
    let fast: Bool
    let ownFast: Bool
    let ultraOk: Bool
    let ultra: Bool

    enum CodingKeys: String, CodingKey {
        case value, label, note, icon, icons, group, ref, free, zero
        case rate, rateWas, context, takes, direct, via, same, served, alias
        case fastFor, fast, ownFast, ultraOk, ultra
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = try c.decodeIfPresent(String.self, forKey: .value) ?? ""
        label = try c.decodeIfPresent(String.self, forKey: .label)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        icons = try c.decodeIfPresent([String].self, forKey: .icons) ?? []
        group = try c.decodeIfPresent(String.self, forKey: .group)
        ref = try c.decodeIfPresent(String.self, forKey: .ref)
        free = try c.decodeIfPresent(Bool.self, forKey: .free) ?? false
        zero = try c.decodeIfPresent(Bool.self, forKey: .zero) ?? false
        rate = try c.decodeIfPresent(Double.self, forKey: .rate)
        rateWas = try c.decodeIfPresent(Double.self, forKey: .rateWas)
        context = try c.decodeIfPresent(Int.self, forKey: .context)
        takes = try c.decodeIfPresent(String.self, forKey: .takes)
        direct = try c.decodeIfPresent(String.self, forKey: .direct)
        via = try c.decodeIfPresent(Bool.self, forKey: .via) ?? false
        same = try c.decodeIfPresent(Bool.self, forKey: .same) ?? false
        served = try c.decodeIfPresent(Bool.self, forKey: .served) ?? false
        alias = try c.decodeIfPresent(String.self, forKey: .alias)
        fastFor = try c.decodeIfPresent(String.self, forKey: .fastFor)
        fast = try c.decodeIfPresent(Bool.self, forKey: .fast) ?? false
        ownFast = try c.decodeIfPresent(Bool.self, forKey: .ownFast) ?? false
        ultraOk = try c.decodeIfPresent(Bool.self, forKey: .ultraOk) ?? false
        ultra = try c.decodeIfPresent(Bool.self, forKey: .ultra) ?? false
    }

    init(
        value: String, label: String?, note: String, icon: String?, icons: [String],
        group: String?, ref: String?, free: Bool, zero: Bool, rate: Double?, rateWas: Double?,
        context: Int?, takes: String?, direct: String?, via: Bool, same: Bool, served: Bool,
        alias: String?, fastFor: String?, fast: Bool, ownFast: Bool, ultraOk: Bool, ultra: Bool
    ) {
        self.value = value
        self.label = label
        self.note = note
        self.icon = icon
        self.icons = icons
        self.group = group
        self.ref = ref
        self.free = free
        self.zero = zero
        self.rate = rate
        self.rateWas = rateWas
        self.context = context
        self.takes = takes
        self.direct = direct
        self.via = via
        self.same = same
        self.served = served
        self.alias = alias
        self.fastFor = fastFor
        self.fast = fast
        self.ownFast = ownFast
        self.ultraOk = ultraOk
        self.ultra = ultra
    }

    func resolvingFastFor(agentID: String) -> RemoteAgentOption {
        guard fastFor == "*" else { return self }
        return RemoteAgentOption(
            value: value, label: label, note: note, icon: icon, icons: icons,
            group: group, ref: ref, free: free, zero: zero, rate: rate, rateWas: rateWas,
            context: context, takes: takes, direct: direct, via: via, same: same, served: served,
            alias: alias, fastFor: agentID, fast: fast, ownFast: ownFast, ultraOk: ultraOk, ultra: ultra
        )
    }

    var displayName: String {
        if let label = label, !label.isEmpty { return label }
        return value.isEmpty ? "默认" : value
    }
}

struct RemoteAgentField: Decodable, Identifiable, Equatable {
    var id: String { key }
    let key: String
    let label: String
    let value: String
    var options: [RemoteAgentOption]
    let list: Int

    enum CodingKeys: String, CodingKey {
        case key, label, value, options, list
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decodeIfPresent(String.self, forKey: .key) ?? ""
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? key
        value = try c.decodeIfPresent(String.self, forKey: .value) ?? ""
        options = try c.decodeIfPresent([RemoteAgentOption].self, forKey: .options) ?? []
        list = try c.decodeIfPresent(Int.self, forKey: .list) ?? 0
    }
}

struct RemoteAgentModelGroupCount: Decodable, Equatable, Identifiable {
    var id: String { name }
    let name: String
    let n: Int
}

struct RemoteAgentModelCount: Decodable, Equatable {
    let shown: Int
    let listed: Int
    let by: [RemoteAgentModelGroupCount]
    let names: [String]

    enum CodingKeys: String, CodingKey {
        case shown, listed, by, names
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shown = try c.decodeIfPresent(Int.self, forKey: .shown) ?? 0
        listed = try c.decodeIfPresent(Int.self, forKey: .listed) ?? 0
        by = try c.decodeIfPresent([RemoteAgentModelGroupCount].self, forKey: .by) ?? []
        names = try c.decodeIfPresent([String].self, forKey: .names) ?? []
    }
}

struct RemoteAgentDrift: Decodable, Equatable {
    let kind: String
    let field: String
    let now: String?
    let want: String
    let detail: String
}

struct RemoteAgentAppRun: Decodable, Equatable {
    let since: String
}

struct RemoteAgentTelemetry: Decodable, Equatable {
    let off: Bool
    let file: String
    let error: String?
    let all: Bool
    let allError: String?

    enum CodingKeys: String, CodingKey {
        case off, file, error, all, allError
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        off = try c.decodeIfPresent(Bool.self, forKey: .off) ?? false
        file = try c.decodeIfPresent(String.self, forKey: .file) ?? ""
        error = try c.decodeIfPresent(String.self, forKey: .error)
        all = try c.decodeIfPresent(Bool.self, forKey: .all) ?? false
        allError = try c.decodeIfPresent(String.self, forKey: .allError)
    }
}

struct RemoteAgent: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
    let path: String
    var fields: [RemoteAgentField]
    let own: [RemoteAgentField]
    let drift: RemoteAgentDrift?
    let wired: Bool
    let models: RemoteAgentModelCount?
    let menu: Bool
    let source: String?
    let stale: Int
    let failover: Bool
    let cliMissing: Bool
    let appRestart: RemoteAgentAppRun?
    let telemetry: RemoteAgentTelemetry?
    let command: String?
    let openApp: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, icon, path, fields, own, drift, wired, models, menu
        case source, stale, failover, cliMissing, appRestart, telemetry, command, openApp
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? ""
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? ""
        fields = try c.decodeIfPresent([RemoteAgentField].self, forKey: .fields) ?? []
        own = try c.decodeIfPresent([RemoteAgentField].self, forKey: .own) ?? []
        drift = try c.decodeIfPresent(RemoteAgentDrift.self, forKey: .drift)
        wired = try c.decodeIfPresent(Bool.self, forKey: .wired) ?? false
        models = try c.decodeIfPresent(RemoteAgentModelCount.self, forKey: .models)
        menu = try c.decodeIfPresent(Bool.self, forKey: .menu) ?? false
        source = try c.decodeIfPresent(String.self, forKey: .source)
        stale = try c.decodeIfPresent(Int.self, forKey: .stale) ?? 0
        failover = try c.decodeIfPresent(Bool.self, forKey: .failover) ?? false
        cliMissing = try c.decodeIfPresent(Bool.self, forKey: .cliMissing) ?? false
        appRestart = try c.decodeIfPresent(RemoteAgentAppRun.self, forKey: .appRestart)
        telemetry = try c.decodeIfPresent(RemoteAgentTelemetry.self, forKey: .telemetry)
        command = try c.decodeIfPresent(String.self, forKey: .command)
        openApp = try c.decodeIfPresent(Bool.self, forKey: .openApp) ?? false
    }

    func unpackingSharedOptions(optionLists: [[Int]], sharedOptions: [RemoteAgentOption]) -> RemoteAgent {
        var copy = self
        copy.fields = fields.map { field in
            guard field.list > 0, field.list <= optionLists.count else { return field }
            let indices = optionLists[field.list - 1]
            let unpacked = indices.compactMap { idx -> RemoteAgentOption? in
                guard idx >= 0, idx < sharedOptions.count else { return nil }
                return sharedOptions[idx].resolvingFastFor(agentID: id)
            }
            var f = field
            f.options = unpacked
            return f
        }
        return copy
    }

    var primaryModelSummary: String? {
        if let first = fields.first(where: { !$0.value.isEmpty }) {
            if let opt = first.options.first(where: { $0.value == first.value }) {
                return opt.displayName
            }
            return first.value
        }
        return nil
    }
}

struct RemoteAgentModelsResponse: Decodable {
    let models: [RemoteAgentModelItem]
    let ordered: Bool
    let only: Bool
    let own: [String]
    let ownHidden: Bool

    enum CodingKeys: String, CodingKey {
        case models, ordered, only, own, ownHidden
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        models = try c.decodeIfPresent([RemoteAgentModelItem].self, forKey: .models) ?? []
        ordered = try c.decodeIfPresent(Bool.self, forKey: .ordered) ?? false
        only = try c.decodeIfPresent(Bool.self, forKey: .only) ?? false
        own = try c.decodeIfPresent([String].self, forKey: .own) ?? []
        ownHidden = try c.decodeIfPresent(Bool.self, forKey: .ownHidden) ?? false
    }
}

struct RemoteAgentModelItem: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let group: String
    let context: Int?
    let hidden: Bool
    let inUse: Bool
    let own: Bool
    let kept: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, group, context, hidden, inUse, own, kept
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        group = try c.decodeIfPresent(String.self, forKey: .group) ?? ""
        context = try c.decodeIfPresent(Int.self, forKey: .context)
        hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        inUse = try c.decodeIfPresent(Bool.self, forKey: .inUse) ?? false
        own = try c.decodeIfPresent(Bool.self, forKey: .own) ?? false
        kept = try c.decodeIfPresent(Bool.self, forKey: .kept) ?? false
    }
}

struct RemoteProfile: Decodable, Identifiable, Equatable {
    var id: String { name }
    let name: String
    let summary: String
    let inUse: Bool
    let agents: [RemoteProfileGroup]

    enum CodingKeys: String, CodingKey {
        case name, summary, inUse, agents
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        inUse = try c.decodeIfPresent(Bool.self, forKey: .inUse) ?? false
        agents = try c.decodeIfPresent([RemoteProfileGroup].self, forKey: .agents) ?? []
    }
}

struct RemoteProfileGroup: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let fields: [RemoteProfileFieldItem]

    enum CodingKeys: String, CodingKey {
        case id, name, fields
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        fields = try c.decodeIfPresent([RemoteProfileFieldItem].self, forKey: .fields) ?? []
    }
}

struct RemoteProfileFieldItem: Decodable, Identifiable, Equatable {
    var id: String { key }
    let key: String
    let label: String
    let value: String
}

struct RemoteFXRate: Decodable, Equatable {
    let rate: Double?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case rate, updatedAt
    }
}

struct RemoteGatewaySkew: Decodable, Equatable {
    let version: String?
    let pid: Int?
}

struct RemotePortHeld: Decodable, Equatable {
    let port: Int?
    let process: String?
    let pid: Int?
}

struct RemoteRedactRule: Codable, Equatable, Identifiable {
    var id: String { "\(kind)|\(prefix ?? "")|\(regex ?? "")" }
    var kind: String
    var prefix: String?
    var regex: String?

    enum CodingKeys: String, CodingKey {
        case kind, prefix, regex
    }
}

struct RemoteSettingsState: Decodable, Equatable {
    // General & Appearance (internal/settings/settings.go)
    var theme: String = "system"
    var lang: String = "system"
    var currency: String = "usd"
    var totalCurrency: String = "usd"
    var chineseUnits: Bool = false
    var dayStart: Int = 0
    var colorblind: Bool = false
    var reduceMotion: Bool = false
    var noBird: Bool = false
    var gatewayMode: String = ""
    var plainNames: Bool = false
    var bareModelIDs: Bool = false
    var bareModelIDsOnly: Bool = false
    var login: Bool = false

    // Privacy & Redaction (internal/settings/settings.go)
    var redact: Bool = true
    var redactPersonal: Bool = false
    var redactShape: Bool = false
    var redactWords: [String] = []
    var redactWordsAnyCase: Bool = false
    var redactWordsWhole: Bool = false
    var redactRules: [RemoteRedactRule] = []
    var redactActions: [String: String] = [:]
    var redactAllow: [String] = []
    var redactRouteTo: String = ""
    var agentTelemetryOff: Bool = false
    var noAccountDiscovery: Bool = false
    var signInLinkOnly: Bool = false
    var requestArchive: Bool = false
    var requestArchiveLocal: Bool = false

    // Allowances & Alerts (internal/settings/settings.go)
    var quotaLeft: Bool = false
    var quotaReads: String = ""
    var usageAlert: Int = 0
    var balanceAlert: Double = 0
    var resetReminder: Int = 0
    var turnDoneAlert: Int = 0
    var maskAlert: Bool = false

    // Network, Proxies & Bark (internal/gui/api.go settingsJSON)
    var proxy: String = ""
    var pluginProxy: String = ""
    var updateProxy: String = ""
    var proxyNow: String = ""
    var proxySource: String = ""
    var proxies: [RemoteSavedProxy] = []
    var lan: Bool = false
    var allowIPs: [String] = []
    var corsOrigins: [String] = []
    var mtls: Bool = false
    var port: Int = 3425
    var githubToken: String = ""
    var barkServer: String = ""
    var barkDaily: String = ""
    var barkKeySet: Bool = false

    // Models, Context, Codex & Search
    var vision: String = ""
    var visionEffort: String = ""
    var imageGen: String = ""
    var videoGen: String = ""
    var replyModel: String = ""
    var busyLoad: Int = 0
    var fullContext: Bool = false
    var compactAt: Int = 0
    var contextCap: Int = 0
    var contextCapAll: Bool = false
    var disabledModels: [String] = []
    var codexAgentsV1: Bool = false
    var codexServiceTier: String = ""
    var codexClient: String = ""
    var codexOpen: String = ""
    var codexTitles: String = ""
    var codexDescriptions: String = ""
    var codexPredictions: String = ""
    var codexSuggestions: String = ""
    var codexAutoReview: String = ""
    var codexAsyncCompact: Bool = false
    var codexAsyncCompactPercent: Int = 0
    var codexWarmup: String = ""
    var claudeWarmup: String = ""
    var codexWarmAt: String = ""
    var claudeWarmAt: String = ""
    var codexResetLead: Int = 0
    var claudeCache: [RemoteClaudeCacheItem] = []
    var claudeAttribution: String = ""
    var searchAll: Bool = false
    var searchCount: Int = 5
    var searchFirst: String = ""
    var searchAPIs: [RemoteSearchAPI] = []

    // Updates
    var updateChannel: String = ""
    var updateMirror: String = ""
    var noAutoUpdate: Bool = false
    var noAutoDownload: Bool = false
    var autoRestart: Bool = false

    var automaticCheckins: [String: Bool] = [:]

    // Server metadata
    var version: String = ""
    var gateway: String = ""
    var publicURL: String = ""
    var onNetwork: Bool = false
    var gatewayOn: Bool = false
    var gatewayWhy: String = ""
    var gatewayPaused: Bool = false

    init() {}

    enum CodingKeys: String, CodingKey {
        case theme, lang, currency, totalCurrency, chineseUnits, dayStart
        case colorblind, reduceMotion, noBird, gatewayMode, plainNames
        case bareModelIDs, bareModelIDsOnly, login
        case redact, redactPersonal, redactShape, redactWords
        case redactWordsAnyCase, redactWordsWhole, redactRules, redactActions, redactAllow, redactRouteTo
        case agentTelemetryOff, noAccountDiscovery, signInLinkOnly, requestArchive, requestArchiveLocal
        case quotaLeft, quotaReads, usageAlert, balanceAlert, resetReminder, turnDoneAlert, maskAlert
        case proxy, pluginProxy, updateProxy, proxyNow, proxySource, proxies
        case lan, allowIPs, corsOrigins, mtls, port, githubToken
        case barkServer, barkDaily, barkKeySet
        case vision, visionEffort, imageGen, videoGen, replyModel
        case busyLoad, fullContext, compactAt, contextCap, contextCapAll, disabledModels
        case codexAgentsV1, codexServiceTier, codexClient, codexOpen
        case codexTitles, codexDescriptions, codexPredictions, codexSuggestions, codexAutoReview
        case codexAsyncCompact, codexAsyncCompactPercent
        case codexWarmup, claudeWarmup, codexWarmAt, claudeWarmAt, codexResetLead
        case claudeCache, claudeAttribution
        case searchAll, searchCount, searchFirst, searchAPIs
        case updateChannel, updateMirror, noAutoUpdate, noAutoDownload, autoRestart
        case workbuddyCheckin, traeCheckin, minimaxCheckin, qoderCheckin
        case version, gateway, publicURL, onNetwork, gatewayOn, gatewayWhy, gatewayPaused
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? "system"
        lang = try c.decodeIfPresent(String.self, forKey: .lang) ?? "system"
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? "usd"
        totalCurrency = try c.decodeIfPresent(String.self, forKey: .totalCurrency) ?? "usd"
        chineseUnits = try c.decodeIfPresent(Bool.self, forKey: .chineseUnits) ?? false
        dayStart = try c.decodeIfPresent(Int.self, forKey: .dayStart) ?? 0
        colorblind = try c.decodeIfPresent(Bool.self, forKey: .colorblind) ?? false
        reduceMotion = try c.decodeIfPresent(Bool.self, forKey: .reduceMotion) ?? false
        noBird = try c.decodeIfPresent(Bool.self, forKey: .noBird) ?? false
        gatewayMode = try c.decodeIfPresent(String.self, forKey: .gatewayMode) ?? ""
        plainNames = try c.decodeIfPresent(Bool.self, forKey: .plainNames) ?? false
        bareModelIDs = try c.decodeIfPresent(Bool.self, forKey: .bareModelIDs) ?? false
        bareModelIDsOnly = try c.decodeIfPresent(Bool.self, forKey: .bareModelIDsOnly) ?? false
        login = try c.decodeIfPresent(Bool.self, forKey: .login) ?? false

        redact = try c.decodeIfPresent(Bool.self, forKey: .redact) ?? false
        redactPersonal = try c.decodeIfPresent(Bool.self, forKey: .redactPersonal) ?? false
        redactShape = try c.decodeIfPresent(Bool.self, forKey: .redactShape) ?? false
        redactWords = try c.decodeIfPresent([String].self, forKey: .redactWords) ?? []
        redactWordsAnyCase = try c.decodeIfPresent(Bool.self, forKey: .redactWordsAnyCase) ?? false
        redactWordsWhole = try c.decodeIfPresent(Bool.self, forKey: .redactWordsWhole) ?? false
        redactRules = try c.decodeIfPresent([RemoteRedactRule].self, forKey: .redactRules) ?? []
        redactActions = try c.decodeIfPresent([String: String].self, forKey: .redactActions) ?? [:]
        redactAllow = try c.decodeIfPresent([String].self, forKey: .redactAllow) ?? []
        redactRouteTo = try c.decodeIfPresent(String.self, forKey: .redactRouteTo) ?? ""
        agentTelemetryOff = try c.decodeIfPresent(Bool.self, forKey: .agentTelemetryOff) ?? false
        noAccountDiscovery = try c.decodeIfPresent(Bool.self, forKey: .noAccountDiscovery) ?? false
        signInLinkOnly = try c.decodeIfPresent(Bool.self, forKey: .signInLinkOnly) ?? false
        requestArchive = try c.decodeIfPresent(Bool.self, forKey: .requestArchive) ?? false
        requestArchiveLocal = try c.decodeIfPresent(Bool.self, forKey: .requestArchiveLocal) ?? false

        quotaLeft = try c.decodeIfPresent(Bool.self, forKey: .quotaLeft) ?? false
        quotaReads = try c.decodeIfPresent(String.self, forKey: .quotaReads) ?? ""
        usageAlert = try c.decodeIfPresent(Int.self, forKey: .usageAlert) ?? 0
        balanceAlert = try c.decodeIfPresent(Double.self, forKey: .balanceAlert) ?? 0
        resetReminder = try c.decodeIfPresent(Int.self, forKey: .resetReminder) ?? 0
        turnDoneAlert = try c.decodeIfPresent(Int.self, forKey: .turnDoneAlert) ?? 0
        maskAlert = try c.decodeIfPresent(Bool.self, forKey: .maskAlert) ?? false

        proxy = try c.decodeIfPresent(String.self, forKey: .proxy) ?? ""
        pluginProxy = try c.decodeIfPresent(String.self, forKey: .pluginProxy) ?? ""
        updateProxy = try c.decodeIfPresent(String.self, forKey: .updateProxy) ?? ""
        proxyNow = try c.decodeIfPresent(String.self, forKey: .proxyNow) ?? ""
        proxySource = try c.decodeIfPresent(String.self, forKey: .proxySource) ?? ""
        proxies = try c.decodeIfPresent([RemoteSavedProxy].self, forKey: .proxies) ?? []
        lan = try c.decodeIfPresent(Bool.self, forKey: .lan) ?? false
        allowIPs = try c.decodeIfPresent([String].self, forKey: .allowIPs) ?? []
        corsOrigins = try c.decodeIfPresent([String].self, forKey: .corsOrigins) ?? []
        mtls = try c.decodeIfPresent(Bool.self, forKey: .mtls) ?? false
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 3425
        githubToken = try c.decodeIfPresent(String.self, forKey: .githubToken) ?? ""
        barkServer = try c.decodeIfPresent(String.self, forKey: .barkServer) ?? ""
        barkDaily = try c.decodeIfPresent(String.self, forKey: .barkDaily) ?? ""
        barkKeySet = try c.decodeIfPresent(Bool.self, forKey: .barkKeySet) ?? false

        vision = try c.decodeIfPresent(String.self, forKey: .vision) ?? ""
        visionEffort = try c.decodeIfPresent(String.self, forKey: .visionEffort) ?? ""
        imageGen = try c.decodeIfPresent(String.self, forKey: .imageGen) ?? ""
        videoGen = try c.decodeIfPresent(String.self, forKey: .videoGen) ?? ""
        replyModel = try c.decodeIfPresent(String.self, forKey: .replyModel) ?? ""
        busyLoad = try c.decodeIfPresent(Int.self, forKey: .busyLoad) ?? 0
        fullContext = try c.decodeIfPresent(Bool.self, forKey: .fullContext) ?? false
        compactAt = try c.decodeIfPresent(Int.self, forKey: .compactAt) ?? 0
        contextCap = try c.decodeIfPresent(Int.self, forKey: .contextCap) ?? 0
        contextCapAll = try c.decodeIfPresent(Bool.self, forKey: .contextCapAll) ?? false
        disabledModels = try c.decodeIfPresent([String].self, forKey: .disabledModels) ?? []
        codexAgentsV1 = try c.decodeIfPresent(Bool.self, forKey: .codexAgentsV1) ?? false
        codexServiceTier = try c.decodeIfPresent(String.self, forKey: .codexServiceTier) ?? ""
        codexClient = try c.decodeIfPresent(String.self, forKey: .codexClient) ?? ""
        codexOpen = try c.decodeIfPresent(String.self, forKey: .codexOpen) ?? ""
        codexTitles = try c.decodeIfPresent(String.self, forKey: .codexTitles) ?? ""
        codexDescriptions = try c.decodeIfPresent(String.self, forKey: .codexDescriptions) ?? ""
        codexPredictions = try c.decodeIfPresent(String.self, forKey: .codexPredictions) ?? ""
        codexSuggestions = try c.decodeIfPresent(String.self, forKey: .codexSuggestions) ?? ""
        codexAutoReview = try c.decodeIfPresent(String.self, forKey: .codexAutoReview) ?? ""
        codexAsyncCompact = try c.decodeIfPresent(Bool.self, forKey: .codexAsyncCompact) ?? false
        codexAsyncCompactPercent = try c.decodeIfPresent(Int.self, forKey: .codexAsyncCompactPercent) ?? 0
        codexWarmup = try c.decodeIfPresent(String.self, forKey: .codexWarmup) ?? ""
        claudeWarmup = try c.decodeIfPresent(String.self, forKey: .claudeWarmup) ?? ""
        codexWarmAt = try c.decodeIfPresent(String.self, forKey: .codexWarmAt) ?? ""
        claudeWarmAt = try c.decodeIfPresent(String.self, forKey: .claudeWarmAt) ?? ""
        codexResetLead = try c.decodeIfPresent(Int.self, forKey: .codexResetLead) ?? 0
        claudeCache = try c.decodeIfPresent([RemoteClaudeCacheItem].self, forKey: .claudeCache) ?? []
        claudeAttribution = try c.decodeIfPresent(String.self, forKey: .claudeAttribution) ?? ""
        searchAll = try c.decodeIfPresent(Bool.self, forKey: .searchAll) ?? false
        searchCount = try c.decodeIfPresent(Int.self, forKey: .searchCount) ?? 5
        searchFirst = try c.decodeIfPresent(String.self, forKey: .searchFirst) ?? ""
        searchAPIs = try c.decodeIfPresent([RemoteSearchAPI].self, forKey: .searchAPIs) ?? []

        updateChannel = try c.decodeIfPresent(String.self, forKey: .updateChannel) ?? ""
        updateMirror = try c.decodeIfPresent(String.self, forKey: .updateMirror) ?? ""
        noAutoUpdate = try c.decodeIfPresent(Bool.self, forKey: .noAutoUpdate) ?? false
        noAutoDownload = try c.decodeIfPresent(Bool.self, forKey: .noAutoDownload) ?? false
        autoRestart = try c.decodeIfPresent(Bool.self, forKey: .autoRestart) ?? false

        automaticCheckins = [
            "workbuddy": try c.decodeIfPresent(Bool.self, forKey: .workbuddyCheckin) ?? false,
            "trae": try c.decodeIfPresent(Bool.self, forKey: .traeCheckin) ?? false,
            "minimax": try c.decodeIfPresent(Bool.self, forKey: .minimaxCheckin) ?? false,
            "qoder": try c.decodeIfPresent(Bool.self, forKey: .qoderCheckin) ?? false
        ]
        version = try c.decodeIfPresent(String.self, forKey: .version) ?? ""
        gateway = try c.decodeIfPresent(String.self, forKey: .gateway) ?? ""
        publicURL = try c.decodeIfPresent(String.self, forKey: .publicURL) ?? ""
        onNetwork = try c.decodeIfPresent(Bool.self, forKey: .onNetwork) ?? false
        gatewayOn = try c.decodeIfPresent(Bool.self, forKey: .gatewayOn) ?? false
        gatewayWhy = try c.decodeIfPresent(String.self, forKey: .gatewayWhy) ?? ""
        gatewayPaused = try c.decodeIfPresent(Bool.self, forKey: .gatewayPaused) ?? false
    }
}

// MARK: - /api/providers & /api/provider/* & /api/keys/*

struct RemoteProvidersResponse: Decodable {
    let providers: [RemoteProvider]
    let presets: [RemotePreset]
    let gateway: RemoteGatewayStatus?
    let codexDaemon: String?
    let codexApp: String?
    let codexProjects: Bool
    let plugins: [RemotePluginSub]
    let onPlugins: [String]
    let movable: [String]
    let movesTo: [String: String]
    let unmoved: [RemoteMoveCandidate]
    let withdrawn: [RemoteWithdrawnPlugin]
    let agyMove: [String]
    let excluded: [RemoteExcludedAccount]

    enum CodingKeys: String, CodingKey {
        case providers, presets, gateway, codexDaemon, codexApp, codexProjects
        case plugins, onPlugins, movable, movesTo, unmoved, withdrawn, agyMove, excluded
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        providers = try c.decodeIfPresent([RemoteProvider].self, forKey: .providers) ?? []
        presets = try c.decodeIfPresent([RemotePreset].self, forKey: .presets) ?? []
        gateway = try c.decodeIfPresent(RemoteGatewayStatus.self, forKey: .gateway)
        codexDaemon = try c.decodeIfPresent(String.self, forKey: .codexDaemon)
        codexApp = try c.decodeIfPresent(String.self, forKey: .codexApp)
        codexProjects = try c.decodeIfPresent(Bool.self, forKey: .codexProjects) ?? false
        plugins = try c.decodeIfPresent([RemotePluginSub].self, forKey: .plugins) ?? []
        onPlugins = try c.decodeIfPresent([String].self, forKey: .onPlugins) ?? []
        movable = try c.decodeIfPresent([String].self, forKey: .movable) ?? []
        movesTo = try c.decodeIfPresent([String: String].self, forKey: .movesTo) ?? [:]
        unmoved = try c.decodeIfPresent([RemoteMoveCandidate].self, forKey: .unmoved) ?? []
        withdrawn = try c.decodeIfPresent([RemoteWithdrawnPlugin].self, forKey: .withdrawn) ?? []
        agyMove = try c.decodeIfPresent([String].self, forKey: .agyMove) ?? []
        excluded = try c.decodeIfPresent([RemoteExcludedAccount].self, forKey: .excluded) ?? []
    }
}

struct RemotePresetRegion: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let chat: String?
    let responses: String?
    let anthropic: String?
    let keysUrl: String?
    let website: String?
}

struct RemotePreset: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let short: String?
    let kind: String
    let note: String?
    let chat: String?
    let responses: String?
    let anthropic: String?
    let decide: String?
    let website: String?
    let keysUrl: String?
    let noKey: Bool
    let keyHint: String?
    let sponsored: Bool
    let added: Bool
    let regions: [RemotePresetRegion]
    let regionLabel: String?
    let keyPlans: Bool
    let endpoint: String?
    let endpointHint: String?

    enum CodingKeys: String, CodingKey {
        case id, name, short, kind, note, chat, responses, anthropic, decide
        case website, keysUrl, noKey, keyHint, sponsored, added, regions, regionLabel
        case keyPlans, endpoint, endpointHint
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        short = try c.decodeIfPresent(String.self, forKey: .short)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "vendor"
        note = try c.decodeIfPresent(String.self, forKey: .note)
        chat = try c.decodeIfPresent(String.self, forKey: .chat)
        responses = try c.decodeIfPresent(String.self, forKey: .responses)
        anthropic = try c.decodeIfPresent(String.self, forKey: .anthropic)
        decide = try c.decodeIfPresent(String.self, forKey: .decide)
        website = try c.decodeIfPresent(String.self, forKey: .website)
        keysUrl = try c.decodeIfPresent(String.self, forKey: .keysUrl)
        noKey = try c.decodeIfPresent(Bool.self, forKey: .noKey) ?? false
        keyHint = try c.decodeIfPresent(String.self, forKey: .keyHint)
        sponsored = try c.decodeIfPresent(Bool.self, forKey: .sponsored) ?? false
        added = try c.decodeIfPresent(Bool.self, forKey: .added) ?? false
        regions = try c.decodeIfPresent([RemotePresetRegion].self, forKey: .regions) ?? []
        regionLabel = try c.decodeIfPresent(String.self, forKey: .regionLabel)
        keyPlans = try c.decodeIfPresent(Bool.self, forKey: .keyPlans) ?? false
        endpoint = try c.decodeIfPresent(String.self, forKey: .endpoint)
        endpointHint = try c.decodeIfPresent(String.self, forKey: .endpointHint)
    }

    var displayTitle: String {
        if let s = short, !s.isEmpty { return s }
        return name
    }
}

struct RemoteProvider: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
    let preset: String
    let host: String
    let chat: String
    let responses: String
    let anthropic: String
    let gemini: String
    let decide: String
    let baseAPI: String
    let modelsURL: String
    let balanceURL: String
    let balancePath: String
    let website: String
    let keysUrl: String
    let ready: Bool
    let off: Bool
    let unlisted: Bool
    let routing: String
    let affinity: String
    let sink: Bool
    let useFirst: Bool
    let noStandIn: Bool
    let unredacted: Bool
    let countFree: Bool
    let billing: String
    let billingKind: String
    let insecureTLS: Bool
    let takesInsecureTLS: Bool
    let http1: Bool
    let limitRestOff: Bool
    let passErrors: Bool
    let takesPassErrors: Bool
    let passUserAgent: Bool
    let authHeader: String
    let bothAuth: Bool
    let listOff: Bool
    let takesListOff: Bool
    let noModels: Bool
    let bestInFamily: Bool
    let chosen: [String]
    let fallback: [String]
    let speaks: [String]
    let exposed: Int
    let models: [RemoteProviderModel]
    let key: RemoteProviderKey?
    let anonKey: String?
    let keyList: [RemoteKeyInfo]
    let account: RemoteProviderAccount?
    let accountModels: [String: [String]]
    let accountNames: [String: String]
    let accountWeights: [String: Int]
    let accountRests: [String: [RemoteKeyRest]]
    let listError: String?
    let priceRate: Double?
    let maxConcurrency: Int?
    let maxAccounts: Int?
    let maxRPM: Int?
    let proxy: String
    let keepLogin: Bool
    let keepLoginAs: String
    let switchOnly: Bool
    let restartApp: Bool
    let capStop: Bool
    let capCareful: Bool
    let accountProxies: [String: String]
    let accountCaps: [String: Int]
    let accountWindowCaps: [String: [String: Int]]
    let accountWindowAmounts: [String: [String: Double]]
    let accountSeats: [String: String]
    let accountUsers: [String: String]
    let accountConcurrency: [String: Int]
    let proxyGone: String?
    let move: RemoteProviderMove?

    enum CodingKeys: String, CodingKey {
        case id, name, icon, preset, host, chat, responses, anthropic, gemini, decide, baseAPI
        case modelsURL, balanceURL, balancePath, website, keysUrl
        case ready, off, unlisted, routing, affinity, sink, useFirst, noStandIn
        case unredacted, countFree, billing, billingKind, insecureTLS, takesInsecureTLS, http1
        case limitRestOff, passErrors, takesPassErrors, passUserAgent, authHeader, bothAuth
        case listOff, takesListOff, noModels, bestInFamily, chosen, fallback, speaks
        case exposed, models, key, anonKey, keyList, account
        case accountModels, accountNames, accountWeights, accountRests
        case listError, priceRate, maxConcurrency, maxAccounts, maxRPM, proxy
        case keepLogin, keepLoginAs, switchOnly, restartApp, capStop, capCareful
        case accountProxies, accountCaps, accountWindowCaps, accountWindowAmounts
        case accountSeats, accountUsers, accountConcurrency, proxyGone, move
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? ""
        preset = try c.decodeIfPresent(String.self, forKey: .preset) ?? ""
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? ""
        chat = try c.decodeIfPresent(String.self, forKey: .chat) ?? ""
        responses = try c.decodeIfPresent(String.self, forKey: .responses) ?? ""
        anthropic = try c.decodeIfPresent(String.self, forKey: .anthropic) ?? ""
        gemini = try c.decodeIfPresent(String.self, forKey: .gemini) ?? ""
        decide = try c.decodeIfPresent(String.self, forKey: .decide) ?? ""
        baseAPI = try c.decodeIfPresent(String.self, forKey: .baseAPI) ?? ""
        modelsURL = try c.decodeIfPresent(String.self, forKey: .modelsURL) ?? ""
        balanceURL = try c.decodeIfPresent(String.self, forKey: .balanceURL) ?? ""
        balancePath = try c.decodeIfPresent(String.self, forKey: .balancePath) ?? ""
        website = try c.decodeIfPresent(String.self, forKey: .website) ?? ""
        keysUrl = try c.decodeIfPresent(String.self, forKey: .keysUrl) ?? ""
        ready = try c.decodeIfPresent(Bool.self, forKey: .ready) ?? false
        off = try c.decodeIfPresent(Bool.self, forKey: .off) ?? false
        unlisted = try c.decodeIfPresent(Bool.self, forKey: .unlisted) ?? false
        routing = try c.decodeIfPresent(String.self, forKey: .routing) ?? ""
        affinity = try c.decodeIfPresent(String.self, forKey: .affinity) ?? ""
        sink = try c.decodeIfPresent(Bool.self, forKey: .sink) ?? false
        useFirst = try c.decodeIfPresent(Bool.self, forKey: .useFirst) ?? false
        noStandIn = try c.decodeIfPresent(Bool.self, forKey: .noStandIn) ?? false
        unredacted = try c.decodeIfPresent(Bool.self, forKey: .unredacted) ?? false
        countFree = try c.decodeIfPresent(Bool.self, forKey: .countFree) ?? false
        billing = try c.decodeIfPresent(String.self, forKey: .billing) ?? ""
        billingKind = try c.decodeIfPresent(String.self, forKey: .billingKind) ?? ""
        insecureTLS = try c.decodeIfPresent(Bool.self, forKey: .insecureTLS) ?? false
        takesInsecureTLS = try c.decodeIfPresent(Bool.self, forKey: .takesInsecureTLS) ?? false
        http1 = try c.decodeIfPresent(Bool.self, forKey: .http1) ?? false
        limitRestOff = try c.decodeIfPresent(Bool.self, forKey: .limitRestOff) ?? false
        passErrors = try c.decodeIfPresent(Bool.self, forKey: .passErrors) ?? false
        takesPassErrors = try c.decodeIfPresent(Bool.self, forKey: .takesPassErrors) ?? false
        passUserAgent = try c.decodeIfPresent(Bool.self, forKey: .passUserAgent) ?? false
        authHeader = try c.decodeIfPresent(String.self, forKey: .authHeader) ?? ""
        bothAuth = try c.decodeIfPresent(Bool.self, forKey: .bothAuth) ?? false
        listOff = try c.decodeIfPresent(Bool.self, forKey: .listOff) ?? false
        takesListOff = try c.decodeIfPresent(Bool.self, forKey: .takesListOff) ?? false
        noModels = try c.decodeIfPresent(Bool.self, forKey: .noModels) ?? false
        bestInFamily = try c.decodeIfPresent(Bool.self, forKey: .bestInFamily) ?? false
        chosen = try c.decodeIfPresent([String].self, forKey: .chosen) ?? []
        fallback = try c.decodeIfPresent([String].self, forKey: .fallback) ?? []
        speaks = try c.decodeIfPresent([String].self, forKey: .speaks) ?? []
        exposed = try c.decodeIfPresent(Int.self, forKey: .exposed) ?? 0
        models = try c.decodeIfPresent([RemoteProviderModel].self, forKey: .models) ?? []
        key = try c.decodeIfPresent(RemoteProviderKey.self, forKey: .key)
        anonKey = try c.decodeIfPresent(String.self, forKey: .anonKey)
        keyList = try c.decodeIfPresent([RemoteKeyInfo].self, forKey: .keyList) ?? []
        account = try c.decodeIfPresent(RemoteProviderAccount.self, forKey: .account)
        accountModels = try c.decodeIfPresent([String: [String]].self, forKey: .accountModels) ?? [:]
        accountNames = try c.decodeIfPresent([String: String].self, forKey: .accountNames) ?? [:]
        accountWeights = try c.decodeIfPresent([String: Int].self, forKey: .accountWeights) ?? [:]
        accountRests = try c.decodeIfPresent([String: [RemoteKeyRest]].self, forKey: .accountRests) ?? [:]
        listError = try c.decodeIfPresent(String.self, forKey: .listError)
        priceRate = try c.decodeIfPresent(Double.self, forKey: .priceRate)
        maxConcurrency = try c.decodeIfPresent(Int.self, forKey: .maxConcurrency)
        maxAccounts = try c.decodeIfPresent(Int.self, forKey: .maxAccounts)
        maxRPM = try c.decodeIfPresent(Int.self, forKey: .maxRPM)
        proxy = try c.decodeIfPresent(String.self, forKey: .proxy) ?? ""
        keepLogin = try c.decodeIfPresent(Bool.self, forKey: .keepLogin) ?? false
        keepLoginAs = try c.decodeIfPresent(String.self, forKey: .keepLoginAs) ?? ""
        switchOnly = try c.decodeIfPresent(Bool.self, forKey: .switchOnly) ?? false
        restartApp = try c.decodeIfPresent(Bool.self, forKey: .restartApp) ?? false
        capStop = try c.decodeIfPresent(Bool.self, forKey: .capStop) ?? false
        capCareful = try c.decodeIfPresent(Bool.self, forKey: .capCareful) ?? false
        accountProxies = try c.decodeIfPresent([String: String].self, forKey: .accountProxies) ?? [:]
        accountCaps = try c.decodeIfPresent([String: Int].self, forKey: .accountCaps) ?? [:]
        accountWindowCaps = try c.decodeIfPresent([String: [String: Int]].self, forKey: .accountWindowCaps) ?? [:]
        accountWindowAmounts = try c.decodeIfPresent([String: [String: Double]].self, forKey: .accountWindowAmounts) ?? [:]
        accountSeats = try c.decodeIfPresent([String: String].self, forKey: .accountSeats) ?? [:]
        accountUsers = try c.decodeIfPresent([String: String].self, forKey: .accountUsers) ?? [:]
        accountConcurrency = try c.decodeIfPresent([String: Int].self, forKey: .accountConcurrency) ?? [:]
        proxyGone = try c.decodeIfPresent(String.self, forKey: .proxyGone)
        move = try c.decodeIfPresent(RemoteProviderMove.self, forKey: .move)
    }

    var primaryEndpointPreview: String {
        for url in [chat, anthropic, responses, gemini, decide, host] where !url.isEmpty {
            return url
        }
        return "订阅账号"
    }

    var exposedCount: Int {
        if exposed > 0 { return exposed }
        return models.filter(\.on).count
    }
}

struct RemoteProviderKey: Decodable, Equatable {
    let set: Bool
    let masked: String
    let optional: Bool

    enum CodingKeys: String, CodingKey {
        case set, masked, optional
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        set = try c.decodeIfPresent(Bool.self, forKey: .set) ?? false
        masked = try c.decodeIfPresent(String.self, forKey: .masked) ?? ""
        optional = try c.decodeIfPresent(Bool.self, forKey: .optional) ?? false
    }
}

struct RemoteKeyInfo: Decodable, Identifiable, Equatable {
    let id: String
    let name: String?
    let masked: String
    let active: Bool
    let on: Bool
    let `protocol`: String?
    let weight: Int?
    let plan: String?
    let rest: RemoteKeyRest?
    let spend: RemoteKeySpend?
    let balance: RemoteKeyOwnBalance?

    enum CodingKeys: String, CodingKey {
        case id, name, masked, active, on, `protocol`, weight, plan, rest, spend, balance
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name)
        masked = try c.decodeIfPresent(String.self, forKey: .masked) ?? ""
        active = try c.decodeIfPresent(Bool.self, forKey: .active) ?? false
        on = try c.decodeIfPresent(Bool.self, forKey: .on) ?? false
        `protocol` = try c.decodeIfPresent(String.self, forKey: .`protocol`)
        weight = try c.decodeIfPresent(Int.self, forKey: .weight)
        plan = try c.decodeIfPresent(String.self, forKey: .plan)
        rest = try c.decodeIfPresent(RemoteKeyRest.self, forKey: .rest)
        spend = try c.decodeIfPresent(RemoteKeySpend.self, forKey: .spend)
        balance = try c.decodeIfPresent(RemoteKeyOwnBalance.self, forKey: .balance)
    }
}

struct RemoteKeyRest: Decodable, Equatable {
    let why: String?
    let status: Int?
    let until: String?
    let rate: Bool?
    let key: String?
    let model: String?
    let probed: Bool?
    let by: String?
}

struct RemoteKeySpend: Decodable, Equatable {
    let usd: Double?
    let period: String?
    let spent: Double?
    let held: Bool?
}

struct RemoteKeyOwnBalance: Decodable, Equatable {
    let amount: Double?
    let left: Double?
    let currency: String?
}

struct RemoteProviderAccount: Decodable, Equatable {
    let agent: String?
    let agentName: String?
    let user: String?
    let plan: String?
    let logins: [RemoteProviderLogin]
    let builtin: String?
    let wsl: String?

    enum CodingKeys: String, CodingKey {
        case agent, agentName, user, plan, logins, builtin, wsl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        agent = try c.decodeIfPresent(String.self, forKey: .agent)
        agentName = try c.decodeIfPresent(String.self, forKey: .agentName)
        user = try c.decodeIfPresent(String.self, forKey: .user)
        plan = try c.decodeIfPresent(String.self, forKey: .plan)
        logins = try c.decodeIfPresent([RemoteProviderLogin].self, forKey: .logins) ?? []
        builtin = try c.decodeIfPresent(String.self, forKey: .builtin)
        wsl = try c.decodeIfPresent(String.self, forKey: .wsl)
    }
}

struct RemoteProviderLogin: Decodable, Identifiable, Equatable {
    var id: String { "\(agent)|\(user)" }
    let agent: String
    let user: String
    let plan: String?
    let seen: String?
    let active: Bool
    let on: Bool
    let lapsed: String?
    let until: String?
    let own: Bool
    let paused: Bool
    let returns: Bool
    let token: Bool
    let uses: Bool
    let accessOnly: Bool

    enum CodingKeys: String, CodingKey {
        case agent, user, plan, seen, active, on, lapsed, until, own, paused, returns, token, uses, accessOnly
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        agent = try c.decodeIfPresent(String.self, forKey: .agent) ?? ""
        user = try c.decodeIfPresent(String.self, forKey: .user) ?? ""
        plan = try c.decodeIfPresent(String.self, forKey: .plan)
        seen = try c.decodeIfPresent(String.self, forKey: .seen)
        active = try c.decodeIfPresent(Bool.self, forKey: .active) ?? false
        on = try c.decodeIfPresent(Bool.self, forKey: .on) ?? false
        lapsed = try c.decodeIfPresent(String.self, forKey: .lapsed)
        until = try c.decodeIfPresent(String.self, forKey: .until)
        own = try c.decodeIfPresent(Bool.self, forKey: .own) ?? false
        paused = try c.decodeIfPresent(Bool.self, forKey: .paused) ?? false
        returns = try c.decodeIfPresent(Bool.self, forKey: .returns) ?? false
        token = try c.decodeIfPresent(Bool.self, forKey: .token) ?? false
        uses = try c.decodeIfPresent(Bool.self, forKey: .uses) ?? false
        accessOnly = try c.decodeIfPresent(Bool.self, forKey: .accessOnly) ?? false
    }
}

// MARK: - OAuth Sign-In, Plugins, Login Quota & Account Migration

struct RemotePluginMethod: Decodable, Equatable {
    let type: String
    let label: String
    let labels: [String: String]
    let placeholder: String?
    let keyless: Bool
    let keyAsked: Bool

    enum CodingKeys: String, CodingKey {
        case type, label, labels, placeholder, keyless, keyAsked
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "oauth"
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        labels = try c.decodeIfPresent([String: String].self, forKey: .labels) ?? [:]
        placeholder = try c.decodeIfPresent(String.self, forKey: .placeholder)
        keyless = try c.decodeIfPresent(Bool.self, forKey: .keyless) ?? false
        keyAsked = try c.decodeIfPresent(Bool.self, forKey: .keyAsked) ?? false
    }

    var localizedLabel: String {
        labels["zh"] ?? labels["zh-CN"] ?? (label.isEmpty ? (type == "api" ? "API Key" : "浏览器授权") : label)
    }
}

struct RemotePluginSub: Decodable, Identifiable, Equatable {
    let id: String
    let pid: String
    let name: String
    let icon: String
    let spec: String
    let methods: [RemotePluginMethod]
    let signedIn: Bool
    let single: Bool
    let models: Int
    let importable: Bool
    let importFrom: String?
    let importFroms: [String: String]

    enum CodingKeys: String, CodingKey {
        case id, pid, name, icon, spec, methods, signedIn, single, models, importable, importFrom, importFroms
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        pid = try c.decodeIfPresent(String.self, forKey: .pid) ?? id
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "generic"
        spec = try c.decodeIfPresent(String.self, forKey: .spec) ?? ""
        methods = try c.decodeIfPresent([RemotePluginMethod].self, forKey: .methods) ?? []
        signedIn = try c.decodeIfPresent(Bool.self, forKey: .signedIn) ?? false
        single = try c.decodeIfPresent(Bool.self, forKey: .single) ?? false
        models = try c.decodeIfPresent(Int.self, forKey: .models) ?? 0
        importable = try c.decodeIfPresent(Bool.self, forKey: .importable) ?? false
        importFrom = try c.decodeIfPresent(String.self, forKey: .importFrom)
        importFroms = try c.decodeIfPresent([String: String].self, forKey: .importFroms) ?? [:]
    }
}

struct RemotePluginPromptOption: Decodable, Equatable {
    let label: String
    let value: String
    let hint: String?
    let labels: [String: String]
    let hints: [String: String]

    enum CodingKeys: String, CodingKey {
        case label, value, hint, labels, hints
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        value = try c.decodeIfPresent(String.self, forKey: .value) ?? ""
        hint = try c.decodeIfPresent(String.self, forKey: .hint)
        labels = try c.decodeIfPresent([String: String].self, forKey: .labels) ?? [:]
        hints = try c.decodeIfPresent([String: String].self, forKey: .hints) ?? [:]
    }

    var localizedLabel: String {
        labels["zh"] ?? labels["zh-CN"] ?? label
    }

    var localizedHint: String? {
        hints["zh"] ?? hints["zh-CN"] ?? hint
    }
}

struct RemotePluginPrompt: Decodable, Equatable {
    let type: String
    let key: String
    let message: String
    let messages: [String: String]
    let placeholder: String?
    let options: [RemotePluginPromptOption]

    enum CodingKeys: String, CodingKey {
        case type, key, message, messages, placeholder, options
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "text"
        key = try c.decodeIfPresent(String.self, forKey: .key) ?? ""
        message = try c.decodeIfPresent(String.self, forKey: .message) ?? ""
        messages = try c.decodeIfPresent([String: String].self, forKey: .messages) ?? [:]
        placeholder = try c.decodeIfPresent(String.self, forKey: .placeholder)
        options = try c.decodeIfPresent([RemotePluginPromptOption].self, forKey: .options) ?? []
    }

    var localizedMessage: String {
        messages["zh"] ?? messages["zh-CN"] ?? message
    }
}

struct RemotePluginPromptResponse: Decodable {
    let prompt: RemotePluginPrompt?
    let inputs: [String: String]
    let error: String?

    enum CodingKeys: String, CodingKey {
        case prompt, inputs, error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        prompt = try c.decodeIfPresent(RemotePluginPrompt.self, forKey: .prompt)
        inputs = try c.decodeIfPresent([String: String].self, forKey: .inputs) ?? [:]
        error = try c.decodeIfPresent(String.self, forKey: .error)
    }
}

struct RemoteSignInState: Decodable, Equatable {
    let id: String
    let agent: String
    let url: String
    let code: String?
    let state: String
    let pasteCallback: Bool
    let pasteCode: Bool
    let pasteKey: Bool
    let keysURL: String?
    let instructions: String?
    let opened: Bool
    let installing: String?
    let user: String?
    let plan: String?
    let using: Bool
    let again: Bool
    let error: String?
    let callbackBlocked: String?
    let callbackPort: Int?
    let proxy: String?
    let linkOnly: Bool
    let openError: String?

    enum CodingKeys: String, CodingKey {
        case id, agent, url, code, state, pasteCallback, pasteCode, pasteKey
        case keysURL, instructions, opened, installing, user, plan, using, again
        case error, callbackBlocked, callbackPort, proxy, linkOnly, openError
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        agent = try c.decodeIfPresent(String.self, forKey: .agent) ?? ""
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        code = try c.decodeIfPresent(String.self, forKey: .code)
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? "waiting"
        pasteCallback = try c.decodeIfPresent(Bool.self, forKey: .pasteCallback) ?? false
        pasteCode = try c.decodeIfPresent(Bool.self, forKey: .pasteCode) ?? false
        pasteKey = try c.decodeIfPresent(Bool.self, forKey: .pasteKey) ?? false
        keysURL = try c.decodeIfPresent(String.self, forKey: .keysURL)
        instructions = try c.decodeIfPresent(String.self, forKey: .instructions)
        opened = try c.decodeIfPresent(Bool.self, forKey: .opened) ?? false
        installing = try c.decodeIfPresent(String.self, forKey: .installing)
        user = try c.decodeIfPresent(String.self, forKey: .user)
        plan = try c.decodeIfPresent(String.self, forKey: .plan)
        using = try c.decodeIfPresent(Bool.self, forKey: .using) ?? false
        again = try c.decodeIfPresent(Bool.self, forKey: .again) ?? false
        error = try c.decodeIfPresent(String.self, forKey: .error)
        callbackBlocked = try c.decodeIfPresent(String.self, forKey: .callbackBlocked)
        callbackPort = try c.decodeIfPresent(Int.self, forKey: .callbackPort)
        proxy = try c.decodeIfPresent(String.self, forKey: .proxy)
        linkOnly = try c.decodeIfPresent(Bool.self, forKey: .linkOnly) ?? false
        openError = try c.decodeIfPresent(String.self, forKey: .openError)
    }
}

struct RemoteImportedAccount: Decodable, Identifiable, Equatable {
    var id: String { "\(user)|\(status)|\(file ?? 0)|\(error ?? "")" }
    let user: String
    let status: String
    let plan: String?
    let error: String?
    let file: Int?

    enum CodingKeys: String, CodingKey {
        case user, status, plan, error, file
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        user = try c.decodeIfPresent(String.self, forKey: .user) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "failed"
        plan = try c.decodeIfPresent(String.self, forKey: .plan)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        file = try c.decodeIfPresent(Int.self, forKey: .file)
    }
}

struct RemoteSignInImportResponse: Decodable {
    let results: [RemoteImportedAccount]
    let providers: RemoteProvidersResponse
}

struct RemoteSignInExportResponse: Decodable {
    let path: String
    let accounts: [String]
    let skipped: [RemoteImportedAccount]

    enum CodingKeys: String, CodingKey {
        case path, accounts, skipped
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? ""
        accounts = try c.decodeIfPresent([String].self, forKey: .accounts) ?? []
        skipped = try c.decodeIfPresent([RemoteImportedAccount].self, forKey: .skipped) ?? []
    }
}

struct RemoteClaudeTokenResponse: Decodable {
    let user: String
}

struct RemoteMoveCandidate: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let package: String
    let accounts: Int
    let error: String?
}

struct RemoteWithdrawnPlugin: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let instead: String
    let package: String
}

struct RemoteProviderMove: Decodable, Equatable {
    let package: String
    let state: String
    let error: String?
}

struct RemoteExcludedAccount: Decodable, Identifiable, Equatable {
    var id: String { "\(agent)|\(provider ?? "")|\(why)" }
    let agent: String
    let provider: String?
    let name: String?
    let agentName: String
    let agentIcon: String
    let why: String
    let signedOut: Bool
    let users: [String]
    let quiet: Bool
    let retry: Bool

    enum CodingKeys: String, CodingKey {
        case agent, provider, name, agentName, agentIcon, why, signedOut, users, quiet, retry
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        agent = try c.decodeIfPresent(String.self, forKey: .agent) ?? ""
        provider = try c.decodeIfPresent(String.self, forKey: .provider)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        agentName = try c.decodeIfPresent(String.self, forKey: .agentName) ?? agent
        agentIcon = try c.decodeIfPresent(String.self, forKey: .agentIcon) ?? "generic"
        why = try c.decodeIfPresent(String.self, forKey: .why) ?? ""
        signedOut = try c.decodeIfPresent(Bool.self, forKey: .signedOut) ?? false
        users = try c.decodeIfPresent([String].self, forKey: .users) ?? []
        quiet = try c.decodeIfPresent(Bool.self, forKey: .quiet) ?? false
        retry = try c.decodeIfPresent(Bool.self, forKey: .retry) ?? false
    }
}

struct RemoteLoginQuotaWindow: Decodable, Identifiable, Equatable {
    var id: String { "\(name)|\(capId ?? "")|\(pool ?? "")|\(family ?? "")" }
    let unlimited: Bool
    let name: String
    let used: Double
    let resetsAt: String?
    let resetSecs: Int64?
    let display: String?
    let text: Bool
    let lane: String?
    let amount: Double?
    let limit: Double?
    let unit: String?
    let balance: Double?
    let spent: Double?
    let family: String?
    let pool: String?
    let credits: Bool
    let extra: Bool
    let capped: Bool
    let capsSome: Bool
    let capId: String?
    let ownCap: Bool

    enum CodingKeys: String, CodingKey {
        case unlimited, name, used, resetsAt, resetSecs, display, text, lane
        case amount, limit, unit, balance, spent, family, pool, credits, extra
        case capped, capsSome, capId, ownCap
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        unlimited = try c.decodeIfPresent(Bool.self, forKey: .unlimited) ?? false
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        used = try c.decodeIfPresent(Double.self, forKey: .used) ?? 0
        resetsAt = try c.decodeIfPresent(String.self, forKey: .resetsAt)
        resetSecs = try c.decodeIfPresent(Int64.self, forKey: .resetSecs)
        display = try c.decodeIfPresent(String.self, forKey: .display)
        text = try c.decodeIfPresent(Bool.self, forKey: .text) ?? false
        lane = try c.decodeIfPresent(String.self, forKey: .lane)
        amount = try c.decodeIfPresent(Double.self, forKey: .amount)
        limit = try c.decodeIfPresent(Double.self, forKey: .limit)
        unit = try c.decodeIfPresent(String.self, forKey: .unit)
        balance = try c.decodeIfPresent(Double.self, forKey: .balance)
        spent = try c.decodeIfPresent(Double.self, forKey: .spent)
        family = try c.decodeIfPresent(String.self, forKey: .family)
        pool = try c.decodeIfPresent(String.self, forKey: .pool)
        credits = try c.decodeIfPresent(Bool.self, forKey: .credits) ?? false
        extra = try c.decodeIfPresent(Bool.self, forKey: .extra) ?? false
        capped = try c.decodeIfPresent(Bool.self, forKey: .capped) ?? false
        capsSome = try c.decodeIfPresent(Bool.self, forKey: .capsSome) ?? false
        capId = try c.decodeIfPresent(String.self, forKey: .capId)
        ownCap = try c.decodeIfPresent(Bool.self, forKey: .ownCap) ?? false
    }
}

struct RemoteLoginQuota: Decodable, Equatable {
    let provider: String
    let name: String
    let icon: String
    let plan: String?
    let accessSku: String?
    let user: String?
    let windows: [RemoteLoginQuotaWindow]
    let balance: String?
    let until: String?
    let renew: String?
    let error: String?
    let pluginError: Bool
    let asOf: String?
    let readAt: String?
    let readDeferred: Bool
    let held: Bool
    let checkins: Bool
    let checkinBy: String?
    let checkinKey: String?
    let checkinOff: Bool

    enum CodingKeys: String, CodingKey {
        case provider, name, icon, plan, accessSku, user, windows, balance
        case until, renew, error, pluginError, asOf, readAt, readDeferred, held
        case checkins, checkinBy, checkinKey, checkinOff
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? ""
        plan = try c.decodeIfPresent(String.self, forKey: .plan)
        accessSku = try c.decodeIfPresent(String.self, forKey: .accessSku)
        user = try c.decodeIfPresent(String.self, forKey: .user)
        windows = try c.decodeIfPresent([RemoteLoginQuotaWindow].self, forKey: .windows) ?? []
        balance = try c.decodeIfPresent(String.self, forKey: .balance)
        until = try c.decodeIfPresent(String.self, forKey: .until)
        renew = try c.decodeIfPresent(String.self, forKey: .renew)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        pluginError = try c.decodeIfPresent(Bool.self, forKey: .pluginError) ?? false
        asOf = try c.decodeIfPresent(String.self, forKey: .asOf)
        readAt = try c.decodeIfPresent(String.self, forKey: .readAt)
        readDeferred = try c.decodeIfPresent(Bool.self, forKey: .readDeferred) ?? false
        held = try c.decodeIfPresent(Bool.self, forKey: .held) ?? false
        checkins = try c.decodeIfPresent(Bool.self, forKey: .checkins) ?? false
        checkinBy = try c.decodeIfPresent(String.self, forKey: .checkinBy)
        checkinKey = try c.decodeIfPresent(String.self, forKey: .checkinKey)
        checkinOff = try c.decodeIfPresent(Bool.self, forKey: .checkinOff) ?? false
    }
}

struct RemoteProviderModel: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let defaultName: String?
    let on: Bool
    let images: Bool
    let imageSet: Bool
    let ownImages: Bool
    let context: Int?
    let output: Int?
    let free: Bool
    let zero: Bool
    let best: Bool
    let kept: [String]
    let efforts: [String]
    let given: Bool
    let reasonless: Bool
    let api: String?
    let noAPI: Bool
    let same: String?
    let kind: String?
    let keys: [String]
    let keyCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name
        case defaultName = "default"
        case on, images, imageSet, ownImages, context, output, free, zero, best
        case kept, efforts, given, reasonless, api, noAPI, same, kind, keys, keyCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        defaultName = try c.decodeIfPresent(String.self, forKey: .defaultName)
        on = try c.decodeIfPresent(Bool.self, forKey: .on) ?? false
        images = try c.decodeIfPresent(Bool.self, forKey: .images) ?? false
        imageSet = try c.decodeIfPresent(Bool.self, forKey: .imageSet) ?? false
        ownImages = try c.decodeIfPresent(Bool.self, forKey: .ownImages) ?? false
        context = try c.decodeIfPresent(Int.self, forKey: .context)
        output = try c.decodeIfPresent(Int.self, forKey: .output)
        free = try c.decodeIfPresent(Bool.self, forKey: .free) ?? false
        zero = try c.decodeIfPresent(Bool.self, forKey: .zero) ?? false
        best = try c.decodeIfPresent(Bool.self, forKey: .best) ?? false
        kept = try c.decodeIfPresent([String].self, forKey: .kept) ?? []
        efforts = try c.decodeIfPresent([String].self, forKey: .efforts) ?? []
        given = try c.decodeIfPresent(Bool.self, forKey: .given) ?? false
        reasonless = try c.decodeIfPresent(Bool.self, forKey: .reasonless) ?? false
        api = try c.decodeIfPresent(String.self, forKey: .api)
        noAPI = try c.decodeIfPresent(Bool.self, forKey: .noAPI) ?? false
        same = try c.decodeIfPresent(String.self, forKey: .same)
        kind = try c.decodeIfPresent(String.self, forKey: .kind)
        keys = try c.decodeIfPresent([String].self, forKey: .keys) ?? []
        keyCount = try c.decodeIfPresent(Int.self, forKey: .keyCount) ?? 0
    }
}

struct RemoteProviderModelsRefreshResponse: Decodable {
    let count: Int
    let dropped: [String]
    let provider: RemoteProvider?

    enum CodingKeys: String, CodingKey {
        case count, dropped, provider
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
        dropped = try c.decodeIfPresent([String].self, forKey: .dropped) ?? []
        provider = try c.decodeIfPresent(RemoteProvider.self, forKey: .provider)
    }
}

struct RemoteProviderBalanceResponse: Decodable {
    let ok: Bool
    let amount: String?
    let error: String?
    let looked: Bool
    let found: String?
    let foundField: String?
    let undetected: Bool

    enum CodingKeys: String, CodingKey {
        case ok, amount, error, looked, found, foundField, undetected
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        if let str = try? c.decodeIfPresent(String.self, forKey: .amount) {
            amount = str
        } else if let num = try? c.decodeIfPresent(Double.self, forKey: .amount) {
            amount = String(format: "%.4f", num)
        } else {
            amount = nil
        }
        error = try c.decodeIfPresent(String.self, forKey: .error)
        looked = try c.decodeIfPresent(Bool.self, forKey: .looked) ?? false
        found = try c.decodeIfPresent(String.self, forKey: .found)
        foundField = try c.decodeIfPresent(String.self, forKey: .foundField)
        undetected = try c.decodeIfPresent(Bool.self, forKey: .undetected) ?? false
    }
}

struct RemoteProviderKeyRevealResponse: Decodable {
    let key: String
    let count: Int?
}

struct RemoteGatewayStatus: Decodable, Equatable {
    let url: String
    let lan: Bool
    let lanURLs: [String]
    let publicURL: String?
    let onNetwork: Bool
    let running: Bool
    let mine: Bool
    let paused: Bool
    let version: String?
    let models: Int

    enum CodingKeys: String, CodingKey {
        case url, lan, lanURLs, publicURL, onNetwork, running, mine, paused, version, models
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        lan = try c.decodeIfPresent(Bool.self, forKey: .lan) ?? false
        lanURLs = try c.decodeIfPresent([String].self, forKey: .lanURLs) ?? []
        publicURL = try c.decodeIfPresent(String.self, forKey: .publicURL)
        onNetwork = try c.decodeIfPresent(Bool.self, forKey: .onNetwork) ?? false
        running = try c.decodeIfPresent(Bool.self, forKey: .running) ?? false
        mine = try c.decodeIfPresent(Bool.self, forKey: .mine) ?? false
        paused = try c.decodeIfPresent(Bool.self, forKey: .paused) ?? false
        version = try c.decodeIfPresent(String.self, forKey: .version)
        models = try c.decodeIfPresent(Int.self, forKey: .models) ?? 0
    }
}

struct RemoteProviderTestResponse: Decodable {
    let results: [RemoteDetectionResult]

    enum CodingKeys: String, CodingKey {
        case results
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        results = try c.decodeIfPresent([RemoteDetectionResult].self, forKey: .results) ?? []
    }
}

struct RemoteDetectionResult: Decodable, Equatable {
    let proto: String?
    let ok: Bool
    let status: Int?
    let ms: Int?
    let error: String?
    let base: String?
}

// MARK: - /api/groups & /api/groups/*

struct RemoteGroupsResponse: Decodable {
    let groups: [RemoteRoutingGroup]
    let models: [RemoteGroupModelRef]
    let deciders: [RemoteGroupModelRef]
    let drawers: [RemoteGroupModelRef]
    let found: Bool
    let skip: [String]
    let templates: [RemoteGroupTemplate]
    let defaults: RemoteGroupDefaults?
    let shared: String?

    enum CodingKeys: String, CodingKey {
        case groups, models, deciders, drawers, found, skip, templates, defaults, shared
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        groups = try c.decodeIfPresent([RemoteRoutingGroup].self, forKey: .groups) ?? []
        models = try c.decodeIfPresent([RemoteGroupModelRef].self, forKey: .models) ?? []
        deciders = try c.decodeIfPresent([RemoteGroupModelRef].self, forKey: .deciders) ?? []
        drawers = try c.decodeIfPresent([RemoteGroupModelRef].self, forKey: .drawers) ?? []
        found = try c.decodeIfPresent(Bool.self, forKey: .found) ?? false
        skip = try c.decodeIfPresent([String].self, forKey: .skip) ?? []
        templates = try c.decodeIfPresent([RemoteGroupTemplate].self, forKey: .templates) ?? []
        defaults = try c.decodeIfPresent(RemoteGroupDefaults.self, forKey: .defaults)
        shared = try c.decodeIfPresent(String.self, forKey: .shared)
    }
}

struct RemoteGroupDefaults: Decodable, Equatable {
    let sink: Bool
    let firstToken: Int
    let patience: Int

    enum CodingKeys: String, CodingKey {
        case sink, firstToken, patience
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sink = try c.decodeIfPresent(Bool.self, forKey: .sink) ?? false
        firstToken = try c.decodeIfPresent(Int.self, forKey: .firstToken) ?? 0
        patience = try c.decodeIfPresent(Int.self, forKey: .patience) ?? 0
    }
}

struct RemoteGroupModelRef: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let provider: String
    let providerName: String
    let context: Int?
    let efforts: [String]
    let canFast: Bool
    let ultraOk: Bool
    let images: Bool
    let free: Bool
    let zero: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, provider, providerName, context, efforts, canFast, ultraOk, images, free, zero
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? ""
        providerName = try c.decodeIfPresent(String.self, forKey: .providerName) ?? provider
        context = try c.decodeIfPresent(Int.self, forKey: .context)
        efforts = try c.decodeIfPresent([String].self, forKey: .efforts) ?? []
        canFast = try c.decodeIfPresent(Bool.self, forKey: .canFast) ?? false
        ultraOk = try c.decodeIfPresent(Bool.self, forKey: .ultraOk) ?? false
        images = try c.decodeIfPresent(Bool.self, forKey: .images) ?? false
        free = try c.decodeIfPresent(Bool.self, forKey: .free) ?? false
        zero = try c.decodeIfPresent(Bool.self, forKey: .zero) ?? false
    }
}

struct RemoteGroupTimeWindow: Codable, Equatable {
    var from: String
    var to: String
    var days: [String]?
    var zone: String?

    init(from: String = "09:00", to: String = "18:00", days: [String]? = nil, zone: String? = nil) {
        self.from = from
        self.to = to
        self.days = days
        self.zone = zone
    }
}

struct RemoteGroupRuleCond: Codable, Equatable, Identifiable {
    var id: String { "\(field)|\(op)|\(value ?? "")" }
    var field: String
    var op: String
    var value: String?
}

struct RemoteGroupRule: Codable, Identifiable, Equatable {
    var id: String {
        "\(use)|\(useEffort ?? "")|\(tokens ?? 0)|\(images ? 1 : 0)|\(effort ?? "")|\(intent ?? "")|\(compact ? 1 : 0)|\(pause ? 1 : 0)|\(time?.from ?? "")-\(time?.to ?? "")|\(agents?.joined(separator: ",") ?? "")"
    }
    var use: String
    var more: [String]?
    var useEffort: String?
    var tokens: Int?
    var images: Bool
    var effort: String?
    var agents: [String]?
    var intent: String?
    var compact: Bool
    var time: RemoteGroupTimeWindow?
    var folders: [String]?
    var exceptFolders: [String]?
    var whereConds: [RemoteGroupRuleCond]?
    var pause: Bool

    enum CodingKeys: String, CodingKey {
        case use, more, useEffort, tokens, images, effort, agents, intent, compact
        case time, folders, exceptFolders
        case whereConds = "where"
        case pause
    }

    init(
        use: String,
        more: [String]? = nil,
        useEffort: String? = nil,
        tokens: Int? = nil,
        images: Bool = false,
        effort: String? = nil,
        agents: [String]? = nil,
        intent: String? = nil,
        compact: Bool = false,
        time: RemoteGroupTimeWindow? = nil,
        folders: [String]? = nil,
        exceptFolders: [String]? = nil,
        whereConds: [RemoteGroupRuleCond]? = nil,
        pause: Bool = false
    ) {
        self.use = use
        self.more = more
        self.useEffort = useEffort
        self.tokens = tokens
        self.images = images
        self.effort = effort
        self.agents = agents
        self.intent = intent
        self.compact = compact
        self.time = time
        self.folders = folders
        self.exceptFolders = exceptFolders
        self.whereConds = whereConds
        self.pause = pause
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        use = try c.decodeIfPresent(String.self, forKey: .use) ?? ""
        more = try c.decodeIfPresent([String].self, forKey: .more)
        useEffort = try c.decodeIfPresent(String.self, forKey: .useEffort)
        tokens = try c.decodeIfPresent(Int.self, forKey: .tokens)
        images = try c.decodeIfPresent(Bool.self, forKey: .images) ?? false
        effort = try c.decodeIfPresent(String.self, forKey: .effort)
        agents = try c.decodeIfPresent([String].self, forKey: .agents)
        intent = try c.decodeIfPresent(String.self, forKey: .intent)
        compact = try c.decodeIfPresent(Bool.self, forKey: .compact) ?? false
        time = try c.decodeIfPresent(RemoteGroupTimeWindow.self, forKey: .time)
        folders = try c.decodeIfPresent([String].self, forKey: .folders)
        exceptFolders = try c.decodeIfPresent([String].self, forKey: .exceptFolders)
        whereConds = try c.decodeIfPresent([RemoteGroupRuleCond].self, forKey: .whereConds)
        pause = try c.decodeIfPresent(Bool.self, forKey: .pause) ?? false
    }

    func toDictionary() -> [String: Any] {
        var d: [String: Any] = ["use": use]
        if let more = more, !more.isEmpty { d["more"] = more }
        if let ue = useEffort, !ue.isEmpty { d["useEffort"] = ue }
        if let t = tokens, t > 0 { d["tokens"] = t }
        if images { d["images"] = true }
        if let e = effort, !e.isEmpty { d["effort"] = e }
        if let ag = agents, !ag.isEmpty { d["agents"] = ag }
        if let intent = intent, !intent.isEmpty { d["intent"] = intent }
        if compact { d["compact"] = true }
        if let time = time, !time.from.isEmpty, !time.to.isEmpty {
            var tw: [String: Any] = ["from": time.from, "to": time.to]
            if let days = time.days, !days.isEmpty { tw["days"] = days }
            if let zone = time.zone, !zone.isEmpty { tw["zone"] = zone }
            d["time"] = tw
        }
        if let folders = folders, !folders.isEmpty { d["folders"] = folders }
        if let exceptFolders = exceptFolders, !exceptFolders.isEmpty { d["exceptFolders"] = exceptFolders }
        if let conditions = whereConds {
            d["where"] = conditions.map { cond -> [String: String] in
                var item = ["field": cond.field, "op": cond.op]
                if let value = cond.value { item["value"] = value }
                return item
            }
        }
        if pause { d["pause"] = true }
        return d
    }

    var summaryText: String {
        var parts: [String] = []
        if pause { parts.append("暂停") }
        if let t = tokens, t > 0 { parts.append("≥\(t) tok") }
        if images { parts.append("含图片") }
        if let e = effort, !e.isEmpty { parts.append("推理≥\(e)") }
        if compact { parts.append("压缩") }
        if let ag = agents, !ag.isEmpty { parts.append(ag.joined(separator: ",")) }
        if let intent = intent, !intent.isEmpty { parts.append("意图:\(intent)") }
        if let tw = time { parts.append("\(tw.from)–\(tw.to)") }
        return parts.isEmpty ? "默认条件" : parts.joined(separator: " · ")
    }
}

struct RemoteGroupMemberInfo: Decodable, Identifiable, Equatable {
    let id: String
    let ready: Bool
    let provider: String?
    let name: String?
    let model: String?
    let on: Int
    let group: Bool
    let providerOff: Bool
    let of: String?
    let effort: String?
    let account: String?
    let billing: String?
    let fast: Bool
    let canFast: Bool
    let ultra: Bool
    let ultraOK: Bool
    let efforts: [String]
    let context: Int?
    let images: Bool
    let free: Bool

    enum CodingKeys: String, CodingKey {
        case id, ready, provider, name, model, on, group, providerOff
        case of, effort, account, billing, fast, canFast, ultra, ultraOK
        case efforts, context, images, free
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        ready = try c.decodeIfPresent(Bool.self, forKey: .ready) ?? false
        provider = try c.decodeIfPresent(String.self, forKey: .provider)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        on = try c.decodeIfPresent(Int.self, forKey: .on) ?? 0
        group = try c.decodeIfPresent(Bool.self, forKey: .group) ?? false
        providerOff = try c.decodeIfPresent(Bool.self, forKey: .providerOff) ?? false
        of = try c.decodeIfPresent(String.self, forKey: .of)
        effort = try c.decodeIfPresent(String.self, forKey: .effort)
        account = try c.decodeIfPresent(String.self, forKey: .account)
        billing = try c.decodeIfPresent(String.self, forKey: .billing)
        fast = try c.decodeIfPresent(Bool.self, forKey: .fast) ?? false
        canFast = try c.decodeIfPresent(Bool.self, forKey: .canFast) ?? false
        ultra = try c.decodeIfPresent(Bool.self, forKey: .ultra) ?? false
        ultraOK = try c.decodeIfPresent(Bool.self, forKey: .ultraOK) ?? false
        efforts = try c.decodeIfPresent([String].self, forKey: .efforts) ?? []
        context = try c.decodeIfPresent(Int.self, forKey: .context)
        images = try c.decodeIfPresent(Bool.self, forKey: .images) ?? false
        free = try c.decodeIfPresent(Bool.self, forKey: .free) ?? false
    }
}

struct RemoteGroupTemplate: Decodable, Identifiable, Equatable {
    var id: String { kind }
    let kind: String
    let group: RemoteRoutingGroup
    let why: String?
    let need: String?
}

struct RemoteRoutingGroup: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let ref: String
    let note: String?
    let members: [String]
    let match: [String]
    let matched: [String]
    let routing: String
    let affinity: String
    let sink: Bool
    let noSink: Bool
    let firstToken: Int
    let patience: Int
    let offMembers: [String]
    let disabled: Bool
    let ready: Bool
    let picked: String?
    let pick: String?
    let rules: [RemoteGroupRule]
    let classifier: String?
    let intentSure: Double?
    let effort: String?
    let context: Int
    let compact: Int
    let levels: [String]
    let fast: [String]
    let ultra: [String]
    let auto: Bool
    let unlists: Bool
    let redact: String
    let memberInfo: [RemoteGroupMemberInfo]
    let offers: [String]

    enum CodingKeys: String, CodingKey {
        case id, name, ref, note, members, match, matched
        case routing, mode, affinity, sink, noSink, firstToken, patience
        case offMembers = "off"
        case disabled
        case ready, picked, pick, rules, classifier, intentSure, effort
        case context, compact, levels, fast, ultra, auto, unlists, redact
        case memberInfo, offers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        ref = try c.decodeIfPresent(String.self, forKey: .ref) ?? "group/\(id)"
        note = try c.decodeIfPresent(String.self, forKey: .note)
        members = try c.decodeIfPresent([String].self, forKey: .members) ?? []
        match = try c.decodeIfPresent([String].self, forKey: .match) ?? []
        matched = try c.decodeIfPresent([String].self, forKey: .matched) ?? []
        let r1 = try c.decodeIfPresent(String.self, forKey: .routing)
        let r2 = try c.decodeIfPresent(String.self, forKey: .mode)
        routing = r1 ?? r2 ?? ""
        affinity = try c.decodeIfPresent(String.self, forKey: .affinity) ?? ""
        sink = try c.decodeIfPresent(Bool.self, forKey: .sink) ?? false
        noSink = try c.decodeIfPresent(Bool.self, forKey: .noSink) ?? false
        firstToken = try c.decodeIfPresent(Int.self, forKey: .firstToken) ?? 0
        patience = try c.decodeIfPresent(Int.self, forKey: .patience) ?? 0
        if let arr = try? c.decodeIfPresent([String].self, forKey: .offMembers) {
            offMembers = arr
            disabled = try c.decodeIfPresent(Bool.self, forKey: .disabled) ?? false
        } else if let boolVal = try? c.decodeIfPresent(Bool.self, forKey: .offMembers) {
            offMembers = []
            disabled = boolVal
        } else {
            offMembers = []
            disabled = try c.decodeIfPresent(Bool.self, forKey: .disabled) ?? false
        }
        ready = try c.decodeIfPresent(Bool.self, forKey: .ready) ?? false
        picked = try c.decodeIfPresent(String.self, forKey: .picked)
        pick = try c.decodeIfPresent(String.self, forKey: .pick)
        rules = try c.decodeIfPresent([RemoteGroupRule].self, forKey: .rules) ?? []
        classifier = try c.decodeIfPresent(String.self, forKey: .classifier)
        intentSure = try c.decodeIfPresent(Double.self, forKey: .intentSure)
        effort = try c.decodeIfPresent(String.self, forKey: .effort)
        context = try c.decodeIfPresent(Int.self, forKey: .context) ?? 0
        compact = try c.decodeIfPresent(Int.self, forKey: .compact) ?? 0
        levels = try c.decodeIfPresent([String].self, forKey: .levels) ?? []
        fast = try c.decodeIfPresent([String].self, forKey: .fast) ?? []
        ultra = try c.decodeIfPresent([String].self, forKey: .ultra) ?? []
        auto = try c.decodeIfPresent(Bool.self, forKey: .auto) ?? false
        unlists = try c.decodeIfPresent(Bool.self, forKey: .unlists) ?? false
        redact = try c.decodeIfPresent(String.self, forKey: .redact) ?? ""
        memberInfo = try c.decodeIfPresent([RemoteGroupMemberInfo].self, forKey: .memberInfo) ?? []
        offers = try c.decodeIfPresent([String].self, forKey: .offers) ?? []
    }

    var isOff: Bool { disabled }
    var effectiveMode: String { routing }
}

// MARK: - /api/gateway/trace & /api/gateway/history & /api/gateway/call

struct RemoteTraceResponse: Decodable {
    let seq: Int64
    let routes: [RemoteRoute]
    let totals: RemoteTraceTotals
    let ids: [Int64]
    let mine: Bool
    let now: String?

    enum CodingKeys: String, CodingKey {
        case seq, routes, totals, ids, mine, now
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seq = try c.decodeIfPresent(Int64.self, forKey: .seq) ?? 0
        routes = try c.decodeIfPresent([RemoteRoute].self, forKey: .routes) ?? []
        totals = try c.decodeIfPresent(RemoteTraceTotals.self, forKey: .totals) ?? RemoteTraceTotals()
        ids = try c.decodeIfPresent([Int64].self, forKey: .ids) ?? []
        mine = try c.decodeIfPresent(Bool.self, forKey: .mine) ?? false
        now = try c.decodeIfPresent(String.self, forKey: .now)
    }
}

struct RemoteHistoryResponse: Decodable {
    let days: [String]
    let routes: [RemoteRoute]
    let cut: Bool

    enum CodingKeys: String, CodingKey {
        case days, routes, cut
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        days = try c.decodeIfPresent([String].self, forKey: .days) ?? []
        routes = try c.decodeIfPresent([RemoteRoute].self, forKey: .routes) ?? []
        cut = try c.decodeIfPresent(Bool.self, forKey: .cut) ?? false
    }
}

struct RemoteTraceTotals: Decodable, Equatable {
    var requests: Int = 0
    var rerouted: Int = 0
    var errors: Int = 0
}

struct RemoteRouteGroupRef: Decodable, Equatable {
    let id: String?
    let name: String?
    let ref: String?
    let mode: String?
}

struct RemoteRouteTry: Decodable, Identifiable, Equatable {
    var uniqueID: String { "\(id)-\(status)-\(ms)" }
    let id: String
    let model: String?
    let done: Bool
    let status: Int
    let ms: Int64
    let ttft: Int64?
    let error: String?
    let fail: String?

    enum CodingKeys: String, CodingKey {
        case id, model, done, status, ms, ttft, error, fail
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        model = try c.decodeIfPresent(String.self, forKey: .model)
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        status = try c.decodeIfPresent(Int.self, forKey: .status) ?? 0
        ms = try c.decodeIfPresent(Int64.self, forKey: .ms) ?? 0
        ttft = try c.decodeIfPresent(Int64.self, forKey: .ttft)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        fail = try c.decodeIfPresent(String.self, forKey: .fail)
    }
}

struct RemoteRouteMasked: Decodable, Equatable {
    let n: Int
    let distinct: Int
    let warned: Int?
    let key: String?

    enum CodingKeys: String, CodingKey {
        case n, distinct, warned, key
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        n = try c.decodeIfPresent(Int.self, forKey: .n) ?? 0
        distinct = try c.decodeIfPresent(Int.self, forKey: .distinct) ?? 0
        warned = try c.decodeIfPresent(Int.self, forKey: .warned)
        key = try c.decodeIfPresent(String.self, forKey: .key)
    }
}

struct RemoteRoute: Decodable, Identifiable, Equatable {
    let id: Int64
    let seq: Int64
    let time: String
    let agent: String
    let model: String
    let provider: String
    let group: RemoteRouteGroupRef?
    let tries: [RemoteRouteTry]
    let masked: RemoteRouteMasked?
    let done: Bool
    let status: Int
    let error: String?
    let fail: String?
    let canceled: Bool
    let ms: Int64
    let tokens: Int
    let out: Int
    let ttft: Int64
    let cost: Double
    let priced: Bool
    let callerKeyName: String?

    enum CodingKeys: String, CodingKey {
        case id, seq, time, agent, model, provider, group, tries, masked
        case done, status, error, fail, canceled, ms, tokens, out, ttft, cost, priced, callerKeyName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int64.self, forKey: .id) ?? 0
        seq = try c.decodeIfPresent(Int64.self, forKey: .seq) ?? 0
        time = try c.decodeIfPresent(String.self, forKey: .time) ?? ""
        agent = try c.decodeIfPresent(String.self, forKey: .agent) ?? ""
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? ""
        group = try c.decodeIfPresent(RemoteRouteGroupRef.self, forKey: .group)
        tries = try c.decodeIfPresent([RemoteRouteTry].self, forKey: .tries) ?? []
        masked = try c.decodeIfPresent(RemoteRouteMasked.self, forKey: .masked)
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        status = try c.decodeIfPresent(Int.self, forKey: .status) ?? 0
        error = try c.decodeIfPresent(String.self, forKey: .error)
        fail = try c.decodeIfPresent(String.self, forKey: .fail)
        canceled = try c.decodeIfPresent(Bool.self, forKey: .canceled) ?? false
        ms = try c.decodeIfPresent(Int64.self, forKey: .ms) ?? 0
        tokens = try c.decodeIfPresent(Int.self, forKey: .tokens) ?? 0
        out = try c.decodeIfPresent(Int.self, forKey: .out) ?? 0
        ttft = try c.decodeIfPresent(Int64.self, forKey: .ttft) ?? 0
        cost = try c.decodeIfPresent(Double.self, forKey: .cost) ?? 0
        priced = try c.decodeIfPresent(Bool.self, forKey: .priced) ?? false
        callerKeyName = try c.decodeIfPresent(String.self, forKey: .callerKeyName)
    }

    var isError: Bool {
        done && !canceled && (status >= 400 || !(error ?? "").isEmpty || !(fail ?? "").isEmpty)
    }
}

struct RemoteGatewayCallDetail: Decodable {
    let requestBody: String?
    let responseBody: String?
    let requestTruncated: Bool?
    let responseTruncated: Bool?
}

// MARK: - /api/usage & /api/usage/quotas

struct RemoteUsageResponse: Decodable {
    let period: String
    let since: String?
    let calls: Int
    let errors: Int
    let retried: Int
    let canceled: Int
    let input: Int
    let output: Int
    let cacheRead: Int
    let cacheWrite: Int
    let reasoning: Int
    let cost: Double
    let unpriced: Int
    let timed: Int
    let ttftMs: Int64
    let bucket: String
    let series: [RemoteUsagePoint]
    let agents: [RemoteUsageGroup]
    let models: [RemoteUsageGroup]
    let accounts: [RemoteUsageGroup]
    let callerKeys: [RemoteUsageGroup]

    enum CodingKeys: String, CodingKey {
        case period, since, calls, errors, retried, canceled
        case input, output
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
        case reasoning, cost, unpriced, timed
        case ttftMs = "ttft_ms"
        case bucket, series, agents, models, accounts, callerKeys
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        period = try c.decodeIfPresent(String.self, forKey: .period) ?? "today"
        since = try c.decodeIfPresent(String.self, forKey: .since)
        calls = try c.decodeIfPresent(Int.self, forKey: .calls) ?? 0
        errors = try c.decodeIfPresent(Int.self, forKey: .errors) ?? 0
        retried = try c.decodeIfPresent(Int.self, forKey: .retried) ?? 0
        canceled = try c.decodeIfPresent(Int.self, forKey: .canceled) ?? 0
        input = try c.decodeIfPresent(Int.self, forKey: .input) ?? 0
        output = try c.decodeIfPresent(Int.self, forKey: .output) ?? 0
        cacheRead = try c.decodeIfPresent(Int.self, forKey: .cacheRead) ?? 0
        cacheWrite = try c.decodeIfPresent(Int.self, forKey: .cacheWrite) ?? 0
        reasoning = try c.decodeIfPresent(Int.self, forKey: .reasoning) ?? 0
        cost = try c.decodeIfPresent(Double.self, forKey: .cost) ?? 0
        unpriced = try c.decodeIfPresent(Int.self, forKey: .unpriced) ?? 0
        timed = try c.decodeIfPresent(Int.self, forKey: .timed) ?? 0
        ttftMs = try c.decodeIfPresent(Int64.self, forKey: .ttftMs) ?? 0
        bucket = try c.decodeIfPresent(String.self, forKey: .bucket) ?? "hour"
        series = try c.decodeIfPresent([RemoteUsagePoint].self, forKey: .series) ?? []
        agents = try c.decodeIfPresent([RemoteUsageGroup].self, forKey: .agents) ?? []
        models = try c.decodeIfPresent([RemoteUsageGroup].self, forKey: .models) ?? []
        accounts = try c.decodeIfPresent([RemoteUsageGroup].self, forKey: .accounts) ?? []
        callerKeys = try c.decodeIfPresent([RemoteUsageGroup].self, forKey: .callerKeys) ?? []
    }
}

struct RemoteUsagePoint: Decodable, Identifiable, Equatable {
    var id: String { label + "|" + time }
    let label: String
    let time: String
    let calls: Int
    let errors: Int
    let input: Int
    let output: Int
    let cost: Double

    enum CodingKeys: String, CodingKey {
        case label, time, calls, errors, input, output, cost
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        time = try c.decodeIfPresent(String.self, forKey: .time) ?? ""
        calls = try c.decodeIfPresent(Int.self, forKey: .calls) ?? 0
        errors = try c.decodeIfPresent(Int.self, forKey: .errors) ?? 0
        input = try c.decodeIfPresent(Int.self, forKey: .input) ?? 0
        output = try c.decodeIfPresent(Int.self, forKey: .output) ?? 0
        cost = try c.decodeIfPresent(Double.self, forKey: .cost) ?? 0
    }
}

struct RemoteUsageGroup: Decodable, Identifiable, Equatable {
    var uniqueID: String { "\(id)|\(sub ?? "")|\(account ?? "")" }
    let id: String
    let name: String
    let sub: String?
    let provider: String?
    let model: String?
    let account: String?
    let calls: Int
    let errors: Int
    let input: Int
    let output: Int
    let cacheRead: Int
    let cost: Double

    enum CodingKeys: String, CodingKey {
        case id, name, sub, provider, model, account, calls, errors, input, output
        case cacheRead = "cache_read"
        case cost
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        sub = try c.decodeIfPresent(String.self, forKey: .sub)
        provider = try c.decodeIfPresent(String.self, forKey: .provider)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        account = try c.decodeIfPresent(String.self, forKey: .account)
        calls = try c.decodeIfPresent(Int.self, forKey: .calls) ?? 0
        errors = try c.decodeIfPresent(Int.self, forKey: .errors) ?? 0
        input = try c.decodeIfPresent(Int.self, forKey: .input) ?? 0
        output = try c.decodeIfPresent(Int.self, forKey: .output) ?? 0
        cacheRead = try c.decodeIfPresent(Int.self, forKey: .cacheRead) ?? 0
        cost = try c.decodeIfPresent(Double.self, forKey: .cost) ?? 0
    }
}

struct RemoteUsageQuota: Decodable, Identifiable, Equatable {
    var id: String { "\(provider)|\(user ?? "")|\(plan ?? "")" }
    let provider: String
    let name: String
    let icon: String
    let plan: String?
    let user: String?
    let windows: [RemoteQuotaWindow]
    let balance: String?
    let error: String?
    let pluginError: String?
    let readAt: String?
    let until: String?
    let renew: String?

    enum CodingKeys: String, CodingKey {
        case provider, name, icon, plan, user, windows, balance, error, pluginError, readAt, until, renew
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? provider
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? ""
        plan = try c.decodeIfPresent(String.self, forKey: .plan)
        user = try c.decodeIfPresent(String.self, forKey: .user)
        windows = try c.decodeIfPresent([RemoteQuotaWindow].self, forKey: .windows) ?? []
        balance = try c.decodeIfPresent(String.self, forKey: .balance)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        pluginError = try c.decodeIfPresent(String.self, forKey: .pluginError)
        readAt = try c.decodeIfPresent(String.self, forKey: .readAt)
        until = try c.decodeIfPresent(String.self, forKey: .until)
        renew = try c.decodeIfPresent(String.self, forKey: .renew)
    }
}

struct RemoteQuotaWindow: Decodable, Identifiable, Equatable {
    var id: String { name + (display ?? "") }
    let unlimited: Bool
    let name: String
    let used: Double
    let resetsAt: String?
    let resetSecs: Int64?
    let display: String?
    let text: Bool
    let amount: Double?
    let limit: Double?
    let unit: String?

    enum CodingKeys: String, CodingKey {
        case unlimited, name, used, resetsAt, resetSecs, display, text, amount, limit, unit
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        unlimited = try c.decodeIfPresent(Bool.self, forKey: .unlimited) ?? false
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        used = try c.decodeIfPresent(Double.self, forKey: .used) ?? 0
        resetsAt = try c.decodeIfPresent(String.self, forKey: .resetsAt)
        resetSecs = try c.decodeIfPresent(Int64.self, forKey: .resetSecs)
        display = try c.decodeIfPresent(String.self, forKey: .display)
        text = try c.decodeIfPresent(Bool.self, forKey: .text) ?? false
        amount = try c.decodeIfPresent(Double.self, forKey: .amount)
        limit = try c.decodeIfPresent(Double.self, forKey: .limit)
        unit = try c.decodeIfPresent(String.self, forKey: .unit)
    }
}

// MARK: - /api/masking/*

struct RemoteMaskingSummary: Decodable {
    let requests: Int
    let n: Int
    let distinct: Int
    let warned: Int
    let blocked: Int
    let by: [String: Int]

    enum CodingKeys: String, CodingKey {
        case requests, n, distinct, warned, blocked, by
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        requests = try c.decodeIfPresent(Int.self, forKey: .requests) ?? 0
        n = try c.decodeIfPresent(Int.self, forKey: .n) ?? 0
        distinct = try c.decodeIfPresent(Int.self, forKey: .distinct) ?? 0
        warned = try c.decodeIfPresent(Int.self, forKey: .warned) ?? 0
        blocked = try c.decodeIfPresent(Int.self, forKey: .blocked) ?? 0
        by = try c.decodeIfPresent([String: Int].self, forKey: .by) ?? [:]
    }
}

struct RemoteMaskingRecordsPage: Decodable {
    let records: [RemoteMaskingRecord]
    let more: Bool

    enum CodingKeys: String, CodingKey {
        case records, more
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        records = try c.decodeIfPresent([RemoteMaskingRecord].self, forKey: .records) ?? []
        more = try c.decodeIfPresent(Bool.self, forKey: .more) ?? false
    }
}

struct RemoteMaskingRecord: Decodable, Identifiable, Equatable {
    var id: String { key }
    let key: String
    let t: String
    let what: String
    let agent: String?
    let provider: String?
    let model: String?
    let n: Int
    let blocked: Bool
    let values: [RemoteMaskingValue]

    enum CodingKeys: String, CodingKey {
        case key, t, what, agent, provider, model, n, blocked, values
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decodeIfPresent(String.self, forKey: .key) ?? UUID().uuidString
        t = try c.decodeIfPresent(String.self, forKey: .t) ?? ""
        what = try c.decodeIfPresent(String.self, forKey: .what) ?? "chat"
        agent = try c.decodeIfPresent(String.self, forKey: .agent)
        provider = try c.decodeIfPresent(String.self, forKey: .provider)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        n = try c.decodeIfPresent(Int.self, forKey: .n) ?? 0
        blocked = try c.decodeIfPresent(Bool.self, forKey: .blocked) ?? false
        values = try c.decodeIfPresent([RemoteMaskingValue].self, forKey: .values) ?? []
    }
}

struct RemoteMaskingValue: Decodable, Identifiable, Equatable {
    var id: String { p }
    let p: String
    let k: String
    let b: String
    let h: String?
    let l: Int
    let n: Int
    let a: String?
    let known: Bool

    enum CodingKeys: String, CodingKey {
        case p, k, b, h, l, n, a, known
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        p = try c.decodeIfPresent(String.self, forKey: .p) ?? ""
        k = try c.decodeIfPresent(String.self, forKey: .k) ?? ""
        b = try c.decodeIfPresent(String.self, forKey: .b) ?? ""
        h = try c.decodeIfPresent(String.self, forKey: .h)
        l = try c.decodeIfPresent(Int.self, forKey: .l) ?? 0
        n = try c.decodeIfPresent(Int.self, forKey: .n) ?? 0
        a = try c.decodeIfPresent(String.self, forKey: .a)
        known = try c.decodeIfPresent(Bool.self, forKey: .known) ?? false
    }
}

struct RemoteMaskingPreview: Decodable, Equatable {
    let text: String
    let hits: [RemoteMaskingHit]
    let off: Bool

    enum CodingKeys: String, CodingKey {
        case text, hits, off
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        hits = try c.decodeIfPresent([RemoteMaskingHit].self, forKey: .hits) ?? []
        off = try c.decodeIfPresent(Bool.self, forKey: .off) ?? false
    }
}

struct RemoteMaskingHit: Decodable, Identifiable, Equatable {
    var id: String { "\(kind)|\(placeholder)|\(len)" }
    let kind: String
    let by: String
    let action: String?
    let placeholder: String
    let head: String?
    let len: Int
}

// MARK: - /api/caller-keys

struct RemoteCallerKeysResponse: Decodable {
    let keys: [RemoteCallerKey]

    enum CodingKeys: String, CodingKey {
        case keys
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keys = try c.decodeIfPresent([RemoteCallerKey].self, forKey: .keys) ?? []
    }
}

struct RemoteCallerKey: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let masked: String
    let off: Bool
    let allModels: Bool
    let models: [String]
    let limit: RemoteCallerLimit?
    let used: RemoteCallerUsage?
    let readOnly: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, masked, off, allModels, models, limit, used, readOnly
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        masked = try c.decodeIfPresent(String.self, forKey: .masked) ?? ""
        off = try c.decodeIfPresent(Bool.self, forKey: .off) ?? false
        limit = try c.decodeIfPresent(RemoteCallerLimit.self, forKey: .limit)
        used = try c.decodeIfPresent(RemoteCallerUsage.self, forKey: .used)
        readOnly = try c.decodeIfPresent(Bool.self, forKey: .readOnly) ?? false
        allModels = try c.decodeIfPresent(Bool.self, forKey: .allModels) ?? false
        models = try c.decodeIfPresent([String].self, forKey: .models) ?? []
    }
}

struct RemoteAgentFastResponse: Decodable {
    let fast: Bool
    let ultra: Bool
}

struct RemotePluginListing: Decodable, Identifiable, Equatable {
    var id: String { package }
    let package: String
    let name: String
    let icon: String?
    let providers: [String]
    let community: Bool
    let replaces: String?
    let kind: String?
    let summary: [String: String]

    enum CodingKeys: String, CodingKey {
        case package, name, icon, providers, community, replaces, kind, summary
    }

    init(
        package: String,
        name: String,
        icon: String? = nil,
        providers: [String] = [],
        community: Bool = true,
        replaces: String? = nil,
        kind: String? = nil,
        summary: [String: String] = [:]
    ) {
        self.package = package
        self.name = name
        self.icon = icon
        self.providers = providers
        self.community = community
        self.replaces = replaces
        self.kind = kind
        self.summary = summary
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        package = try c.decodeIfPresent(String.self, forKey: .package) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? package
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        providers = try c.decodeIfPresent([String].self, forKey: .providers) ?? []
        community = try c.decodeIfPresent(Bool.self, forKey: .community) ?? false
        replaces = try c.decodeIfPresent(String.self, forKey: .replaces)
        kind = try c.decodeIfPresent(String.self, forKey: .kind)
        summary = try c.decodeIfPresent([String: String].self, forKey: .summary) ?? [:]
    }

    var localizedSummary: String {
        summary["zh"] ?? summary["zh-CN"] ?? summary["en"] ?? ""
    }
}

struct RemotePluginListingsResponse: Decodable {
    let listings: [RemotePluginListing]

    enum CodingKeys: String, CodingKey {
        case listings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        listings = try c.decodeIfPresent([RemotePluginListing].self, forKey: .listings) ?? []
    }
}
