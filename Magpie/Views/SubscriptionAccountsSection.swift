import SwiftUI

struct SubscriptionAccountsSection: View {
    @ObservedObject var store: GatewayStore
    let provider: RemoteProvider
    let account: RemoteProviderAccount
    var highlightedUser: String? = nil
    var onOpenSignIn: (SubscriptionSignInSheet.InitialMode, String?, String?) -> Void

    @State private var isLoadingUsage = false
    @State private var editingLogin: RemoteProviderLogin?
    @State private var aliasDraft = ""
    @State private var capDraft = ""
    @State private var weightDraft = "1"
    @State private var weightError: String?
    @State private var concurrencyDraft = ""
    @State private var proxyDraft = ""
    @State private var modelTargetLogin: RemoteProviderLogin?
    @State private var allowedModelsDraft: Set<String> = []
    @State private var confirmForgetLogin: RemoteProviderLogin?

    @State private var showingMaxAccountsSheet = false
    @State private var maxAccountsInput = ""
    @State private var maxAccountsError: String?

    private var agent: String {
        account.agent ?? provider.id
    }

    private var platform: SubscriptionPlatform {
        SubscriptionCatalog.resolve(
            agent: agent,
            plugins: store.pluginSubs,
            onPlugins: store.onPlugins,
            movable: store.movableSubs
        )
    }

    private var isPriorityMode: Bool {
        SubscriptionCatalog.isPriorityRouting(provider.routing)
    }

    private var logins: [RemoteProviderLogin] {
        account.logins
    }

    private var usableLogins: [RemoteProviderLogin] {
        logins.filter { $0.lapsed == nil && !$0.paused && ($0.active || $0.on) }
    }

    private var reserveUserKeys: Set<String> {
        guard let cap = provider.effectiveMaxAccounts, cap > 0 else { return [] }
        let nonCoolingUsable = usableLogins.filter { login in
            let rests = provider.accountRests[login.user.lowercased()] ?? []
            return !rests.contains { ($0.model ?? "").isEmpty }
        }
        guard nonCoolingUsable.count > cap else { return [] }
        return Set(nonCoolingUsable.dropFirst(cap).map { $0.user.lowercased() })
    }

    private var usageMap: [String: RemoteLoginQuota] {
        store.loginUsageByAgent[agent] ?? [:]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.cardPadding) {
            if agent == "codex" {
                codexStaleNotices
            }

            MinimalSection(
                title: "订阅账号池 (\(logins.count))",
                trailingText: isPriorityMode ? "按顺位优先 · 不限账号数" : "N 账号通用轮询"
            ) {
                HStack(spacing: Spacing.sm) {
                    Button("+ OAuth 添加") {
                        onOpenSignIn(.auto, nil, provider.proxy)
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))

                    if platform.importable {
                        Button("导入") {
                            onOpenSignIn(.importAccounts, nil, provider.proxy)
                        }
                        .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
                    }

                    if platform.supportsClaudeToken {
                        Button("Token") {
                            onOpenSignIn(.claudeToken, nil, provider.proxy)
                        }
                        .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
                    }

                    if platform.supportsExport && !logins.isEmpty {
                        Button("导出") {
                            onOpenSignIn(.exportAccounts, nil, provider.proxy)
                        }
                        .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))
                    }

                    Spacer()

