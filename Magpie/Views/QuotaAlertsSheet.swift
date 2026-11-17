import SwiftUI
import UIKit

// MARK: - Reusable Quick Switch Feedback Banner

struct QuickSwitchResultBanner: View {
    @ObservedObject var store: GatewayStore
    let result: QuickSwitchResult
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        let tone = result.succeeded ? StatusPalette.ok : StatusPalette.err
        let surface = result.succeeded ? StatusPalette.okSurface : StatusPalette.errSurface

        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                Circle()
                    .fill(tone)
                    .frame(width: 7, height: 7)
                Text(result.succeeded ? "切号已完成 · \(result.providerName)" : "切号未完成 · \(result.providerName)")
                    .font(Typography.rowTitle)
                    .foregroundColor(MagpieTheme.ink)
                Spacer()
                if result.succeeded && result.fromID != nil {
                    Button(store.isSwitchingAccount ? "切回中…" : "撤回") {
                        Task { _ = await store.undoLastQuickSwitch(result) }
                    }
                    .font(Typography.captionMedium)
                    .foregroundColor(tone)
                    .disabled(store.isSwitchingAccount)
                    .accessibilityIdentifier("undoQuickSwitchButton")
                }
                if let onDismiss = onDismiss {
                    Button("关闭") { onDismiss() }
                        .font(Typography.caption)
                        .foregroundColor(MagpieTheme.textMuted)
                }
            }

            Text("\(result.fromDisplay) → \(result.toDisplay)")
                .font(Typography.captionMono)
                .foregroundColor(MagpieTheme.ink)

            Text(result.message)
                .font(Typography.caption)
                .foregroundColor(MagpieTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if !result.executedEndpoints.isEmpty {
                Text("已执行：\(result.executedEndpoints.joined(separator: " + "))")
                    .font(Typography.nanoMono)
                    .foregroundColor(MagpieTheme.textMuted)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: Corners.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Corners.lg, style: .continuous)
                .stroke(tone.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quickSwitchResultBanner")
    }
}

// MARK: - Quota Alerts, Rules & Widget Preview Sheet

struct QuotaAlertsSheet: View {
    @ObservedObject var store: GatewayStore
    var initialSection: SectionTab = .alerts
    var onJumpToBark: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    enum SectionTab: String, CaseIterable, Identifiable {
        case alerts = "预警列表"
        case rules = "阈值与通知"
        case widget = "桌面组件"

        var id: String { rawValue }
    }

    enum AlertViewMode: String, CaseIterable {
        case byAccount = "按账号"
        case byProvider = "按供应商"
    }

    @State private var activeSection: SectionTab = .alerts
    @State private var didApplyInitial = false
    @State private var viewMode: AlertViewMode = .byAccount
    @State private var thresholdInput: String = "10"
    @State private var thresholdError: String?
    @State private var editingOverrideTarget: OverrideTarget?
    @State private var overrideThresholdInput: String = ""
    @State private var isRefreshing = false

    struct OverrideTarget: Identifiable {
        let id: String
        let title: String
        let providerID: String
        let user: String?
        let currentThreshold: Int
        let hasCustomOverride: Bool
    }

    private var providerSummaries: [ProviderQuotaAlertSummary] {
        QuotaAlertEvaluator.summarizeByProvider(
            items: store.quotaAlerts,
            providers: store.providers,
            config: store.alertConfig
        )
    }

