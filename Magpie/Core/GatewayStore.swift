import Foundation
import SwiftUI
import UIKit

@MainActor
final class GatewayStore: ObservableObject {
    // MARK: - Server Profiles & Connection State
    @Published var servers: [MagpieServerProfile] = []
    @Published var activeServerID: UUID?
    @Published var health: ConnectionHealth = .untested
    @Published var isConnecting = false
    @Published var toastMessage: String?

    // MARK: - Remote State (`/api/state`, `/api/settings`, `/api/providers`, `/api/groups`)
    @Published var remoteState: RemoteStateResponse?
    @Published var remoteSettings: RemoteSettingsState = RemoteSettingsState()
    @Published var providers: [RemoteProvider] = []
    @Published var presets: [RemotePreset] = []
    @Published var gatewayStatus: RemoteGatewayStatus?
    @Published var pluginSubs: [RemotePluginSub] = []
    @Published var pluginListings: [RemotePluginListing] = []
    @Published var onPlugins: [String] = []
    @Published var movableSubs: [String] = []
    @Published var movesTo: [String: String] = [:]
    @Published var unmovedSubs: [RemoteMoveCandidate] = []
    @Published var withdrawnPlugins: [RemoteWithdrawnPlugin] = []
    @Published var agyMoveUsers: [String] = []
    @Published var excludedAccounts: [RemoteExcludedAccount] = []
    @Published var codexDaemonStale: String?
    @Published var codexAppStale: String?
    @Published var codexProjectsShort: Bool = false
    @Published var loginUsageByAgent: [String: [String: RemoteLoginQuota]] = [:]
    @Published var groups: [RemoteRoutingGroup] = []
    @Published var groupModels: [RemoteGroupModelRef] = []
    @Published var groupDeciders: [RemoteGroupModelRef] = []
    @Published var groupDrawers: [RemoteGroupModelRef] = []
    @Published var groupTemplates: [RemoteGroupTemplate] = []
    @Published var groupDefaults: RemoteGroupDefaults?
    @Published var autoGroupsFound: Bool = false
    @Published var balanceOutputsByID: [String: String] = [:]

    // MARK: - Live Trace & History (`/api/gateway/trace`, `/api/gateway/history`)
    @Published var traceRoutes: [RemoteRoute] = []
    @Published var traceTotals: RemoteTraceTotals = RemoteTraceTotals()
    @Published var traceSeq: Int64 = 0
    @Published var isLiveTraceActive = false
    @Published var historyDays: [String] = []
    @Published var historyRoutes: [RemoteRoute] = []
    @Published var selectedHistoryDay: String = ""

    // MARK: - Usage & Quotas (`/api/usage`, `/api/usage/quotas`)
    @Published var usagePeriod: String = "today"
    @Published var usagePeriodPreset: String = "today"
    @Published var customUsageStart: Date = UsageDateRange.presetLastDays(7).startDate
    @Published var customUsageEnd: Date = UsageDateRange.presetLastDays(7).endDate
    @Published var usageSummary: RemoteUsageResponse?
    @Published var usageError: String?
    @Published var isLoadingUsage = false
    @Published var quotas: [RemoteUsageQuota] = []
    @Published var isLoadingQuotas = false

    // MARK: - Navigation & Error Aggregation
    @Published var pendingAccountJump: AccountJumpTarget?
    @Published var pendingDeepLink: MagpieDeepLink?

    // MARK: - Phase 3: Quota Alerts, Quick Switch & Widget Snapshot
    @Published var todayUsageSummary: RemoteUsageResponse?
    @Published var alertConfig: QuotaAlertConfig = QuotaAlertConfig()
    @Published var quotaAlerts: [QuotaAlertItem] = []
    @Published var notificationAuthState: NotificationAuthState = .notDetermined
    @Published var lastQuickSwitchResult: QuickSwitchResult?
    @Published var isSwitchingAccount = false
    @Published var widgetSnapshot: MagpieWidgetSnapshot = .unconfigured

    // MARK: - Masking & Caller Keys (`/api/masking/*`, `/api/caller-keys`)
    @Published var maskingSummary: RemoteMaskingSummary?
    @Published var maskingRecords: [RemoteMaskingRecord] = []
    @Published var maskingPreview: RemoteMaskingPreview?
    @Published var callerKeys: [RemoteCallerKey] = []

    // MARK: - Action Errors
    @Published var lastActionError: String?

    let client = MagpieWebClient()

