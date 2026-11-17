import SwiftUI

struct ProvidersView: View {
    @ObservedObject var store: GatewayStore
    @State private var sectionTab: ProviderSectionTab = .providers
    @State private var searchText = ""
    @State private var presentingAddSheet = false
    @State private var addSheetInitialMode: AddProviderSheet.CreationMode = .subscription
    @State private var signingPlatform: SubscriptionPlatform?
    @State private var presentingPriceSheet = false
    @State private var presentingGroupExtras = false
    @State private var testingProviderID: String?
    @State private var testResultsByID: [String: String] = [:]
    struct ProviderDetailSelection: Identifiable, Equatable {
        let id = UUID()
        let providerID: String
        var initialTab: ProviderDetailSheet.DetailTab = .overview
        var highlightedAccountUser: String? = nil
        var highlightedKeyID: String? = nil
    }

    @State private var pendingDelete: RemoteProvider?
    @State private var detailSelection: ProviderDetailSelection?
    @State private var showingAccountErrors = false
    @State private var editingGroup: RemoteRoutingGroup?
    @State private var creatingGroup = false
    @State private var copyingGroup: RemoteRoutingGroup?
    @State private var pendingGroupDelete: RemoteRoutingGroup?

    enum ProviderSectionTab: String, CaseIterable {
        case providers = "供应商"
        case groups = "路由组"
    }

