import Foundation

enum MagpieSharedConstants {
    static let appGroupID = "group.ai.usemagpie.ios"
    static let snapshotDefaultsKey = "magpie.widget.snapshot.v1"
    static let snapshotFileName = "magpie-widget-snapshot.json"
    static let widgetKind = "MagpieStatusWidget"
}

// MARK: - Privacy Masking for Shared Widget Cache

enum WidgetPrivacyMasker {
    /// Masks email/account identifiers and strips any credential-like substrings before writing to App Group storage.
    static func maskAccountLabel(_ raw: String, alias: String? = nil) -> String {
        if let alias = alias?.trimmingCharacters(in: .whitespacesAndNewlines), !alias.isEmpty {
            if alias.contains("@") {
                return maskEmail(alias)
            }
            return maskSecretLikePrefix(alias)
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "未命名账号" }
        if trimmed.contains("@") {
            return maskEmail(trimmed)
        }
        return maskSecretLikePrefix(trimmed)
    }

    static func maskEmail(_ email: String) -> String {
        let parts = email.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return maskSecretLikePrefix(email) }
        let local = parts[0]
        let domain = parts[1]
        if local.count <= 1 {
            return "***@\(domain)"
        }
        if local.count <= 3 {
            return "\(local.prefix(1))***@\(domain)"
        }
        return "\(local.prefix(2))***\(local.suffix(2))@\(domain)"
    }

    static func maskSecretLikePrefix(_ text: String) -> String {
        let lower = text.lowercased()
        let looksLikeSecret = lower.hasPrefix("sk-")
            || lower.hasPrefix("key-")
            || lower.hasPrefix("tvly-")
            || lower.hasPrefix("ghp_")
            || lower.contains("token")
            || lower.contains("bearer")
        if looksLikeSecret {
            if text.count <= 8 {
                return "••••"
            }
            return "\(text.prefix(4))···\(text.suffix(4))"
        }
        return text
    }

    /// Ensures server label never leaks URL query parameters such as `?k=...`.
    static func sanitizeServerTitle(name: String?, baseURL: String?) -> String {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedName.isEmpty && !trimmedName.contains("?k=") && !trimmedName.contains("://") {
            return trimmedName
        }
        if let rawURL = baseURL, let url = URL(string: rawURL), let host = url.host, !host.isEmpty {
            if let port = url.port {
                return "\(host):\(port)"
            }
            return host
        }
        return "Magpie 实例"
    }
}

// MARK: - Deep Links (`magpie://...`)

enum MagpieDeepLink: Equatable {
    case dashboard
    case usage
    case alerts
    case providers(providerID: String?, accountHint: String?)
    case refresh

    static func parse(_ url: URL) -> MagpieDeepLink? {
        guard url.scheme?.lowercased() == "magpie" else { return nil }
        let host = (url.host ?? "").lowercased()
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        let route = host.isEmpty ? (pathComponents.first?.lowercased() ?? "dashboard") : host
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let queryValue: (String) -> String? = { key in
            items.first(where: { $0.name == key })?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        switch route {
        case "", "dashboard", "home":
            return .dashboard
        case "usage", "quotas":
            return .usage
        case "alerts", "alert":
            return .alerts
        case "providers", "provider":
            let pid = queryValue("id")
            let account = queryValue("account")
            return .providers(
                providerID: (pid?.isEmpty == false) ? pid : nil,
                accountHint: (account?.isEmpty == false) ? account : nil
            )
        case "refresh":
            return .refresh
        default:
            return .dashboard
        }
    }

    var url: URL {
        switch self {
        case .dashboard:
            return URL(string: "magpie://dashboard")!
        case .usage:
            return URL(string: "magpie://usage")!
        case .alerts:
            return URL(string: "magpie://alerts")!
        case .providers(let providerID, let accountHint):
            var comp = URLComponents()
            comp.scheme = "magpie"
            comp.host = "providers"
            var q: [URLQueryItem] = []
            if let pid = providerID, !pid.isEmpty {
                q.append(URLQueryItem(name: "id", value: pid))
            }
            if let account = accountHint, !account.isEmpty {
                q.append(URLQueryItem(name: "account", value: account))
            }
            if !q.isEmpty { comp.queryItems = q }
            return comp.url ?? URL(string: "magpie://providers")!
        case .refresh:
            return URL(string: "magpie://refresh")!
        }
    }
}

// MARK: - Shared Widget Snapshot Models

enum MagpieWidgetConnectionState: String, Codable, Equatable {
    case unconfigured
    case connected
    case offline
}

struct MagpieWidgetAccountItem: Codable, Identifiable, Equatable {
    let id: String
    let providerID: String
    let providerName: String
    let maskedAccount: String
    let windowName: String
    let remainingPercent: Double?
    let usedPercent: Double?
    let resetSecs: Int64?
    let isCooling: Bool
    let isLapsed: Bool
    let isAlerting: Bool
    let isActive: Bool
}

struct MagpieWidgetSnapshot: Codable, Equatable {
    let schemaVersion: Int
    let updatedAt: Date
    let connectionState: MagpieWidgetConnectionState
    let serverTitle: String
    let todayCalls: Int
    let todayErrors: Int
    let todayTokens: Int
    let todayCostUSD: Double
    let alertThresholdPercent: Int
    let alertCount: Int
    let coolingCount: Int
    let accounts: [MagpieWidgetAccountItem]

