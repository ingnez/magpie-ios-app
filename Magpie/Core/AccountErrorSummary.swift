import Foundation

enum AccountErrorCategory: String, CaseIterable, Identifiable, Equatable {
    case auth
    case rateLimit
    case quota
    case upstream

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auth: return "鉴权失效"
        case .rateLimit: return "限流冷却"
        case .quota: return "额度耗尽"
        case .upstream: return "上游异常"
        }
    }

    var sortOrder: Int {
        switch self {
        case .auth: return 0
        case .quota: return 1
        case .rateLimit: return 2
        case .upstream: return 3
        }
    }
}

enum AccountErrorTargetTab: Equatable {
    case overview
    case keys
}

struct AccountErrorItem: Identifiable, Equatable {
    let id: String
    let providerID: String
    let providerName: String
    let accountUser: String?
    let keyID: String?
    let displayName: String
    let subtitle: String?
    let category: AccountErrorCategory
    let failureCount: Int
    let isConsecutive: Bool
    let lastFailureAt: String?
    let cooldownUntil: String?
    let reason: String
    let rawDetail: String?
    let statusCode: Int?
    let affectedModels: [String]
    let restKeys: [String]
    let targetTab: AccountErrorTargetTab
}

struct AccountJumpTarget: Identifiable, Equatable {
    let id = UUID()
    let providerID: String
    let tab: AccountErrorTargetTab
    let accountUser: String?
    let keyID: String?
}

