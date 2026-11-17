import Foundation
import SwiftUI

extension GatewayStore {

    // MARK: - Alert Configuration & Persistence

    func loadAlertConfig() {
        if let data = UserDefaults.standard.data(forKey: "magpie.quotaAlertConfig.v1"),
           let decoded = try? JSONDecoder().decode(QuotaAlertConfig.self, from: data) {
            alertConfig = decoded
        }
        widgetSnapshot = MagpieWidgetSnapshotStore.load() ?? .unconfigured
    }

    func saveAlertConfig(_ next: QuotaAlertConfig) {
        var clamped = next
        clamped.defaultRemainingThresholdPercent = QuotaAlertConfig.clampThreshold(next.defaultRemainingThresholdPercent)
        alertConfig = clamped
        if let data = try? JSONEncoder().encode(clamped) {
            UserDefaults.standard.set(data, forKey: "magpie.quotaAlertConfig.v1")
        }
        recomputeAlertsAndWidgetSnapshot(triggerNotifications: false)
    }

    func refreshNotificationAuthState() async {
        notificationAuthState = await QuotaNotificationManager.shared.currentAuthState()
    }

    func setLocalNotificationsEnabled(_ enabled: Bool) async {
        var next = alertConfig
        if enabled {
            let state = await QuotaNotificationManager.shared.currentAuthState()
            if state == .notDetermined {
                let res = await QuotaNotificationManager.shared.requestAuthorization()
                notificationAuthState = res.state
                if !res.granted {
                    next.notificationsEnabled = false
                    saveAlertConfig(next)
                    showToast("未获得系统通知权限，可在系统设置中开启")
                    return
                }
            } else if state == .denied {
                notificationAuthState = .denied
                next.notificationsEnabled = false
                saveAlertConfig(next)
                showToast("系统通知已关闭，请前往系统设置开启后再启用")
                return
            } else {
                notificationAuthState = state
            }
        }
        next.notificationsEnabled = enabled
        saveAlertConfig(next)
        if enabled {
            await evaluateAndDeliverNotifications()
        }
    }

    func requestNotificationPermissionExplicitly() async {
        let res = await QuotaNotificationManager.shared.requestAuthorization()
        notificationAuthState = res.state
        if res.granted {
            var next = alertConfig
            next.notificationsEnabled = true
            saveAlertConfig(next)
            showToast("已开启本地余量预警通知")
            await evaluateAndDeliverNotifications()
        } else {
            showToast("系统未授予通知权限")
        }
    }

    func sendTestLocalNotification() async {
        let res = await QuotaNotificationManager.shared.sendTestNotification()
        await refreshNotificationAuthState()
        switch res {
        case .success:
            showToast("已调度测试通知（1 秒后展示）")
        case .failure(let err):
            showToast(err.localizedDescription)
        }
    }

    // MARK: - Alerts & Widget Snapshot Synchronization

    func recomputeAlertsAndWidgetSnapshot(triggerNotifications: Bool) {
        let evaluated = QuotaAlertEvaluator.evaluate(
            providers: providers,
            quotas: quotas,
            loginUsageByAgent: loginUsageByAgent,
            config: alertConfig
        )
        quotaAlerts = evaluated

        let todayUsage: RemoteUsageResponse? = {
            if usagePeriod == "today", let u = usageSummary {
                return u
            }
            return todayUsageSummary ?? usageSummary
        }()

        let snapshot = MagpieWidgetSnapshotStore.buildSnapshot(
            isConfigured: activeServer != nil,
            isConnected: health.kind == .connected,
            serverName: activeServer?.name,
            serverBaseURL: activeServer?.baseURL,
            todayUsage: todayUsage,
            providers: providers,
            quotas: quotas,
            loginUsageByAgent: loginUsageByAgent,
            alerts: evaluated,
            alertThresholdPercent: alertConfig.defaultRemainingThresholdPercent,
            now: Date()
        )
        widgetSnapshot = snapshot
        MagpieWidgetSnapshotStore.save(snapshot)
        QuotaNotificationManager.shared.reloadWidgets()

        if triggerNotifications {
            Task {
                await evaluateAndDeliverNotifications()
            }
        }
    }

    func evaluateAndDeliverNotifications() async {
        _ = await QuotaNotificationManager.shared.processAlerts(
            quotaAlerts,
            serverID: activeServerID,
            config: alertConfig
        )
    }

    func refreshAllLoginUsagesForSubscriptionProviders() async {
        let agents = Set(providers.compactMap { p -> String? in
            guard !p.off, let acc = p.account, !acc.logins.isEmpty else { return nil }
            return acc.agent ?? p.id
        })
        await withTaskGroup(of: Void.self) { group in
            for agent in agents {
                group.addTask { await self.fetchLoginUsage(agent: agent) }
            }
        }
    }

