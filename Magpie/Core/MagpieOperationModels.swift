import Foundation

// MARK: - Caller Keys & Masking Operations

struct RemoteCallerKeyChangeResponse: Decodable {
    let keys: [RemoteCallerKey]
    let secret: String?
}

struct RemoteCallerLimit: Decodable, Equatable {
    let period: String
    let tokens: Int64?
    let cost: Double?
}

struct RemoteCallerUsage: Decodable, Equatable {
    let period: String
    let tokens: Int64
    let cost: Double
    let reset: String
}

struct RemoteMaskingSent: Decodable {
    let body: String
}

struct RemoteMaskingValues: Decodable {
    let values: [String: String]
}

// MARK: - Warmup & Check-in Operations

struct RemoteWarmResponse: Decodable {
    let results: [RemoteWarmResult]
}

struct RemoteWarmResult: Decodable {
    let user: String?
    let skip: String?
    let error: String?
}

struct RemoteCheckinResult: Decodable {
    let user: String?
    let outcome: String
    let msg: String?
}

// MARK: - Named Proxies (`internal/gui/proxies.go`)

struct RemoteProxyUse: Decodable, Equatable, Identifiable {
    var id: String { "\(whereTarget ?? "")|\(provider ?? "")|\(account ?? "")" }
    let whereTarget: String?
    let provider: String?
    let account: String?

    enum CodingKeys: String, CodingKey {
        case whereTarget = "where"
        case provider
        case account
    }
}

struct RemoteProxyTestResult: Decodable, Equatable {
    let ok: Bool
    let ms: Int64?
    let ip: String?
    let loc: String?
    let error: String?
    let at: Int64?

    enum CodingKeys: String, CodingKey {
        case ok, ms, ip, loc, error, at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        ms = try c.decodeIfPresent(Int64.self, forKey: .ms)
        ip = try c.decodeIfPresent(String.self, forKey: .ip)
        loc = try c.decodeIfPresent(String.self, forKey: .loc)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        at = try c.decodeIfPresent(Int64.self, forKey: .at)
    }
}

struct RemoteSavedProxy: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let url: String
    let user: String
    let hasPass: Bool
    let uses: [RemoteProxyUse]
    let check: RemoteProxyTestResult?

    enum CodingKeys: String, CodingKey {
        case id, name, url, user, hasPass, uses, check
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        user = try c.decodeIfPresent(String.self, forKey: .user) ?? ""
        hasPass = try c.decodeIfPresent(Bool.self, forKey: .hasPass) ?? false
        uses = try c.decodeIfPresent([RemoteProxyUse].self, forKey: .uses) ?? []
        check = try c.decodeIfPresent(RemoteProxyTestResult.self, forKey: .check)
    }
}

// MARK: - Backup, AutoBackup & WebDAV/S3/GitHub Sync (`internal/gui/backup.go`, `internal/davsync/davsync.go`)

struct RemoteBackupExportResponse: Decodable, Equatable {
    let path: String
    let providers: Int
    let profiles: Int
    let agents: Int
    let library: Bool
    let signIns: Int

    enum CodingKeys: String, CodingKey {
        case path, providers, profiles, agents, library, signIns
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? ""
        providers = try c.decodeIfPresent(Int.self, forKey: .providers) ?? 0
        profiles = try c.decodeIfPresent(Int.self, forKey: .profiles) ?? 0
        agents = try c.decodeIfPresent(Int.self, forKey: .agents) ?? 0
        library = try c.decodeIfPresent(Bool.self, forKey: .library) ?? false
        signIns = try c.decodeIfPresent(Int.self, forKey: .signIns) ?? 0
    }
}

struct RemoteBackupRestoreResult: Decodable, Equatable {
    let providers: Int
    let profiles: Int
    let agents: Int
    let settings: Bool
    let library: Bool
    let memory: Int
    let signIns: Int
    let signInsLocked: Bool