    private var filteredProviders: [RemoteProvider] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return store.providers }
        return store.providers.filter { p in
            p.name.lowercased().contains(q)
                || p.id.lowercased().contains(q)
                || p.models.contains(where: { $0.id.lowercased().contains(q) })
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Spacing.sectionGap) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(sectionTab == .providers ? "供应商号池" : "跨供应商路由组")
                            .font(Typography.pageTitle)
                            .foregroundColor(MagpieTheme.ink)
                        Text(subtitleText)
                            .font(Typography.body)
                            .foregroundColor(MagpieTheme.textSecondary)
                    }
                    Spacer()
                    if sectionTab == .providers {
                        HStack(spacing: Spacing.xs) {
                            Button("定价") {
                                presentingPriceSheet = true
                            }
                            .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))
                            .fixedSize(horizontal: true, vertical: false)
                            .disabled(store.activeServer == nil)

                            Button("OAuth 授权") {
                                addSheetInitialMode = .subscription
                                presentingAddSheet = true
                            }
                            .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
                            .fixedSize(horizontal: true, vertical: false)
                            .disabled(store.activeServer == nil)

                            Button("新增") {
                                addSheetInitialMode = .custom
                                presentingAddSheet = true
                            }
                            .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
                            .fixedSize(horizontal: true, vertical: false)
                            .disabled(store.activeServer == nil)
                        }
                    } else {
                        HStack(spacing: Spacing.sm) {
                            Button("模板/导入/默认") {
                                presentingGroupExtras = true
                            }
                            .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))

                            Button("新建") { creatingGroup = true }
                                .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
                        }
                    }
                }

                segmentedHeader

                if store.activeServer == nil {
                    MinimalSection {
                        Text("请先在「总览」或「隐私与设置」中连接一台 magpie web 服务器。")
                            .font(Typography.body)
                            .foregroundColor(MagpieTheme.textSecondary)
                    }
                } else if sectionTab == .providers {
                    searchField
                    accountErrorsSummaryBanner
                    subscriptionNoticeCards
                    if filteredProviders.isEmpty {
                        MinimalSection {
                            Text(store.providers.isEmpty ? "服务端暂无已配置的供应商" : "没有匹配的供应商或模型")
                                .font(Typography.body)
                                .foregroundColor(MagpieTheme.textSecondary)
                        }
                    } else {
                        ForEach(filteredProviders) { provider in
                            providerCard(provider)
                        }
                    }
                } else {
                    HStack {
                        Text("同名模型自动归组")
                        Spacer()
                        MagpieToggle(isOn: Binding(get: { store.autoGroupsFound }, set: { on in
                            Task { await store.toggleAutoGroups(on) }
                        }))
                    }
                    if store.groups.isEmpty {
                        MinimalSection {
                            Text("服务端暂无路由组（group/*）")
                                .font(Typography.body)
                                .foregroundColor(MagpieTheme.textSecondary)
                        }
                    } else {
                        ForEach(store.groups) { group in
                            groupCard(group)
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.pageHorizontal)
            .padding(.top, Spacing.pageTop)
            .padding(.bottom, Spacing.pageBottom)
        }
        .refreshable {
            await store.refreshProviders()
            await store.refreshGroups()
        }
        .sheet(isPresented: $presentingAddSheet) {
            AddProviderSheet(store: store, initialMode: addSheetInitialMode) { platform in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    signingPlatform = platform
                }
            }
        }
        .sheet(item: $signingPlatform) { platform in
            SubscriptionSignInSheet(store: store, platform: platform) { finishedAgent in
                Task {
                    await store.fetchLoginUsage(agent: finishedAgent)
                    await store.refreshUsage()
                }
            }
        }
        .sheet(isPresented: $presentingPriceSheet) {
            ModelPriceEditorView(store: store)
        }
        .sheet(isPresented: $presentingGroupExtras) {
            GroupExtrasSheet(store: store)
        }
        .sheet(isPresented: $showingAccountErrors, onDismiss: {
            consumePendingAccountJump(delay: 0.05)
        }) {
            AccountErrorsView(store: store)
        }
        .sheet(item: $detailSelection) { selection in
            ProviderDetailSheet(
                store: store,
                providerID: selection.providerID,
                initialTab: selection.initialTab,
                highlightedAccountUser: selection.highlightedAccountUser,
                highlightedKeyID: selection.highlightedKeyID
            )
        }
        .onAppear {
            consumePendingAccountJump(delay: 0.35)
        }
        .onChange(of: store.pendingAccountJump) { _ in
            if !showingAccountErrors {
                consumePendingAccountJump(delay: 0.35)
            }
        }
        .sheet(item: $editingGroup) { group in
            GroupEditorSheet(store: store, existing: group)
        }
        .sheet(isPresented: $creatingGroup) {
            GroupEditorSheet(store: store, existing: nil)
        }
        .sheet(item: $copyingGroup) { group in
            CopyGroupSheet(store: store, group: group)
        }
        .alert("删除路由组？", isPresented: Binding(get: { pendingGroupDelete != nil }, set: { if !$0 { pendingGroupDelete = nil } })) {
            Button("删除", role: .destructive) {
                if let group = pendingGroupDelete { Task { await store.deleteGroup(group) } }
                pendingGroupDelete = nil
            }
            Button("取消", role: .cancel) { pendingGroupDelete = nil }
        } message: { Text("将从服务器移除此路由组。") }
        .alert(
            "删除供应商？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { target in
            Button("删除", role: .destructive) {
                Task { await store.deleteProvider(target) }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) {
                pendingDelete = nil
            }
        } message: { target in
            Text("将从远端 Magpie 配置中移除「\(target.name)」。")
        }
    }

    private var subtitleText: String {
        if sectionTab == .providers {
            let activeCount = store.providers.filter { !$0.off && $0.ready }.count
            return "共 \(store.providers.count) 个供应商 · \(activeCount) 个在线"
        }
        return "共 \(store.groups.count) 个路由组\(store.autoGroupsFound ? " · 已启用自动归组" : "")"
    }

    private var segmentedHeader: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(ProviderSectionTab.allCases, id: \.self) { tab in
                let selected = sectionTab == tab
                Button(tab.rawValue) {
                    sectionTab = tab
                }
                .font(Typography.bodySmallMedium)
                .foregroundColor(selected ? MagpieTheme.onInk : MagpieTheme.textSecondary)
                .padding(.horizontal, Spacing.cardGap)
                .padding(.vertical, 7)
                .background(selected ? MagpieTheme.ink : MagpieTheme.surface)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(MagpieTheme.hairline, lineWidth: selected ? 0 : 1))
                .buttonStyle(.plain)
            }
            Spacer()
            if store.activeServer != nil {
                Button(store.accountErrorItems.isEmpty ? "异常总览" : "异常 (\(store.accountErrorItems.count))") {
                    showingAccountErrors = true
                }
                .buttonStyle(MagpieButtonStyle(tone: store.accountErrorItems.isEmpty ? .subtle : .danger, compact: true))
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityIdentifier("openAccountErrorsButton")
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(Typography.body)
                .foregroundColor(MagpieTheme.textMuted)
            TextField("搜索供应商或模型名…", text: $searchText)
                .font(Typography.bodyInputMono)
                .foregroundColor(MagpieTheme.ink)
                .autocapitalization(.none)
                .disableAutocorrection(true)
        }
        .padding(.horizontal, Spacing.cardGap)
        .padding(.vertical, 10)
        .background(MagpieTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Corners.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Corners.md, style: .continuous)
                .stroke(MagpieTheme.hairline, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var accountErrorsSummaryBanner: some View {
        let errItems = store.accountErrorItems
        if !errItems.isEmpty {
            let authCount = errItems.filter { $0.category == .auth }.count
            let rateCount = errItems.filter { $0.category == .rateLimit }.count
            let accent = authCount > 0 ? StatusPalette.err : StatusPalette.warn
            let surfaceTint = authCount > 0 ? StatusPalette.errSurface : StatusPalette.warnSurface
            Button {
                showingAccountErrors = true
            } label: {
                HStack(spacing: Spacing.md) {
                    Circle()
                        .fill(accent)
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("检测到 \(errItems.count) 个异常/冷却账号")
                            .font(Typography.rowTitle)
                            .foregroundColor(MagpieTheme.ink)
                        Text("鉴权失效 \(authCount) · 限流冷却 \(rateCount) · 点击查看归类并快速跳转")
                            .font(Typography.caption)
                            .foregroundColor(MagpieTheme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text("查看")
                        .font(Typography.captionMedium)
                        .foregroundColor(accent)
                    Image(systemName: "chevron.right")
                        .font(Typography.captionMedium)
                        .foregroundColor(accent)
                }
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(surfaceTint)
                .clipShape(RoundedRectangle(cornerRadius: Corners.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Corners.lg, style: .continuous)
                        .stroke(accent.opacity(0.35), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("providersErrorSummaryBanner")
        }
    }

    private func consumePendingAccountJump(delay: TimeInterval) {
        guard let jump = store.pendingAccountJump else { return }
        sectionTab = .providers
        store.pendingAccountJump = nil
        let targetTab: ProviderDetailSheet.DetailTab = jump.tab == .keys ? .keys : .overview
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            detailSelection = ProviderDetailSelection(
                providerID: jump.providerID,
                initialTab: targetTab,
                highlightedAccountUser: jump.accountUser,
                highlightedKeyID: jump.keyID
            )
        }
    }

    @ViewBuilder
    private var subscriptionNoticeCards: some View {
        if !store.agyMoveUsers.isEmpty {
            MinimalSection(title: "Antigravity 迁移提示", trailingText: "安全迁移") {
                Text("Google 会封禁在官方 Antigravity 客户端之外使用的账号。可将已保存账号一键迁至 local agy CLI：\(store.agyMoveUsers.joined(separator: ", "))")
                    .font(Typography.bodySmall)
                    .foregroundColor(StatusPalette.warn)
                Button("一键迁移至 local agy CLI") {
                    Task { _ = await store.moveAntigravityToAgy() }
                }
                .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
            }
        }
        ForEach(store.unmovedSubs) { candidate in
            MinimalSection(title: "\(candidate.name) 需迁移至插件", trailingText: candidate.package) {
                let errMsg = candidate.error?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                Text(errMsg.isEmpty ? "该内置订阅已下线，请安装对应插件后继续使用已有账号与模型。" : errMsg)
                    .font(Typography.bodySmall)
                    .foregroundColor(StatusPalette.warn)
                if !candidate.package.isEmpty {
                    Button("一键安装插件 \(candidate.package)") {
                        Task { _ = await store.installSubscriptionPlugin(spec: candidate.package) }
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
                }
            }
        }
        ForEach(store.excludedAccounts.filter { !$0.quiet }) { ex in
            MinimalSection(title: "\(ex.agentName) 账号状态异常") {
                Text(ex.why)
                    .font(Typography.bodySmall)
                    .foregroundColor(MagpieTheme.textSecondary)
                if let pid = ex.provider, !pid.isEmpty {
                    HStack(spacing: Spacing.sm) {
                        Button("重新恢复") {
                            Task { _ = await store.restoreExcludedProvider(id: pid, name: ex.agentName) }
                        }
                        .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
                        Button("彻底登出") {
                            Task { _ = await store.forgetExcludedProvider(id: pid, name: ex.agentName) }
                        }
                        .buttonStyle(MagpieButtonStyle(tone: .danger, compact: true))
                    }
                }
            }
        }
    }

    private func providerCard(_ provider: RemoteProvider) -> some View {
        let isEnabled = !provider.off
        let statusKind: ConnectionStatusKind = provider.off ? .untested : (provider.ready ? .connected : .failed)

        return VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .center, spacing: Spacing.sm) {
                MagpieStatusLight(kind: statusKind)
                Text(provider.name)
                    .font(Typography.cardTitle)
                    .foregroundColor(MagpieTheme.ink)
                Spacer()
                if store.providers.count > 1 {
                    Button("↑") {
                        Task { await store.moveProvider(provider, offset: -1) }
                    }
                    .font(Typography.captionMono)
                    .foregroundColor(MagpieTheme.textSecondary)
                    .buttonStyle(.plain)

                    Button("↓") {
                        Task { await store.moveProvider(provider, offset: 1) }
                    }
                    .font(Typography.captionMono)
                    .foregroundColor(MagpieTheme.textSecondary)
                    .buttonStyle(.plain)
                }
                MagpieToggle(
                    isOn: Binding(
                        get: { isEnabled },
                        set: { newVal in
                            Task { await store.toggleProvider(provider, enabled: newVal) }
                        }
                    )
                )
            }

            Text(provider.primaryEndpointPreview)
                .font(Typography.sectionHeaderMono)
                .foregroundColor(MagpieTheme.textSecondary)
                .lineLimit(1)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    MagpieTag(text: "\(provider.exposed)/\(provider.models.count) 模型")
                    let hasPool = (provider.account?.logins.count ?? 0) > 1 || provider.keyList.count > 1
                    if !provider.routing.isEmpty || hasPool {
                        MagpieTag(
                            text: SubscriptionCatalog.routingShortTag(provider.routing),
                            tone: SubscriptionCatalog.isPriorityRouting(provider.routing) ? MagpieTheme.ink : StatusPalette.ok
                        )
                    }
                    if !provider.keyList.isEmpty {
                        let onKeys = provider.keyList.filter(\.on).count
                        MagpieTag(text: "\(onKeys)/\(provider.keyList.count) Key")
                        let restKeys = provider.keyList.filter { $0.rest != nil }.count
                        if restKeys > 0 {
                            MagpieTag(text: "\(restKeys) 冷却", tone: StatusPalette.warn)
                        }
                    } else if let masked = provider.key?.masked, !masked.isEmpty {
                        MagpieTag(text: masked, monospaced: true)
                    } else if let acc = provider.account {
                        if !acc.logins.isEmpty {
                            let onCount = acc.logins.filter { !$0.paused && ($0.on || $0.active) && $0.lapsed == nil }.count
                            MagpieTag(text: "\(onCount)/\(acc.logins.count) 账号", tone: MagpieTheme.ink)
                            if let cap = provider.effectiveMaxAccounts, cap > 0, onCount > cap {
                                MagpieTag(text: "上限 \(cap)", tone: StatusPalette.warn)
                            }
                        }
                        if !provider.accountRests.isEmpty {
                            MagpieTag(text: "\(provider.accountRests.count) 号冷却", tone: StatusPalette.warn)
                        }
                        let lapsedCount = acc.logins.filter { $0.lapsed != nil }.count
                        if lapsedCount > 0 {
                            MagpieTag(text: "\(lapsedCount) 失效", tone: StatusPalette.err)
                        }
                        if let user = acc.user, !user.isEmpty {
                            MagpieTag(text: user)
                        }
                        if let plan = acc.plan, !plan.isEmpty {
                            MagpieTag(text: plan, tone: StatusPalette.ok)
                        }
                    }
                }
            }

            if let err = provider.listError, !err.isEmpty {
                Text(err)
                    .font(Typography.caption)
                    .foregroundColor(StatusPalette.err)
            }

            if let testOutput = testResultsByID[provider.id] {
                Text(testOutput)
                    .font(Typography.captionMono)
                    .foregroundColor(MagpieTheme.textSecondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MagpieTheme.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: Corners.sm + 1, style: .continuous))
            }

            Rectangle().fill(MagpieTheme.hairline).frame(height: 1)

            HStack(spacing: Spacing.sm) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.xs) {
                        Button("管理") { detailSelection = ProviderDetailSelection(providerID: provider.id) }
                            .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
                        if let agent = provider.account?.agent, !agent.isEmpty {
                            Button("授权") {
                                signingPlatform = SubscriptionCatalog.resolve(
                                    agent: agent,
                                    plugins: store.pluginSubs,
                                    onPlugins: store.onPlugins,
                                    movable: store.movableSubs
                                )
                            }
                            .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
                        }
                        Button(testingProviderID == provider.id ? "测连中…" : "测连") {
                            testingProviderID = provider.id
                            Task {
                                testResultsByID[provider.id] = await store.testProvider(provider)
                                testingProviderID = nil
                            }
                        }
                        .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
                        .disabled(testingProviderID == provider.id)

                        Button("拉取模型") {
                            Task { await store.refreshProviderModels(provider) }
                        }
                        .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))

                        Button("查余额") {
                            Task { await store.refreshProviderBalance(provider) }
                        }
                        .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))
                    }
                }

                Button("删除") {
                    pendingDelete = provider
                }
                .font(Typography.sectionHeader)
                .foregroundColor(MagpieTheme.textMuted)
                .fixedSize(horizontal: true, vertical: false)
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.cardPadding)
        .background(MagpieTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Corners.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Corners.xl, style: .continuous)
                .stroke(MagpieTheme.hairline, lineWidth: 1)
        )
    }

    private func groupCard(_ group: RemoteRoutingGroup) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                MagpieStatusLight(kind: group.isOff ? .untested : (group.ready ? .connected : .failed))
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .font(Typography.cardTitle)
                        .foregroundColor(MagpieTheme.ink)
                    Text(group.ref)
                        .font(Typography.captionMono)
                        .foregroundColor(MagpieTheme.textMuted)
                }
                Spacer()
                if !group.auto && store.groups.filter({ !$0.auto }).count > 1 {
                    Button("↑") {
                        Task { await store.moveGroup(group, offset: -1) }
                    }
                    .font(Typography.captionMono)
                    .foregroundColor(MagpieTheme.textSecondary)
                    .buttonStyle(.plain)

                    Button("↓") {
                        Task { await store.moveGroup(group, offset: 1) }
                    }
                    .font(Typography.captionMono)
                    .foregroundColor(MagpieTheme.textSecondary)
                    .buttonStyle(.plain)
                }
                MagpieToggle(
                    isOn: Binding(
                        get: { !group.isOff },
                        set: { newVal in
                            Task { await store.switchGroup(group, enabled: newVal) }
                        }
                    )
                )
            }

            if let note = group.note, !note.isEmpty {
                Text(note)
                    .font(Typography.sectionHeader)
                    .foregroundColor(MagpieTheme.textSecondary)
            }

            HStack(spacing: Spacing.xs) {
                if !group.routing.isEmpty {
                    MagpieTag(text: "策略: \(group.routing)")
                }
                MagpieTag(text: "\(group.members.count) 个成员")
                if let picked = group.picked, !picked.isEmpty {
                    MagpieTag(text: "当前: \(picked)", monospaced: true)
                }
            }

            HStack {
                if !group.auto {
                    Button("编辑") { editingGroup = group }
                        .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
                }
                Button("复制") { copyingGroup = group }
                    .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
                Button("分享") {
                    Task {
                        if let text = await store.shareGroup(group) {
                            store.copyToClipboard(text, label: "路由组分享文本")
                        }
                    }
                }
                .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))
                Spacer()
                if !group.auto {
                    Button("删除", role: .destructive) { pendingGroupDelete = group }
                }
            }
            if !group.members.isEmpty {
                Rectangle().fill(MagpieTheme.hairline).frame(height: 1)
                ForEach(group.members, id: \.self) { member in
                    let isPicked = group.picked == member
                    HStack {
                        Text(member)
                            .font(Typography.sectionHeaderMono)
                            .foregroundColor(isPicked ? MagpieTheme.ink : MagpieTheme.textSecondary)
                            .lineLimit(1)
                        Spacer()
                        if group.routing.lowercased() == "manual" {
                            Button(isPicked ? "已选中" : "切换") {
                                Task { await store.pickGroupMember(group, member: member) }
                            }
                            .buttonStyle(MagpieButtonStyle(tone: isPicked ? .primary : .subtle, compact: true))
                        }
                    }
                }
            }
        }
        .padding(Spacing.cardPadding)
        .background(MagpieTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Corners.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Corners.xl, style: .continuous)
                .stroke(MagpieTheme.hairline, lineWidth: 1)
        )
    }
}