    func refreshTodayUsageForWidgetIfNeeded() async {
        if usagePeriod == "today" {
            todayUsageSummary = usageSummary
            return
        }
        if let today = try? await client.fetchUsage(period: "today") {
            todayUsageSummary = today
            recomputeAlertsAndWidgetSnapshot(triggerNotifications: false)
        }
    }

    // MARK: - One-Tap Account / Key Switch

    func quickSwitchPlan(for provider: RemoteProvider, sourceID: String? = nil) -> QuickSwitchPlan? {
        AccountSwitchPlanner.plan(
            for: provider,
            sourceAccountOrKeyID: sourceID,
            loginUsageByAgent: loginUsageByAgent,
            quotas: quotas
        )
    }

    func executeQuickSwitch(provider: RemoteProvider, targetID: String, sourceID: String? = nil) async -> QuickSwitchResult {
        isSwitchingAccount = true
        defer { isSwitchingAccount = false }

        if let account = provider.account, !account.logins.isEmpty {
            let agent = account.agent ?? provider.id
            let logins = account.logins
            let previousOrder = logins.map(\.user)
            let resolvedFrom = sourceID
                ?? logins.first(where: { $0.active })?.user
                ?? account.user
                ?? previousOrder.first
            let fromDisplay = resolvedFrom.map { AccountSwitchPlanner.displayName(for: $0, in: provider) } ?? "当前账号"
            let toDisplay = AccountSwitchPlanner.displayName(for: targetID, in: provider)

            var executed: [String] = []
            var arranged = false

            do {
                if previousOrder.first?.caseInsensitiveCompare(targetID) != .orderedSame {
                    var nextOrder = previousOrder.filter { $0.caseInsensitiveCompare(targetID) != .orderedSame }
                    nextOrder.insert(targetID, at: 0)
                    let arrangedResp = try await client.arrangeProviderAccounts(id: provider.id, accountOrder: nextOrder)
                    applyProvidersResponse(arrangedResp)
                    executed.append("POST /api/provider/arrange")
                    arranged = true
                }

                let switchedResp = try await client.loginAction("switch", agent: agent, user: targetID)
                applyProvidersResponse(switchedResp)
                executed.append("POST /api/login/switch")

                await fetchLoginUsage(agent: agent)
                await refreshStateOnly()
                await refreshQuotas(asked: false, all: false)
                recomputeAlertsAndWidgetSnapshot(triggerNotifications: false)

                let res = QuickSwitchResult(
                    id: UUID(),
                    succeeded: true,
                    providerID: provider.id,
                    providerName: provider.name,
                    agent: agent,
                    kind: .subscription,
                    fromID: resolvedFrom,
                    fromDisplay: fromDisplay,
                    toID: targetID,
                    toDisplay: toDisplay,
                    executedEndpoints: executed,
                    rolledBack: false,
                    message: "已切至「\(toDisplay)」（已置顶为顺位 #1 并切换当前活跃账号，原账号已保留未覆盖）",
                    previousOrder: previousOrder,
                    timestamp: Date()
                )
                lastQuickSwitchResult = res
                showToast("已切换至「\(toDisplay)」")
                return res
            } catch {
                var rolledBack = false
                if arranged {
                    if let rollbackResp = try? await client.arrangeProviderAccounts(id: provider.id, accountOrder: previousOrder) {
                        applyProvidersResponse(rollbackResp)
                        rolledBack = true
                    }
                }
                let errMsg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                let msg = rolledBack
                    ? "切号未完成（\(errMsg)），已自动恢复原账号顺序「\(fromDisplay)」，未覆盖任何账号。"
                    : "切号失败：\(errMsg)。所有已有账号均保留在号池中。"
                let res = QuickSwitchResult(
                    id: UUID(),
                    succeeded: false,
                    providerID: provider.id,
                    providerName: provider.name,
                    agent: agent,
                    kind: .subscription,
                    fromID: resolvedFrom,
                    fromDisplay: fromDisplay,
                    toID: targetID,
                    toDisplay: toDisplay,
                    executedEndpoints: executed,
                    rolledBack: rolledBack,
                    message: msg,
                    previousOrder: previousOrder,
                    timestamp: Date()
                )
                lastQuickSwitchResult = res
                lastActionError = msg
                showToast(msg)
                return res
            }
        } else {
            let keys = provider.keyList
            let resolvedFrom = sourceID ?? keys.first(where: \.active)?.id ?? keys.first?.id
            let fromKey = keys.first(where: { $0.id == resolvedFrom })
            let toKey = keys.first(where: { $0.id == targetID })
            let fromDisplay = (fromKey?.name?.isEmpty == false ? fromKey!.name! : fromKey?.masked) ?? "原 Key"
            let toDisplay = (toKey?.name?.isEmpty == false ? toKey!.name! : toKey?.masked) ?? targetID

            do {
                let resp = try await client.useProviderKey(id: provider.id, ref: targetID)
                applyProvidersResponse(resp)
                recomputeAlertsAndWidgetSnapshot(triggerNotifications: false)

                let res = QuickSwitchResult(
                    id: UUID(),
                    succeeded: true,
                    providerID: provider.id,
                    providerName: provider.name,
                    agent: nil,
                    kind: .apiKey,
                    fromID: resolvedFrom,
                    fromDisplay: fromDisplay,
                    toID: targetID,
                    toDisplay: toDisplay,
                    executedEndpoints: ["POST /api/keys/use"],
                    rolledBack: false,
                    message: "已将 Key「\(toDisplay)」设为优先使用（原 Key 已保留）",
                    previousOrder: nil,
                    timestamp: Date()
                )
                lastQuickSwitchResult = res
                showToast("已切至 Key「\(toDisplay)」")
                return res
            } catch {
                let errMsg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                let res = QuickSwitchResult(
                    id: UUID(),
                    succeeded: false,
                    providerID: provider.id,
                    providerName: provider.name,
                    agent: nil,
                    kind: .apiKey,
                    fromID: resolvedFrom,
                    fromDisplay: fromDisplay,
                    toID: targetID,
                    toDisplay: toDisplay,
                    executedEndpoints: [],
                    rolledBack: false,
                    message: "切换 Key 失败：\(errMsg)",
                    previousOrder: nil,
                    timestamp: Date()
                )
                lastQuickSwitchResult = res
                lastActionError = errMsg
                showToast(res.message)
                return res
            }
        }
    }

