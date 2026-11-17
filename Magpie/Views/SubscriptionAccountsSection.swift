import SwiftUI

struct SubscriptionAccountsSection: View {
    @ObservedObject var store: GatewayStore
    let provider: RemoteProvider
    let account: RemoteProviderAccount
    var onOpenSignIn: (SubscriptionSignInSheet.InitialMode, String?, String?) -> Void

    @State private var isLoadingUsage = false
    @State private var editingLogin: RemoteProviderLogin?
    @State private var aliasDraft = ""
    @State private var capDraft = ""
    @State private var weightDraft = "1"
    @State private var concurrencyDraft = ""
    @State private var proxyDraft = ""
    @State private var modelTargetLogin: RemoteProviderLogin?
    @State private var allowedModelsDraft: Set<String> = []
    @State private var confirmForgetLogin: RemoteProviderLogin?

    private var agent: String {
        account.agent ?? provider.id
    }

    private var platform: SubscriptionPlatform {
        SubscriptionCatalog.resolve(
            agent: agent,
            plugins: store.pluginSubs,
            onPlugins: store.onPlugins
        )
    }

    private var logins: [RemoteProviderLogin] {
        account.logins
    }

    private var usageMap: [String: RemoteLoginQuota] {
        store.loginUsageByAgent[agent] ?? [:]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if agent == "codex" {
                codexStaleNotices
            }

            MinimalSection(
                title: "订阅账号池 (\(logins.count))",
                trailingText: provider.routing.isEmpty ? "smart" : provider.routing
            ) {
                HStack(spacing: 8) {
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

                if logins.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(account.user.map { "当前登录：\($0)" } ?? "暂无多账号记录")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(MagpieTheme.ink)
                        Text("点击上方「+ OAuth 添加」可接入更多 \(platform.name) 账号进行多号轮换与并发分流。")
                            .font(.system(size: 12))
                            .foregroundColor(MagpieTheme.textSecondary)
                    }
                } else {
                    ForEach(Array(logins.enumerated()), id: \.element.id) { idx, login in
                        if idx > 0 {
                            Rectangle().fill(MagpieTheme.hairline).frame(height: 1)
                        }
                        accountRow(idx: idx, login: login)
                    }
                }
            }