    private let serversKey = "magpie.remote.servers.v1"
    private let activeServerKey = "magpie.remote.activeServerID.v1"
    private var traceLoopTask: Task<Void, Never>?
    private var quotaPollTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

    init() {
        loadServers()
        loadAlertConfig()
        QuotaNotificationManager.shared.configureDelegate()
        QuotaNotificationManager.shared.onSelectDeepLink = { [weak self] url in
            self?.handleDeepLink(url)
        }
        Task {
            await refreshNotificationAuthState()
            await configureClientForActiveServer()
            if activeServer != nil {
                await connectAndRefreshAll()
            }
        }
    }

    deinit {
        traceLoopTask?.cancel()
        quotaPollTask?.cancel()
    }

    var activeServer: MagpieServerProfile? {
        guard let id = activeServerID else { return nil }
        return servers.first(where: { $0.id == id })
    }

    func webKey(for serverID: UUID) -> String {
        KeychainStore.loadWebKey(forServerID: serverID) ?? ""
    }

    // MARK: - Toast & Clipboard

    func showToast(_ message: String) {
        toastTask?.cancel()
        toastMessage = message
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if !Task.isCancelled {
                toastMessage = nil
            }
        }
    }

    func copyToClipboard(_ text: String, label: String) {
        UIPasteboard.general.string = text
        showToast("已复制\(label)")
    }

    // MARK: - Server CRUD

    func saveServer(
        editingID: UUID?,
        name: String,
        rawAddressOrLink: String,
        rawWebKey: String,
        allowInsecureTLS: Bool,
        activateImmediately: Bool = true
    ) -> Result<MagpieServerProfile, ProfileSaveError> {
        let trimmedInput = rawAddressOrLink.trimmingCharacters(in: .whitespacesAndNewlines)
        var resolvedBaseURL: String?
        var resolvedKey = rawWebKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if let parsed = MagpieWebLinkParser.parse(trimmedInput) {
            resolvedBaseURL = parsed.baseURL
            if resolvedKey.isEmpty, let extracted = parsed.webKey {
                resolvedKey = extracted
            }
        } else {
            let check = URLValidator.validateAndNormalize(trimmedInput)
            guard case .valid(let normalized) = check else {
                return .failure(.message(check.errorReason ?? "服务器地址不合法"))
            }
            resolvedBaseURL = normalized
        }

        guard let baseURL = resolvedBaseURL else {
            return .failure(.message("服务器地址不合法"))
        }

        if resolvedKey.isEmpty {
            if let editingID = editingID, !webKey(for: editingID).isEmpty {
                resolvedKey = webKey(for: editingID)
            } else {
                return .failure(.message("请输入 magpie web 访问密钥 k（或直接粘贴带 ?k= 的启动链接）"))
            }
        }

        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = cleanName.isEmpty ? (URL(string: baseURL)?.host ?? "Magpie 实例") : cleanName

        let saved: MagpieServerProfile
        if let editingID = editingID, let idx = servers.firstIndex(where: { $0.id == editingID }) {
            var updated = servers[idx]
            updated.name = finalName
            updated.baseURL = baseURL
            updated.allowInsecureTLS = allowInsecureTLS
            updated.updatedAt = Date()
            servers[idx] = updated
            saved = updated
        } else {
            let created = MagpieServerProfile(
                name: finalName,
                baseURL: baseURL,
                allowInsecureTLS: allowInsecureTLS
            )
            servers.insert(created, at: 0)
            saved = created
        }

        KeychainStore.saveWebKey(resolvedKey, forServerID: saved.id)

        if activateImmediately || activeServerID == nil {
            activeServerID = saved.id
        }
        persistServers()

        Task {
            await configureClientForActiveServer()
            await connectAndRefreshAll()
        }
        return .success(saved)
    }

    func activateServer(_ server: MagpieServerProfile) {
        stopLiveTrace()
        activeServerID = server.id
        persistServers()
        resetRemoteData()
        showToast("已切换至「\(server.name)」")
        Task {
            await configureClientForActiveServer()
            await connectAndRefreshAll()
        }
    }

    func deleteServer(_ server: MagpieServerProfile) {
        stopLiveTrace()
        servers.removeAll { $0.id == server.id }
        KeychainStore.deleteWebKey(forServerID: server.id)
        if activeServerID == server.id {
            activeServerID = servers.first?.id
            resetRemoteData()
        }
        persistServers()
        showToast("已移除「\(server.name)」")
        Task {
            await configureClientForActiveServer()
            if activeServer != nil {
                await connectAndRefreshAll()
            }
        }
    }

    private func resetRemoteData() {
        remoteState = nil
        remoteSettings = RemoteSettingsState()
        providers = []
        presets = []
        pluginSubs = []
        pluginListings = []
        onPlugins = []
        movableSubs = []
        movesTo = [:]
        unmovedSubs = []
        withdrawnPlugins = []
        agyMoveUsers = []
        excludedAccounts = []
        loginUsageByAgent = [:]
        gatewayStatus = nil
        groups = []
        groupModels = []
        groupDeciders = []
        groupDrawers = []
        groupTemplates = []
        groupDefaults = nil
        autoGroupsFound = false
        balanceOutputsByID = [:]
        traceRoutes = []
        traceTotals = RemoteTraceTotals()
        traceSeq = 0
        historyDays = []
        historyRoutes = []
        usageSummary = nil
        todayUsageSummary = nil
        usageError = nil
        pendingAccountJump = nil
        quotas = []
        quotaAlerts = []
        lastQuickSwitchResult = nil
        recomputeAlertsAndWidgetSnapshot(triggerNotifications: false)
        maskingSummary = nil
        maskingRecords = []
        maskingPreview = nil
        callerKeys = []
        health = .untested
        lastActionError = nil
    }

    private func configureClientForActiveServer() async {
        if let server = activeServer {
            await client.configure(server: server, webKey: webKey(for: server.id))
        } else {
            await client.configure(server: nil, webKey: "")
        }
    }

    // MARK: - Connection & Full Sync

    func connectAndRefreshAll() async {
        guard activeServer != nil else {
            health = .untested
            return
        }
        isConnecting = true
        lastActionError = nil
        health = .checking

        do {
            await configureClientForActiveServer()
            let (stateResp, latency) = try await client.probeAndFetchState(forceReauth: true)
            remoteState = stateResp
            remoteSettings = stateResp.settings
            health = ConnectionHealth(
                kind: .connected,
                latencyMs: latency,
                statusCode: 200,
                message: "已认证（Cookie 有效）· 服务 \(stateResp.served) 个模型",
                checkedAt: Date()
            )
            isConnecting = false

            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.refreshProviders() }
                group.addTask { await self.refreshGroups() }
                group.addTask { await self.refreshTraceOnce() }
                group.addTask { await self.refreshUsage() }
                group.addTask { await self.refreshQuotas(asked: false, all: false) }
                group.addTask { await self.refreshSettings() }
            }
            await refreshAllLoginUsagesForSubscriptionProviders()
            await refreshTodayUsageForWidgetIfNeeded()
            recomputeAlertsAndWidgetSnapshot(triggerNotifications: true)
            startLiveTraceIfNeeded()
        } catch {
            isConnecting = false
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            health = ConnectionHealth(
                kind: .failed,
                latencyMs: nil,
                statusCode: nil,
                message: msg,
                checkedAt: Date()
            )
            lastActionError = msg
        }
    }

    // MARK: - Trace & History

    func startLiveTraceIfNeeded() {
        guard activeServer != nil, health.kind == .connected else { return }
        if traceLoopTask != nil { return }
        isLiveTraceActive = true
        traceLoopTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                do {
                    let seq = self.traceSeq
                    let resp = try await self.client.fetchTrace(after: seq, wait: true)
                    if Task.isCancelled { break }
                    self.applyTraceResponse(resp)
                    if resp.seq == seq {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                    }
                } catch {
                    if Task.isCancelled { break }
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                }
            }
        }
    }

    func stopLiveTrace() {
        traceLoopTask?.cancel()
        traceLoopTask = nil
        isLiveTraceActive = false
    }

    func refreshTraceOnce() async {
        do {
            let resp = try await client.fetchTrace(after: 0, wait: false)
            applyTraceResponse(resp)
        } catch {
            recordActionError(error)
        }
    }

    private func applyTraceResponse(_ resp: RemoteTraceResponse) {
        if traceSeq != resp.seq {
            traceSeq = resp.seq
        }
        if traceTotals != resp.totals {
            traceTotals = resp.totals
        }
        if resp.ids.isEmpty && traceRoutes.isEmpty {
            let sorted = resp.routes.sorted { $0.id > $1.id }
            if traceRoutes != sorted {
                traceRoutes = sorted
            }
            return
        }
        var byID: [Int64: RemoteRoute] = [:]
        for r in traceRoutes { byID[r.id] = r }
        for r in resp.routes { byID[r.id] = r }
        if !resp.ids.isEmpty {
            let valid = Set(resp.ids)
            byID = byID.filter { valid.contains($0.key) }
        }
        let sorted = byID.values.sorted { $0.id > $1.id }
        if traceRoutes != sorted {
            traceRoutes = sorted
        }
    }

    func loadHistory(day: String? = nil) async {
        do {
            let resp = try await client.fetchHistory(day: day)
            historyDays = resp.days
            historyRoutes = resp.routes.sorted { $0.id > $1.id }
            if selectedHistoryDay.isEmpty, let first = resp.days.first {
                selectedHistoryDay = first
            }
        } catch {
            recordActionError(error)
        }
    }

    func fetchCallDetail(routeID: Int64) async -> Result<RemoteGatewayCallDetail, MagpieWebError> {
        do {
            let detail = try await client.fetchCallDetail(routeID: routeID)
            return .success(detail)
        } catch let err as MagpieWebError {
            return .failure(err)
        } catch {
            return .failure(.networkError(error.localizedDescription))
        }
    }

    // MARK: - Providers & Groups

    func applyProvidersResponse(_ resp: RemoteProvidersResponse) {
        providers = resp.providers
        if !resp.presets.isEmpty {
            presets = resp.presets
        }
        if let gw = resp.gateway {
            gatewayStatus = gw
        }
        pluginSubs = resp.plugins
        onPlugins = resp.onPlugins
        movableSubs = resp.movable
        movesTo = resp.movesTo
        unmovedSubs = resp.unmoved
        withdrawnPlugins = resp.withdrawn
        agyMoveUsers = resp.agyMove
        excludedAccounts = resp.excluded
        codexDaemonStale = resp.codexDaemon
        codexAppStale = resp.codexApp
        codexProjectsShort = resp.codexProjects
        recomputeAlertsAndWidgetSnapshot(triggerNotifications: false)
    }

    func applyGroupsResponse(_ resp: RemoteGroupsResponse) {
        groups = resp.groups
        groupModels = resp.models
        groupDeciders = resp.deciders
        groupDrawers = resp.drawers
        groupTemplates = resp.templates
        if let defs = resp.defaults {
            groupDefaults = defs
        }
        autoGroupsFound = resp.found
    }

    func applyStateResponse(_ resp: RemoteStateResponse) {
        remoteState = resp
        remoteSettings = resp.settings
        if let notice = resp.notice, !notice.isEmpty {
            showToast(notice)
        }
    }

    func refreshProviders() async {
        do {
            let resp = try await client.fetchProviders()
            applyProvidersResponse(resp)
        } catch {
            recordActionError(error)
        }
    }

    func toggleProvider(_ provider: RemoteProvider, enabled: Bool) async {
        do {
            let resp = try await client.setProviderEnabled(id: provider.id, enabled: enabled)
            applyProvidersResponse(resp)
            showToast(enabled ? "已启用「\(provider.name)」" : "已停用「\(provider.name)」")
        } catch {
            recordActionError(error)
        }
    }

    func testProvider(_ provider: RemoteProvider) async -> String {
        do {
            let results = try await client.testProvider(id: provider.id)
            if results.isEmpty {
                return "未返回探测结果"
            }
            let summary = results.map { item -> String in
                let p = item.proto ?? "api"
                if item.ok {
                    return "\(p): OK (\(item.ms ?? 0) ms)"
                }
                return "\(p): 失败 \(item.error ?? "HTTP \(item.status ?? 0)")"
            }.joined(separator: "\n")
            return summary
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            recordActionError(error)
            return msg
        }
    }

    func refreshProviderModels(_ provider: RemoteProvider) async {
        do {
            let resp = try await client.refreshProviderModels(id: provider.id)
            if let updated = resp.provider, let idx = providers.firstIndex(where: { $0.id == updated.id }) {
                providers[idx] = updated
            } else {
                await refreshProviders()
            }
            await refreshGroups()
            showToast("「\(provider.name)」已同步 \(resp.count) 个模型")
        } catch {
            recordActionError(error)
        }
    }

    func refreshProviderBalance(_ provider: RemoteProvider) async {
        do {
            let resp = try await client.refreshProviderBalance(id: provider.id)
            if resp.ok {
                let amount = resp.amount ?? "已返回"
                balanceOutputsByID[provider.id] = "余额：\(amount)"
                showToast("「\(provider.name)」余额：\(amount)")
            } else if let err = resp.error, !err.isEmpty {
                balanceOutputsByID[provider.id] = "查询失败：\(err)"
                showToast(err)
            } else if resp.undetected {
                balanceOutputsByID[provider.id] = "未自动探测到余额接口，可在高级设置填写 Balance URL"
                showToast("未探测到余额接口")
            } else {
                balanceOutputsByID[provider.id] = "暂无余额数据"
            }
            await refreshProviders()
        } catch {
            recordActionError(error)
        }
    }

    func addCustomProvider(
        name: String,
        key: String,
        chatURL: String,
        anthropicURL: String,
        responsesURL: String,
        geminiURL: String
    ) async -> Bool {
        do {
            let resp = try await client.saveCustomProvider(
                id: nil,
                name: name,
                key: key,
                chat: chatURL,
                anthropic: anthropicURL,
                responses: responsesURL,
                gemini: geminiURL
            )
            providers = resp.providers
            showToast("已添加供应商「\(name)」")
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func deleteProvider(_ provider: RemoteProvider) async {
        do {
            let resp = try await client.deleteProvider(id: provider.id)
            providers = resp.providers
            showToast("已删除「\(provider.name)」")
        } catch {
            recordActionError(error)
        }
    }

    func refreshGroups() async {
        do {
            let resp = try await client.fetchGroups()
            applyGroupsResponse(resp)
        } catch {
            recordActionError(error)
        }
    }

    func switchGroup(_ group: RemoteRoutingGroup, enabled: Bool) async {
        do {
            let resp = try await client.switchGroup(id: group.id, on: enabled)
            applyGroupsResponse(resp)
            showToast(enabled ? "已开启路由组「\(group.name)」" : "已停用路由组「\(group.name)」")
        } catch {
            recordActionError(error)
        }
    }

    func pickGroupMember(_ group: RemoteRoutingGroup, member: String) async {
        do {
            let resp = try await client.pickGroupMember(id: group.id, member: member)
            applyGroupsResponse(resp)
            showToast("已切换成员：\(member)")
        } catch {
            recordActionError(error)
        }
    }

    // MARK: - Usage & Quotas

    // MARK: - Error Aggregation & Jump

    var accountErrorItems: [AccountErrorItem] {
        AccountErrorAggregator.aggregate(
            providers: providers,
            excludedAccounts: excludedAccounts,
            loginUsageByAgent: loginUsageByAgent,
            quotas: quotas,
            routes: traceRoutes + historyRoutes
        )
    }

    func jumpToAccount(_ item: AccountErrorItem) {
        pendingAccountJump = AccountJumpTarget(
            providerID: item.providerID,
            tab: item.targetTab,
            accountUser: item.accountUser,
            keyID: item.keyID
        )
    }

    func refreshUsage(period: String? = nil) async {
        if let p = period {
            if p == "custom" {
                usagePeriodPreset = "custom"
                let range = UsageDateRange(startDate: customUsageStart, endDate: customUsageEnd)
                usagePeriod = range.apiPeriodString()
            } else if p.contains("..") {
                usagePeriodPreset = "custom"
                usagePeriod = p
            } else {
                usagePeriodPreset = p
                usagePeriod = p
            }
        }
        isLoadingUsage = true
        usageError = nil
        defer { isLoadingUsage = false }
        do {
            let fetched = try await client.fetchUsage(period: usagePeriod)
            usageSummary = fetched
            if usagePeriod == "today" {
                todayUsageSummary = fetched
            }
            recomputeAlertsAndWidgetSnapshot(triggerNotifications: false)
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            usageError = msg
            recordActionError(error)
        }
    }

    func refreshCustomUsage(start: Date, end: Date) async {
        let range = UsageDateRange(startDate: start, endDate: end)
        let norm = range.normalized()
        customUsageStart = norm.start
        customUsageEnd = norm.end
        usagePeriodPreset = "custom"
        usagePeriod = range.apiPeriodString()
        await refreshUsage()
    }

    func refreshQuotas(asked: Bool = true, all: Bool = false) async {
        quotaPollTask?.cancel()
        isLoadingQuotas = true
        do {
            let res = try await client.fetchQuotas(asked: asked, all: all)
            quotas = res.quotas
            isLoadingQuotas = false
            recomputeAlertsAndWidgetSnapshot(triggerNotifications: !res.isReading)
            if res.isReading {
                scheduleQuotaFollowUp()
            }
        } catch {
            isLoadingQuotas = false
            recordActionError(error)
        }
    }

    func refreshSingleQuota(provider: String, user: String?) async {
        do {
            quotas = try await client.refreshQuota(provider: provider, user: user)
            recomputeAlertsAndWidgetSnapshot(triggerNotifications: true)
            showToast("已刷新额度窗口")
        } catch {
            recordActionError(error)
        }
    }

    private func scheduleQuotaFollowUp() {
        quotaPollTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self = self, !Task.isCancelled else { return }
            if let res = try? await self.client.fetchQuotas(asked: false, all: false) {
                self.quotas = res.quotas
                self.recomputeAlertsAndWidgetSnapshot(triggerNotifications: !res.isReading)
                if res.isReading && !Task.isCancelled {
                    self.scheduleQuotaFollowUp()
                }
            }
        }
    }

    // MARK: - Masking, Settings & Caller Keys

    func refreshSettings() async {
        do {
            remoteSettings = try await client.fetchSettings()
        } catch {
            recordActionError(error)
        }
    }

    func refreshMaskingData() async {
        do {
            async let sum = client.fetchMaskingSummary(days: 7)
            async let rec = client.fetchMaskingRecords(limit: 40)
            async let keys = client.fetchCallerKeys()
            maskingSummary = try await sum
            maskingRecords = try await rec.records
            callerKeys = try await keys
        } catch {
            recordActionError(error)
        }
    }

    func updatePrivacySettingsPatch(_ patch: [String: Any]) async {
        do {
            remoteSettings = try await client.patchSettings(patch)
            showToast("已同步服务端脱敏配置")
        } catch {
            recordActionError(error)
        }
    }

    func saveRedactRules(_ rules: [RemoteRedactRule]) async {
        do {
            remoteSettings = try await client.updateRedactRules(rules)
            showToast("已保存自定义脱敏规则")
        } catch {
            recordActionError(error)
        }
    }

    func saveRedactAllow(_ allow: [String]) async {
        do {
            remoteSettings = try await client.updateRedactAllow(allow)
            showToast("已更新脱敏放行白名单")
        } catch {
            recordActionError(error)
        }
    }

    func runMaskingPreview(text: String) async {
        do {
            maskingPreview = try await client.previewMasking(text: text)
        } catch {
            recordActionError(error)
        }
    }

    func clearMaskingRecords() async {
        do {
            try await client.clearMaskingRecords()
            maskingRecords = []
            maskingSummary = nil
            showToast("已清空服务端脱敏记录")
        } catch {
            recordActionError(error)
        }
    }

    func setLANEnabled(_ on: Bool, rotateKey: Bool = false) async {
        do {
            remoteSettings = try await client.updateLAN(on: on, newKey: rotateKey)
            await refreshProviders()
            showToast(on ? "已开启局域网共享" : "已关闭局域网共享")
        } catch {
            recordActionError(error)
        }
    }

    func saveAllowIPs(_ rawText: String) async {
        let ips = rawText
            .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == " " })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        do {
            remoteSettings = try await client.updateAllowIPs(ips)
            showToast("已保存 IP 白名单")
        } catch {
            recordActionError(error)
        }
    }

    func saveBarkConfig(server: String, key: String, daily: String) async {
        do {
            remoteSettings = try await client.updateBark(
                server: server.trimmingCharacters(in: .whitespacesAndNewlines),
                key: key.isEmpty ? nil : key.trimmingCharacters(in: .whitespacesAndNewlines),
                daily: daily.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            showToast("已保存 Bark 推送配置")
        } catch {
            recordActionError(error)
        }
    }

    func sendBarkTest() async {
        do {
            try await client.testBark()
            showToast("已发送 Bark 测试推送")
        } catch {
            recordActionError(error)
        }
    }

    // MARK: - Persistence & Helpers

    func recordActionError(_ error: Error) {
        let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        lastActionError = msg
        showToast(msg)
    }

    private func loadServers() {
        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: serversKey),
           let decoded = try? decoder.decode([MagpieServerProfile].self, from: data) {
            servers = decoded
        }
        if let idStr = UserDefaults.standard.string(forKey: activeServerKey),
           let uuid = UUID(uuidString: idStr),
           servers.contains(where: { $0.id == uuid }) {
            activeServerID = uuid
        } else {
            activeServerID = servers.first?.id
        }
    }

    private func persistServers() {
        if let data = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(data, forKey: serversKey)
        }
        if let id = activeServerID {
            UserDefaults.standard.set(id.uuidString, forKey: activeServerKey)
        } else {
            UserDefaults.standard.removeObject(forKey: activeServerKey)
        }
    }
}

enum ProfileSaveError: Error {
    case message(String)

    var text: String {
        switch self {
        case .message(let s): return s
        }
    }
}
