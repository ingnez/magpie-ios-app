import Foundation

// MARK: - Quota Alert Config & Overrides

struct QuotaAlertConfig: Codable, Equatable {
    var enabled: Bool = true
    var notificationsEnabled: Bool = false
    var defaultRemainingThresholdPercent: Int = 10
    var providerThresholds: [String: Int] = [:]
    var accountThresholds: [String: Int] = [:]
    var mutedTargets: Set<String> = []
    var cooldownMinutes: Int = 240

    static func clampThreshold(_ value: Int) -> Int {
        min(max(value, 1), 95)
    }

    static func providerKey(_ providerID: String) -> String {
        "provider:\(providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    static func accountKey(providerID: String, user: String) -> String {
        let p = providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let u = user.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "account:\(p)|\(u)"
    }

    func effectiveThreshold(providerID: String, user: String?) -> Int {
        if let user = user, !user.isEmpty {
            let aKey = Self.accountKey(providerID: providerID, user: user)
            if let v = accountThresholds[aKey] {
                return Self.clampThreshold(v)
            }
        }
        let pKey = Self.providerKey(providerID)
        if let v = providerThresholds[pKey] {
            return Self.clampThreshold(v)
        }
        return Self.clampThreshold(defaultRemainingThresholdPercent)
    }

    func isMuted(providerID: String, user: String?) -> Bool {
        if mutedTargets.contains(Self.providerKey(providerID)) {
            return true
        }
        if let user = user, !user.isEmpty {
            return mutedTargets.contains(Self.accountKey(providerID: providerID, user: user))
        }
        return false
    }

    mutating func setProviderThreshold(_ threshold: Int?, providerID: String) {
        let key = Self.providerKey(providerID)
        if let t = threshold {
            providerThresholds[key] = Self.clampThreshold(t)
        } else {
            providerThresholds.removeValue(forKey: key)
        }
    }

    mutating func setAccountThreshold(_ threshold: Int?, providerID: String, user: String) {
        let key = Self.accountKey(providerID: providerID, user: user)
        if let t = threshold {
            accountThresholds[key] = Self.clampThreshold(t)
        } else {
            accountThresholds.removeValue(forKey: key)
        }
    }

    mutating func setMuted(_ muted: Bool, providerID: String, user: String? = nil) {
        let key = (user?.isEmpty == false)
            ? Self.accountKey(providerID: providerID, user: user!)
            : Self.providerKey(providerID)
        if muted {
            mutedTargets.insert(key)
        } else {
            mutedTargets.remove(key)
        }
    }
}

// MARK: - Evaluated Alert Models

enum QuotaAlertSeverity: String, Codable, Equatable, Comparable {
    case warning
    case critical

    static func < (lhs: QuotaAlertSeverity, rhs: QuotaAlertSeverity) -> Bool {
        let rank: (QuotaAlertSeverity) -> Int = { $0 == .critical ? 1 : 0 }
        return rank(lhs) < rank(rhs)
    }

    var title: String {
        switch self {
        case .critical: return "告急"
        case .warning: return "预警"
        }
    }
}

struct QuotaAlertItem: Identifiable, Equatable, Codable {
    let id: String
    let dedupKey: String
    let providerID: String
    let providerName: String
    let accountUser: String?
    let accountDisplayName: String
    let windowName: String
    let affectedWindowCount: Int
    let usedPercent: Double
    let remainingPercent: Double
    let thresholdPercent: Int
    let resetSecs: Int64?
    let resetsAt: String?
    let severity: QuotaAlertSeverity
    let isCooling: Bool
    let hasSwitchCandidate: Bool
    let recommendedSwitchUser: String?
    let recommendedSwitchDisplay: String?
}

struct ProviderQuotaAlertSummary: Identifiable, Equatable {
    var id: String { providerID }
    let providerID: String
    let providerName: String
    let effectiveThresholdPercent: Int
    let isMuted: Bool
    let alertingAccountCount: Int
    let lowestRemainingPercent: Double?
    let items: [QuotaAlertItem]
}

// MARK: - Evaluator