enum AccountErrorAggregator {
    static func aggregate(
        providers: [RemoteProvider],
        excludedAccounts: [RemoteExcludedAccount] = [],
        loginUsageByAgent: [String: [String: RemoteLoginQuota]] = [:],
        quotas: [RemoteUsageQuota] = [],
        routes: [RemoteRoute] = []
    ) -> [AccountErrorItem] {
        var items: [AccountErrorItem] = []

        for provider in providers {
            let failedProviderRoutes = routes.filter {
                $0.isError && $0.provider.caseInsensitiveCompare(provider.id) == .orderedSame
            }
            let latestProviderRouteErrorTime = latestISOString(failedProviderRoutes.map(\.time))

            if let account = provider.account {
                let agent = account.agent ?? provider.id
                let agentUsage = loginUsageByAgent[agent] ?? [:]

                for login in account.logins {
                    let lower = login.user.lowercased()
                    let rests = provider.accountRests.first(where: { $0.key.lowercased() == lower })?.value ?? []
                    let lapsed = nonEmpty(login.lapsed)
                    let loginQuota = agentUsage.first(where: { $0.key.caseInsensitiveCompare(login.user) == .orderedSame })?.value
                    let quotaMatch = quotas.first(where: {
                        $0.provider.caseInsensitiveCompare(provider.id) == .orderedSame
                            && ($0.user?.caseInsensitiveCompare(login.user) == .orderedSame)
                    })
                    let quotaError = nonEmpty(quotaMatch?.pluginError) ?? nonEmpty(quotaMatch?.error) ?? nonEmpty(loginQuota?.error)
                    let excluded = excludedAccounts.first(where: { ex in
                        let matchesProvider = ex.provider?.caseInsensitiveCompare(provider.id) == .orderedSame
                            || ex.agent.caseInsensitiveCompare(agent) == .orderedSame
                        guard matchesProvider else { return false }
                        if ex.users.isEmpty { return true }
                        return ex.users.contains(where: { $0.caseInsensitiveCompare(login.user) == .orderedSame })
                    })

                    guard lapsed != nil || !rests.isEmpty || quotaError != nil || excluded != nil else {
                        continue
                    }

                    let alias = nonEmpty(provider.accountNames[lower])
                    let vendorUser = nonEmpty(provider.accountUsers[lower])
                    let displayName = alias ?? vendorUser ?? login.user
                    let subtitle = displayName != login.user ? login.user : nil

                    let category = classify(
                        lapsed: lapsed,
                        excluded: excluded,
                        rests: rests,
                        quotaError: quotaError
                    )

                    let explicitFailures = rests.compactMap(\.failures).max() ?? 0
                    let signalCount = rests.count + (lapsed != nil ? 1 : 0) + (quotaError != nil ? 1 : 0) + (excluded != nil ? 1 : 0)
                    let failureCount = max(1, max(explicitFailures, signalCount))
                    let isConsecutive = failureCount > 1
                        || rests.contains(where: { ($0.by ?? "").lowercased() == "backoff" })
                        || lapsed != nil

                    let lastFailureAt = latestISOString([
                        latestProviderRouteErrorTime,
                        nonZeroISO(quotaMatch?.readAt),
                        nonZeroISO(loginQuota?.readAt),
                        nonZeroISO(login.seen)
                    ].compactMap { $0 })

                    let cooldownUntil = earliestOrLatestFutureISO(rests.compactMap { nonZeroISO($0.until) })
                    let affectedModels = Array(Set(rests.compactMap { nonEmpty($0.model) })).sorted()
                    let restKeys = Array(Set(rests.compactMap { nonEmpty($0.key) })).sorted()
                    let statusCode = rests.compactMap(\.status).first(where: { $0 > 0 })
                    let reason = buildReason(
                        category: category,
                        lapsed: lapsed,
                        excluded: excluded,
                        rests: rests,
                        quotaError: quotaError,
                        statusCode: statusCode
                    )
                    let rawDetail = firstNonEmpty([
                        lapsed,
                        rests.compactMap { nonEmpty($0.error) }.first,
                        excluded.flatMap { nonEmpty($0.why) },
                        quotaError
                    ])

                    items.append(AccountErrorItem(
                        id: "login:\(provider.id):\(lower)",
                        providerID: provider.id,
                        providerName: provider.name,
                        accountUser: login.user,
                        keyID: nil,
                        displayName: displayName,
                        subtitle: subtitle,
                        category: category,
                        failureCount: failureCount,
                        isConsecutive: isConsecutive,
                        lastFailureAt: lastFailureAt,
                        cooldownUntil: cooldownUntil,
                        reason: reason,
                        rawDetail: rawDetail,
                        statusCode: statusCode,
                        affectedModels: affectedModels,
                        restKeys: restKeys,
                        targetTab: .keys
                    ))
                }
            }

            for keyInfo in provider.keyList {
                guard let rest = keyInfo.rest else { continue }
                let category = classify(lapsed: nil, excluded: nil, rests: [rest], quotaError: nil)
                let failureCount = max(1, rest.failures ?? 1)
                let isConsecutive = failureCount > 1 || (rest.by ?? "").lowercased() == "backoff"
                let displayName = nonEmpty(keyInfo.name) ?? (keyInfo.masked.isEmpty ? keyInfo.id : keyInfo.masked)
                let subtitle = nonEmpty(keyInfo.name) != nil && !keyInfo.masked.isEmpty ? keyInfo.masked : nil
                let statusCode = (rest.status ?? 0) > 0 ? rest.status : nil
                let reason = buildReason(
                    category: category,
                    lapsed: nil,
                    excluded: nil,
                    rests: [rest],
                    quotaError: nil,
                    statusCode: statusCode
                )
                let rawDetail = nonEmpty(rest.error)
                items.append(AccountErrorItem(
                    id: "key:\(provider.id):\(keyInfo.id)",
                    providerID: provider.id,
                    providerName: provider.name,
                    accountUser: nil,
                    keyID: keyInfo.id,
                    displayName: displayName,
                    subtitle: subtitle,
                    category: category,
                    failureCount: failureCount,
                    isConsecutive: isConsecutive,
                    lastFailureAt: latestProviderRouteErrorTime,
                    cooldownUntil: nonZeroISO(rest.until),
                    reason: reason,
                    rawDetail: rawDetail,
                    statusCode: statusCode,
                    affectedModels: nonEmpty(rest.model).map { [$0] } ?? [],
                    restKeys: nonEmpty(rest.key).map { [$0] } ?? [],
                    targetTab: .keys
                ))
            }

            if let listErr = nonEmpty(provider.listError) {
                let statusCode = failedProviderRoutes.first(where: { $0.status >= 400 })?.status
                let cat = classifyReasonText(listErr, status: statusCode)
                items.append(AccountErrorItem(
                    id: "provider:\(provider.id)",
                    providerID: provider.id,
                    providerName: provider.name,
                    accountUser: nil,
                    keyID: nil,
                    displayName: provider.name,
                    subtitle: provider.primaryEndpointPreview,
                    category: cat,
                    failureCount: max(1, failedProviderRoutes.count),
                    isConsecutive: failedProviderRoutes.count > 1,
                    lastFailureAt: latestProviderRouteErrorTime,
                    cooldownUntil: nil,
                    reason: "供应商模型拉取/状态异常",
                    rawDetail: listErr,
                    statusCode: statusCode,
                    affectedModels: [],
                    restKeys: [],
                    targetTab: .overview
                ))
            }
        }

        // Catch excluded accounts that might not appear in provider.account.logins
        let coveredLoginIDs = Set(items.compactMap { item -> String? in
            guard let user = item.accountUser else { return nil }
            return "\(item.providerID.lowercased())|\(user.lowercased())"
        })
        for ex in excludedAccounts {
            let pid = nonEmpty(ex.provider) ?? ex.agent
            let targetUsers = ex.users.isEmpty ? [""] : ex.users
            for u in targetUsers {
                if !u.isEmpty && coveredLoginIDs.contains("\(pid.lowercased())|\(u.lowercased())") {
                    continue
                }
                let cat: AccountErrorCategory = ex.signedOut ? .auth : classifyReasonText(ex.why, status: nil)
                let providerName = providers.first(where: { $0.id.caseInsensitiveCompare(pid) == .orderedSame })?.name ?? ex.agentName
                items.append(AccountErrorItem(
                    id: "excluded:\(pid):\(u):\(ex.why)",
                    providerID: pid,
                    providerName: providerName,
                    accountUser: nonEmpty(u),
                    keyID: nil,
                    displayName: nonEmpty(u) ?? ex.agentName,
                    subtitle: ex.agentName,
                    category: cat,
                    failureCount: 1,
                    isConsecutive: ex.signedOut,
                    lastFailureAt: nil,
                    cooldownUntil: nil,
                    reason: ex.signedOut ? "账号已退出或授权中断" : (nonEmpty(ex.why) ?? "账号被排除调度"),
                    rawDetail: nonEmpty(ex.why),
                    statusCode: nil,
                    affectedModels: [],
                    restKeys: [],
                    targetTab: .keys
                ))
            }
        }

        return items.sorted { lhs, rhs in
            if lhs.category.sortOrder != rhs.category.sortOrder {
                return lhs.category.sortOrder < rhs.category.sortOrder
            }
            if lhs.failureCount != rhs.failureCount {
                return lhs.failureCount > rhs.failureCount
            }
            if lhs.providerName != rhs.providerName {
                return lhs.providerName < rhs.providerName
            }
            return lhs.displayName < rhs.displayName
        }
    }