    func undoLastQuickSwitch(_ result: QuickSwitchResult) async -> Bool {
        guard result.succeeded, let provider = providers.first(where: { $0.id == result.providerID }) else {
            return false
        }
        isSwitchingAccount = true
        defer { isSwitchingAccount = false }

        switch result.kind {
        case .subscription:
            let agent = result.agent ?? provider.id
            do {
                if let prevOrder = result.previousOrder, !prevOrder.isEmpty {
                    let resp = try await client.arrangeProviderAccounts(id: provider.id, accountOrder: prevOrder)
                    applyProvidersResponse(resp)
                }
                if let prevUser = result.fromID, !prevUser.isEmpty {
                    let resp = try await client.loginAction("switch", agent: agent, user: prevUser)
                    applyProvidersResponse(resp)
                }
                await fetchLoginUsage(agent: agent)
                await refreshStateOnly()
                recomputeAlertsAndWidgetSnapshot(triggerNotifications: false)
                lastQuickSwitchResult = nil
                showToast("已恢复切回「\(result.fromDisplay)」")
                return true
            } catch {
                recordActionError(error)
                return false
            }
        case .apiKey:
            guard let prevKey = result.fromID, !prevKey.isEmpty else { return false }
            do {
                let resp = try await client.useProviderKey(id: provider.id, ref: prevKey)
                applyProvidersResponse(resp)
                recomputeAlertsAndWidgetSnapshot(triggerNotifications: false)
                lastQuickSwitchResult = nil
                showToast("已切回原 Key「\(result.fromDisplay)」")
                return true
            } catch {
                recordActionError(error)
                return false
            }
        }
    }

    // MARK: - Background Refresh & Deep Link

    func performBackgroundQuotaRefresh() async -> Bool {
        guard activeServer != nil else { return false }
        do {
            await configureClientForActiveServer()
            _ = try await client.probeAndFetchState(forceReauth: false)
            await refreshProviders()
            await refreshAllLoginUsagesForSubscriptionProviders()
            await refreshQuotas(asked: false, all: false)
            if let today = try? await client.fetchUsage(period: "today") {
                todayUsageSummary = today
                if usagePeriod == "today" {
                    usageSummary = today
                }
            }
            recomputeAlertsAndWidgetSnapshot(triggerNotifications: true)
            return true
        } catch {
            recomputeAlertsAndWidgetSnapshot(triggerNotifications: false)
            return false
        }
    }

    func handleDeepLink(_ url: URL) {
        guard let link = MagpieDeepLink.parse(url) else { return }
        pendingDeepLink = link
        if case .refresh = link {
            Task {
                await connectAndRefreshAll()
                showToast("已从桌面组件触发刷新")
            }
        }
    }
}