enum QuotaAlertEvaluator {
    static func evaluate(
        providers: [RemoteProvider],
        quotas: [RemoteUsageQuota],
        loginUsageByAgent: [String: [String: RemoteLoginQuota]],
        config: QuotaAlertConfig
    ) -> [QuotaAlertItem] {
        guard config.enabled else { return [] }
        var items: [QuotaAlertItem] = []

        for provider in providers where !provider.off {
            if let account = provider.account, !account.logins.isEmpty {
                let agent = account.agent ?? provider.id
                let usageMap = loginUsageByAgent[agent] ?? [:]

                for login in account.logins {
                    guard login.lapsed == nil && (login.on || login.active) else { continue }
                    guard !config.isMuted(providerID: provider.id, user: login.user) else { continue }

                    let threshold = config.effectiveThreshold(providerID: provider.id, user: login.user)
                    let windows = resolveWindows(
                        providerID: provider.id,
                        agent: agent,
                        user: login.user,
                        usageMap: usageMap,
                        quotas: quotas
                    )
                    guard let picked = pickRepresentativeLowWindow(from: windows, threshold: threshold) else {
                        continue
                    }

                    let lower = login.user.lowercased()
                    let display = nonEmpty(provider.accountNames[lower])
                        ?? nonEmpty(provider.accountUsers[lower])
                        ?? login.user
                    let rests = provider.accountRests[lower] ?? []
                    let isCooling = rests.contains { ($0.model ?? "").isEmpty }

                    let plan = AccountSwitchPlanner.plan(
                        for: provider,
                        sourceAccountOrKeyID: login.user,
                        loginUsageByAgent: loginUsageByAgent,
                        quotas: quotas
                    )

                    let remaining = picked.remaining
                    let severity: QuotaAlertSeverity = remaining <= 3.0 ? .critical : .warning
                    let stableID = "\(provider.id.lowercased())|\(lower)|\(picked.window.name.lowercased())"
                    let resetBucket = nonEmpty(picked.window.resetsAt) ?? picked.window.resetSecs.map { "sec:\($0 / 300)" } ?? "none"

                    items.append(QuotaAlertItem(
                        id: stableID,
                        dedupKey: "\(stableID)|\(resetBucket)",
                        providerID: provider.id,
                        providerName: provider.name,
                        accountUser: login.user,
                        accountDisplayName: display,
                        windowName: picked.window.name,
                        affectedWindowCount: picked.lowCount,
                        usedPercent: picked.window.used,
                        remainingPercent: remaining,
                        thresholdPercent: threshold,
                        resetSecs: picked.window.resetSecs,
                        resetsAt: picked.window.resetsAt,
                        severity: severity,
                        isCooling: isCooling,
                        hasSwitchCandidate: plan?.recommended != nil,
                        recommendedSwitchUser: plan?.recommended?.id,
                        recommendedSwitchDisplay: plan?.recommended?.displayName
                    ))
                }
            } else {
                guard !config.isMuted(providerID: provider.id, user: nil) else { continue }
                let threshold = config.effectiveThreshold(providerID: provider.id, user: nil)
                let matchingQuotas = quotas.filter {
                    $0.provider.caseInsensitiveCompare(provider.id) == .orderedSame
                }
                for q in matchingQuotas {
                    let user = nonEmpty(q.user)
                    if let user = user, config.isMuted(providerID: provider.id, user: user) { continue }
                    let effectiveThreshold = config.effectiveThreshold(providerID: provider.id, user: user)
                    let windows = q.windows.map { RemoteLoginQuotaWindow(quotaWindow: $0) }
                    guard let picked = pickRepresentativeLowWindow(from: windows, threshold: effectiveThreshold) else {
                        continue
                    }
                    let accountKey = user?.lowercased() ?? "provider"
                    let stableID = "\(provider.id.lowercased())|\(accountKey)|\(picked.window.name.lowercased())"
                    let resetBucket = nonEmpty(picked.window.resetsAt) ?? picked.window.resetSecs.map { "sec:\($0 / 300)" } ?? "none"
                    let plan = AccountSwitchPlanner.plan(
                        for: provider,
                        sourceAccountOrKeyID: user,
                        loginUsageByAgent: loginUsageByAgent,
                        quotas: quotas
                    )
                    items.append(QuotaAlertItem(
                        id: stableID,
                        dedupKey: "\(stableID)|\(resetBucket)",
                        providerID: provider.id,
                        providerName: provider.name,
                        accountUser: user,
                        accountDisplayName: user ?? provider.name,
                        windowName: picked.window.name,
                        affectedWindowCount: picked.lowCount,
                        usedPercent: picked.window.used,
                        remainingPercent: picked.remaining,
                        thresholdPercent: threshold,
                        resetSecs: picked.window.resetSecs,
                        resetsAt: picked.window.resetsAt,
                        severity: picked.remaining <= 3.0 ? .critical : .warning,
                        isCooling: false,
                        hasSwitchCandidate: plan?.recommended != nil,
                        recommendedSwitchUser: plan?.recommended?.id,
                        recommendedSwitchDisplay: plan?.recommended?.displayName
                    ))
                }

                // Also evaluate key-pool explicit balance left/amount when available
                for k in provider.keyList where k.on {
                    if config.isMuted(providerID: provider.id, user: k.id) { continue }
                    if let bal = k.balance, let amount = bal.amount, let left = bal.left, amount > 0 {
                        let remaining = max(0, min(100, (left / amount) * 100.0))
                        let threshold = config.effectiveThreshold(providerID: provider.id, user: k.id)
                        if remaining <= Double(threshold) {
                            let label = nonEmpty(k.name) ?? k.masked
                            let stableID = "\(provider.id.lowercased())|key:\(k.id)|balance"
                            let plan = AccountSwitchPlanner.plan(
                                for: provider,
                                sourceAccountOrKeyID: k.id,
                                loginUsageByAgent: loginUsageByAgent,
                                quotas: quotas
                            )
                            items.append(QuotaAlertItem(
                                id: stableID,
                                dedupKey: stableID,
                                providerID: provider.id,
                                providerName: provider.name,
                                accountUser: k.id,
                                accountDisplayName: label,
                                windowName: "Key 余额",
                                affectedWindowCount: 1,
                                usedPercent: max(0, 100.0 - remaining),
                                remainingPercent: remaining,
                                thresholdPercent: threshold,
                                resetSecs: nil,
                                resetsAt: nil,
                                severity: remaining <= 3.0 ? .critical : .warning,
                                isCooling: k.rest != nil,
                                hasSwitchCandidate: plan?.recommended != nil,
                                recommendedSwitchUser: plan?.recommended?.id,
                                recommendedSwitchDisplay: plan?.recommended?.displayName
                            ))
                        }
                    }
                }
            }
        }

        return items.sorted { lhs, rhs in
            if lhs.severity != rhs.severity {
                return lhs.severity > rhs.severity
            }
            if lhs.remainingPercent != rhs.remainingPercent {
                return lhs.remainingPercent < rhs.remainingPercent
            }
            return lhs.providerName.localizedCaseInsensitiveCompare(rhs.providerName) == .orderedAscending
        }
    }