    static let unconfigured = MagpieWidgetSnapshot(
        schemaVersion: 1,
        updatedAt: Date(),
        connectionState: .unconfigured,
        serverTitle: "未配置实例",
        todayCalls: 0,
        todayErrors: 0,
        todayTokens: 0,
        todayCostUSD: 0,
        alertThresholdPercent: 10,
        alertCount: 0,
        coolingCount: 0,
        accounts: []
    )

    func isStale(relativeTo now: Date = Date(), maxAge: TimeInterval = 7200) -> Bool {
        now.timeIntervalSince(updatedAt) > maxAge
    }
}

// MARK: - Snapshot Builder & App Group Persistence

enum MagpieWidgetSnapshotStore {
    struct StorageDiagnostics: Equatable {
        let appGroupContainerAvailable: Bool
        let userDefaultsSuiteAvailable: Bool
        let storageModeDescription: String
    }

    static func diagnostics(fileManager: FileManager = .default) -> StorageDiagnostics {
        let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: MagpieSharedConstants.appGroupID)
        let suiteAvailable = UserDefaults(suiteName: MagpieSharedConstants.appGroupID) != nil
        let mode: String
        if containerURL != nil {
            mode = "App Group 容器 (\(MagpieSharedConstants.appGroupID))"
        } else if suiteAvailable {
            mode = "App Group UserDefaults (\(MagpieSharedConstants.appGroupID))"
        } else {
            mode = "进程内缓存（无签名构建下 App Group 未授权，仅支持 App 内预览）"
        }
        return StorageDiagnostics(
            appGroupContainerAvailable: containerURL != nil,
            userDefaultsSuiteAvailable: suiteAvailable,
            storageModeDescription: mode
        )
    }