private struct GroupExtrasSheet: View {
    @ObservedObject var store: GatewayStore
    @Environment(\.dismiss) private var dismiss

    @State private var templateName = ""
    @State private var importText = ""
    @State private var replaceExisting = false
    @State private var defaultSink = true
    @State private var defaultFirstToken = "45"
    @State private var defaultPatience = "30"

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("从内置模板创建路由组 (/api/groups/template)")) {
                    TextField("自定义组名（留空使用模板默认名）", text: $templateName)
                    if store.groupTemplates.isEmpty {
                        Text("服务端未返回内置模板").font(.caption).foregroundColor(MagpieTheme.textSecondary)
                    } else {
                        ForEach(store.groupTemplates) { tpl in
                            Button("创建「\(tpl.group.name.isEmpty ? tpl.kind : tpl.group.name)」") {
                                let defaultName = tpl.group.name.isEmpty ? tpl.kind : tpl.group.name
                                let finalName = templateName.trimmingCharacters(in: .whitespaces).isEmpty ? defaultName : templateName
                                Task {
                                    if await store.createGroupFromTemplate(tpl, name: finalName) {
                                        dismiss()
                                    }
                                }
                            }
                        }
                    }
                }

                Section(header: Text("导入路由组 (/api/groups/import)")) {
                    TextField("粘贴路由组分享文本或 JSON", text: $importText)
                        .font(.caption.monospaced())
                        .autocapitalization(.none)
                    Toggle("覆盖同名路由组", isOn: $replaceExisting)
                    Button("导入路由组") {
                        Task {
                            if await store.importGroup(text: importText, replace: replaceExisting) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section(header: Text("路由组全局默认设置 (/api/groups/defaults)")) {
                    Toggle("报错/限流成员自动沉底 (sink)", isOn: $defaultSink)
                    HStack {
                        Text("首字超时 (firstToken 秒)")
                        Spacer()
                        TextField("45", text: $defaultFirstToken)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    HStack {
                        Text("故障容忍窗口 (patience 秒)")
                        Spacer()
                        TextField("30", text: $defaultPatience)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    Button("保存路由组全局默认值") {
                        let ft = Int(defaultFirstToken) ?? 45
                        let pt = Int(defaultPatience) ?? 30
                        Task {
                            if await store.saveGroupDefaults(sink: defaultSink, firstToken: ft, patience: pt) {
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle("模板、导入与默认项")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear {
                if let defs = store.groupDefaults {
                    defaultSink = defs.sink
                    defaultFirstToken = String(defs.firstToken)
                    defaultPatience = String(defs.patience)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

private struct AddProviderSheet: View {
    @ObservedObject var store: GatewayStore
    var initialMode: CreationMode = .subscription
    var onSelectSubscription: (SubscriptionPlatform) -> Void
    @Environment(\.dismiss) private var dismiss

    enum CreationMode: String, CaseIterable {
        case subscription = "订阅 OAuth"
        case preset = "API Key 预设"
        case custom = "自定义地址"
    }

    @State private var mode: CreationMode = .subscription
    @State private var subQuery = ""
    @State private var presetQuery = ""
    @State private var selectedPresetID: String = ""
    @State private var selectedRegionID: String = ""
    @State private var name = ""
    @State private var apiKey = ""
    @State private var chatURL = ""
    @State private var anthropicURL = ""
    @State private var responsesURL = ""
    @State private var geminiURL = ""
    @State private var isSaving = false
    @State private var errorMsg: String?

    private var catalog: (builtins: [SubscriptionPlatform], extraPlugins: [SubscriptionPlatform]) {
        SubscriptionCatalog.allPlatforms(plugins: store.pluginSubs, onPlugins: store.onPlugins, movable: store.movableSubs)
    }

    private var marketPlatforms: [SubscriptionPlatform] {
        SubscriptionCatalog.communityMarketPlatforms(
            plugins: store.pluginSubs,
            onPlugins: store.onPlugins,
            listings: store.pluginListings
        )
    }

    private var filteredPresets: [RemotePreset] {
        let q = presetQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return store.presets }
        return store.presets.filter {
            $0.name.lowercased().contains(q)
                || $0.id.lowercased().contains(q)
                || ($0.short?.lowercased().contains(q) ?? false)
        }
    }

    private func matches(_ p: SubscriptionPlatform) -> Bool {
        let q = subQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        return p.name.lowercased().contains(q)
            || p.agent.lowercased().contains(q)
            || p.subtitle.lowercased().contains(q)
            || p.keywords.lowercased().contains(q)
    }

    private func loginCount(for agent: String) -> Int {
        guard let p = store.providers.first(where: { $0.account?.agent == agent }) else { return 0 }
        return max(p.account?.logins.count ?? 0, (p.account?.user?.isEmpty == false) ? 1 : 0)
    }

    var body: some View {
        ZStack {
            MagpieTheme.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button("取消") { dismiss() }
                        .font(Typography.bodyMedium)
                        .foregroundColor(MagpieTheme.textSecondary)
                    Spacer()
                    Text("新增远程供应商")
                        .font(Typography.navTitle)
                        .foregroundColor(MagpieTheme.ink)
                    Spacer()
                    if mode == .subscription {
                        Text("选择平台")
                            .font(Typography.body)
                            .foregroundColor(MagpieTheme.textMuted)
                    } else {
                        Button(isSaving ? "保存中…" : "保存") { commit() }
                            .font(Typography.bodyMedium)
                            .foregroundColor(MagpieTheme.ink)
                            .disabled(isSaving)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
                .background(MagpieTheme.surface)
                .overlay(Rectangle().fill(MagpieTheme.hairline).frame(height: 1), alignment: .bottom)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Spacing.cardPadding) {
                        Picker("添加方式", selection: $mode) {
                            ForEach(CreationMode.allCases, id: \.self) { m in
                                Text(m.rawValue).tag(m)
                            }
                        }
                        .pickerStyle(.segmented)

                        if mode == .subscription {
                            subscriptionListContent
                        } else {
                            if mode == .preset, !store.presets.isEmpty {
                                MinimalSection(title: "选择厂商预设", trailingText: "\(filteredPresets.count)/\(store.presets.count) 个预设") {
                                    TextField("搜索预设：DeepSeek / Kimi / 智谱 / 火山 / 硅基流动…", text: $presetQuery)
                                        .font(Typography.bodySmall)
                                        .autocapitalization(.none)
                                        .disableAutocorrection(true)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .background(MagpieTheme.canvas)
                                        .clipShape(RoundedRectangle(cornerRadius: Corners.sm + 1, style: .continuous))

                                    ForEach(filteredPresets) { preset in
                                        Button {
                                            selectedPresetID = preset.id
                                            let r = preset.regions.first
                                            selectedRegionID = r?.id ?? ""
                                            name = preset.displayTitle
                                            chatURL = r?.chat ?? preset.chat ?? ""
                                            anthropicURL = r?.anthropic ?? preset.anthropic ?? ""
                                            responsesURL = r?.responses ?? preset.responses ?? ""
                                        } label: {
                                            HStack {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(preset.displayTitle)
                                                        .font(Typography.rowTitle)
                                                        .foregroundColor(MagpieTheme.ink)
                                                    if !preset.regions.isEmpty {
                                                        Text(preset.regions.map(\.name).joined(separator: " · "))
                                                            .font(Typography.micro)
                                                            .foregroundColor(MagpieTheme.textMuted)
                                                            .lineLimit(1)
                                                    }
                                                }
                                                Spacer()
                                                if preset.added {
                                                    MagpieTag(text: "已添加")
                                                }
                                                if selectedPresetID == preset.id {
                                                    MagpieTag(text: "已选", tone: StatusPalette.ok)
                                                }
                                            }
                                        }
                                        .buttonStyle(.plain)

                                        if selectedPresetID == preset.id && preset.regions.count > 1 {
                                            ScrollView(.horizontal, showsIndicators: false) {
                                                HStack(spacing: Spacing.xs) {
                                                    ForEach(preset.regions) { reg in
                                                        let activeReg = selectedRegionID == reg.id
                                                        Button(reg.name) {
                                                            selectedRegionID = reg.id
                                                            chatURL = reg.chat ?? preset.chat ?? ""
                                                            anthropicURL = reg.anthropic ?? preset.anthropic ?? ""
                                                            responsesURL = reg.responses ?? preset.responses ?? ""
                                                        }
                                                        .font(activeReg ? Typography.captionMedium : Typography.caption)
                                                        .foregroundColor(activeReg ? MagpieTheme.onInk : MagpieTheme.ink)
                                                        .padding(.horizontal, 10)
                                                        .padding(.vertical, 5)
                                                        .background(activeReg ? MagpieTheme.ink : MagpieTheme.canvas)
                                                        .clipShape(Capsule())
                                                        .buttonStyle(.plain)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            } else if mode == .preset && store.presets.isEmpty {
                                MinimalSection(title: "提示") {
                                    Text("服务端未返回内置 API Key 预设，可切换为「自定义地址」或「订阅 OAuth」。")
                                        .font(Typography.bodySmall)
                                        .foregroundColor(MagpieTheme.textSecondary)
                                }
                            }

                            MinimalSection(title: "供应商参数", trailingText: "/api/provider/save") {
                                MagpieInputField(label: "名称", placeholder: "例如：OpenRouter / 自建中转", text: $name)
                                MagpieInputField(label: "API Key", placeholder: "sk-...", text: $apiKey, isSecure: true, monospaced: true)
                                MagpieInputField(label: "OpenAI Chat Base URL", placeholder: "https://api.openai.com/v1", text: $chatURL, monospaced: true, keyboardType: .URL)
                                MagpieInputField(label: "Anthropic Base URL（可选）", placeholder: "https://api.anthropic.com", text: $anthropicURL, monospaced: true, keyboardType: .URL)
                                MagpieInputField(label: "Responses Base URL（可选）", placeholder: "https://api.openai.com/v1", text: $responsesURL, monospaced: true, keyboardType: .URL)
                                MagpieInputField(label: "Gemini Base URL（可选）", placeholder: "https://generativelanguage.googleapis.com/v1beta", text: $geminiURL, monospaced: true, keyboardType: .URL)
                            }

                            if let err = errorMsg {
                                MagpieErrorBanner(title: "保存失败", message: err)
                            }
                        }
                    }
                    .padding(22)
                }
            }
        }
        .onAppear {
            mode = initialMode
            Task { await store.refreshPluginListings() }
        }
    }

    @ViewBuilder
    private var subscriptionListContent: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(Typography.body)
                .foregroundColor(MagpieTheme.textMuted)
            TextField("搜索平台：反重力 / Codex / Claude / Gemini / Copilot…", text: $subQuery)
                .font(Typography.body)
                .autocapitalization(.none)
                .disableAutocorrection(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(MagpieTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Corners.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Corners.md, style: .continuous).stroke(MagpieTheme.hairline, lineWidth: 1))

        let filteredBuiltins = catalog.builtins.filter(matches)
        let filteredExtras = catalog.extraPlugins.filter(matches)
        let filteredMarket = marketPlatforms.filter(matches)

        MinimalSection(title: "官方与内置反代订阅平台", trailingText: "\(filteredBuiltins.count) 个平台") {
            ForEach(filteredBuiltins) { platform in
                subscriptionPlatformRow(platform)
            }
        }

        if !filteredExtras.isEmpty {
            MinimalSection(title: "已安装的插件反代平台", trailingText: "\(filteredExtras.count) 个插件") {
                ForEach(filteredExtras) { platform in
                    subscriptionPlatformRow(platform)
                }
            }
        }

        if !filteredMarket.isEmpty {
            MinimalSection(title: "社区插件反代平台（可一键安装）", trailingText: "\(filteredMarket.count) 个平台") {
                ForEach(filteredMarket) { platform in
                    subscriptionPlatformRow(platform)
                }
            }
        }

        let quietRemoved = store.excludedAccounts.filter { $0.quiet && ($0.provider?.isEmpty == false) }
        if !quietRemoved.isEmpty {
            MinimalSection(title: "已移除仍保持登录的账号") {
                ForEach(quietRemoved) { ex in
                    HStack {
                        Text(ex.agentName)
                            .font(Typography.rowTitle)
                            .foregroundColor(MagpieTheme.ink)
                        Spacer()
                        if let pid = ex.provider {
                            Button("加回") {
                                Task { _ = await store.restoreExcludedProvider(id: pid, name: ex.agentName) }
                            }
                            .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
                            Button("登出") {
                                Task { _ = await store.forgetExcludedProvider(id: pid, name: ex.agentName) }
                            }
                            .buttonStyle(MagpieButtonStyle(tone: .danger, compact: true))
                        }
                    }
                }
            }
        }
    }

    private func subscriptionPlatformRow(_ platform: SubscriptionPlatform) -> some View {
        let count = loginCount(for: platform.agent)
        return Button {
            dismiss()
            onSelectSubscription(platform)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: Spacing.xs) {
                        Text(platform.name)
                            .font(Typography.bodyMedium)
                            .foregroundColor(MagpieTheme.ink)
                        if count > 0 {
                            MagpieTag(text: "\(count) 账号", tone: StatusPalette.ok)
                        }
                        if platform.isPluginBacked {
                            MagpieTag(text: "插件", tone: MagpieTheme.ink)
                        } else if platform.pluginSpec != nil {
                            MagpieTag(text: "待装插件")
                        }
                        if platform.risk {
                            MagpieTag(text: "风控", tone: StatusPalette.warn)
                        }
                    }
                    Text(platform.subtitle)
                        .font(Typography.sectionHeader)
                        .foregroundColor(MagpieTheme.textSecondary)
                        .lineLimit(1)
                    Text(platform.plans)
                        .font(Typography.micro)
                        .foregroundColor(MagpieTheme.textMuted)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(Typography.sectionHeader)
                    .foregroundColor(MagpieTheme.textMuted)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private func commit() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanName.isEmpty {
            errorMsg = "请填写供应商名称"
            return
        }
        if mode == .preset, let preset = store.presets.first(where: { $0.id == selectedPresetID }) {
            errorMsg = nil
            isSaving = true
            Task {
                let ok = await store.addPresetProvider(
                    preset: preset,
                    name: cleanName,
                    key: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                    region: preset.regions.first(where: { $0.id == selectedRegionID }) ?? preset.regions.first,
                    customEndpoint: chatURL.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                isSaving = false
                if ok { dismiss() } else { errorMsg = store.lastActionError }
            }
            return
        }
        if chatURL.isEmpty && anthropicURL.isEmpty && responsesURL.isEmpty && geminiURL.isEmpty {
            errorMsg = "至少填写一个协议接口 Base URL"
            return
        }
        errorMsg = nil
        isSaving = true
        Task {
            let ok = await store.addCustomProvider(
                name: cleanName,
                key: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                chatURL: chatURL.trimmingCharacters(in: .whitespacesAndNewlines),
                anthropicURL: anthropicURL.trimmingCharacters(in: .whitespacesAndNewlines),
                responsesURL: responsesURL.trimmingCharacters(in: .whitespacesAndNewlines),
                geminiURL: geminiURL.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            isSaving = false
            if ok {
                dismiss()
            } else {
                errorMsg = store.lastActionError
            }
        }
    }
}