    var body: some View {
        NavigationView {
            ZStack {
                MagpieTheme.canvas.ignoresSafeArea()

                VStack(spacing: 0) {
                    sectionTabBar

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: Spacing.sectionGap) {
                            if let res = store.lastQuickSwitchResult {
                                QuickSwitchResultBanner(store: store, result: res) {
                                    store.lastQuickSwitchResult = nil
                                }
                            }

                            switch activeSection {
                            case .alerts:
                                alertsOverviewSection
                            case .rules:
                                rulesAndNotificationSection
                            case .widget:
                                widgetPreviewSection
                            }
                        }
                        .padding(.horizontal, Spacing.pageHorizontal)
                        .padding(.top, Spacing.sheetPadding)
                        .padding(.bottom, Spacing.pageBottom)
                    }
                }
            }
            .navigationTitle("余量预警与桌面组件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .foregroundColor(MagpieTheme.textSecondary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(isRefreshing ? "刷新中" : "刷新") {
                        refreshNow()
                    }
                    .foregroundColor(MagpieTheme.ink)
                    .disabled(isRefreshing || store.activeServer == nil)
                }
            }
            .onAppear {
                if !didApplyInitial {
                    activeSection = initialSection
                    didApplyInitial = true
                }
                thresholdInput = String(store.alertConfig.defaultRemainingThresholdPercent)
                Task { await store.refreshNotificationAuthState() }
            }
            .sheet(item: $editingOverrideTarget) { target in
                overrideEditorSheet(target)
            }
        }
        .navigationViewStyle(.stack)
    }

    private var sectionTabBar: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(SectionTab.allCases) { tab in
                let selected = activeSection == tab
                Button(tab.rawValue) {
                    activeSection = tab
                }
                .font(Typography.bodySmallMedium)
                .foregroundColor(selected ? MagpieTheme.onInk : MagpieTheme.textSecondary)
                .padding(.horizontal, Spacing.md + 1)
                .padding(.vertical, 6)
                .background(selected ? MagpieTheme.ink : MagpieTheme.surface)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(MagpieTheme.hairline, lineWidth: selected ? 0 : 1))
                .buttonStyle(.plain)
                .accessibilityIdentifier("quotaAlertsSection_\(tab == .alerts ? "alerts" : (tab == .rules ? "rules" : "widget"))")
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.pageHorizontal)
        .padding(.vertical, Spacing.sm)
        .background(MagpieTheme.canvas)
    }

    // MARK: - Tab 1: Alerts Overview

    private var alertsOverviewSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sectionGap) {
            MinimalSection(
                title: "余量预警状态",
                trailingText: "默认阈值 ≤ \(store.alertConfig.defaultRemainingThresholdPercent)%"
            ) {
                HStack(spacing: 0) {
                    statCell(
                        value: "\(store.quotaAlerts.count)",
                        label: "触发预警",
                        tone: store.quotaAlerts.isEmpty ? StatusPalette.ok : StatusPalette.warn
                    )
                    statCell(
                        value: "\(store.quotaAlerts.filter { $0.severity == .critical }.count)",
                        label: "告急 (≤3%)",
                        tone: store.quotaAlerts.contains { $0.severity == .critical } ? StatusPalette.err : MagpieTheme.textMuted
                    )
                    statCell(
                        value: "\(store.alertConfig.defaultRemainingThresholdPercent)%",
                        label: "默认余量阈值",
                        tone: MagpieTheme.ink
                    )
                }

                HStack(spacing: Spacing.sm) {
                    ForEach(AlertViewMode.allCases, id: \.self) { mode in
                        let selected = viewMode == mode
                        Button(mode.rawValue) {
                            viewMode = mode
                        }
                        .font(Typography.captionMedium)
                        .foregroundColor(selected ? MagpieTheme.onInk : MagpieTheme.textSecondary)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, 5)
                        .background(selected ? MagpieTheme.ink : MagpieTheme.canvas)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(MagpieTheme.hairline, lineWidth: selected ? 0 : 1))
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(mode == .byAccount ? "alertViewMode_account" : "alertViewMode_provider")
                    }
                    Spacer()
                    Button("调整阈值") {
                        activeSection = .rules
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))
                }
            }

            if viewMode == .byAccount {
                if store.quotaAlerts.isEmpty {
                    MinimalSection {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(StatusPalette.ok)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("已读取的数据暂无余量预警")
                                    .font(Typography.rowTitle)
                                    .foregroundColor(MagpieTheme.ink)
                                Text("未获取额度的账号不参与判断；已读取数据未触及设定阈值（默认 \(store.alertConfig.defaultRemainingThresholdPercent)%）。")
                                    .font(Typography.caption)
                                    .foregroundColor(MagpieTheme.textSecondary)
                            }
                        }
                    }
                } else {
                    ForEach(store.quotaAlerts) { item in
                        accountAlertCard(item)
                    }
                }
            } else {
                if providerSummaries.isEmpty {
                    MinimalSection {
                        Text("暂无可监控配额的供应商或账号。")
                            .font(Typography.body)
                            .foregroundColor(MagpieTheme.textSecondary)
                    }
                } else {
                    ForEach(providerSummaries) { summary in
                        providerAlertCard(summary)
                    }
                }
            }
        }
    }

    private func accountAlertCard(_ item: QuotaAlertItem) -> some View {
        let tone = item.severity == .critical ? StatusPalette.err : StatusPalette.warn
        let surface = item.severity == .critical ? StatusPalette.errSurface : StatusPalette.warnSurface
        let remainingStr = String(format: "%.0f%%", item.remainingPercent)

        return MinimalSection {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Circle()
                    .fill(tone)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Spacing.xs) {
                        Text(item.accountDisplayName)
                            .font(Typography.rowTitleMono)
                            .foregroundColor(MagpieTheme.ink)
                            .lineLimit(1)
                        MagpieTag(text: item.providerName)
                        if item.isCooling {
                            MagpieTag(text: "冷却中", tone: StatusPalette.warn, background: StatusPalette.warnSurface)
                        }
                    }
                    Text("\(item.windowName)\(item.affectedWindowCount > 1 ? " 等 \(item.affectedWindowCount) 项窗口" : "") · 阈值 ≤\(item.thresholdPercent)%")
                        .font(Typography.caption)
                        .foregroundColor(MagpieTheme.textSecondary)
                }
                Spacer()
                MagpieTag(
                    text: "\(item.severity.title) 剩 \(remainingStr)",
                    tone: tone,
                    background: surface,
                    monospaced: true
                )
            }

            MagpieProgressBar(ratio: item.usedPercent / 100.0)

            HStack(spacing: Spacing.sm) {
                if let targetUser = item.recommendedSwitchUser,
                   let targetDisplay = item.recommendedSwitchDisplay,
                   let provider = store.providers.first(where: { $0.id == item.providerID }) {
                    Button(store.isSwitchingAccount ? "切号中…" : "一键切至 \(targetDisplay)") {
                        Task {
                            _ = await store.executeQuickSwitch(
                                provider: provider,
                                targetID: targetUser,
                                sourceID: item.accountUser
                            )
                        }
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
                    .disabled(store.isSwitchingAccount)
                    .accessibilityIdentifier("quickSwitchAlertButton_\(item.accountUser ?? item.providerID)")
                } else {
                    Text("同平台暂无其他可用账号")
                        .font(Typography.caption)
                        .foregroundColor(MagpieTheme.textMuted)
                }

                Spacer()

                Button("定位号池") {
                    store.pendingAccountJump = AccountJumpTarget(
                        providerID: item.providerID,
                        tab: .keys,
                        accountUser: item.accountUser,
                        keyID: nil
                    )
                    dismiss()
                }
                .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quotaAlertCard_\(item.accountUser ?? item.providerID)")
    }

    private func providerAlertCard(_ summary: ProviderQuotaAlertSummary) -> some View {
        let hasAlert = summary.alertingAccountCount > 0
        let tone = hasAlert ? StatusPalette.warn : StatusPalette.ok

        return MinimalSection(
            title: summary.providerName,
            trailingText: "阈值 ≤ \(summary.effectiveThresholdPercent)%"
        ) {
            HStack(spacing: Spacing.sm) {
                Circle()
                    .fill(summary.isMuted ? StatusPalette.neutral : tone)
                    .frame(width: 8, height: 8)
                if summary.isMuted {
                    Text("已静音此供应商本地预警")
                        .font(Typography.bodySmall)
                        .foregroundColor(MagpieTheme.textMuted)
                } else if hasAlert {
                    let lowestStr = summary.lowestRemainingPercent.map { String(format: "%.0f%%", $0) } ?? "--"
                    Text("\(summary.alertingAccountCount) 个账号低于阈值 · 最低剩 \(lowestStr)")
                        .font(Typography.bodySmallMedium)
                        .foregroundColor(StatusPalette.warn)
                } else {
                    Text("未发现低于 \(summary.effectiveThresholdPercent)%")
                        .font(Typography.bodySmall)
                        .foregroundColor(StatusPalette.ok)
                }
                Spacer()
            }

            HStack(spacing: Spacing.xs) {
                Button("改此供应商阈值") {
                    let key = QuotaAlertConfig.providerKey(summary.providerID)
                    editingOverrideTarget = OverrideTarget(
                        id: key,
                        title: summary.providerName,
                        providerID: summary.providerID,
                        user: nil,
                        currentThreshold: summary.effectiveThresholdPercent,
                        hasCustomOverride: store.alertConfig.providerThresholds[key] != nil
                    )
                    overrideThresholdInput = String(summary.effectiveThresholdPercent)
                }
                .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))

                Button(summary.isMuted ? "取消静音" : "静音") {
                    var next = store.alertConfig
                    next.setMuted(!summary.isMuted, providerID: summary.providerID, user: nil)
                    store.saveAlertConfig(next)
                }
                .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))

                Spacer()

                Button("查看号池") {
                    store.pendingAccountJump = AccountJumpTarget(
                        providerID: summary.providerID,
                        tab: .keys,
                        accountUser: summary.items.first?.accountUser,
                        keyID: nil
                    )
                    dismiss()
                }
                .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))
            }
        }
    }

    // MARK: - Tab 2: Thresholds, Notifications & Honest Limitations

    private var rulesAndNotificationSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sectionGap) {
            MinimalSection(title: "全局余量预警阈值") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("启用本地余量预警评估")
                            .font(Typography.rowTitle)
                            .foregroundColor(MagpieTheme.ink)
                        Text("当账号/供应商非无限窗口剩余百分比 ≤ 阈值时展示预警")
                            .font(Typography.caption)
                            .foregroundColor(MagpieTheme.textSecondary)
                    }
                    Spacer()
                    MagpieToggle(isOn: Binding(
                        get: { store.alertConfig.enabled },
                        set: { val in
                            var next = store.alertConfig
                            next.enabled = val
                            store.saveAlertConfig(next)
                        }
                    ))
                }

                Rectangle().fill(MagpieTheme.hairline).frame(height: 1)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("默认剩余额度触发阈值 (%)")
                        .font(Typography.sectionHeader)
                        .foregroundColor(MagpieTheme.textSecondary)

                    HStack(spacing: Spacing.sm) {
                        TextField("10", text: $thresholdInput)
                            .keyboardType(.numberPad)
                            .font(Typography.bodyInputMono)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, 8)
                            .background(MagpieTheme.canvas)
                            .clipShape(RoundedRectangle(cornerRadius: Corners.sm + 1, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Corners.sm + 1, style: .continuous).stroke(MagpieTheme.hairline, lineWidth: 1))
                            .accessibilityIdentifier("globalAlertThresholdField")

                        Button("应用阈值") {
                            applyGlobalThreshold()
                        }
                        .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
                        .accessibilityIdentifier("saveGlobalAlertThresholdButton")
                    }

                    HStack(spacing: Spacing.xs) {
                        ForEach([5, 10, 20, 30], id: \.self) { preset in
                            let selected = store.alertConfig.defaultRemainingThresholdPercent == preset
                            Button("≤ \(preset)%") {
                                thresholdInput = String(preset)
                                applyGlobalThreshold()
                            }
                            .buttonStyle(MagpieButtonStyle(tone: selected ? .primary : .secondary, compact: true))
                        }
                        Spacer()
                        Button("收起键盘") {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                        .font(Typography.caption)
                        .foregroundColor(MagpieTheme.textMuted)
                    }

                    if let err = thresholdError {
                        Text(err)
                            .font(Typography.caption)
                            .foregroundColor(StatusPalette.err)
                    }
                }
            }

            MinimalSection(title: "本地通知与去重策略", trailingText: store.notificationAuthState.label) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("触发系统本地通知")
                            .font(Typography.rowTitle)
                            .foregroundColor(MagpieTheme.ink)
                        Text("开启时向 iOS 请求通知授权；同一重置周期内默认每 4 小时最多提醒一次，余量高于阈值后重新允许提醒")
                            .font(Typography.caption)
                            .foregroundColor(MagpieTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    MagpieToggle(isOn: Binding(
                        get: { store.alertConfig.notificationsEnabled },
                        set: { val in
                            Task { await store.setLocalNotificationsEnabled(val) }
                        }
                    ))
                    .accessibilityIdentifier("localNotifyToggle")
                }

                HStack(spacing: Spacing.sm) {
                    if store.notificationAuthState != .authorized {
                        Button("请求通知权限") {
                            Task { await store.requestNotificationPermissionExplicitly() }
                        }
                        .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
                    }
                    Button("发送测试通知") {
                        Task { await store.sendTestLocalNotification() }
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))

                    Button("清除去重记录") {
                        QuotaNotificationManager.shared.resetDeduplicationHistory(for: store.activeServerID)
                        store.showToast("已清除本实例本地通知去重记录")
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))
                }
            }

            // Honest technical explanation of iOS background refresh vs server push
            MinimalSection(title: "iOS 后台刷新机制与实时推送说明", trailingText: "如实说明") {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("• 客户端本地通知：仅在 App 前台活跃刷新或系统授予的 BGAppRefreshTask 后台窗口执行检查，受 iOS 省电策略与调度频率限制，不保证锁屏状态下秒级实时送达。")
                        .font(Typography.caption)
                        .foregroundColor(MagpieTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("• 服务端实时推送依赖：如需 24 小时稳定锁屏提醒，须由 Magpie 服务端主动触发推送。可通过支持 Bark 的 Magpie 服务端与 Bark 客户端配置推送（当前读取状态：\(store.remoteSettings.barkKeySet ? "已配置 Key" : "未配置 Key")，服务端用量告警阈值 \(store.remoteSettings.usageAlert)%），也可在后续版本扩展服务端 APNs 推送网关。")
                        .font(Typography.caption)
                        .foregroundColor(MagpieTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let onJumpToBark = onJumpToBark {
                    Button("前往服务端 Bark 推送配置") {
                        dismiss()
                        onJumpToBark()
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
                }
            }

            // Per-account custom overrides
            if !allAccountTargets.isEmpty {
                MinimalSection(title: "按账号单独配置阈值", trailingText: "\(allAccountTargets.count) 个账号") {
                    ForEach(Array(allAccountTargets.enumerated()), id: \.element.id) { idx, target in
                        if idx > 0 {
                            Rectangle().fill(MagpieTheme.hairline).frame(height: 1)
                        }
                        let muted = store.alertConfig.isMuted(providerID: target.providerID, user: target.user)
                        HStack(spacing: Spacing.sm) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(target.title)
                                    .font(Typography.rowTitleMono)
                                    .foregroundColor(MagpieTheme.ink)
                                    .lineLimit(1)
                                Text("\(target.providerID) · 当前阈值 ≤\(target.currentThreshold)%\(target.hasCustomOverride ? "（专属）" : "（继承）")\(muted ? " · 已静音" : "")")
                                    .font(Typography.micro)
                                    .foregroundColor(MagpieTheme.textMuted)
                            }
                            Spacer()
                            Button("改阈值") {
                                editingOverrideTarget = target
                                overrideThresholdInput = String(target.currentThreshold)
                            }
                            .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))

                            Button(muted ? "取消静音" : "静音") {
                                var next = store.alertConfig
                                next.setMuted(!muted, providerID: target.providerID, user: target.user)
                                store.saveAlertConfig(next)
                            }
                            .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))
                        }
                    }
                }
            }
        }
    }

    private var allAccountTargets: [OverrideTarget] {
        var list: [OverrideTarget] = []
        for p in store.providers {
            if let acc = p.account {
                for login in acc.logins {
                    let key = QuotaAlertConfig.accountKey(providerID: p.id, user: login.user)
                    let display = AccountSwitchPlanner.displayName(for: login.user, in: p)
                    list.append(OverrideTarget(
                        id: key,
                        title: display,
                        providerID: p.id,
                        user: login.user,
                        currentThreshold: store.alertConfig.effectiveThreshold(providerID: p.id, user: login.user),
                        hasCustomOverride: store.alertConfig.accountThresholds[key] != nil
                    ))
                }
            }
        }
        return list
    }

    private func overrideEditorSheet(_ target: OverrideTarget) -> some View {
        NavigationView {
            Form {
                Section(header: Text(target.title)) {
                    Text("设置余量预警触发阈值（剩余百分比 ≤ 该值时提示），范围 1–95%。")
                        .font(.caption)
                        .foregroundColor(MagpieTheme.textSecondary)
                    TextField("例如 15", text: $overrideThresholdInput)
                        .keyboardType(.numberPad)
                        .font(.body.monospaced())
                    if target.hasCustomOverride {
                        Button("恢复继承全局默认 (\(store.alertConfig.defaultRemainingThresholdPercent)%)", role: .destructive) {
                            var next = store.alertConfig
                            if let user = target.user {
                                next.setAccountThreshold(nil, providerID: target.providerID, user: user)
                            } else {
                                next.setProviderThreshold(nil, providerID: target.providerID)
                            }
                            store.saveAlertConfig(next)
                            editingOverrideTarget = nil
                        }
                    }
                }
            }
            .navigationTitle("专属预警阈值")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { editingOverrideTarget = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let parsed = Int(overrideThresholdInput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? target.currentThreshold
                        var next = store.alertConfig
                        if let user = target.user {
                            next.setAccountThreshold(parsed, providerID: target.providerID, user: user)
                        } else {
                            next.setProviderThreshold(parsed, providerID: target.providerID)
                        }
                        store.saveAlertConfig(next)
                        editingOverrideTarget = nil
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Tab 3: Widget Preview & Shared Cache Diagnostics

    private var widgetPreviewSection: some View {
        let snap = store.widgetSnapshot
        let diag = MagpieWidgetSnapshotStore.diagnostics()

        return VStack(alignment: .leading, spacing: Spacing.sectionGap) {
            MinimalSection(title: "桌面组件效果预览（共享缓存实时数据）", trailingText: "Small + Medium") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("中号组件 (systemMedium)")
                        .font(Typography.microSemibold)
                        .foregroundColor(MagpieTheme.textMuted)
                    MagpieWidgetPreviewMediumCard(snapshot: snap)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("widgetPreviewMediumCard")

                    Text("小号组件 (systemSmall)")
                        .font(Typography.microSemibold)
                        .foregroundColor(MagpieTheme.textMuted)
                    HStack {
                        MagpieWidgetPreviewSmallCard(snapshot: snap)
                            .frame(width: 162, height: 162)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("widgetPreviewSmallCard")
                        Spacer()
                    }
                }
            }

            MinimalSection(title: "App Group 共享缓存与脱敏校验", trailingText: "v\(snap.schemaVersion)") {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("存储通道：\(diag.storageModeDescription)")
                        .font(Typography.caption)
                        .foregroundColor(MagpieTheme.textSecondary)
                    Text("脱敏保障：快照仅包含实例显示名、今日汇总与脱敏账号标识（如 de***@gmail.com），严禁写入访问密钥 k、Cookie、API Key 或 Token。")
                        .font(Typography.caption)
                        .foregroundColor(MagpieTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("点击深链：支持 magpie://usage、magpie://alerts、magpie://providers?id=… 与 magpie://refresh。")
                        .font(Typography.captionMono)
                        .foregroundColor(MagpieTheme.textMuted)
                }

                if !snap.accounts.isEmpty {
                    Rectangle().fill(MagpieTheme.hairline).frame(height: 1)
                    ForEach(snap.accounts) { item in
                        HStack {
                            Text(item.maskedAccount)
                                .font(Typography.captionMono)
                                .foregroundColor(MagpieTheme.ink)
                            Text("(\(item.providerName))")
                                .font(Typography.micro)
                                .foregroundColor(MagpieTheme.textMuted)
                            Spacer()
                            if let rem = item.remainingPercent {
                                Text(String(format: "剩 %.0f%%", rem))
                                    .font(Typography.captionMono)
                                    .foregroundColor(item.isAlerting ? StatusPalette.warn : StatusPalette.ok)
                            } else {
                                Text(item.windowName)
                                    .font(Typography.micro)
                                    .foregroundColor(MagpieTheme.textSecondary)
                            }
                        }
                    }
                }

                Rectangle().fill(MagpieTheme.hairline).frame(height: 1)

                HStack(spacing: Spacing.sm) {
                    Button("同步写入共享快照") {
                        store.recomputeAlertsAndWidgetSnapshot(triggerNotifications: false)
                        store.showToast("已写入脱敏共享快照并通知 WidgetKit")
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))

                    Button("模拟点击深链 (用量)") {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            store.handleDeepLink(MagpieDeepLink.usage.url)
                        }
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
                    .accessibilityIdentifier("testWidgetDeepLinkUsageButton")
                }
            }
        }
    }

    // MARK: - Helpers

    private func applyGlobalThreshold() {
        let trimmed = thresholdInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let val = Int(trimmed), (1...95).contains(val) else {
            thresholdError = "请输入 1–95 之间的整数百分比"
            return
        }
        thresholdError = nil
        var next = store.alertConfig
        next.defaultRemainingThresholdPercent = val
        store.saveAlertConfig(next)
        store.showToast("已将默认余量预警阈值设为 ≤ \(val)%")
    }

    private func refreshNow() {
        isRefreshing = true
        Task {
            await store.refreshProviders()
            await store.refreshAllLoginUsagesForSubscriptionProviders()
            await store.refreshQuotas(asked: true, all: false)
            await store.refreshTodayUsageForWidgetIfNeeded()
            store.recomputeAlertsAndWidgetSnapshot(triggerNotifications: true)
            isRefreshing = false
        }
    }

    private func statCell(value: String, label: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundColor(tone)
            Text(label)
                .font(Typography.micro)
                .foregroundColor(MagpieTheme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Widget Preview Cards (Shared Styling with MagpieWidget Extension)

struct MagpieWidgetPreviewSmallCard: View {
    let snapshot: MagpieWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(snapshot.serverTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(MagpieTheme.ink)
                    .lineLimit(1)
                Spacer()
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 7, height: 7)
            }

            if snapshot.connectionState == .unconfigured {
                Spacer()
                Text("未配置实例")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MagpieTheme.ink)
                Text("点击打开 Magpie 连接服务器")
                    .font(.system(size: 10.5))
                    .foregroundColor(MagpieTheme.textMuted)
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(snapshot.todayCalls) 次调用")
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundColor(MagpieTheme.ink)
                    Text(String(format: "今日 $%.2f · 错 %d", snapshot.todayCostUSD, snapshot.todayErrors))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(MagpieTheme.textSecondary)
                }

                Spacer(minLength: 2)

                if let top = snapshot.accounts.first {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(top.maskedAccount)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundColor(MagpieTheme.ink)
                            .lineLimit(1)
                        if let rem = top.remainingPercent {
                            Text(String(format: "%@ 剩 %.0f%%", top.windowName, rem))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(top.isAlerting ? StatusPalette.warn : StatusPalette.ok)
                                .lineLimit(1)
                        } else {
                            Text(top.windowName)
                                .font(.system(size: 10))
                                .foregroundColor(MagpieTheme.textMuted)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(MagpieTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(MagpieTheme.hairline, lineWidth: 1))
    }

    private var statusDotColor: Color {
        switch snapshot.connectionState {
        case .unconfigured: return StatusPalette.neutral
        case .offline: return StatusPalette.warn
        case .connected:
            return snapshot.alertCount > 0 ? StatusPalette.warn : StatusPalette.ok
        }
    }
}

struct MagpieWidgetPreviewMediumCard: View {
    let snapshot: MagpieWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    MagpieMarkView(size: 16)
                    Text(snapshot.serverTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(MagpieTheme.ink)
                        .lineLimit(1)
                }
                Spacer()
                if snapshot.connectionState == .offline {
                    MagpieTag(text: "离线缓存", tone: StatusPalette.warn, background: StatusPalette.warnSurface)
                } else if snapshot.alertCount > 0 {
                    MagpieTag(text: "预警 \(snapshot.alertCount)", tone: StatusPalette.warn, background: StatusPalette.warnSurface)
                } else if snapshot.connectionState == .connected {
                    MagpieTag(text: "在线", tone: StatusPalette.ok, background: StatusPalette.okSurface)
                } else {
                    MagpieTag(text: "未配置")
                }
            }

            if snapshot.connectionState == .unconfigured {
                Text("尚未配置 magpie web 实例。轻点卡片前往连接，桌面组件将自动展示今日用量与脱敏后的账号余量。")
                    .font(Typography.caption)
                    .foregroundColor(MagpieTheme.textSecondary)
            } else {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(snapshot.todayCalls)")
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                            .foregroundColor(MagpieTheme.ink)
                        Text("今日调用")
                            .font(Typography.nano)
                            .foregroundColor(MagpieTheme.textMuted)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "$%.2f", snapshot.todayCostUSD))
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                            .foregroundColor(MagpieTheme.ink)
                        Text("今日费用")
                            .font(Typography.nano)
                            .foregroundColor(MagpieTheme.textMuted)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        ForEach(snapshot.accounts.prefix(2)) { acc in
                            HStack(spacing: 5) {
                                Text(acc.maskedAccount)
                                    .font(Typography.nanoMono)
                                    .foregroundColor(MagpieTheme.textSecondary)
                                    .lineLimit(1)
                                if let rem = acc.remainingPercent {
                                    Text(String(format: "%.0f%%", rem))
                                        .font(Typography.nanoMono)
                                        .foregroundColor(acc.isAlerting ? StatusPalette.warn : StatusPalette.ok)
                                } else {
                                    Text(acc.isCooling ? "冷却" : "正常")
                                        .font(Typography.nano)
                                        .foregroundColor(acc.isCooling ? StatusPalette.warn : MagpieTheme.textMuted)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MagpieTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(MagpieTheme.hairline, lineWidth: 1))
    }
}
