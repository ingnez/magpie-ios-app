import Foundation

// MARK: - One-Tap Account / Key Switch Models

struct SwitchCandidate: Identifiable, Equatable {
    let id: String
    let displayName: String
    let subtitle: String?
    let plan: String?
    let lowestRemainingPercent: Double?
    let quotaSummary: String
    let isReserve: Bool
    let isActiveOnServer: Bool
    let score: Double
}

struct QuickSwitchPlan: Equatable {
    enum Kind: String, Equatable {
        case subscription
        case apiKey
    }

    let providerID: String
    let providerName: String
    let agent: String?
    let kind: Kind
    let currentID: String?
    let currentDisplayName: String?
    let candidates: [SwitchCandidate]
    let unavailableReasons: [String]

    var recommended: SwitchCandidate? {
        candidates.first
    }
}

struct QuickSwitchResult: Identifiable, Equatable {
    let id: UUID
    let succeeded: Bool
    let providerID: String
    let providerName: String
    let agent: String?
    let kind: QuickSwitchPlan.Kind
    let fromID: String?
    let fromDisplay: String
    let toID: String
    let toDisplay: String
    let executedEndpoints: [String]
    let rolledBack: Bool
    let message: String
    let previousOrder: [String]?
    let timestamp: Date
}

// MARK: - Planner

enum AccountSwitchPlanner {
    static func plan(
        for provider: RemoteProvider,
        sourceAccountOrKeyID: String? = nil,
        loginUsageByAgent: [String: [String: RemoteLoginQuota]] = [:],
        quotas: [RemoteUsageQuota] = []
    ) -> QuickSwitchPlan? {
        if let account = provider.account, !account.logins.isEmpty {
            return planSubscription(
                provider: provider,
                account: account,
                sourceUser: sourceAccountOrKeyID,
                loginUsageByAgent: loginUsageByAgent,
                quotas: quotas
            )
        }
        if provider.keyList.count > 1 {
            return planKeyPool(provider: provider, sourceKeyID: sourceAccountOrKeyID)
        }
        return nil
    }

    private static func planSubscription(
        provider: RemoteProvider,
        account: RemoteProviderAccount,
        sourceUser: String?,
        loginUsageByAgent: [String: [String: RemoteLoginQuota]],
        quotas: [RemoteUsageQuota]
    ) -> QuickSwitchPlan {
        let agent = account.agent ?? provider.id
        let logins = account.logins
        let resolvedSource = nonEmpty(sourceUser)
            ?? logins.first(where: { $0.active })?.user
            ?? nonEmpty(account.user)
            ?? logins.first?.user

        let sourceDisplay = resolvedSource.map { displayName(for: $0, in: provider) }

        let usableLogins = logins.filter { $0.lapsed == nil && !$0.paused && ($0.active || $0.on) }
        let reserveSet: Set<String> = {
            guard let cap = provider.effectiveMaxAccounts, cap > 0 else { return [] }
            let nonCooling = usableLogins.filter { item in
                let rests = provider.accountRests[item.user.lowercased()] ?? []
                return !rests.contains { ($0.model ?? "").isEmpty }
            }
            guard nonCooling.count > cap else { return [] }
            return Set(nonCooling.dropFirst(cap).map { $0.user.lowercased() })
        }()

        let usageMap = loginUsageByAgent[agent] ?? [:]
        var candidates: [SwitchCandidate] = []
        var unavailableReasons: [String] = []

        for (index, login) in logins.enumerated() {
            if let src = resolvedSource, login.user.caseInsensitiveCompare(src) == .orderedSame {
                continue
            }
            let lower = login.user.lowercased()
            let display = displayName(for: login.user, in: provider)

            if let lapsed = nonEmpty(login.lapsed) {
                unavailableReasons.append("\(display)：授权失效 (\(lapsed))")
                continue
            }
            if login.paused {
                unavailableReasons.append("\(display)：已暂停")
                continue
            }
            if !login.on && !login.active {
                unavailableReasons.append("\(display)：已停用")
                continue
            }

            let rests = provider.accountRests[lower] ?? []
            if let wholeRest = rests.first(where: { ($0.model ?? "").isEmpty }) {
                let why = nonEmpty(wholeRest.why) ?? "限流冷却"
                unavailableReasons.append("\(display)：\(why)")
                continue
            }

            let windows = resolveWindows(
                providerID: provider.id,
                agent: agent,
                user: login.user,
                usageMap: usageMap,
                quotas: quotas
            )
            let numericWindows = windows.filter { !$0.unlimited && !$0.text }
            let lowestRemaining = numericWindows.map { max(0, min(100, 100.0 - $0.used)) }.min()
            let summary = summarizeWindows(numericWindows, allWindows: windows)
            let isReserve = reserveSet.contains(lower)

            // Higher remaining quota first; unknown quota ranks between healthy (>10%) and low (<=10%)
            let remainingScore: Double = {
                guard let rem = lowestRemaining else { return 55.0 }
                return rem
            }()
            let modelCoolPenalty = rests.isEmpty ? 0.0 : -15.0
            let orderBonus = max(0.0, Double(logins.count - index)) * 0.01
            let score = remainingScore + modelCoolPenalty + orderBonus

            candidates.append(SwitchCandidate(
                id: login.user,
                displayName: display,
                subtitle: display != login.user ? login.user : nil,
                plan: nonEmpty(login.plan),
                lowestRemainingPercent: lowestRemaining,
                quotaSummary: summary,
                isReserve: isReserve,
                isActiveOnServer: login.active,
                score: score
            ))
        }

        candidates.sort { $0.score > $1.score }
        return QuickSwitchPlan(
            providerID: provider.id,
            providerName: provider.name,
            agent: agent,
            kind: .subscription,
            currentID: resolvedSource,
            currentDisplayName: sourceDisplay,
            candidates: candidates,
            unavailableReasons: unavailableReasons
        )
    }