            subscriptionPolicySection
        }
        .onAppear {
            refreshUsage()
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
                    .font(.system(size: 12.5))
                    .foregroundColor(MagpieTheme.warn)
                HStack(spacing: 8) {
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
                    .font(.system(size: 12.5))
                    .foregroundColor(MagpieTheme.warn)
                HStack(spacing: 8) {
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
        let quota = usageMap.first(where: { $0.key.caseInsensitiveCompare(login.user) == .orderedSame })?.value
        let isUsable = login.lapsed == nil && !login.paused && (login.active || login.on)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(login.lapsed != nil ? MagpieTheme.err : (isUsable ? MagpieTheme.ok : MagpieTheme.textMuted))
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(displayTitle)
                            .font(.system(size: 13.5, weight: .semibold, design: (alias?.isEmpty == false) ? .default : .monospaced))
                            .foregroundColor(MagpieTheme.ink)
                        if idx == 0 {
                            MagpieTag(text: "首选 #1", tone: MagpieTheme.accent)
                        }
                        if login.active {
                            MagpieTag(text: "主用", tone: MagpieTheme.ok)
                        }
                        if login.lapsed != nil {
                            MagpieTag(text: "已失效", tone: MagpieTheme.err)
                        } else if login.paused {
                            MagpieTag(text: "已暂停", tone: MagpieTheme.warn)
                        } else if !login.on && !login.active {
                            MagpieTag(text: "已停用")
                        }
                    }

                    if displayTitle != login.user {
                        Text(login.user)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(MagpieTheme.textMuted)
                    }
                }

                Spacer()

                if logins.count > 1 {
                    HStack(spacing: 4) {
                        Button("↑") {
                            Task { _ = await store.moveAccountOrder(provider: provider, user: login.user, offset: -1, logins: logins) }
                        }
                        .font(.system(size: 11.5, design: .monospaced))
                        .disabled(idx == 0)
                        Button("↓") {
                            Task { _ = await store.moveAccountOrder(provider: provider, user: login.user, offset: 1, logins: logins) }
                        }
                        .font(.system(size: 11.5, design: .monospaced))
                        .disabled(idx >= logins.count - 1)
                    }
                }
            }

            // Metadata tags
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    if let plan = login.plan, !plan.isEmpty {
                        MagpieTag(text: plan, tone: MagpieTheme.info)
                    }
                    if login.token {
                        MagpieTag(text: login.uses ? "Token 使用中" : "Setup-Token")
                    }
                    if login.accessOnly {
                        MagpieTag(text: "仅 AccessToken", tone: MagpieTheme.warn)
                    }
                    if let c = cap, c > 0, c < 100 {
                        MagpieTag(text: "上限 \(c)%")
                    }
                    if let w = weight, w > 1 {
                        MagpieTag(text: "权重 \(w)")
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

            // Quota windows
            if let lapsed = login.lapsed, !lapsed.isEmpty {
                Text("授权已失效：\(lapsed)")
                    .font(.system(size: 11.5))
                    .foregroundColor(MagpieTheme.err)
            } else if let q = quota {
                if let err = q.error, !err.isEmpty {
                    Text("额度查询提示：\(err)")
                        .font(.system(size: 11.5))
                        .foregroundColor(MagpieTheme.warn)
                }
                if !q.windows.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(q.windows) { w in
                            quotaWindowRow(w)
                        }
                    }
                    .padding(9)
                    .background(MagpieTheme.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else if let bal = q.balance, !bal.isEmpty {
                    Text("余额：\(bal)")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(MagpieTheme.textSecondary)
                }
            }

            // Rests
            ForEach(Array(rests.enumerated()), id: \.offset) { _, rest in
                Text("冷却中：\(rest.why ?? "限流") \(rest.until ?? "")")
                    .font(.system(size: 11.5))
                    .foregroundColor(MagpieTheme.warn)
            }

            // Actions
            HStack(spacing: 8) {
                if idx > 0 && login.lapsed == nil {
                    Button("设为首选") {
                        Task { _ = await store.makeAccountFirst(provider: provider, user: login.user, logins: logins) }
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
                }

                if login.token && !login.uses {
                    Button("CLI 使用此 Token") {
                        Task {
                            _ = await store.performLoginAction("switch", agent: agent, user: login.user, toast: "已切换至 \(login.user)")
                        }
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
                }

                if login.lapsed == nil && !login.token {
                    Button(login.on ? "停用" : "启用") {
                        let act = login.on ? "off" : "on"
                        Task {
                            _ = await store.performLoginAction(
                                act,
                                agent: agent,
                                user: login.user,
                                toast: login.on ? "已停用 \(login.user)" : "已启用 \(login.user)"
                            )
                        }
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))
                }

                Button("重授权") {
                    onOpenSignIn(.auto, login.user, ownProxy ?? provider.proxy)
                }
                .buttonStyle(MagpieButtonStyle(tone: login.lapsed != nil ? .primary : .subtle, compact: true))

                Button("设置") {
                    openSettings(for: login)
                }
                .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))

                Spacer()

                Button("移除") {
                    confirmForgetLogin = login
                }
                .buttonStyle(MagpieButtonStyle(tone: .danger, compact: true))
            }
        }
    }

    private func quotaWindowRow(_ w: RemoteQuotaWindow) -> some View {
        let clamped = min(max(w.used, 0), 100)
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(w.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(MagpieTheme.ink)
                Spacer()
                if let display = w.display, !display.isEmpty {
                    Text(display)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(MagpieTheme.textSecondary)
                } else if w.unlimited {
                    Text("不限量")
                        .font(.system(size: 11))
                        .foregroundColor(MagpieTheme.ok)
                } else {
                    Text(String(format: "已用 %.0f%%", clamped))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(clamped >= 90 ? MagpieTheme.err : MagpieTheme.textSecondary)
                }
            }
            if !w.text && !w.unlimited {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(MagpieTheme.hairline)
                            .frame(height: 5)
                        Capsule()
                            .fill(clamped >= 90 ? MagpieTheme.err : (clamped >= 70 ? MagpieTheme.warn : MagpieTheme.ok))
                            .frame(width: geo.size.width * CGFloat(clamped / 100.0), height: 5)
                    }
                }
                .frame(height: 5)
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
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(MagpieTheme.ink)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundColor(MagpieTheme.textSecondary)
            }
            Spacer()
            MagpieToggle(isOn: isOn)
        }
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

                    TextField("轮询权重 (默认 1)", text: $weightDraft)
                        .keyboardType(.numberPad)
                    Button("保存权重") {
                        let w = max(Int(weightDraft.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1, 1)
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
            }
        }
        .navigationViewStyle(.stack)
        .preferredColorScheme(.light)
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
                                        .foregroundColor(MagpieTheme.accent)
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
        .preferredColorScheme(.light)
    }

    // MARK: - Helpers

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