    private static func classify(
        lapsed: String?,
        excluded: RemoteExcludedAccount?,
        rests: [RemoteKeyRest],
        quotaError: String?
    ) -> AccountErrorCategory {
        if lapsed != nil || excluded?.signedOut == true {
            return .auth
        }
        if rests.contains(where: {
            let why = ($0.why ?? "").lowercased()
            let by = ($0.by ?? "").lowercased()
            let st = $0.status ?? 0
            return st == 401 || st == 403 || why.contains("verify") || why.contains("auth") || by == "restricted"
        }) {
            return .auth
        }
        if rests.contains(where: {
            let why = ($0.why ?? "").lowercased()
            return why.contains("quota") || why.contains("credit") || $0.status == 402
        }) {
            return .quota
        }
        if rests.contains(where: {
            let why = ($0.why ?? "").lowercased()
            return $0.rate == true || $0.status == 429 || why.contains("rate")
        }) {
            return .rateLimit
        }
        if let qErr = quotaError {
            return classifyReasonText(qErr, status: nil)
        }
        if let exWhy = excluded?.why {
            return classifyReasonText(exWhy, status: nil)
        }
        return .upstream
    }

    private static func classifyReasonText(_ text: String, status: Int?) -> AccountErrorCategory {
        let low = text.lowercased()
        if status == 401 || status == 403 || low.contains("unauthorized") || low.contains("expired") || low.contains("token") || low.contains("revoked") || low.contains("auth") {
            return .auth
        }
        if status == 402 || low.contains("quota") || low.contains("credit") || low.contains("balance") || low.contains("insufficient") {
            return .quota
        }
        if status == 429 || low.contains("rate") || low.contains("too many") || low.contains("limit") {
            return .rateLimit
        }
        return .upstream
    }