    enum CodingKeys: String, CodingKey {
        case providers, profiles, agents, settings, library, memory, signIns, signInsLocked
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        providers = try c.decodeIfPresent(Int.self, forKey: .providers) ?? 0
        profiles = try c.decodeIfPresent(Int.self, forKey: .profiles) ?? 0
        agents = try c.decodeIfPresent(Int.self, forKey: .agents) ?? 0
        settings = try c.decodeIfPresent(Bool.self, forKey: .settings) ?? false
        library = try c.decodeIfPresent(Bool.self, forKey: .library) ?? false
        memory = try c.decodeIfPresent(Int.self, forKey: .memory) ?? 0
        signIns = try c.decodeIfPresent(Int.self, forKey: .signIns) ?? 0
        signInsLocked = try c.decodeIfPresent(Bool.self, forKey: .signInsLocked) ?? false
    }
}

struct RemoteAutoBackupItem: Decodable, Equatable, Identifiable {
    var id: String { name }
    let name: String
    let made: String
    let reason: String
    let app: String?
    let size: Int64
    let providers: Int
    let library: Bool
    let signIns: Bool

    enum CodingKeys: String, CodingKey {
        case name, made, reason, app, size, providers, library, signIns
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        made = try c.decodeIfPresent(String.self, forKey: .made) ?? ""
        reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? "auto"
        app = try c.decodeIfPresent(String.self, forKey: .app)
        size = try c.decodeIfPresent(Int64.self, forKey: .size) ?? 0
        providers = try c.decodeIfPresent(Int.self, forKey: .providers) ?? 0
        library = try c.decodeIfPresent(Bool.self, forKey: .library) ?? false
        signIns = try c.decodeIfPresent(Bool.self, forKey: .signIns) ?? false
    }
}

struct RemoteAutoBackupView: Decodable, Equatable {
    var on: Bool = true
    var hours: Int = 24
    var keep: Int = 7
    var dir: String = ""
    var custom: Bool = false
    var error: String?
    var backups: [RemoteAutoBackupItem] = []
    var signIns: Bool = false
    var passphrase: Bool = false

    init() {}

    enum CodingKeys: String, CodingKey {
        case on, hours, keep, dir, custom, error, backups, signIns, passphrase, view
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.view), let nested = try c.decodeIfPresent(RemoteAutoBackupView.self, forKey: .view) {
            self = nested
            return
        }
        on = try c.decodeIfPresent(Bool.self, forKey: .on) ?? true
        hours = try c.decodeIfPresent(Int.self, forKey: .hours) ?? 24
        keep = try c.decodeIfPresent(Int.self, forKey: .keep) ?? 7
        dir = try c.decodeIfPresent(String.self, forKey: .dir) ?? ""
        custom = try c.decodeIfPresent(Bool.self, forKey: .custom) ?? false
        error = try c.decodeIfPresent(String.self, forKey: .error)
        backups = try c.decodeIfPresent([RemoteAutoBackupItem].self, forKey: .backups) ?? []
        signIns = try c.decodeIfPresent(Bool.self, forKey: .signIns) ?? false
        passphrase = try c.decodeIfPresent(Bool.self, forKey: .passphrase) ?? false
    }
}

struct RemoteDavSyncView: Decodable, Equatable {
    var on: Bool = false
    var url: String = ""
    var user: String = ""
    var passwordSet: Bool = false
    var passphraseSet: Bool = false
    var keys: Bool = true
    var agents: Bool = true
    var kind: String = "webdav"
    var endpoint: String = ""
    var region: String = ""
    var pathStyle: Bool = false
    var branch: String = ""
    var library: Bool = true
    var memory: Bool = true
    var providers: Bool = true
    var settings: Bool = true
    var profiles: Bool = true
    var usage: Bool = false
    var signIns: Bool = false
    var usageError: String?
    var last: String?
    var error: String?
    var auto: Int = 3
    var followServer: Bool = false
    var undo: Bool = false
    var brought: [String] = []

    init() {}