    static func summarizeByProvider(
        items: [QuotaAlertItem],
        providers: [RemoteProvider],
        config: QuotaAlertConfig
    ) -> [ProviderQuotaAlertSummary] {
        var grouped: [String: [QuotaAlertItem]] = [:]
        for item in items {
            grouped[item.providerID, default: []].append(item)
        }
        return providers.compactMap { provider -> ProviderQuotaAlertSummary? in
            let pItems = grouped[provider.id] ?? []
            let hasOverride = config.providerThresholds[QuotaAlertConfig.providerKey(provider.id)] != nil
            let isMuted = config.isMuted(providerID: provider.id, user: nil)
            let hasAccounts = (provider.account?.logins.isEmpty == false) || !provider.keyList.isEmpty
            guard !pItems.isEmpty || hasOverride || isMuted || hasAccounts else { return nil }
            let lowest = pItems.map(\.remainingPercent).min()
            return ProviderQuotaAlertSummary(
                providerID: provider.id,
                providerName: provider.name,
                effectiveThresholdPercent: config.effectiveThreshold(providerID: provider.id, user: nil),
                isMuted: isMuted,
                alertingAccountCount: Set(pItems.map { $0.accountUser ?? $0.accountDisplayName }).count,
                lowestRemainingPercent: lowest,
                items: pItems
            )
        }.sorted { lhs, rhs in
            if lhs.alertingAccountCount != rhs.alertingAccountCount {
                return lhs.alertingAccountCount > rhs.alertingAccountCount
            }
            return (lhs.lowestRemainingPercent ?? 101) < (rhs.lowestRemainingPercent ?? 101)
        }
    }