    private static func buildReason(
        category: AccountErrorCategory,
        lapsed: String?,
        excluded: RemoteExcludedAccount?,
        rests: [RemoteKeyRest],
        quotaError: String?,
        statusCode: Int?
    ) -> String {
        let codePrefix = statusCode.map { "HTTP \($0) · " } ?? ""
        switch category {
        case .auth:
            if let lapsed = lapsed {
                return "\(codePrefix)登录授权失效（\(lapsed)），需重新授权"
            }
            if excluded?.signedOut == true {
                return "\(codePrefix)账号已登出或凭据被拒绝"
            }
            return "\(codePrefix)鉴权受限或账号需验证"
        case .quota:
            if let by = nonEmpty(rests.first?.by) {
                return "\(codePrefix)额度或余额不足（\(by)）"
            }
            return "\(codePrefix)额度或余额已耗尽"
        case .rateLimit:
            let by = nonEmpty(rests.first?.by)
            if by == "backoff" {
                return "\(codePrefix)连续触发限流，已进入指数退避冷却"
            }
            if let by = by {
                return "\(codePrefix)触发限流冷却（\(by)）"
            }
            return "\(codePrefix)触发上游速率限制，冷却跳过中"
        case .upstream:
            if let why = nonEmpty(rests.first?.why) {
                return "\(codePrefix)上游响应异常（\(why)）"
            }
            if let quotaError = quotaError {
                return "额度探测异常：\(quotaError)"
            }
            if let exWhy = nonEmpty(excluded?.why) {
                return exWhy
            }
            return "\(codePrefix)连续请求失败，正在退避等待"
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func firstNonEmpty(_ values: [String?]) -> String? {
        for v in values {
            if let valid = nonEmpty(v) { return valid }
        }
        return nil
    }

    private static func nonZeroISO(_ value: String?) -> String? {
        guard let str = nonEmpty(value), !str.hasPrefix("0001-01-01") else { return nil }
        return str
    }

    static func parseISO8601(_ raw: String) -> Date? {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: raw) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: raw)
    }

    static func formatDisplayTimestamp(_ raw: String?) -> String? {
        guard let raw = nonZeroISO(raw) else { return nil }
        guard let date = parseISO8601(raw) else { return raw }
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "MM-dd HH:mm"
        return fmt.string(from: date)
    }

    private static func latestISOString(_ values: [String]) -> String? {
        var best: (String, Date)?
        for raw in values {
            guard let clean = nonZeroISO(raw), let d = parseISO8601(clean) else { continue }
            if best == nil || d > best!.1 {
                best = (clean, d)
            }
        }
        return best?.0 ?? values.compactMap(nonZeroISO).first
    }

    private static func earliestOrLatestFutureISO(_ values: [String]) -> String? {
        var best: (String, Date)?
        for raw in values {
            guard let clean = nonZeroISO(raw), let d = parseISO8601(clean) else { continue }
            if best == nil || d > best!.1 {
                best = (clean, d)
            }
        }
        return best?.0 ?? values.compactMap(nonZeroISO).first
    }
}