    static func save(_ snapshot: MagpieWidgetSnapshot, fileManager: FileManager = .default) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }

        if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: MagpieSharedConstants.appGroupID) {
            let fileURL = containerURL.appendingPathComponent(MagpieSharedConstants.snapshotFileName)
            try? data.write(to: fileURL, options: .atomic)
        }
        if let groupDefaults = UserDefaults(suiteName: MagpieSharedConstants.appGroupID) {
            groupDefaults.set(data, forKey: MagpieSharedConstants.snapshotDefaultsKey)
        }
        UserDefaults.standard.set(data, forKey: MagpieSharedConstants.snapshotDefaultsKey)
    }

    static func load(fileManager: FileManager = .default) -> MagpieWidgetSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: MagpieSharedConstants.appGroupID) {
            let fileURL = containerURL.appendingPathComponent(MagpieSharedConstants.snapshotFileName)
            if let data = try? Data(contentsOf: fileURL),
               let decoded = try? decoder.decode(MagpieWidgetSnapshot.self, from: data) {
                return decoded
            }
        }
        if let groupDefaults = UserDefaults(suiteName: MagpieSharedConstants.appGroupID),
           let data = groupDefaults.data(forKey: MagpieSharedConstants.snapshotDefaultsKey),
           let decoded = try? decoder.decode(MagpieWidgetSnapshot.self, from: data) {
            return decoded
        }
        if let data = UserDefaults.standard.data(forKey: MagpieSharedConstants.snapshotDefaultsKey),
           let decoded = try? decoder.decode(MagpieWidgetSnapshot.self, from: data) {
            return decoded
        }
        return nil
    }

    static func clear(fileManager: FileManager = .default) {
        if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: MagpieSharedConstants.appGroupID) {
            let fileURL = containerURL.appendingPathComponent(MagpieSharedConstants.snapshotFileName)
            try? fileManager.removeItem(at: fileURL)
        }
        UserDefaults(suiteName: MagpieSharedConstants.appGroupID)?.removeObject(forKey: MagpieSharedConstants.snapshotDefaultsKey)
        UserDefaults.standard.removeObject(forKey: MagpieSharedConstants.snapshotDefaultsKey)
    }

    static func buildSnapshot(
        isConfigured: Bool,
        isConnected: Bool,
        serverName: String?,
        serverBaseURL: String?,
        todayUsage: RemoteUsageResponse?,
        providers: [RemoteProvider],
        quotas: [RemoteUsageQuota],
        loginUsageByAgent: [String: [String: RemoteLoginQuota]],
        alerts: [QuotaAlertItem],
        alertThresholdPercent: Int,
        now: Date = Date()
    ) -> MagpieWidgetSnapshot {
        guard isConfigured else {
            return MagpieWidgetSnapshot(
                schemaVersion: 1,
                updatedAt: now,
                connectionState: .unconfigured,
                serverTitle: "未配置实例",
                todayCalls: 0,
                todayErrors: 0,
                todayTokens: 0,
                todayCostUSD: 0,
                alertThresholdPercent: alertThresholdPercent,
                alertCount: 0,
                coolingCount: 0,
                accounts: []
            )
        }

        let cleanTitle = WidgetPrivacyMasker.sanitizeServerTitle(name: serverName, baseURL: serverBaseURL)
        let alertLookup = Set(alerts.map { "\($0.providerID.lowercased())|\(($0.accountUser ?? "").lowercased())" })

        var items: [MagpieWidgetAccountItem] = []
        var coolingTotal = 0

        for provider in providers where !provider.off {
            if let account = provider.account, !account.logins.isEmpty {
                let agent = account.agent ?? provider.id
                let usageMap = loginUsageByAgent[agent] ?? [:]

                for login in account.logins where login.on || login.active || login.lapsed != nil {
                    let lower = login.user.lowercased()
                    let alias = provider.accountNames[lower] ?? provider.accountUsers[lower]
                    let masked = WidgetPrivacyMasker.maskAccountLabel(login.user, alias: alias)
                    let rests = provider.accountRests[lower] ?? []
                    let isCooling = rests.contains { ($0.model ?? "").isEmpty }
                    if isCooling { coolingTotal += 1 }
                    let isLapsed = login.lapsed != nil
                    let windows = QuotaAlertEvaluator.resolveWindows(
                        providerID: provider.id,
                        agent: agent,
                        user: login.user,
                        usageMap: usageMap,
                        quotas: quotas
                    )
                    let numeric = windows.filter { !$0.unlimited && !$0.text }
                    let lowestWindow = numeric.min { (100.0 - $0.used) < (100.0 - $1.used) }
                    let rem = lowestWindow.map { max(0, min(100, 100.0 - $0.used)) }
                    let isAlerting = alertLookup.contains("\(provider.id.lowercased())|\(lower)")

                    items.append(MagpieWidgetAccountItem(
                        id: "\(provider.id)|\(masked)|\(items.count)",
                        providerID: provider.id,
                        providerName: provider.name,
                        maskedAccount: masked,
                        windowName: lowestWindow?.name ?? (isLapsed ? "授权失效" : (isCooling ? "冷却中" : "在线")),
                        remainingPercent: rem,
                        usedPercent: lowestWindow?.used,
                        resetSecs: lowestWindow?.resetSecs,
                        isCooling: isCooling,
                        isLapsed: isLapsed,
                        isAlerting: isAlerting,
                        isActive: login.active
                    ))
                }
            } else if !provider.keyList.isEmpty {
                let coolingKeys = provider.keyList.filter { $0.rest != nil }.count
                coolingTotal += coolingKeys
                let activeKeys = provider.keyList.filter(\.on).count
                let primaryKey = provider.keyList.first(where: \.active) ?? provider.keyList.first
                let masked = WidgetPrivacyMasker.maskAccountLabel(primaryKey?.masked ?? "API Key", alias: primaryKey?.name)
                let rem: Double? = {
                    if let bal = primaryKey?.balance, let amt = bal.amount, let left = bal.left, amt > 0 {
                        return max(0, min(100, (left / amt) * 100.0))
                    }
                    return nil
                }()
                items.append(MagpieWidgetAccountItem(
                    id: "\(provider.id)|keypool",
                    providerID: provider.id,
                    providerName: provider.name,
                    maskedAccount: masked,
                    windowName: "\(activeKeys)/\(provider.keyList.count) Key",
                    remainingPercent: rem,
                    usedPercent: rem.map { max(0, 100.0 - $0) },
                    resetSecs: nil,
                    isCooling: coolingKeys > 0,
                    isLapsed: false,
                    isAlerting: alerts.contains { $0.providerID == provider.id },
                    isActive: provider.ready
                ))
            }
        }

        // Prioritize alerting / cooling / active accounts first, limit snapshot size to 6
        let prioritized = items.sorted { a, b in
            if a.isAlerting != b.isAlerting { return a.isAlerting }
            if a.isCooling != b.isCooling { return a.isCooling }
            if a.isLapsed != b.isLapsed { return a.isLapsed }
            if a.isActive != b.isActive { return a.isActive }
            return (a.remainingPercent ?? 101) < (b.remainingPercent ?? 101)
        }

        let tokens = (todayUsage?.input ?? 0) + (todayUsage?.output ?? 0)
        return MagpieWidgetSnapshot(
            schemaVersion: 1,
            updatedAt: now,
            connectionState: isConnected ? .connected : .offline,
            serverTitle: cleanTitle,
            todayCalls: todayUsage?.calls ?? 0,
            todayErrors: todayUsage?.errors ?? 0,
            todayTokens: tokens,
            todayCostUSD: todayUsage?.cost ?? 0,
            alertThresholdPercent: alertThresholdPercent,
            alertCount: alerts.count,
            coolingCount: coolingTotal,
            accounts: Array(prioritized.prefix(6))
        )
    }
}
