import Foundation

// MARK: - /api/state & /api/settings

struct RemoteStateResponse: Decodable {
    let agents: [RemoteAgent]
    let served: Int
    let notice: String?
    let settings: RemoteSettingsState
    let fx: RemoteFXRate?
    let gatewayOther: RemoteGatewaySkew?
    let gatewayHeld: RemotePortHeld?

    enum CodingKeys: String, CodingKey {
        case agents, served, notice, settings, fx, gatewayOther, gatewayHeld
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        agents = try c.decodeIfPresent([RemoteAgent].self, forKey: .agents) ?? []
        served = try c.decodeIfPresent(Int.self, forKey: .served) ?? 0
        notice = try c.decodeIfPresent(String.self, forKey: .notice)
        settings = try c.decodeIfPresent(RemoteSettingsState.self, forKey: .settings) ?? RemoteSettingsState()
        fx = try c.decodeIfPresent(RemoteFXRate.self, forKey: .fx)
        gatewayOther = try c.decodeIfPresent(RemoteGatewaySkew.self, forKey: .gatewayOther)
        gatewayHeld = try c.decodeIfPresent(RemotePortHeld.self, forKey: .gatewayHeld)
    }
}

struct RemoteAgent: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String?
    let present: Bool
    let connected: Bool
    let model: String?
    let ready: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, icon, present, connected, model, ready
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        present = try c.decodeIfPresent(Bool.self, forKey: .present) ?? false
        connected = try c.decodeIfPresent(Bool.self, forKey: .connected) ?? false
        model = try c.decodeIfPresent(String.self, forKey: .model)
        ready = try c.decodeIfPresent(Bool.self, forKey: .ready) ?? false
    }
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
    var theme: String = "system"
    var lang: String = "system"
    var currency: String = "usd"
    var totalCurrency: String = "usd"
    var chineseUnits: Bool = false

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

    // Network & Bark (internal/gui/api.go settingsJSON)
    var lan: Bool = false
    var allowIPs: [String] = []
    var mtls: Bool = false
    var port: Int = 3425
    var barkServer: String = ""
    var barkDaily: String = ""
    var barkKeySet: Bool = false

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
        case theme, lang, currency, totalCurrency, chineseUnits
        case redact, redactPersonal, redactShape, redactWords
        case redactWordsAnyCase, redactWordsWhole, redactRules, redactActions, redactAllow, redactRouteTo
        case lan, allowIPs, mtls, port
        case barkServer, barkDaily, barkKeySet
        case version, gateway, publicURL, onNetwork, gatewayOn, gatewayWhy, gatewayPaused
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? "system"
        lang = try c.decodeIfPresent(String.self, forKey: .lang) ?? "system"
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? "usd"
        totalCurrency = try c.decodeIfPresent(String.self, forKey: .totalCurrency) ?? "usd"
        chineseUnits = try c.decodeIfPresent(Bool.self, forKey: .chineseUnits) ?? false

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

        lan = try c.decodeIfPresent(Bool.self, forKey: .lan) ?? false
        allowIPs = try c.decodeIfPresent([String].self, forKey: .allowIPs) ?? []
        mtls = try c.decodeIfPresent(Bool.self, forKey: .mtls) ?? false
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 3425
        barkServer = try c.decodeIfPresent(String.self, forKey: .barkServer) ?? ""
        barkDaily = try c.decodeIfPresent(String.self, forKey: .barkDaily) ?? ""
        barkKeySet = try c.decodeIfPresent(Bool.self, forKey: .barkKeySet) ?? false

        version = try c.decodeIfPresent(String.self, forKey: .version) ?? ""
        gateway = try c.decodeIfPresent(String.self, forKey: .gateway) ?? ""
        publicURL = try c.decodeIfPresent(String.self, forKey: .publicURL) ?? ""
        onNetwork = try c.decodeIfPresent(Bool.self, forKey: .onNetwork) ?? false
        gatewayOn = try c.decodeIfPresent(Bool.self, forKey: .gatewayOn) ?? false
        gatewayWhy = try c.decodeIfPresent(String.self, forKey: .gatewayWhy) ?? ""
        gatewayPaused = try c.decodeIfPresent(Bool.self, forKey: .gatewayPaused) ?? false
    }
}

// MARK: - /api/providers

struct RemoteProvidersResponse: Decodable {
    let providers: [RemoteProvider]
    let gateway: RemoteGatewayStatus?
    let codexDaemon: String?
    let codexApp: String?

    enum CodingKeys: String, CodingKey {
        case providers, gateway, codexDaemon, codexApp
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        providers = try c.decodeIfPresent([RemoteProvider].self, forKey: .providers) ?? []
        gateway = try c.decodeIfPresent(RemoteGatewayStatus.self, forKey: .gateway)
        codexDaemon = try c.decodeIfPresent(String.self, forKey: .codexDaemon)
        codexApp = try c.decodeIfPresent(String.self, forKey: .codexApp)
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
    let ready: Bool
    let off: Bool
    let unlisted: Bool
    let routing: String
    let affinity: String
    let exposed: Int
    let models: [RemoteProviderModel]
    let key: RemoteProviderKey?
    let keyList: [RemoteKeyInfo]
    let account: RemoteProviderAccount?
    let listError: String?
    let priceRate: Double?