    static func resolveWindows(
        providerID: String,
        agent: String,
        user: String,
        usageMap: [String: RemoteLoginQuota],
        quotas: [RemoteUsageQuota]
    ) -> [RemoteLoginQuotaWindow] {
        let local = usageMap.first(where: { $0.key.caseInsensitiveCompare(user) == .orderedSame })?.value
        let global = quotas.first(where: {
            ($0.provider.caseInsensitiveCompare(providerID) == .orderedSame
             || $0.provider.caseInsensitiveCompare(agent) == .orderedSame)
            && ($0.user?.caseInsensitiveCompare(user) == .orderedSame)
        })
        func date(_ raw: String?) -> Date? {
            guard let raw = raw else { return nil }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: raw) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: raw)
        }
        if let global = global, !global.windows.isEmpty,
           let globalDate = date(global.readAt), globalDate > (date(local?.readAt) ?? .distantPast) {
            return global.windows.map { RemoteLoginQuotaWindow(quotaWindow: $0) }
        }
        if let local = local, !local.windows.isEmpty { return local.windows }
        if let global = global { return global.windows.map { RemoteLoginQuotaWindow(quotaWindow: $0) } }
        return []
    }

    private static func pickRepresentativeLowWindow(
        from windows: [RemoteLoginQuotaWindow],
        threshold: Int
    ) -> (window: RemoteLoginQuotaWindow, remaining: Double, lowCount: Int)? {
        let numericWindows = windows.filter { !$0.unlimited && !$0.text }
        var lowCandidates: [(window: RemoteLoginQuotaWindow, remaining: Double)] = []
        for w in numericWindows {
            let remaining = max(0, min(100, 100.0 - w.used))
            if remaining <= Double(threshold) {
                lowCandidates.append((w, remaining))
            }
        }
        guard !lowCandidates.isEmpty else { return nil }

        // Prefer core aggregate windows (5h / 7d / capId) when remaining is tied, else lowest remaining
        let sorted = lowCandidates.sorted { a, b in
            if abs(a.remaining - b.remaining) > 0.01 {
                return a.remaining < b.remaining
            }
            let aCore = isCoreWindow(a.window)
            let bCore = isCoreWindow(b.window)
            if aCore != bCore { return aCore }
            return a.window.name.count < b.window.name.count
        }
        return (sorted[0].window, sorted[0].remaining, lowCandidates.count)
    }

    private static func isCoreWindow(_ w: RemoteLoginQuotaWindow) -> Bool {
        let lower = w.name.lowercased()
        return (w.capId?.isEmpty == false)
            || lower.contains("hour")
            || lower.contains("小时")
            || lower.contains("day")
            || lower.contains("周")
            || lower.contains("5h")
            || lower.contains("7d")
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}

// MARK: - Notification Deduplicator

struct QuotaNotificationHistoryEntry: Codable, Equatable {
    let lastNotifiedAt: Date
    let lastRemainingPercent: Double
    let resetKey: String
}

enum QuotaNotificationDeduplicator {
    static func filterItemsToNotify(
        items: [QuotaAlertItem],
        history: [String: QuotaNotificationHistoryEntry],
        now: Date = Date(),
        cooldownMinutes: Int = 240,
        hysteresisRecoveryPercent: Double = 5.0
    ) -> (toNotify: [QuotaAlertItem], updatedHistory: [String: QuotaNotificationHistoryEntry]) {
        var nextHistory = history
        let activeIDs = Set(items.map(\.id))

        // Clear entries whose alerts have resolved (hysteresis: no longer below threshold)
        for key in Array(nextHistory.keys) where !activeIDs.contains(key) {
            nextHistory.removeValue(forKey: key)
        }

        let cooldownInterval = TimeInterval(max(1, cooldownMinutes) * 60)
        var toNotify: [QuotaAlertItem] = []

        for item in items {
            let resetKey = item.resetsAt ?? ""
            if let prev = nextHistory[item.id] {
                let sameCycle = prev.resetKey == resetKey
                let withinCooldown = now.timeIntervalSince(prev.lastNotifiedAt) < cooldownInterval
                let escalatedToCritical = (item.severity == .critical) && (prev.lastRemainingPercent > 3.0)
                let droppedSignificantly = (prev.lastRemainingPercent - item.remainingPercent) >= hysteresisRecoveryPercent && item.remainingPercent <= 3.0

                if sameCycle && withinCooldown && !escalatedToCritical && !droppedSignificantly {
                    continue
                }
            }
            toNotify.append(item)
            nextHistory[item.id] = QuotaNotificationHistoryEntry(
                lastNotifiedAt: now,
                lastRemainingPercent: item.remainingPercent,
                resetKey: resetKey
            )
        }

        return (toNotify, nextHistory)
    }
}

extension RemoteLoginQuotaWindow {
    init(quotaWindow w: RemoteQuotaWindow) {
        unlimited = w.unlimited; name = w.name; used = w.used
        resetsAt = w.resetsAt; resetSecs = w.resetSecs; display = w.display
        text = w.text; amount = w.amount; limit = w.limit; unit = w.unit
        lane = nil; balance = nil; spent = nil; family = nil; pool = nil
        credits = false; extra = false; capped = false; capsSome = false
        capId = nil; ownCap = false
    }
}
