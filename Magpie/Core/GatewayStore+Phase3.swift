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
            guard let fetchedAt = todayUsageFetchedAt, Calendar.current.isDateInToday(fetchedAt) else { return nil }
            if usagePeriod == "today", let u = usageSummary {
                return u
            }
            return todayUsageSummary
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
            now: lastWidgetDataRefresh ?? todayUsageFetchedAt ?? Date(timeIntervalSince1970: 0)
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
            todayUsageFetchedAt = Date()
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
        guard !isSwitchingAccount else {
            return failedSwitch(provider: provider, target: targetID, message: "已有切号操作正在进行，请稍候")
        }
        isSwitchingAccount = true
        defer { isSwitchingAccount = false }
        let serverID = activeServerID
        var before: RemoteProvider = provider
        var endpoints: [String] = []
        var attemptedMutation = false
        do {
            let latest = try await client.fetchProviders()
            guard serverID == activeServerID,
                  let fresh = latest.providers.first(where: { $0.id == provider.id }) else {
                throw MagpieWebError.decodingError("实例或账号池已改变，请重新打开号池")
            }
            before = fresh
            applyProvidersResponse(latest)
            let origin = fresh.account?.logins.first(where: \.active)?.user ?? fresh.account?.user ?? fresh.keyList.first(where: \.active)?.id
            guard !fresh.off,
                  let plan = quickSwitchPlan(for: fresh, sourceID: origin),
                  plan.candidates.contains(where: { $0.id.caseInsensitiveCompare(targetID) == .orderedSame }) else {
                throw MagpieWebError.decodingError("目标账号已不可用或已是当前账号，请刷新后重选")
            }
            let order = fresh.account?.logins.map(\.user)
            attemptedMutation = true
            if let order = order {
                let next = [targetID] + order.filter { $0.caseInsensitiveCompare(targetID) != .orderedSame }
                endpoints.append("POST /api/provider/arrange")
                _ = try await client.arrangeProviderAccounts(id: fresh.id, accountOrder: next)
            } else {
                endpoints.append("POST /api/keys/use")
                _ = try await client.useProviderKey(id: fresh.id, ref: targetID)
            }
            // A successful HTTP status alone is not proof the selection changed.
            let checked = try await client.fetchProviders()
            guard serverID == activeServerID, let selected = checked.providers.first(where: { $0.id == fresh.id }),
                  switchSelectionMatches(selected, targetID: targetID, original: fresh) else {
                throw MagpieWebError.decodingError("服务端尚未确认目标账号已置顶，正在核查并恢复")
            }
            applyProvidersResponse(checked)
            let result = QuickSwitchResult(
                id: UUID(), succeeded: true, providerID: fresh.id, providerName: fresh.name,
                agent: fresh.account?.agent, kind: plan.kind, fromID: origin,
                fromDisplay: origin.map { AccountSwitchPlanner.displayName(for: $0, in: fresh) } ?? "原账号",
                toID: targetID, toDisplay: plan.candidates.first(where: { $0.id == targetID })?.displayName ?? targetID,
                executedEndpoints: endpoints, rolledBack: false,
                message: "服务端已确认目标账号优先顺序，账号池完整保留。实际请求仍受当前调度策略与模型可用范围约束。",
                previousOrder: order, timestamp: Date())
            lastQuickSwitchResult = result
            recomputeAlertsAndWidgetSnapshot(triggerNotifications: false)
            showToast("已确认切至「\(result.toDisplay)」")
            return result
        } catch {
            let reason = error.localizedDescription
            var recovered = false
            if attemptedMutation && serverID == activeServerID {
                // A timeout is an unknown outcome: inspect current state before any recovery write.
                if let state = try? await client.fetchProviders(), let current = state.providers.first(where: { $0.id == before.id }) {
                    let originalIDs = Set(before.account?.logins.map(\.user) ?? before.keyList.map(\.id))
                    let currentIDs = Set(current.account?.logins.map(\.user) ?? current.keyList.map(\.id))
                    if originalIDs == currentIDs {
                        if let order = before.account?.logins.map(\.user) {
                            _ = try? await client.arrangeProviderAccounts(id: before.id, accountOrder: order)
                        } else if let old = before.keyList.first(where: \.active)?.id {
                            _ = try? await client.useProviderKey(id: before.id, ref: old)
                        }
                        if let verified = try? await client.fetchProviders(), let restored = verified.providers.first(where: { $0.id == before.id }) {
                            recovered = (restored.account?.logins.map(\.user) == before.account?.logins.map(\.user))
                                && restored.keyList.first(where: \.active)?.id == before.keyList.first(where: \.active)?.id
                            applyProvidersResponse(verified)
                        }
                    } else {
                        applyProvidersResponse(state)
                    }
                }
            }
            let suffix = !attemptedMutation ? "未提交切号修改。" : (recovered ? "已读回确认原顺序恢复。" : "结果未确定，请刷新号池核实；未执行删除或凭据覆盖。")
            var result = failedSwitch(provider: before, target: targetID, message: "切号未完成：\(reason)。\(suffix)", endpoints: endpoints, recovered: recovered)
            if serverID != activeServerID { result = failedSwitch(provider: before, target: targetID, message: "实例已切换，请回到原实例核查操作结果") }
            lastQuickSwitchResult = result
            showToast(result.message)
            return result
        }
    }

    private func switchSelectionMatches(_ selected: RemoteProvider, targetID: String, original: RemoteProvider) -> Bool {
        if let logins = selected.account?.logins, let old = original.account?.logins {
            return logins.first?.user.caseInsensitiveCompare(targetID) == .orderedSame && Set(logins.map(\.user)) == Set(old.map(\.user))
        }
        return selected.keyList.first(where: \.active)?.id == targetID && Set(selected.keyList.map(\.id)) == Set(original.keyList.map(\.id))
    }

    private func failedSwitch(provider: RemoteProvider, target: String, message: String, endpoints: [String] = [], recovered: Bool = false) -> QuickSwitchResult {
        QuickSwitchResult(id: UUID(), succeeded: false, providerID: provider.id, providerName: provider.name,
                          agent: provider.account?.agent, kind: provider.account == nil ? .apiKey : .subscription,
                          fromID: nil, fromDisplay: "原账号", toID: target, toDisplay: target,
                          executedEndpoints: endpoints, rolledBack: recovered, message: message, previousOrder: nil, timestamp: Date())
    }

    func undoLastQuickSwitch(_ result: QuickSwitchResult) async -> Bool {
        guard !isSwitchingAccount, result.succeeded else { return false }
        isSwitchingAccount = true
        defer { isSwitchingAccount = false }
        do {
            let latest = try await client.fetchProviders()
            guard let p = latest.providers.first(where: { $0.id == result.providerID }) else { return false }
            if let order = result.previousOrder {
                guard Set(order) == Set(p.account?.logins.map(\.user) ?? []), p.account?.logins.first?.user == result.toID else {
                    throw MagpieWebError.decodingError("账号池已再次改变，撤回已停止，请手动选择账号")
                }
                _ = try await client.arrangeProviderAccounts(id: p.id, accountOrder: order)
            } else if let old = result.fromID {
                guard p.keyList.first(where: \.active)?.id == result.toID else {
                    throw MagpieWebError.decodingError("主用 Key 已再次改变，撤回已停止")
                }
                _ = try await client.useProviderKey(id: p.id, ref: old)
            }
            let state = try await client.fetchProviders()
            guard let p = state.providers.first(where: { $0.id == result.providerID }),
                  (result.previousOrder.map { $0 == p.account?.logins.map(\.user) } ?? (p.keyList.first(where: \.active)?.id == result.fromID)) else {
                throw MagpieWebError.decodingError("撤回尚未得到服务端确认，请刷新核查")
            }
            applyProvidersResponse(state)
            lastQuickSwitchResult = nil
            showToast("已确认恢复原账号顺序")
            return true
        } catch { recordActionError(error); return false }
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
            todayUsageFetchedAt = Date()
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