                    Button(isLoadingUsage ? "刷新中…" : "刷额度") {
                        refreshUsage()
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))
                    .disabled(isLoadingUsage)
                }

                // Capacity & maxAccounts configuration bar
                HStack(spacing: Spacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("可用 \(usableLogins.count)/\(logins.count) · 同时调度：\(provider.maxAccountsSummary)")
                            .font(Typography.sectionHeader)
                            .foregroundColor(MagpieTheme.ink)
                        Text("号池支持无限新增账号；上限留空 (null) 或 0 表示不限")
                            .font(Typography.micro)
                            .foregroundColor(MagpieTheme.textMuted)
                    }
                    Spacer()
                    Button("上限设置") {
                        maxAccountsInput = provider.maxAccounts.map(String.init) ?? ""
                        maxAccountsError = nil
                        showingMaxAccountsSheet = true
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
                    .accessibilityIdentifier("configureMaxAccountsButton")
                }
                .padding(.horizontal, Spacing.md - 2)
                .padding(.vertical, Spacing.sm)
                .background(MagpieTheme.canvas)
                .clipShape(RoundedRectangle(cornerRadius: Corners.sm + 1, style: .continuous))

                if let cap = provider.effectiveMaxAccounts, cap > 0, usableLogins.count > cap {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(Typography.bodySmall)
                            .foregroundColor(StatusPalette.warn)
                            .padding(.top, 1)
                        Text("已超出同时启用上限（\(cap) 个）：当前 \(usableLogins.count) 个可用账号中仅前 \(cap) 个同时参与调度，其余 \(usableLogins.count - cap) 个自动作为候补顺延，在主用号冷却或耗尽时顶替。")
                            .font(Typography.caption)
                            .foregroundColor(StatusPalette.warn)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Spacing.sm + 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(StatusPalette.warnSurface)
                    .clipShape(RoundedRectangle(cornerRadius: Corners.sm + 1, style: .continuous))
                } else if let cap = provider.effectiveMaxAccounts, cap > 0, logins.count >= cap {
                    Text("号池账号数已达同时调度上限 \(cap) 个；仍可继续新增账号作为候补，或点击「上限设置」设为不限 (null)。")
                        .font(Typography.caption)
                        .foregroundColor(MagpieTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if logins.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(account.user.map { "当前登录：\($0)" } ?? "暂无多账号记录")
                            .font(Typography.bodyMono)
                            .foregroundColor(MagpieTheme.ink)
                        Text("点击上方「+ OAuth 添加」可接入更多 \(platform.name) 账号进行多号轮换与并发分流。")
                            .font(Typography.sectionHeader)
                            .foregroundColor(MagpieTheme.textSecondary)
                    }
                } else {
                    ForEach(Array(logins.enumerated()), id: \.element.id) { idx, login in
                        if idx > 0 {
                            Rectangle().fill(MagpieTheme.hairline).frame(height: 1)
                        }
                        accountRow(idx: idx, login: login)
                            .id("accountRow_\(login.user.lowercased())")
                    }
                }
            }

            MinimalSection(
                title: "调度模式：优先级 vs 轮询",
                trailingText: provider.routing.isEmpty ? "smart" : provider.routing
            ) {
                Text(SubscriptionCatalog.routingCategorySummary(provider.routing))
                    .font(Typography.sectionHeader)
                    .foregroundColor(MagpieTheme.textSecondary)

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("优先级模式（顺位为主）")
                        .font(Typography.microSemibold)
                        .foregroundColor(MagpieTheme.textMuted)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 7)], alignment: .leading, spacing: 7) {
                        routingQuickChip(id: "", title: "Smart 智能优先级")
                        routingQuickChip(id: "order", title: "Order 严格顺序")
                        routingQuickChip(id: "drain", title: "Drain 用尽顺延")
                    }
                    Text("轮询与均衡模式（多号分流）")
                        .font(Typography.microSemibold)
                        .foregroundColor(MagpieTheme.textMuted)
                        .padding(.top, 2)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 7)], alignment: .leading, spacing: 7) {
                        routingQuickChip(id: "rotate", title: "Rotate 逐轮轮询")
                        routingQuickChip(id: "weight", title: "Weight 权重轮询")
                        routingQuickChip(id: "usage", title: "Usage 最少已用")
                        routingQuickChip(id: "pace", title: "Pace 速率均衡")
                        routingQuickChip(id: "fast", title: "Fast 速度优先")
                        routingQuickChip(id: "free", title: "Free 免费优先")
                    }
                }
            }

            subscriptionPolicySection
        }
        .onAppear {
            refreshUsage()
        }
        .sheet(isPresented: $showingMaxAccountsSheet) {
            maxAccountsEditorSheet
        }
        .sheet(item: $editingLogin) { login in
            accountSettingsSheet(login)
        }
        .sheet(item: $modelTargetLogin) { login in
            accountModelsSheet(login)
        }
        .alert(
            "移除账号？",
            isPresented: Binding(
                get: { confirmForgetLogin != nil },
                set: { if !$0 { confirmForgetLogin = nil } }
            ),
            presenting: confirmForgetLogin
        ) { login in
            Button("移除", role: .destructive) {
                Task {
                    _ = await store.performLoginAction(
                        "forget",
                        agent: agent,
                        user: login.user,
                        toast: "已移除账号「\(login.user)」"
                    )
                }
                confirmForgetLogin = nil
            }
            Button("取消", role: .cancel) {
                confirmForgetLogin = nil
            }
        } message: { login in
            Text("Magpie 将忘记「\(login.user)」的登录凭证（平台账号本身不受影响）。")
        }
    }

    // MARK: - Codex Stale Notices

    @ViewBuilder
    private var codexStaleNotices: some View {
        if let stale = store.codexDaemonStale, !stale.isEmpty {
            MinimalSection(title: "Codex 后台服务需重启", trailingText: stale) {
                Text("Codex 后台 app-server 仍停留在旧账号 \(stale)，重启后才会切换到新账号。")
                    .font(Typography.bodySmall)
                    .foregroundColor(StatusPalette.warn)
                HStack(spacing: Spacing.sm) {
                    Button("重启后台服务") {
                        Task { _ = await store.codexDaemonAction("restart", toast: "已重启 Codex 后台服务") }
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
                    Button("稍后") {
                        Task { _ = await store.codexDaemonAction("dismiss", toast: "") }
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))
                }
            }
        }
        if let appStale = store.codexAppStale, !appStale.isEmpty {
            MinimalSection(title: "Codex 桌面应用提醒", trailingText: appStale) {
                Text("Codex App 仍停留在旧账号 \(appStale)，重启其 app-server 后生效。")
                    .font(Typography.bodySmall)
                    .foregroundColor(StatusPalette.warn)
                HStack(spacing: Spacing.sm) {
                    Button("重启 Codex App 服务") {
                        Task { _ = await store.codexDaemonAction("restart-app", toast: "已重启 Codex App 服务") }
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
                    Button("知道了") {
                        Task { _ = await store.codexDaemonAction("dismiss-app", toast: "") }
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))
                }
            }
        }
    }

    // MARK: - Account Row

    private func accountRow(idx: Int, login: RemoteProviderLogin) -> some View {
        let lower = login.user.lowercased()
        let alias = provider.accountNames[lower]
        let vendUser = provider.accountUsers[lower]
        let displayTitle = (alias?.isEmpty == false ? alias! : (vendUser?.isEmpty == false ? vendUser! : login.user))
        let cap = provider.accountCaps[lower]
        let weight = provider.accountWeights[lower]
        let conc = provider.accountConcurrency[lower]
        let ownProxy = provider.accountProxies[lower]
        let allowedModels = provider.accountModels[lower] ?? []
        let rests = provider.accountRests[lower] ?? []
        let isCoolingWhole = rests.contains { ($0.model ?? "").isEmpty }
        let isReserve = reserveUserKeys.contains(lower)
        let quota = usageMap.first(where: { $0.key.caseInsensitiveCompare(login.user) == .orderedSame })?.value
        let totalEnabledWeight = usableLogins.reduce(0) { sum, item in
            sum + max(provider.accountWeights[item.user.lowercased()] ?? 1, 1)
        }
        let thisWeight = max(weight ?? 1, 1)
        let weightSharePct = totalEnabledWeight > 0 ? Int(round(Double(thisWeight) / Double(totalEnabledWeight) * 100.0)) : 0
        let isUsable = login.lapsed == nil && !login.paused && (login.active || login.on)
        let isCurrentlyOn = !login.paused && (login.on || login.active)
        let soleFixedPrimary = login.active && !login.paused && usableLogins.count <= 1 && agent != "codex" && agent != "claude"
        let dotColor: Color = {
            if login.lapsed != nil { return StatusPalette.err }
            if isCoolingWhole || isReserve { return StatusPalette.warn }
            return isUsable ? StatusPalette.ok : StatusPalette.neutral
        }()
        let isHighlighted = highlightedUser.map { $0.caseInsensitiveCompare(login.user) == .orderedSame } ?? false

        return VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: Spacing.xs - 1) {
                        Text(displayTitle)
                            .font((alias?.isEmpty == false) ? Typography.rowTitle : Typography.rowTitleMono)
                            .foregroundColor(MagpieTheme.ink)
                            .lineLimit(1)
                            .accessibilityIdentifier("accountTitle_\(login.user)")
                        if login.lapsed != nil {
                            MagpieTag(text: "登录失效", tone: StatusPalette.err)
                        } else if login.paused {
                            MagpieTag(text: "已暂停", tone: StatusPalette.warn)
                        } else if !login.on && !login.active {
                            MagpieTag(text: "已停用")
                        } else if isCoolingWhole {
                            MagpieTag(text: "冷却跳过", tone: StatusPalette.warn)
                        } else if isReserve {
                            MagpieTag(text: "候补顺延", tone: StatusPalette.warn)
                        } else if isPriorityMode {
                            MagpieTag(text: idx == 0 ? "优先级 #1" : "顺位 #\(idx + 1)", tone: idx == 0 ? MagpieTheme.ink : StatusPalette.ok)
                        } else if provider.routing.lowercased() == "weight" {
                            MagpieTag(text: "权重 \(thisWeight) · \(weightSharePct)%", tone: StatusPalette.ok)
                        } else {
                            MagpieTag(text: "参与轮询", tone: StatusPalette.ok)
                        }
                        if login.active && !isPriorityMode && !isReserve {
                            MagpieTag(text: "主用", tone: MagpieTheme.ink)
                        }
                    }

                    if displayTitle != login.user {
                        Text(login.user)
                            .font(Typography.microMono)
                            .foregroundColor(MagpieTheme.textMuted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                if logins.count > 1 {
                    HStack(spacing: 3) {
                        Button("↑") {
                            Task { _ = await store.moveAccountOrder(provider: provider, user: login.user, offset: -1, logins: logins) }
                        }
                        .font(Typography.captionMono)
                        .disabled(idx == 0)
                        Button("↓") {
                            Task { _ = await store.moveAccountOrder(provider: provider, user: login.user, offset: 1, logins: logins) }
                        }
                        .font(Typography.captionMono)
                        .disabled(idx >= logins.count - 1)
                    }
                }

                if login.lapsed == nil && !login.token {
                    MagpieToggle(
                        isOn: Binding(
                            get: { isCurrentlyOn },
                            set: { enable in
                                Task {
                                    _ = await store.performLoginAction(
                                        enable ? "on" : "off",
                                        agent: agent,
                                        user: login.user,
                                        toast: enable ? "已启用 \(login.user)" : "已停用 \(login.user)"
                                    )
                                }
                            }
                        )
                    )
                    .disabled(soleFixedPrimary)
                    .opacity(soleFixedPrimary ? 0.45 : 1)
                    .accessibilityIdentifier("accountToggle_\(login.user)")
                    .accessibilityLabel("启用开关 \(login.user)")
                }
            }

            // Metadata tags
            let hasMeta = (login.plan?.isEmpty == false) || login.token || login.accessOnly || (cap ?? 0) > 0 || thisWeight > 1 || (conc ?? 0) > 0 || (ownProxy?.isEmpty == false) || !allowedModels.isEmpty
            if hasMeta {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.xs - 1) {
                        if let plan = login.plan, !plan.isEmpty {
                            MagpieTag(text: plan, tone: MagpieTheme.ink)
                        }
                        if login.token {
                            MagpieTag(text: login.uses ? "Token 使用中" : "Setup-Token")
                        }
                        if login.accessOnly {
                            MagpieTag(text: "仅 AccessToken", tone: StatusPalette.warn)
                        }
                        if let c = cap, c > 0, c < 100 {
                            MagpieTag(text: "上限 \(c)%")
                        }
                        if thisWeight > 1 {
                            MagpieTag(text: "权重 \(thisWeight)")
                        }
                        if let conc = conc, conc > 0 {
                            MagpieTag(text: "并发 \(conc)")
                        }
                        if let px = ownProxy, !px.isEmpty {
                            MagpieTag(text: "代理 \(px)")
                        }
                        if !allowedModels.isEmpty {
                            MagpieTag(text: "限 \(allowedModels.count) 模型")
                        }
                    }
                }
            }

            // Quota windows
            if let lapsed = login.lapsed, !lapsed.isEmpty {
                Text("授权已失效：\(lapsed)")
                    .font(Typography.caption)
                    .foregroundColor(StatusPalette.err)
            } else if let q = quota {
                if let err = q.error, !err.isEmpty {
                    Text("额度查询提示：\(err)")
                        .font(Typography.micro)
                        .foregroundColor(StatusPalette.warn)
                }
                if !q.windows.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(q.windows) { w in
                            quotaWindowRow(w)
                        }
                    }
                    .padding(Corners.sm)
                    .background(MagpieTheme.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: Corners.sm, style: .continuous))
                } else if let bal = q.balance, !bal.isEmpty {
                    Text("余额：\(bal)")
                        .font(Typography.captionMono)
                        .foregroundColor(MagpieTheme.textSecondary)
                }
            }

            // Rests (generic across all N accounts)
            ForEach(Array(rests.enumerated()), id: \.offset) { _, rest in
                let scope = (rest.model?.isEmpty == false) ? "模型 \(rest.model!) 冷却" : "整号冷却"
                HStack(spacing: Spacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(scope)：\(rest.why ?? "限流/异常")")
                            .font(Typography.captionMedium)
                            .foregroundColor(StatusPalette.warn)
                        if let until = rest.until, !until.isEmpty {
                            Text("预计恢复：\(until)")
                                .font(Typography.nanoMono)
                                .foregroundColor(MagpieTheme.textMuted)
                        }
                    }
                    Spacer()
                    if let restKey = rest.key, !restKey.isEmpty {
                        Button("解除冷却") {
                            Task { _ = await store.liftGatewayKeyRest(key: restKey) }
                        }
                        .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
                    }
                }
                .padding(Corners.sm)
                .background(MagpieTheme.canvas)
                .clipShape(RoundedRectangle(cornerRadius: Corners.sm, style: .continuous))
            }

            // Actions (compact layout so buttons never clip or crowd on N-account lists)
            HStack(spacing: Spacing.xs) {
                if login.lapsed == nil && !login.token {
                    let btnLabel = login.paused ? "恢复" : (isCurrentlyOn ? (login.active ? "暂停" : "停用") : "启用")
                    compactRowButton(btnLabel, tone: .subtle) {
                        let act = isCurrentlyOn ? "off" : "on"
                        Task {
                            _ = await store.performLoginAction(
                                act,
                                agent: agent,
                                user: login.user,
                                toast: isCurrentlyOn ? "已停用 \(login.user)" : "已启用 \(login.user)"
                            )
                        }
                    }
                    .disabled(soleFixedPrimary)
                }

                compactRowButton("权重 \(thisWeight)", tone: .subtle) {
                    openSettings(for: login)
                }

                compactRowButton("重授权", tone: login.lapsed != nil ? .primary : .subtle) {
                    onOpenSignIn(.auto, login.user, ownProxy ?? provider.proxy)
                }

                compactRowButton("设置", tone: .subtle) {
                    openSettings(for: login)
                }

                Spacer(minLength: 2)

                compactRowButton("移除", tone: .danger) {
                    confirmForgetLogin = login
                }
            }

            if (idx > 0 && login.lapsed == nil && isPriorityMode) || (login.token && !login.uses) {
                HStack(spacing: Spacing.xs) {
                    if idx > 0 && login.lapsed == nil && isPriorityMode {
                        compactRowButton("设为首选", tone: .secondary) {
                            Task { _ = await store.makeAccountFirst(provider: provider, user: login.user, logins: logins) }
                        }
                    }
                    if login.token && !login.uses {
                        compactRowButton("CLI 使用此 Token", tone: .secondary) {
                            Task {
                                _ = await store.performLoginAction("switch", agent: agent, user: login.user, toast: "已切换至 \(login.user)")
                            }
                        }
                    }
                }
            }
        }
        .padding(isHighlighted ? Spacing.sm : 0)
        .background(isHighlighted ? StatusPalette.warnSurface : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Corners.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Corners.md, style: .continuous)
                .stroke(isHighlighted ? StatusPalette.warn.opacity(0.55) : Color.clear, lineWidth: isHighlighted ? 1.5 : 0)
        )
    }

    private func compactRowButton(_ title: String, tone: MagpieButtonTone, action: @escaping () -> Void) -> some View {
        let bg: Color
        let fg: Color
        let border: Color
        switch tone {
        case .primary:
            bg = MagpieTheme.ink
            fg = MagpieTheme.onInk
            border = MagpieTheme.ink
        case .secondary:
            bg = MagpieTheme.surface
            fg = MagpieTheme.ink
            border = MagpieTheme.hairline
        case .subtle:
            bg = MagpieTheme.surfaceSubtle
            fg = MagpieTheme.ink
            border = Color.clear
        case .danger:
            bg = StatusPalette.errSurface
            fg = StatusPalette.err
            border = StatusPalette.err.opacity(0.35)
        }
        return Button(title, action: action)
            .font(Typography.captionMedium)
            .foregroundColor(fg)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 5)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: Corners.sm, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Corners.sm, style: .continuous).stroke(border, lineWidth: 1))
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func quotaWindowRow(_ w: RemoteLoginQuotaWindow) -> some View {
        let clamped = min(max(w.used, 0), 100)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(w.name)
                    .font(Typography.microMedium)
                    .foregroundColor(MagpieTheme.ink)
                Spacer()
                if let display = w.display, !display.isEmpty {
                    Text(display)
                        .font(Typography.nanoMono)
                        .foregroundColor(MagpieTheme.textSecondary)
                } else if w.unlimited {
                    Text("不限量")
                        .font(Typography.nano)
                        .foregroundColor(StatusPalette.ok)
                } else {
                    let resetHint = formatResetSecs(w.resetSecs)
                    Text(resetHint.isEmpty ? String(format: "已用 %.0f%%", clamped) : String(format: "已用 %.0f%% · %@", clamped, resetHint))
                        .font(Typography.nanoMono)
                        .foregroundColor(clamped >= 90 ? StatusPalette.err : MagpieTheme.textSecondary)
                }
            }
            if !w.text && !w.unlimited {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(MagpieTheme.hairline)
                            .frame(height: 4)
                        Capsule()
                            .fill(clamped >= 90 ? StatusPalette.err : (clamped >= 70 ? StatusPalette.warn : StatusPalette.ok))
                            .frame(width: geo.size.width * CGFloat(clamped / 100.0), height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
    }

    // MARK: - Subscription Policy Toggles

    private var subscriptionPolicySection: some View {
        MinimalSection(title: "订阅切号与配额策略") {
            if agent == "codex" || agent == "claude" {
                toggleItem(
                    title: "自动切换本地 CLI 登录账号",
                    subtitle: "关闭时将固定客户端保持登录在主号上，其余账号仅通过网关代发",
                    isOn: Binding(
                        get: { provider.switchOnly || !provider.keepLogin },
                        set: { auto in
                            Task { _ = await store.setProviderKeepLogin(id: provider.id, keepLogin: !auto) }
                        }
                    )
                )

                Rectangle().fill(MagpieTheme.hairline).frame(height: 1)

                toggleItem(
                    title: "仅切号不走网关代发 (Switch Only)",
                    subtitle: "请求直连官方接口，Magpie 仅负责自动切换客户端登录账号",
                    isOn: Binding(
                        get: { provider.switchOnly },
                        set: { val in
                            Task { _ = await store.setProviderSwitchOnly(id: provider.id, switchOnly: val) }
                        }
                    )
                )

                if agent == "codex" {
                    Rectangle().fill(MagpieTheme.hairline).frame(height: 1)
                    toggleItem(
                        title: "切号后自动重启 Codex App 服务",
                        subtitle: "切换账号后自动重启 Codex 桌面端后台服务使新账号立即生效",
                        isOn: Binding(
                            get: { provider.restartApp },
                            set: { val in
                                Task { _ = await store.setProviderRestartApp(id: provider.id, restartApp: val) }
                            }
                        )
                    )
                }

                Rectangle().fill(MagpieTheme.hairline).frame(height: 1)
            }

            toggleItem(
                title: "触及配额上限即停止请求 (Cap Stop)",
                subtitle: "所有账号均达到设定百分比上限时直接返回 429，不转入后备供应商",
                isOn: Binding(
                    get: { provider.capStop },
                    set: { val in
                        Task { _ = await store.setProviderCapStop(id: provider.id, capStop: val) }
                    }
                )
            )

            Rectangle().fill(MagpieTheme.hairline).frame(height: 1)

            toggleItem(
                title: "接近上限时自动复核额度 (Cap Careful)",
                subtitle: "账号接近配额上限时向官方重新查询实时余量后再路由",
                isOn: Binding(
                    get: { provider.capCareful },
                    set: { val in
                        Task { _ = await store.setProviderCapCareful(id: provider.id, capCareful: val) }
                    }
                )
            )
        }
    }

    private func toggleItem(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Typography.rowTitle)
                    .foregroundColor(MagpieTheme.ink)
                Text(subtitle)
                    .font(Typography.caption)
                    .foregroundColor(MagpieTheme.textSecondary)
            }
            Spacer()
            MagpieToggle(isOn: isOn)
        }
    }

    // MARK: - Max Accounts Limit Sheet

    private var maxAccountsEditorSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("同时启用上限 (maxAccounts)")) {
                    Text("控制同一时间最多多少个可用账号直接参与调度；留空 (null) 或设为 0 表示不限。号池本身支持无限新增账号，超出上限的账号会自动作为候补，在前序账号冷却或耗尽时顺延顶替。")
                        .font(.caption)
                        .foregroundColor(MagpieTheme.textSecondary)

                    TextField("留空 = 不限 (null)，或输入 0–1000", text: $maxAccountsInput)
                        .keyboardType(.numberPad)
                        .font(.body.monospaced())
                        .accessibilityIdentifier("maxAccountsLimitField")

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.sm) {
                            Button("不限 (null)") {
                                maxAccountsInput = ""
                                maxAccountsError = nil
                            }
                            .buttonStyle(MagpieButtonStyle(tone: maxAccountsInput.isEmpty ? .primary : .secondary, compact: true))

                            ForEach(["0", "2", "3", "5", "10"], id: \.self) { val in
                                Button(val == "0" ? "不限 (0)" : "\(val) 个") {
                                    maxAccountsInput = val
                                    maxAccountsError = nil
                                }
                                .buttonStyle(MagpieButtonStyle(tone: maxAccountsInput == val ? .primary : .secondary, compact: true))
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    if let err = maxAccountsError {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(StatusPalette.err)
                    }

                    Button("保存上限") {
                        let trimmed = maxAccountsInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        let parsed: Int?
                        if trimmed.isEmpty {
                            parsed = nil
                        } else if let n = Int(trimmed), (0...1000).contains(n) {
                            parsed = n
                        } else {
                            maxAccountsError = "请输入 0–1000 的整数，或留空表示不限 (null)"
                            return
                        }
                        maxAccountsError = nil
                        Task {
                            if await store.updateProviderMaxAccounts(provider, maxAccounts: parsed) {
                                showingMaxAccountsSheet = false
                            }
                        }
                    }
                    .accessibilityIdentifier("saveMaxAccountsButton")
                }
            }
            .navigationTitle("账号容量与上限")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showingMaxAccountsSheet = false }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Account Settings Sheet

    private func openSettings(for login: RemoteProviderLogin) {
        let lower = login.user.lowercased()
        aliasDraft = provider.accountNames[lower] ?? ""
        if let cap = provider.accountCaps[lower], cap > 0, cap < 100 {
            capDraft = String(cap)
        } else {
            capDraft = ""
        }
        weightDraft = String(max(provider.accountWeights[lower] ?? 1, 1))
        weightError = nil
        if let c = provider.accountConcurrency[lower], c > 0 {
            concurrencyDraft = String(c)
        } else {
            concurrencyDraft = ""
        }
        proxyDraft = provider.accountProxies[lower] ?? ""
        editingLogin = login
    }

    private func accountSettingsSheet(_ login: RemoteProviderLogin) -> some View {
        NavigationView {
            Form {
                Section(header: Text("账号信息")) {
                    Text(login.user)
                        .font(.caption.monospaced())
                    TextField("自定义别名（留空恢复默认）", text: $aliasDraft)
                    Button("保存别名") {
                        Task {
                            if await store.renameAccount(
                                providerID: provider.id,
                                account: login.user,
                                alias: aliasDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            ) {
                                editingLogin = nil
                            }
                        }
                    }
                }

                Section(header: Text("额度上限与调度")) {
                    TextField("配额上限百分比 (1-99，留空不限)", text: $capDraft)
                        .keyboardType(.numberPad)
                    Button("保存配额上限") {
                        let cap = Int(capDraft.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                        Task {
                            _ = await store.setAccountCap(providerID: provider.id, account: login.user, cap: cap)
                        }
                    }

                    TextField("轮询权重 (1–1000，默认 1)", text: $weightDraft)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("accountWeightField")

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.sm) {
                            ForEach([1, 2, 3, 5, 10], id: \.self) { w in
                                Button("\(w)x") {
                                    weightDraft = String(w)
                                    weightError = nil
                                }
                                .buttonStyle(MagpieButtonStyle(tone: weightDraft == String(w) ? .primary : .secondary, compact: true))
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    if let wErr = weightError {
                        Text(wErr)
                            .font(.caption)
                            .foregroundColor(StatusPalette.err)
                    }

                    Button("保存权重") {
                        let trimmed = weightDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard let w = Int(trimmed), (1...1000).contains(w) else {
                            weightError = "权重须为 1–1000 的整数"
                            return
                        }
                        weightError = nil
                        Task {
                            _ = await store.setAccountWeight(providerID: provider.id, account: login.user, weight: w)
                        }
                    }

                    TextField("单号最大并发（留空跟随供应商）", text: $concurrencyDraft)
                        .keyboardType(.numberPad)
                    Button("保存并发限制") {
                        let lim = Int(concurrencyDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                        Task {
                            _ = await store.setAccountConcurrency(providerID: provider.id, account: login.user, limit: lim)
                        }
                    }
                }

                Section(header: Text("专属出口代理")) {
                    TextField("留空跟随供应商 / direct / @代理ID / URL", text: $proxyDraft)
                        .autocapitalization(.none)
                        .font(.caption.monospaced())
                    if !store.remoteSettings.proxies.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                Button("跟随默认") { proxyDraft = "" }
                                Button("直连") { proxyDraft = "direct" }
                                ForEach(store.remoteSettings.proxies) { px in
                                    Button(px.name.isEmpty ? px.id : px.name) {
                                        proxyDraft = "@\(px.id)"
                                    }
                                }
                            }
                        }
                    }
                    Button("保存账号代理") {
                        Task {
                            _ = await store.setAccountProxy(provider: provider, account: login.user, proxy: proxyDraft)
                        }
                    }
                }

                Section(header: Text("模型范围与凭证模式")) {
                    Button("限定此账号可服务的模型…") {
                        let lower = login.user.lowercased()
                        allowedModelsDraft = Set(provider.accountModels[lower] ?? [])
                        editingLogin = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            modelTargetLogin = login
                        }
                    }

                    if agent == "codex" {
                        Button(login.accessOnly ? "恢复自动刷新 Refresh Token" : "改为仅保留 Access Token（不自动刷新）") {
                            let act = login.accessOnly ? "renewed" : "access-only"
                            Task {
                                if await store.performLoginAction(
                                    act,
                                    agent: agent,
                                    user: login.user,
                                    toast: login.accessOnly ? "已恢复自动刷新" : "已设为仅保留 AccessToken"
                                ) {
                                    editingLogin = nil
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("账号设置")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { editingLogin = nil }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func accountModelsSheet(_ login: RemoteProviderLogin) -> some View {
        NavigationView {
            List {
                Section(header: Text("不勾选任何模型表示服务该平台全部可用模型")) {
                    ForEach(provider.models) { model in
                        let checked = allowedModelsDraft.contains(model.id)
                        Button {
                            if checked {
                                allowedModelsDraft.remove(model.id)
                            } else {
                                allowedModelsDraft.insert(model.id)
                            }
                        } label: {
                            HStack {
                                Text(model.name.isEmpty ? model.id : model.name)
                                    .foregroundColor(MagpieTheme.ink)
                                Spacer()
                                if checked {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(MagpieTheme.ink)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("限定账号可用模型")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { modelTargetLogin = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            let ok = await store.updateAccountModels(
                                providerID: provider.id,
                                account: login.user.lowercased(),
                                allow: Array(allowedModelsDraft).sorted()
                            )
                            if ok { modelTargetLogin = nil }
                        }
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func routingQuickChip(id: String, title: String) -> some View {
        let selected = provider.routing == id
        return Button(title) {
            Task { await store.updateProviderRouting(provider, routing: id) }
        }
        .font(selected ? Typography.captionMedium : Typography.caption)
        .foregroundColor(selected ? MagpieTheme.onInk : MagpieTheme.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(selected ? MagpieTheme.ink : MagpieTheme.canvas)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(MagpieTheme.hairline, lineWidth: selected ? 0 : 1))
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func formatResetSecs(_ secs: Int64?) -> String {
        guard let s = secs, s > 0 else { return "" }
        if s >= 86400 {
            let d = s / 86400
            let h = (s % 86400) / 3600
            return h > 0 ? "\(d)天\(h)时重置" : "\(d)天重置"
        }
        if s >= 3600 {
            let h = s / 3600
            let m = (s % 3600) / 60
            return m > 0 ? "\(h)时\(m)分重置" : "\(h)小时重置"
        }
        return "\(max(s / 60, 1))分重置"
    }

    private func refreshUsage() {
        isLoadingUsage = true
        Task {
            await store.fetchLoginUsage(agent: agent)
            await MainActor.run {
                isLoadingUsage = false
            }
        }
    }
}