    private static func planKeyPool(provider: RemoteProvider, sourceKeyID: String?) -> QuickSwitchPlan {
        let keys = provider.keyList
        let resolvedSource = nonEmpty(sourceKeyID)
            ?? keys.first(where: { $0.active })?.id
            ?? keys.first?.id
        let sourceItem = keys.first(where: { $0.id == resolvedSource })
        let sourceDisplay = sourceItem.map { nonEmpty($0.name) ?? $0.masked }

        var candidates: [SwitchCandidate] = []
        var unavailableReasons: [String] = []

        for (index, item) in keys.enumerated() {
            if item.id == resolvedSource { continue }
            let label = nonEmpty(item.name) ?? item.masked
            if !item.on {
                unavailableReasons.append("\(label)：已停用")
                continue
            }
            if let rest = item.rest {
                let why = nonEmpty(rest.why) ?? "HTTP \(rest.status ?? 429) 冷却中"
                unavailableReasons.append("\(label)：\(why)")
                continue
            }

            var remainingPct: Double?
            var summary = "可用 · 权重 \(max(1, item.weight ?? 1))"
            if let bal = item.balance, let left = bal.left {
                if let amount = bal.amount, amount > 0 {
                    remainingPct = max(0, min(100, (left / amount) * 100.0))
                    summary = String(format: "余额 %.2f (剩 %.0f%%)", left, remainingPct!)
                } else {
                    summary = String(format: "余额 %.2f", left)
                }
            }
            let score = (remainingPct ?? 60.0) + Double(max(1, item.weight ?? 1)) * 0.5 - Double(index) * 0.01
            candidates.append(SwitchCandidate(
                id: item.id,
                displayName: label,
                subtitle: nonEmpty(item.name) != nil ? item.masked : nil,
                plan: nonEmpty(item.plan),
                lowestRemainingPercent: remainingPct,
                quotaSummary: summary,
                isReserve: false,
                isActiveOnServer: item.active,
                score: score
            ))
        }

        candidates.sort { $0.score > $1.score }
        return QuickSwitchPlan(
            providerID: provider.id,
            providerName: provider.name,
            agent: nil,
            kind: .apiKey,
            currentID: resolvedSource,
            currentDisplayName: sourceDisplay,
            candidates: candidates,
            unavailableReasons: unavailableReasons
        )
    }

    static func displayName(for user: String, in provider: RemoteProvider) -> String {
        let lower = user.lowercased()
        return nonEmpty(provider.accountNames[lower])
            ?? nonEmpty(provider.accountUsers[lower])
            ?? user
    }

    private static func resolveWindows(
        providerID: String,
        agent: String,
        user: String,
        usageMap: [String: RemoteLoginQuota],
        quotas: [RemoteUsageQuota]
    ) -> [RemoteLoginQuotaWindow] {
        if let loginQuota = usageMap.first(where: { $0.key.caseInsensitiveCompare(user) == .orderedSame })?.value,
           !loginQuota.windows.isEmpty {
            return loginQuota.windows
        }
        if let q = quotas.first(where: {
            ($0.provider.caseInsensitiveCompare(providerID) == .orderedSame
             || $0.provider.caseInsensitiveCompare(agent) == .orderedSame)
            && ($0.user?.caseInsensitiveCompare(user) == .orderedSame)
        }) {
            return q.windows.map { RemoteLoginQuotaWindow(quotaWindow: $0) }
        }
        return []
    }

    private static func summarizeWindows(
        _ numericWindows: [RemoteLoginQuotaWindow],
        allWindows: [RemoteLoginQuotaWindow]
    ) -> String {
        if numericWindows.isEmpty {
            if allWindows.contains(where: { $0.unlimited }) {
                return "不限量 · 状态健康"
            }
            return "状态正常 · 暂无窗口数据"
        }
        let sorted = numericWindows.sorted { a, b in
            let aRem = max(0, 100.0 - a.used)
            let bRem = max(0, 100.0 - b.used)
            return aRem < bRem
        }
        let topParts = sorted.prefix(2).map { w in
            let rem = Int(round(max(0, min(100, 100.0 - w.used))))
            return "\(w.name) 剩 \(rem)%"
        }
        return topParts.joined(separator: " · ")
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}