    enum CodingKeys: String, CodingKey {
        case id, name, icon, preset, host, chat, responses, anthropic, gemini
        case ready, off, unlisted, routing, affinity, exposed, models
        case key, keyList, account, listError, priceRate
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
        ready = try c.decodeIfPresent(Bool.self, forKey: .ready) ?? false
        off = try c.decodeIfPresent(Bool.self, forKey: .off) ?? false
        unlisted = try c.decodeIfPresent(Bool.self, forKey: .unlisted) ?? false
        routing = try c.decodeIfPresent(String.self, forKey: .routing) ?? ""
        affinity = try c.decodeIfPresent(String.self, forKey: .affinity) ?? ""
        exposed = try c.decodeIfPresent(Int.self, forKey: .exposed) ?? 0
        models = try c.decodeIfPresent([RemoteProviderModel].self, forKey: .models) ?? []
        key = try c.decodeIfPresent(RemoteProviderKey.self, forKey: .key)
        keyList = try c.decodeIfPresent([RemoteKeyInfo].self, forKey: .keyList) ?? []
        account = try c.decodeIfPresent(RemoteProviderAccount.self, forKey: .account)
        listError = try c.decodeIfPresent(String.self, forKey: .listError)
        priceRate = try c.decodeIfPresent(Double.self, forKey: .priceRate)
    }

    var primaryEndpointPreview: String {
        for url in [chat, anthropic, responses, gemini, host] where !url.isEmpty {
            return url
        }
        return "订阅账号"
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
    let rest: RemoteKeyRest?

    enum CodingKeys: String, CodingKey {
        case id, name, masked, active, on, rest
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name)
        masked = try c.decodeIfPresent(String.self, forKey: .masked) ?? ""
        active = try c.decodeIfPresent(Bool.self, forKey: .active) ?? false
        on = try c.decodeIfPresent(Bool.self, forKey: .on) ?? false
        rest = try c.decodeIfPresent(RemoteKeyRest.self, forKey: .rest)
    }
}

struct RemoteKeyRest: Decodable, Equatable {
    let reason: String?
    let until: String?
}

struct RemoteProviderAccount: Decodable, Equatable {
    let agent: String?
    let agentName: String?
    let user: String?
    let plan: String?
}

struct RemoteProviderModel: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let on: Bool
    let images: Bool
    let context: Int?
    let output: Int?
    let free: Bool
    let zero: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, on, images, context, output, free, zero
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        on = try c.decodeIfPresent(Bool.self, forKey: .on) ?? false
        images = try c.decodeIfPresent(Bool.self, forKey: .images) ?? false
        context = try c.decodeIfPresent(Int.self, forKey: .context)
        output = try c.decodeIfPresent(Int.self, forKey: .output)
        free = try c.decodeIfPresent(Bool.self, forKey: .free) ?? false
        zero = try c.decodeIfPresent(Bool.self, forKey: .zero) ?? false
    }
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

// MARK: - /api/groups

struct RemoteGroupsResponse: Decodable {
    let groups: [RemoteRoutingGroup]
    let found: Bool

    enum CodingKeys: String, CodingKey {
        case groups, found
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        groups = try c.decodeIfPresent([RemoteRoutingGroup].self, forKey: .groups) ?? []
        found = try c.decodeIfPresent(Bool.self, forKey: .found) ?? false
    }
}

struct RemoteRoutingGroup: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let ref: String
    let note: String?
    let members: [String]
    let mode: String?
    let off: Bool
    let ready: Bool
    let picked: String?

    enum CodingKeys: String, CodingKey {
        case id, name, ref, note, members, mode, off, ready, picked
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        ref = try c.decodeIfPresent(String.self, forKey: .ref) ?? "group/\(id)"
        note = try c.decodeIfPresent(String.self, forKey: .note)
        members = try c.decodeIfPresent([String].self, forKey: .members) ?? []
        mode = try c.decodeIfPresent(String.self, forKey: .mode)
        off = try c.decodeIfPresent(Bool.self, forKey: .off) ?? false
        ready = try c.decodeIfPresent(Bool.self, forKey: .ready) ?? false
        picked = try c.decodeIfPresent(String.self, forKey: .picked)
    }
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

    enum CodingKeys: String, CodingKey {
        case id, name, masked, off, allModels, models
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        masked = try c.decodeIfPresent(String.self, forKey: .masked) ?? ""
        off = try c.decodeIfPresent(Bool.self, forKey: .off) ?? false
        allModels = try c.decodeIfPresent(Bool.self, forKey: .allModels) ?? false
        models = try c.decodeIfPresent([String].self, forKey: .models) ?? []
    }
}