    enum CodingKeys: String, CodingKey {
        case on, url, user, passwordSet, passphraseSet, keys, agents, kind
        case endpoint, region, pathStyle, branch, library, memory, providers, settings, profiles
        case usage, signIns, usageError, last, error, auto, followServer, undo, brought
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        on = try c.decodeIfPresent(Bool.self, forKey: .on) ?? false
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        user = try c.decodeIfPresent(String.self, forKey: .user) ?? ""
        passwordSet = try c.decodeIfPresent(Bool.self, forKey: .passwordSet) ?? false
        passphraseSet = try c.decodeIfPresent(Bool.self, forKey: .passphraseSet) ?? false
        keys = try c.decodeIfPresent(Bool.self, forKey: .keys) ?? true
        agents = try c.decodeIfPresent(Bool.self, forKey: .agents) ?? true
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "webdav"
        endpoint = try c.decodeIfPresent(String.self, forKey: .endpoint) ?? ""
        region = try c.decodeIfPresent(String.self, forKey: .region) ?? ""
        pathStyle = try c.decodeIfPresent(Bool.self, forKey: .pathStyle) ?? false
        branch = try c.decodeIfPresent(String.self, forKey: .branch) ?? ""
        library = try c.decodeIfPresent(Bool.self, forKey: .library) ?? true
        memory = try c.decodeIfPresent(Bool.self, forKey: .memory) ?? true
        providers = try c.decodeIfPresent(Bool.self, forKey: .providers) ?? true
        settings = try c.decodeIfPresent(Bool.self, forKey: .settings) ?? true
        profiles = try c.decodeIfPresent(Bool.self, forKey: .profiles) ?? true
        usage = try c.decodeIfPresent(Bool.self, forKey: .usage) ?? false
        signIns = try c.decodeIfPresent(Bool.self, forKey: .signIns) ?? false
        usageError = try c.decodeIfPresent(String.self, forKey: .usageError)
        last = try c.decodeIfPresent(String.self, forKey: .last)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        auto = try c.decodeIfPresent(Int.self, forKey: .auto) ?? 3
        followServer = try c.decodeIfPresent(Bool.self, forKey: .followServer) ?? false
        undo = try c.decodeIfPresent(Bool.self, forKey: .undo) ?? false
        brought = try c.decodeIfPresent([String].self, forKey: .brought) ?? []
    }
}

// MARK: - Context & Cache Tuning (`internal/gui/tune.go`)

struct RemoteTuneSetting: Decodable, Equatable {
    let value: String
    let source: String
    let locked: String
    let ours: Bool
    let take: Bool

    enum CodingKeys: String, CodingKey {
        case value, source, locked, ours, take
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = try c.decodeIfPresent(String.self, forKey: .value) ?? ""
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
        locked = try c.decodeIfPresent(String.self, forKey: .locked) ?? ""
        ours = try c.decodeIfPresent(Bool.self, forKey: .ours) ?? false
        take = try c.decodeIfPresent(Bool.self, forKey: .take) ?? false
    }
}

struct RemoteTuneCompaction: Decodable, Equatable {
    let model: String
    let current: Int
    let window: Int
    let best: Int
    let cost: Double
    let low: Double
    let cheapest: Int?

    enum CodingKeys: String, CodingKey {
        case model, current, window, best, cost, low, cheapest
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        current = try c.decodeIfPresent(Int.self, forKey: .current) ?? 0
        window = try c.decodeIfPresent(Int.self, forKey: .window) ?? 0
        best = try c.decodeIfPresent(Int.self, forKey: .best) ?? 0
        cost = try c.decodeIfPresent(Double.self, forKey: .cost) ?? 0
        low = try c.decodeIfPresent(Double.self, forKey: .low) ?? 0
        cheapest = try c.decodeIfPresent(Int.self, forKey: .cheapest)
    }
}

struct RemoteTuneTTL: Decodable, Equatable {
    let current: String
    let best: String
    let cost: Double
    let low: Double
    let short: Double
    let hour: Double

    enum CodingKeys: String, CodingKey {
        case current, best, cost, low, short, hour
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        current = try c.decodeIfPresent(String.self, forKey: .current) ?? "5m"
        best = try c.decodeIfPresent(String.self, forKey: .best) ?? "5m"
        cost = try c.decodeIfPresent(Double.self, forKey: .cost) ?? 0
        low = try c.decodeIfPresent(Double.self, forKey: .low) ?? 0
        short = try c.decodeIfPresent(Double.self, forKey: .short) ?? 0
        hour = try c.decodeIfPresent(Double.self, forKey: .hour) ?? 0
    }
}

struct RemoteTuneAsync: Decodable, Equatable {
    let percent: Int
    let value: Int
    let window: Int
    let setting: RemoteTuneSetting?
}

struct RemoteTuneAdvice: Decodable, Equatable, Identifiable {
    var id: String { "\(knob)|\(model ?? "")" }
    let knob: String
    let model: String?
    let setting: RemoteTuneSetting
    let compact: RemoteTuneCompaction?
    let ttl: RemoteTuneTTL?
    let async: RemoteTuneAsync?
    let few: Bool

    enum CodingKeys: String, CodingKey {
        case knob, model, setting, compact, ttl, async, few
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        knob = try c.decodeIfPresent(String.self, forKey: .knob) ?? ""
        model = try c.decodeIfPresent(String.self, forKey: .model)
        setting = try c.decodeIfPresent(RemoteTuneSetting.self, forKey: .setting) ?? try JSONDecoder().decode(RemoteTuneSetting.self, from: Data("{}".utf8))
        compact = try c.decodeIfPresent(RemoteTuneCompaction.self, forKey: .compact)
        ttl = try c.decodeIfPresent(RemoteTuneTTL.self, forKey: .ttl)
        async = try c.decodeIfPresent(RemoteTuneAsync.self, forKey: .async)
        few = try c.decodeIfPresent(Bool.self, forKey: .few) ?? false
    }
}

struct RemoteTuneAgent: Decodable, Equatable, Identifiable {
    var id: String { agent }
    let agent: String
    let calls: Int
    let advice: [RemoteTuneAdvice]

    enum CodingKeys: String, CodingKey {
        case agent, calls, advice
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        agent = try c.decodeIfPresent(String.self, forKey: .agent) ?? ""
        calls = try c.decodeIfPresent(Int.self, forKey: .calls) ?? 0
        advice = try c.decodeIfPresent([RemoteTuneAdvice].self, forKey: .advice) ?? []
    }
}

struct RemoteTuneState: Decodable, Equatable {
    var days: Int = 7
    var agents: [RemoteTuneAgent] = []
    var gateway: Bool = false

    init() {}

    enum CodingKeys: String, CodingKey {
        case days, agents, gateway
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        days = try c.decodeIfPresent(Int.self, forKey: .days) ?? 7
        agents = try c.decodeIfPresent([RemoteTuneAgent].self, forKey: .agents) ?? []
        gateway = try c.decodeIfPresent(Bool.self, forKey: .gateway) ?? false
    }
}

struct RemoteClaudeCacheItem: Decodable, Equatable, Identifiable {
    var id: String { knob }
    let knob: String
    let value: String
    let locked: String

    enum CodingKeys: String, CodingKey {
        case knob, value, locked
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        knob = try c.decodeIfPresent(String.self, forKey: .knob) ?? ""
        value = try c.decodeIfPresent(String.self, forKey: .value) ?? ""
        locked = try c.decodeIfPresent(String.self, forKey: .locked) ?? ""
    }
}

// MARK: - Gateway Control & Model Pricing & Privacy Model

struct RemoteGatewayFixResponse: Decodable, Equatable {
    let ok: Bool
    let reason: String?
    let pid: Int?
    let path: String?
    let port: String?
    let version: String?
    let error: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case ok, reason, pid, path, port, version, error, name
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        pid = try c.decodeIfPresent(Int.self, forKey: .pid)
        path = try c.decodeIfPresent(String.self, forKey: .path)
        port = try c.decodeIfPresent(String.self, forKey: .port)
        version = try c.decodeIfPresent(String.self, forKey: .version)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        name = try c.decodeIfPresent(String.self, forKey: .name)
    }
}

struct RemoteGatewayPauseResponse: Decodable, Equatable {
    let paused: Bool
    let agents: [String]
    let agent: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case paused, agents, agent, error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        paused = try c.decodeIfPresent(Bool.self, forKey: .paused) ?? false
        agents = try c.decodeIfPresent([String].self, forKey: .agents) ?? []
        agent = try c.decodeIfPresent(String.self, forKey: .agent)
        error = try c.decodeIfPresent(String.self, forKey: .error)
    }
}

struct RemoteGatewayUnrestResponse: Decodable, Equatable {
    let lifted: Bool
}

struct RemotePortUpdateResponse: Decodable {
    let settings: RemoteSettingsState
}

struct RemoteModelPriceSpec: Codable, Equatable {
    var input: Double
    var output: Double
    var cacheRead: Double
    var cacheWrite: Double
    var cacheWrite1h: Double?

    enum CodingKeys: String, CodingKey {
        case input
        case output
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
        case cacheWrite1h = "cache_write_1h"
    }

    init(input: Double = 0, output: Double = 0, cacheRead: Double = 0, cacheWrite: Double = 0, cacheWrite1h: Double? = nil) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
        self.cacheWrite1h = cacheWrite1h
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        input = try c.decodeIfPresent(Double.self, forKey: .input) ?? 0
        output = try c.decodeIfPresent(Double.self, forKey: .output) ?? 0
        cacheRead = try c.decodeIfPresent(Double.self, forKey: .cacheRead) ?? 0
        cacheWrite = try c.decodeIfPresent(Double.self, forKey: .cacheWrite) ?? 0
        cacheWrite1h = try c.decodeIfPresent(Double.self, forKey: .cacheWrite1h)
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "input": input,
            "output": output,
            "cache_read": cacheRead,
            "cache_write": cacheWrite
        ]
        if let cw1h = cacheWrite1h, cw1h > 0 {
            dict["cache_write_1h"] = cw1h
        }
        return dict
    }
}

struct RemoteModelPriceResponse: Decodable, Equatable {
    let model: String
    let price: RemoteModelPriceSpec?
    let maker: RemoteModelPriceSpec?
}

struct RemoteSearchAPI: Decodable, Equatable, Identifiable {
    var id: String { vendor }
    let vendor: String
    let name: String
    let url: String?
    let key: String?
    let ready: Bool
    let keys: Int
    let off: Bool

    enum CodingKeys: String, CodingKey {
        case vendor, name, url, key, ready, keys, off
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        vendor = try c.decodeIfPresent(String.self, forKey: .vendor) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? vendor
        url = try c.decodeIfPresent(String.self, forKey: .url)
        key = try c.decodeIfPresent(String.self, forKey: .key)
        ready = try c.decodeIfPresent(Bool.self, forKey: .ready) ?? false
        keys = try c.decodeIfPresent(Int.self, forKey: .keys) ?? 0
        off = try c.decodeIfPresent(Bool.self, forKey: .off) ?? false
    }
}

struct RemotePrivacyModelResponse: Decodable, Equatable {
    var on: Bool = false
    var chosen: Bool = false
    var id: String = ""
    var name: String = ""
    var installed: Bool = false
    var downloading: Bool = false
    var minScore: Double = 0.85
    var defaultScore: Double = 0.85

    init() {}

    enum CodingKeys: String, CodingKey {
        case on, chosen, id, name, installed, downloading, minScore, defaultScore
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        on = try c.decodeIfPresent(Bool.self, forKey: .on) ?? false
        chosen = try c.decodeIfPresent(Bool.self, forKey: .chosen) ?? false
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        installed = try c.decodeIfPresent(Bool.self, forKey: .installed) ?? false
        downloading = try c.decodeIfPresent(Bool.self, forKey: .downloading) ?? false
        minScore = try c.decodeIfPresent(Double.self, forKey: .minScore) ?? 0.85
        defaultScore = try c.decodeIfPresent(Double.self, forKey: .defaultScore) ?? 0.85
    }
}

struct RemoteArchiveStateResponse: Decodable, Equatable {
    let on: Bool
    let bucket: String?
    let folder: String?
    let cap: Int64?
    let error: String?
}
