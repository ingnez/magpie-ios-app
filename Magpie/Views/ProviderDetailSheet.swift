import SwiftUI

struct ProviderDetailSheet: View {
    @ObservedObject var store: GatewayStore
    let providerID: String
    var initialTab: DetailTab = .overview
    var highlightedAccountUser: String? = nil
    var highlightedKeyID: String? = nil
    @Environment(\.dismiss) private var dismiss

    enum DetailTab: String, CaseIterable {
        case overview = "概况与策略"
        case keys = "多 Key 号池"
        case models = "模型管理"
        case advanced = "高级配置"
    }

    @State private var activeTab: DetailTab = .overview
    @State private var didApplyInitialTab = false
    @State private var isTesting = false
    @State private var isRefreshingModels = false
    @State private var isCheckingBalance = false
    @State private var testOutput: String?
    @State private var confirmDelete = false
    @State private var signInRequest: SignInSheetRequest?

    private struct SignInSheetRequest: Identifiable {
        let id = UUID()
        let platform: SubscriptionPlatform
        let mode: SubscriptionSignInSheet.InitialMode
        let forUser: String?
        let defaultProxy: String?
    }

    // Key pool states
    @State private var newKeyName = ""
    @State private var newKeySecret = ""
    @State private var newKeyProto = ""
    @State private var batchKeysText = ""
    @State private var batchKeysProto = ""
    @State private var showingAddKeyForm = false
    @State private var showingImportKeysForm = false
    @State private var editingKeyTarget: RemoteKeyInfo?
    @State private var keyRenameDraft = ""
    @State private var keyReplaceDraft = ""
    @State private var keyWeightDraft = "1"
    @State private var keyProtoDraft = ""
    @State private var keyModelsTarget: RemoteKeyInfo?
    @State private var keyAllowedModelsDraft: Set<String> = []

    // Model list states
    @State private var modelSearch = ""
    @State private var draftChosen: Set<String> = []
    @State private var draftNoModels = false
    @State private var draftBestInFamily = false
    @State private var modelsDirty = false
    @State private var editingModel: RemoteProviderModel?
    @State private var modelAliasDraft = ""
    @State private var modelEffortsDraft: Set<String> = []
    @State private var modelImagesDraft: Int = 0 // 0=auto, 1=yes, 2=no

    // Advanced form drafts
    @State private var formInitializedForID: String?
    @State private var nameDraft = ""
    @State private var idDraft = ""
    @State private var chatDraft = ""
    @State private var anthropicDraft = ""
    @State private var responsesDraft = ""
    @State private var geminiDraft = ""
    @State private var decideDraft = ""
    @State private var modelsURLDraft = ""
    @State private var balanceURLDraft = ""
    @State private var balancePathDraft = ""
    @State private var proxyDraft = ""
    @State private var fallbackDraft = ""
    @State private var billingDraft = ""
    @State private var priceRateDraft = ""
    @State private var maxConcurrencyDraft = ""
    @State private var maxAccountsDraft = ""
    @State private var maxRPMDraft = ""
    @State private var authHeaderDraft = ""
    @State private var unredactedDraft = false
    @State private var countFreeDraft = false
    @State private var insecureTLSDraft = false
    @State private var http1Draft = false
    @State private var limitRestOffDraft = false
    @State private var passErrorsDraft = false
    @State private var listOffDraft = false
    @State private var isSavingAdvanced = false

    private var provider: RemoteProvider? {
        store.providers.first(where: { $0.id == providerID })
    }

    private let priorityRoutingOptions: [(id: String, title: String, note: String)] = [
        ("", "Smart 智能优先级", "非均分轮询：优先即将重置的可用账号，快耗尽或异常时切换（Key 按列表顺序）"),
        ("order", "Order 严格顺序优先级", "严格按 #1 → #2 → #3 顺序调用，仅耗尽/限流冷却/失败时顺延，恢复后回到高优先级"),
        ("drain", "Drain 用尽顺延", "锁定当前顺位直至耗尽才切下一位，不主动回切；冷却时暂时跳过")
    ]

    private let rotationRoutingOptions: [(id: String, title: String, note: String)] = [
        ("rotate", "Rotate 逐轮轮询", "每次用户新消息在已启用账号间轮流分发（同轮工具调用保持同号；Session 粘性可锁定整会话）"),
        ("weight", "Weight 权重轮询", "按各账号/Key 权重比例平滑轮询分配流量"),
        ("usage", "Usage 最少已用", "优先使用当前已用量比例最低的账号"),
        ("pace", "Pace 速率均衡", "优先消耗重置前单位时间余量最充裕的账号"),
        ("fast", "Fast 速度优先", "按近期首字与输出速度优先选择"),
        ("free", "Free 免费优先", "优先消耗不扣减付费配额的免费模型或免费额度")
    ]

    private let affinityOptions: [(id: String, title: String)] = [
        ("", "自动 (Auto)"),
        ("session", "整会话锁定"),
        ("turn", "单轮锁定"),
        ("off", "不粘性"),
        ("strict", "严格锁定")
    ]

    private let protocolOptions: [(id: String, title: String)] = [
        ("", "全部协议"),
        ("chat", "OpenAI Chat"),
        ("responses", "Responses"),
        ("anthropic", "Anthropic"),
        ("gemini", "Gemini")
    ]

    private let allEffortLevels = ["low", "medium", "high", "xhigh", "max"]

    var body: some View {
        ZStack {
            MagpieTheme.canvas.ignoresSafeArea()

            if let p = provider {
                VStack(spacing: 0) {
                    sheetHeader(p)
                    subTabBar(p)
                    ScrollViewReader { scrollProxy in
                        ScrollView(showsIndicators: false) {
                            VStack(alignment: .leading, spacing: Spacing.cardPadding) {
                                switch activeTab {
                                case .overview:
                                    overviewSection(p)
                                case .keys:
                                    keysSection(p)
                                case .models:
                                    modelsSection(p)
                                case .advanced:
                                    advancedSection(p)
                                }
                            }
                            .padding(Spacing.sheetPadding)
                            .padding(.bottom, 40)
                        }
                        .accessibilityIdentifier("providerDetailScrollView")
                        .onAppear {
                            if !didApplyInitialTab {
                                activeTab = initialTab
                                didApplyInitialTab = true
                            }
                            if let user = highlightedAccountUser, !user.isEmpty {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        scrollProxy.scrollTo("accountRow_\(user.lowercased())", anchor: .center)
                                    }
                                }
                            } else if let kid = highlightedKeyID, !kid.isEmpty {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        scrollProxy.scrollTo("keyRow_\(kid)", anchor: .center)
                                    }
                                }
                            }
                        }
                    }
                }
                .onAppear {
                    if !didApplyInitialTab {
                        activeTab = initialTab
                        didApplyInitialTab = true
                    }
                    syncDrafts(from: p)
                }
                .onChange(of: p.id) { _ in
                    syncDrafts(from: p)
                }
                .onChange(of: p.maxAccounts) { newMax in
                    maxAccountsDraft = newMax.map { String($0) } ?? ""
                }
            } else {
                VStack(spacing: 12) {
                    Text("该供应商已不存在")
                        .font(.system(size: 14))
                        .foregroundColor(MagpieTheme.textSecondary)
                    Button("关闭") { dismiss() }
                        .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
                }
            }
        }
        .sheet(item: $editingKeyTarget) { keyItem in
            keyEditorSheet(keyItem)
        }
        .sheet(item: $keyModelsTarget) { keyItem in
            keyModelsSheet(keyItem)
        }
        .sheet(item: $editingModel) { model in
            modelEditorSheet(model)
        }
        .sheet(item: $signInRequest) { req in
            SubscriptionSignInSheet(
                store: store,
                platform: req.platform,
                initialMode: req.mode,
                forUser: req.forUser,
                defaultProxy: req.defaultProxy
            ) { finishedAgent in
                Task {
                    await store.fetchLoginUsage(agent: finishedAgent)
                    await store.refreshUsage()
                }
            }
        }
        .alert("删除供应商？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) {
                if let p = provider {
                    Task {
                        await store.deleteProvider(p)
                        dismiss()
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将从远端 Magpie 移除「\(provider?.name ?? providerID)」。")
        }
    }

    // MARK: - Header & Tabs

    private func sheetHeader(_ p: RemoteProvider) -> some View {
        HStack(spacing: 10) {
            Button("关闭") { dismiss() }
                .font(.system(size: 14))
                .foregroundColor(MagpieTheme.textSecondary)

            Spacer()

            HStack(spacing: 6) {
                MagpieStatusLight(kind: p.off ? .untested : (p.ready ? .connected : .failed))
                Text(p.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MagpieTheme.ink)
                    .lineLimit(1)
            }

            Spacer()

            MagpieToggle(
                isOn: Binding(
                    get: { !p.off },
                    set: { val in
                        Task { await store.toggleProvider(p, enabled: val) }
                    }
                )
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(MagpieTheme.surface)
        .overlay(Rectangle().fill(MagpieTheme.hairline).frame(height: 1), alignment: .bottom)
    }

    private func subTabBar(_ p: RemoteProvider) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DetailTab.allCases, id: \.self) { tab in
                    let selected = activeTab == tab
                    let label = (tab == .keys && p.account != nil) ? "多账号号池" : tab.rawValue
                    Button(label) {
                        activeTab = tab
                    }
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(selected ? MagpieTheme.onInk : MagpieTheme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(selected ? MagpieTheme.ink : MagpieTheme.surface)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(MagpieTheme.hairline, lineWidth: selected ? 0 : 1))
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .background(MagpieTheme.canvas)
    }

    // MARK: - Tab 1: Overview & Routing Strategy

    private func overviewSection(_ p: RemoteProvider) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            MinimalSection(title: "实例状态与诊断", trailingText: p.id) {
                Text(p.primaryEndpointPreview)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundColor(MagpieTheme.textSecondary)

                HStack(spacing: 6) {
                    MagpieTag(text: "\(p.exposedCount)/\(p.models.count) 模型在线")
                    if !p.keyList.isEmpty {
                        MagpieTag(text: "\(p.keyList.filter(\.on).count)/\(p.keyList.count) Key")
                    }
                    if !p.billingKind.isEmpty {
                        MagpieTag(text: p.billingKind.uppercased(), monospaced: true)
                    }
                    if p.unredacted {
                        MagpieTag(text: "不脱敏", tone: MagpieTheme.warn)
                    }
                }

                if let err = p.listError, !err.isEmpty {
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundColor(MagpieTheme.err)
                }

                if let bal = store.balanceOutputsByID[p.id] {
                    Text(bal)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(MagpieTheme.ink)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(MagpieTheme.canvas)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                if let testOut = testOutput {
                    Text(testOut)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(MagpieTheme.textSecondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(MagpieTheme.canvas)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                Rectangle().fill(MagpieTheme.hairline).frame(height: 1)

                HStack(spacing: 8) {
                    Button(isTesting ? "测连中…" : "测试连通") {
                        isTesting = true
                        Task {
                            testOutput = await store.testProvider(p)
                            isTesting = false
                        }
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
                    .disabled(isTesting)

                    Button(isRefreshingModels ? "拉取中…" : "拉取模型") {
                        isRefreshingModels = true
                        Task {
                            await store.refreshProviderModels(p)
                            syncModelDrafts(from: store.providers.first(where: { $0.id == p.id }) ?? p)
                            isRefreshingModels = false
                        }
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
                    .disabled(isRefreshingModels)

                    Button(isCheckingBalance ? "查询中…" : "查余额") {
                        isCheckingBalance = true
                        Task {
                            await store.refreshProviderBalance(p)
                            isCheckingBalance = false
                        }
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))
                    .disabled(isCheckingBalance)
                }
            }

            MinimalSection(
                title: "优先级与顺延策略",
                trailingText: SubscriptionCatalog.isPriorityRouting(p.routing) ? (p.routing.isEmpty ? "smart" : p.routing) : "未启用"
            ) {
                ForEach(priorityRoutingOptions, id: \.id) { opt in
                    routingOptionRow(p: p, opt: opt)
                }
            }

            MinimalSection(
                title: "轮询与负载均衡策略",
                trailingText: !SubscriptionCatalog.isPriorityRouting(p.routing) ? p.routing : "未启用"
            ) {
                ForEach(rotationRoutingOptions, id: \.id) { opt in
                    routingOptionRow(p: p, opt: opt)
                }
            }

            MinimalSection(title: "会话粘性与行为开关") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("会话粘性 (Affinity)")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(MagpieTheme.textSecondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(affinityOptions, id: \.id) { opt in
                                let selected = p.affinity == opt.id
                                Button(opt.title) {
                                    Task { await store.updateProviderAffinity(p, affinity: opt.id) }
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(selected ? MagpieTheme.onInk : MagpieTheme.ink)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(selected ? MagpieTheme.ink : MagpieTheme.canvas)
                                .clipShape(Capsule())
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if p.routing != "rotate" && p.routing != "weight" {
                    Rectangle().fill(MagpieTheme.hairline).frame(height: 1)

                    toggleRow(
                        title: "限流后沉底 (Sink)",
                        subtitle: "触发 429 后暂排到号池队尾，避免频繁撞限流",
                        isOn: Binding(
                            get: { p.sink },
                            set: { val in Task { await store.updateProviderSink(p, sink: val) } }
                        )
                    )
                }

                Rectangle().fill(MagpieTheme.hairline).frame(height: 1)

                toggleRow(
                    title: "Smart 优先使用 (Use First)",
                    subtitle: "同模型跨供应商竞争时优先消耗本供应商",
                    isOn: Binding(
                        get: { p.useFirst },
                        set: { val in Task { await store.updateProviderUseFirst(p, useFirst: val) } }
                    )
                )

                Rectangle().fill(MagpieTheme.hairline).frame(height: 1)

                toggleRow(
                    title: "不作为其他模型兜底 (No Stand-in)",
                    subtitle: "防止其他供应商或本地模型请求故障转移到本账号",
                    isOn: Binding(
                        get: { p.noStandIn },
                        set: { val in Task { await store.updateProviderNoStandIn(p, noStandIn: val) } }
                    )
                )
            }

            MinimalSection(title: "排序与危险操作") {
                HStack(spacing: 10) {
                    Button("上移优先级") {
                        Task { await store.moveProvider(p, offset: -1) }
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))

                    Button("下移优先级") {
                        Task { await store.moveProvider(p, offset: 1) }
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))

                    Spacer()

                    Button("删除供应商") {
                        confirmDelete = true
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .danger, compact: true))
                }
            }
        }
    }

    private func routingOptionRow(p: RemoteProvider, opt: (id: String, title: String, note: String)) -> some View {
        let isSelected = p.routing == opt.id
        return Button {
            Task { await store.updateProviderRouting(p, routing: opt.id) }
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundColor(isSelected ? MagpieTheme.ink : MagpieTheme.textMuted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(opt.title)
                        .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(MagpieTheme.ink)
                    Text(opt.note)
                        .font(.system(size: 11.5))
                        .foregroundColor(MagpieTheme.textMuted)
                }
                Spacer()
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab 2: Multi-Key Pool

    private func keysSection(_ p: RemoteProvider) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if let acc = p.account {
                SubscriptionAccountsSection(store: store, provider: p, account: acc, highlightedUser: highlightedAccountUser) { mode, user, proxy in
                    let agent = acc.agent ?? p.id
                    let platform = SubscriptionCatalog.resolve(
                        agent: agent,
                        plugins: store.pluginSubs,
                        onPlugins: store.onPlugins,
                        movable: store.movableSubs
                    )
                    signInRequest = SignInSheetRequest(
                        platform: platform,
                        mode: mode,
                        forUser: user,
                        defaultProxy: proxy
                    )
                }
            }

            if p.account == nil || !p.keyList.isEmpty {
                MinimalSection(title: "API Key 号池 (\(p.keyList.count))", trailingText: p.routing.isEmpty ? "smart" : p.routing) {
                HStack(spacing: 8) {
                    Button(showingAddKeyForm ? "收起添加" : "添加 Key") {
                        showingAddKeyForm.toggle()
                        if showingAddKeyForm { showingImportKeysForm = false }
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))

                    Button(showingImportKeysForm ? "收起导入" : "批量导入") {
                        showingImportKeysForm.toggle()
                        if showingImportKeysForm { showingAddKeyForm = false }
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))

                    Spacer()

                    if !p.keyList.isEmpty {
                        Button("复制全部") {
                            Task {
                                if let raw = await store.revealProviderKey(id: p.id, allKeys: true) {
                                    store.copyToClipboard(raw, label: "全部 Key")
                                }
                            }
                        }
                        .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))
                    }
                }

                if showingAddKeyForm {
                    VStack(alignment: .leading, spacing: 10) {
                        Rectangle().fill(MagpieTheme.hairline).frame(height: 1)
                        MagpieInputField(label: "备注名（可选）", placeholder: "例如：主号 / 备用Key", text: $newKeyName)
                        MagpieInputField(label: "API Key", placeholder: p.anonKey != nil ? "留空可添加公共匿名 Key" : "sk-...", text: $newKeySecret, isSecure: true, monospaced: true)
                        protocolPickerRow(selected: $newKeyProto, label: "限定协议")
                        Button("确认添加") {
                            Task {
                                let ok = await store.addProviderKey(
                                    providerID: p.id,
                                    name: newKeyName.trimmingCharacters(in: .whitespacesAndNewlines),
                                    key: newKeySecret.trimmingCharacters(in: .whitespacesAndNewlines),
                                    protocol: newKeyProto
                                )
                                if ok {
                                    newKeyName = ""
                                    newKeySecret = ""
                                    showingAddKeyForm = false
                                }
                            }
                        }
                        .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
                    }
                }

                if showingImportKeysForm {
                    VStack(alignment: .leading, spacing: 10) {
                        Rectangle().fill(MagpieTheme.hairline).frame(height: 1)
                        Text("每行或逗号分隔粘贴多个 API Key")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(MagpieTheme.textSecondary)
                        TextEditor(text: $batchKeysText)
                            .font(.system(size: 12.5, design: .monospaced))
                            .frame(minHeight: 88)
                            .padding(8)
                            .background(MagpieTheme.canvas)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(MagpieTheme.hairline, lineWidth: 1))
                        protocolPickerRow(selected: $batchKeysProto, label: "统一限定协议")
                        Button("开始导入") {
                            let raw = batchKeysText.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !raw.isEmpty else { return }
                            Task {
                                let ok = await store.importProviderKeys(providerID: p.id, keysText: raw, protocol: batchKeysProto)
                                if ok {
                                    batchKeysText = ""
                                    showingImportKeysForm = false
                                }
                            }
                        }
                        .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
                    }
                }

                    if p.keyList.isEmpty {
                        Text("暂无多 Key 记录")
                            .font(.system(size: 12.5))
                            .foregroundColor(MagpieTheme.textMuted)
                    } else {
                        ForEach(Array(p.keyList.enumerated()), id: \.element.id) { idx, k in
                            if idx > 0 {
                                Rectangle().fill(MagpieTheme.hairline).frame(height: 1)
                            }
                            keyRow(p, keyInfo: k)
                                .id("keyRow_\(k.id)")
                                .padding(highlightedKeyID == k.id ? Spacing.xs : 0)
                                .background(highlightedKeyID == k.id ? StatusPalette.warnSurface : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: Corners.sm, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    private func keyRow(_ p: RemoteProvider, keyInfo k: RemoteKeyInfo) -> some View {
        let allowedModels = p.accountModels[k.id] ?? []
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(k.rest != nil ? MagpieTheme.warn : (k.on ? MagpieTheme.ok : MagpieTheme.textMuted))
                    .frame(width: 7, height: 7)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text((k.name?.isEmpty == false) ? k.name! : k.masked)
                            .font(.system(size: 13.5, weight: .semibold, design: (k.name?.isEmpty == false) ? .default : .monospaced))
                            .foregroundColor(MagpieTheme.ink)
                        if k.active {
                            MagpieTag(text: "主用", tone: MagpieTheme.ok)
                        }
                    }
                    if k.name?.isEmpty == false {
                        Text(k.masked)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundColor(MagpieTheme.textMuted)
                    }
                }

                Spacer()

                MagpieToggle(
                    isOn: Binding(
                        get: { k.on },
                        set: { val in
                            Task { await store.toggleProviderKey(providerID: p.id, ref: k.id, on: val) }
                        }
                    )
                )
            }

            HStack(spacing: 6) {
                if let proto = k.protocol, !proto.isEmpty {
                    MagpieTag(text: proto, monospaced: true)
                }
                if let w = k.weight, w > 1 {
                    MagpieTag(text: "权重 \(w)")
                }
                if let plan = k.plan, !plan.isEmpty {
                    MagpieTag(text: plan)
                }
                if !allowedModels.isEmpty {
                    MagpieTag(text: "限 \(allowedModels.count) 模型")
                }
                if let bal = k.balance, let left = bal.left {
                    MagpieTag(text: String(format: "余 %.2f", left), monospaced: true)
                }
                if let sp = k.spend, let spent = sp.spent, let usd = sp.usd {
                    MagpieTag(text: String(format: "$%.2f / $%.2f", spent, usd), tone: sp.held == true ? MagpieTheme.err : MagpieTheme.textSecondary, monospaced: true)
                }
            }

            if let rest = k.rest {
                Text("冷却中：\(rest.why ?? "HTTP \(rest.status ?? 429)") \(rest.until ?? "")")
                    .font(.system(size: 11.5))
                    .foregroundColor(MagpieTheme.warn)
            }

            HStack(spacing: 8) {
                if !k.active && k.on {
                    Button("设为优先") {
                        Task { await store.useProviderKey(providerID: p.id, ref: k.id) }
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
                }

                Button("复制") {
                    Task {
                        if let raw = await store.revealProviderKey(id: p.id, account: k.id) {
                            store.copyToClipboard(raw, label: "Key")
                        }
                    }
                }
                .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))

                Button("编辑") {
                    keyRenameDraft = k.name ?? ""
                    keyReplaceDraft = ""
                    keyWeightDraft = "\(max(1, k.weight ?? 1))"
                    keyProtoDraft = k.protocol ?? ""
                    editingKeyTarget = k
                }
                .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))

                if !p.models.isEmpty {
                    Button("限模型") {
                        keyAllowedModelsDraft = Set(p.accountModels[k.id] ?? [])
                        keyModelsTarget = k
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))
                }

                Spacer()

                if p.keyList.count > 1 {
                    Button("移除") {
                        Task { await store.removeProviderKey(providerID: p.id, ref: k.id) }
                    }
                    .font(.system(size: 12))
                    .foregroundColor(MagpieTheme.err)
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Tab 3: Models & Per-Model Settings

    private func modelsSection(_ p: RemoteProvider) -> some View {
        let q = modelSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = p.models.filter { m in
            q.isEmpty || m.id.lowercased().contains(q) || m.name.lowercased().contains(q)
        }

        return VStack(alignment: .leading, spacing: 18) {
            MinimalSection(
                title: "模型暴露范围",
                trailingText: "\(p.exposedCount)/\(p.models.count)"
            ) {
                HStack(spacing: 8) {
                    Button("全选") {
                        draftNoModels = false
                        draftBestInFamily = false
                        draftChosen = Set(p.models.map(\.id))
                        modelsDirty = true
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))

                    Button("同系列最新") {
                        draftNoModels = false
                        draftBestInFamily = true
                        draftChosen = []
                        modelsDirty = true
                    }
                    .buttonStyle(MagpieButtonStyle(tone: draftBestInFamily ? .primary : .secondary, compact: true))

                    Button("全不选") {
                        draftNoModels = true
                        draftBestInFamily = false
                        draftChosen = []
                        modelsDirty = true
                    }
                    .buttonStyle(MagpieButtonStyle(tone: draftNoModels ? .primary : .subtle, compact: true))

                    Spacer()

                    if modelsDirty {
                        Button("保存选择") {
                            Task { await saveModelSelection(p) }
                        }
                        .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
                    }
                }

                if draftBestInFamily {
                    Text("当前模式：仅暴露每个模型家族的最新版本（Best in family）。勾选任意单个模型将转为手动挑选。")
                        .font(.system(size: 11.5))
                        .foregroundColor(MagpieTheme.textSecondary)
                } else if draftNoModels {
                    Text("当前模式：Select none（未向 Agent 暴露任何模型，仅保留余额与额度查询）。")
                        .font(.system(size: 11.5))
                        .foregroundColor(MagpieTheme.warn)
                }

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12.5))
                        .foregroundColor(MagpieTheme.textMuted)
                    TextField("搜索模型 ID 或名称…", text: $modelSearch)
                        .font(.system(size: 13, design: .monospaced))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                .padding(10)
                .background(MagpieTheme.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                if filtered.isEmpty {
                    Text(p.models.isEmpty ? "暂无模型，可点击「拉取模型」获取厂商列表" : "没有匹配的模型")
                        .font(.system(size: 12.5))
                        .foregroundColor(MagpieTheme.textMuted)
                } else {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, m in
                        if idx > 0 {
                            Rectangle().fill(MagpieTheme.hairline).frame(height: 1)
                        }
                        modelRow(p, model: m)
                    }
                }
            }
        }
    }

    private func modelRow(_ p: RemoteProvider, model m: RemoteProviderModel) -> some View {
        let isPicked: Bool = {
            if modelsDirty {
                if draftNoModels { return false }
                if draftBestInFamily { return m.best }
                return draftChosen.contains(m.id)
            }
            return m.on
        }()

        return HStack(spacing: 10) {
            Button {
                draftNoModels = false
                draftBestInFamily = false
                if !modelsDirty {
                    draftChosen = Set(p.models.filter(\.on).map(\.id))
                }
                if draftChosen.contains(m.id) {
                    draftChosen.remove(m.id)
                } else {
                    draftChosen.insert(m.id)
                }
                if draftChosen.isEmpty {
                    draftNoModels = true
                }
                modelsDirty = true
            } label: {
                Image(systemName: isPicked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 17))
                    .foregroundColor(isPicked ? MagpieTheme.ink : MagpieTheme.textMuted)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(m.name)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(isPicked ? MagpieTheme.ink : MagpieTheme.textSecondary)
                        .lineLimit(1)
                    if m.best { MagpieTag(text: "最新", tone: MagpieTheme.ok) }
                    if m.free || m.zero { MagpieTag(text: "免费", tone: MagpieTheme.ok) }
                    if m.images { MagpieTag(text: "图片") }
                }
                HStack(spacing: 6) {
                    if m.name != m.id {
                        Text(m.id)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(MagpieTheme.textMuted)
                            .lineLimit(1)
                    }
                    if let ctx = m.context, ctx > 0 {
                        Text("\(ctx / 1000)k ctx")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(MagpieTheme.textMuted)
                    }
                    if !m.efforts.isEmpty {
                        Text("推理: \(m.kept.isEmpty ? m.efforts.joined(separator: "/") : m.kept.joined(separator: "/"))")
                            .font(.system(size: 11))
                            .foregroundColor(MagpieTheme.textMuted)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Button("设置") {
                modelAliasDraft = (m.defaultName != nil && m.name != m.id) ? m.name : ""
                modelEffortsDraft = Set(m.kept.isEmpty ? m.efforts : m.kept)
                if m.imageSet {
                    modelImagesDraft = m.images ? 1 : 2
                } else {
                    modelImagesDraft = 0
                }
                editingModel = m
            }
            .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))
        }
        .padding(.vertical, 2)
    }

    // MARK: - Tab 4: Advanced Settings

    private func advancedSection(_ p: RemoteProvider) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            MinimalSection(title: "基础标识与接口地址") {
                MagpieInputField(label: "显示名称", placeholder: p.name, text: $nameDraft)
                MagpieInputField(label: "供应商 ID（修改会重命名路由前缀）", placeholder: p.id, text: $idDraft, monospaced: true)
                if p.account == nil {
                    MagpieInputField(label: "OpenAI Chat Base URL", placeholder: "https://.../v1", text: $chatDraft, monospaced: true, keyboardType: .URL)
                    MagpieInputField(label: "Anthropic Base URL", placeholder: "https://...", text: $anthropicDraft, monospaced: true, keyboardType: .URL)
                    MagpieInputField(label: "Responses Base URL", placeholder: "https://.../v1", text: $responsesDraft, monospaced: true, keyboardType: .URL)
                    MagpieInputField(label: "Gemini Base URL", placeholder: "https://.../v1beta", text: $geminiDraft, monospaced: true, keyboardType: .URL)
                    MagpieInputField(label: "Models URL（自定义模型列表地址）", placeholder: "可选", text: $modelsURLDraft, monospaced: true, keyboardType: .URL)
                    MagpieInputField(label: "Balance URL（余额查询地址）", placeholder: "可选", text: $balanceURLDraft, monospaced: true, keyboardType: .URL)
                    MagpieInputField(label: "Balance JSON Path", placeholder: "例如 data.balance", text: $balancePathDraft, monospaced: true)
                }
            }

            MinimalSection(title: "并发限流、倍率与兜底") {
                MagpieInputField(label: "备用模型 Fallback（逗号分隔 provider/model）", placeholder: "例如 deepseek/deepseek-chat", text: $fallbackDraft, monospaced: true)
                MagpieInputField(label: "计费倍率 PriceRate（如 0.8 或 1.5，空为按官方价）", placeholder: "1.0", text: $priceRateDraft, monospaced: true, keyboardType: .decimalPad)
                HStack(spacing: 10) {
                    MagpieInputField(label: "单号并发上限", placeholder: "不限", text: $maxConcurrencyDraft, monospaced: true, keyboardType: .numberPad)
                    MagpieInputField(label: "同时启用号数", placeholder: "不限", text: $maxAccountsDraft, monospaced: true, keyboardType: .numberPad)
                    MagpieInputField(label: "每分钟 RPM", placeholder: "不限", text: $maxRPMDraft, monospaced: true, keyboardType: .numberPad)
                }
                MagpieInputField(label: "专属代理（空为跟随全局，direct 为直连）", placeholder: "http://127.0.0.1:7890 或 direct", text: $proxyDraft, monospaced: true)
            }

            MinimalSection(title: "协议、TLS 与脱敏开关") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("计费类型标记")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(MagpieTheme.textSecondary)
                    HStack(spacing: 8) {
                        ForEach([("", "自动判断"), ("plan", "套餐订阅"), ("payg", "按量付费")], id: \.0) { item in
                            let selected = billingDraft == item.0
                            Button(item.1) { billingDraft = item.0 }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(selected ? MagpieTheme.onInk : MagpieTheme.ink)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(selected ? MagpieTheme.ink : MagpieTheme.canvas)
                                .clipShape(Capsule())
                                .buttonStyle(.plain)
                        }
                    }
                }

                if p.bothAuth {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Anthropic 鉴权头")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(MagpieTheme.textSecondary)
                        HStack(spacing: 8) {
                            ForEach([("", "双头默认"), ("x-api-key", "x-api-key"), ("bearer", "Bearer")], id: \.0) { item in
                                let selected = authHeaderDraft == item.0
                                Button(item.1) { authHeaderDraft = item.0 }
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(selected ? MagpieTheme.onInk : MagpieTheme.ink)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 6)
                                    .background(selected ? MagpieTheme.ink : MagpieTheme.canvas)
                                    .clipShape(Capsule())
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }

                toggleRow(title: "请求跳过隐私脱敏 (Unredacted)", subtitle: "适合本地模型或可信内网服务", isOn: $unredactedDraft)
                toggleRow(title: "计为免费供应商 (CountFree)", subtitle: "在 Free first / Cheapest 路由中按免费优先", isOn: $countFreeDraft)
                toggleRow(title: "忽略 429 / 额度退避冷却", isOn: $limitRestOffDraft)
                if p.takesPassErrors {
                    toggleRow(title: "错误原文透传给客户端 (PassErrors)", isOn: $passErrorsDraft)
                }
                if p.takesListOff {
                    toggleRow(title: "关闭自动拉取模型列表 (ListOff)", isOn: $listOffDraft)
                }
                if p.takesInsecureTLS {
                    toggleRow(title: "跳过 HTTPS 自签证书校验", isOn: $insecureTLSDraft)
                    toggleRow(title: "强制使用 HTTP/1.1", isOn: $http1Draft)
                }

                Button(isSavingAdvanced ? "保存中…" : "保存高级设置") {
                    Task { await saveAdvanced(p) }
                }
                .buttonStyle(MagpieButtonStyle(tone: .primary))
                .disabled(isSavingAdvanced)
            }
        }
    }

    // MARK: - Sub Sheets

    private func keyEditorSheet(_ keyItem: RemoteKeyInfo) -> some View {
        ZStack {
            MagpieTheme.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button("取消") { editingKeyTarget = nil }
                        .foregroundColor(MagpieTheme.textSecondary)
                    Spacer()
                    Text("编辑 Key · \(keyItem.masked)")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    Spacer()
                    Button("保存") {
                        guard let p = provider else { return }
                        Task {
                            let trimmedName = keyRenameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            if trimmedName != (keyItem.name ?? "") {
                                _ = await store.renameProviderKey(providerID: p.id, ref: keyItem.id, name: trimmedName)
                            }
                            let trimmedKey = keyReplaceDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmedKey.isEmpty {
                                _ = await store.replaceProviderKey(providerID: p.id, ref: keyItem.id, key: trimmedKey)
                            }
                            if let w = Int(keyWeightDraft), w != max(1, keyItem.weight ?? 1) {
                                _ = await store.setProviderKeyWeight(providerID: p.id, ref: keyItem.id, weight: max(1, w))
                            }
                            if keyProtoDraft != (keyItem.protocol ?? "") {
                                await store.setProviderKeyProtocol(providerID: p.id, ref: keyItem.id, protocol: keyProtoDraft)
                            }
                            editingKeyTarget = nil
                        }
                    }
                    .font(.system(size: 14, weight: .semibold))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(MagpieTheme.surface)
                .overlay(Rectangle().fill(MagpieTheme.hairline).frame(height: 1), alignment: .bottom)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        MinimalSection(title: "Key 属性") {
                            MagpieInputField(label: "备注名称", placeholder: "例如：团队额度 Key", text: $keyRenameDraft)
                            MagpieInputField(label: "替换为新密钥（留空则保留原密钥）", placeholder: "sk-...", text: $keyReplaceDraft, isSecure: true, monospaced: true)
                            MagpieInputField(label: "权重（Weight 策略下生效，1–100）", placeholder: "1", text: $keyWeightDraft, monospaced: true, keyboardType: .numberPad)
                            protocolPickerRow(selected: $keyProtoDraft, label: "限定协议")
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    private func keyModelsSheet(_ keyItem: RemoteKeyInfo) -> some View {
        ZStack {
            MagpieTheme.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button("取消") { keyModelsTarget = nil }
                        .foregroundColor(MagpieTheme.textSecondary)
                    Spacer()
                    Text("限定模型 · \(keyItem.name ?? keyItem.masked)")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Button("保存") {
                        guard let p = provider else { return }
                        Task {
                            let ok = await store.updateAccountModels(
                                providerID: p.id,
                                account: keyItem.id,
                                allow: Array(keyAllowedModelsDraft).sorted()
                            )
                            if ok { keyModelsTarget = nil }
                        }
                    }
                    .font(.system(size: 14, weight: .semibold))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(MagpieTheme.surface)
                .overlay(Rectangle().fill(MagpieTheme.hairline).frame(height: 1), alignment: .bottom)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        MinimalSection(title: "勾选该 Key 独占服务的模型（全不选表示服务全部模型）") {
                            HStack {
                                Button("清空限制（全部模型）") {
                                    keyAllowedModelsDraft.removeAll()
                                }
                                .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))
                                Spacer()
                                Text("已选 \(keyAllowedModelsDraft.count) 个")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(MagpieTheme.textMuted)
                            }
                            if let p = provider {
                                ForEach(p.models) { m in
                                    let on = keyAllowedModelsDraft.contains(m.id)
                                    Button {
                                        if on {
                                            keyAllowedModelsDraft.remove(m.id)
                                        } else {
                                            keyAllowedModelsDraft.insert(m.id)
                                        }
                                    } label: {
                                        HStack {
                                            Image(systemName: on ? "checkmark.square.fill" : "square")
                                                .foregroundColor(on ? MagpieTheme.ink : MagpieTheme.textMuted)
                                            Text(m.id)
                                                .font(.system(size: 12.5, design: .monospaced))
                                                .foregroundColor(MagpieTheme.ink)
                                                .lineLimit(1)
                                            Spacer()
                                        }
                                        .padding(.vertical, 3)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    private func modelEditorSheet(_ model: RemoteProviderModel) -> some View {
        ZStack {
            MagpieTheme.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button("取消") { editingModel = nil }
                        .foregroundColor(MagpieTheme.textSecondary)
                    Spacer()
                    Text(model.id)
                        .font(.system(size: 13.5, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                    Spacer()
                    Button("保存") {
                        guard let p = provider else { return }
                        Task {
                            _ = await store.updateProviderModelName(
                                providerID: p.id,
                                modelID: model.id,
                                name: modelAliasDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            )
                            if !model.efforts.isEmpty || !modelEffortsDraft.isEmpty {
                                let ordered = allEffortLevels.filter { modelEffortsDraft.contains($0) }
                                _ = await store.updateProviderModelEfforts(providerID: p.id, modelID: model.id, efforts: ordered)
                            }
                            let imgVal: Bool? = modelImagesDraft == 0 ? nil : (modelImagesDraft == 1)
                            _ = await store.updateProviderModelImages(providerID: p.id, modelID: model.id, images: imgVal)
                            editingModel = nil
                        }
                    }
                    .font(.system(size: 14, weight: .semibold))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(MagpieTheme.surface)
                .overlay(Rectangle().fill(MagpieTheme.hairline).frame(height: 1), alignment: .bottom)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        MinimalSection(title: "模型显示与能力") {
                            MagpieInputField(label: "自定义显示名称（留空恢复厂商原名）", placeholder: model.defaultName ?? model.id, text: $modelAliasDraft)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("保留推理档位 (Efforts)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(MagpieTheme.textSecondary)
                                HStack(spacing: 8) {
                                    ForEach(allEffortLevels, id: \.self) { lvl in
                                        let on = modelEffortsDraft.contains(lvl)
                                        Button(lvl) {
                                            if on { modelEffortsDraft.remove(lvl) } else { modelEffortsDraft.insert(lvl) }
                                        }
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundColor(on ? MagpieTheme.onInk : MagpieTheme.ink)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(on ? MagpieTheme.ink : MagpieTheme.canvas)
                                        .clipShape(Capsule())
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("视觉输入支持 (Images)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(MagpieTheme.textSecondary)
                                HStack(spacing: 8) {
                                    ForEach([(0, "跟随厂商"), (1, "支持图片"), (2, "不支持")], id: \.0) { item in
                                        let selected = modelImagesDraft == item.0
                                        Button(item.1) { modelImagesDraft = item.0 }
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(selected ? MagpieTheme.onInk : MagpieTheme.ink)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(selected ? MagpieTheme.ink : MagpieTheme.canvas)
                                            .clipShape(Capsule())
                                            .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    // MARK: - Helpers & Persistence

    private func syncDrafts(from p: RemoteProvider) {
        if formInitializedForID != p.id {
            formInitializedForID = p.id
            nameDraft = p.name
            idDraft = p.id
            chatDraft = p.chat
            anthropicDraft = p.anthropic
            responsesDraft = p.responses
            geminiDraft = p.gemini
            decideDraft = p.decide
            modelsURLDraft = p.modelsURL
            balanceURLDraft = p.balanceURL
            balancePathDraft = p.balancePath
            proxyDraft = p.proxy
            fallbackDraft = p.fallback.joined(separator: ", ")
            billingDraft = p.billing
            priceRateDraft = p.priceRate.map { String($0) } ?? ""
            maxConcurrencyDraft = p.maxConcurrency.map { String($0) } ?? ""
            maxAccountsDraft = p.maxAccounts.map { String($0) } ?? ""
            maxRPMDraft = p.maxRPM.map { String($0) } ?? ""
            authHeaderDraft = p.authHeader
            unredactedDraft = p.unredacted
            countFreeDraft = p.countFree
            insecureTLSDraft = p.insecureTLS
            http1Draft = p.http1
            limitRestOffDraft = p.limitRestOff
            passErrorsDraft = p.passErrors
            listOffDraft = p.listOff
            syncModelDrafts(from: p)
        }
    }

    private func syncModelDrafts(from p: RemoteProvider) {
        draftChosen = Set(p.chosen)
        draftNoModels = p.noModels
        draftBestInFamily = p.bestInFamily
        modelsDirty = false
    }

    private func buildPreservedPayload(from p: RemoteProvider) -> [String: Any] {
        var payload: [String: Any] = [
            "id": idDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? p.id : idDraft.trimmingCharacters(in: .whitespacesAndNewlines),
            "from": p.id,
            "name": nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? p.name : nameDraft.trimmingCharacters(in: .whitespacesAndNewlines),
            "preset": p.preset,
            "baseAPI": p.baseAPI,
            "routing": p.routing,
            "affinity": p.affinity,
            "sink": p.sink,
            "unlisted": p.unlisted,
            "noModels": draftNoModels,
            "bestInFamily": draftBestInFamily,
            "models": (draftNoModels || draftBestInFamily) ? [] : (modelsDirty ? Array(draftChosen).sorted() : p.chosen)
        ]
        if p.account == nil {
            payload["chat"] = chatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            payload["anthropic"] = anthropicDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            payload["responses"] = responsesDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            payload["gemini"] = geminiDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            payload["decide"] = decideDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            payload["modelsURL"] = modelsURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            payload["balanceURL"] = balanceURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            payload["balancePath"] = balancePathDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return payload
    }

    private func saveModelSelection(_ p: RemoteProvider) async {
        let payload = buildPreservedPayload(from: p)
        let ok = await store.saveProviderPayload(payload, toast: "已保存模型暴露设置")
        if ok {
            modelsDirty = false
        }
    }

    private func saveAdvanced(_ p: RemoteProvider) async {
        isSavingAdvanced = true
        defer { isSavingAdvanced = false }
        var payload = buildPreservedPayload(from: p)
        payload["proxy"] = proxyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let fb = fallbackDraft
            .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "\n" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        payload["fallback"] = fb
        payload["billing"] = billingDraft
        payload["unredacted"] = unredactedDraft
        payload["countFree"] = countFreeDraft
        payload["limitRestOff"] = limitRestOffDraft
        if p.takesPassErrors { payload["passErrors"] = passErrorsDraft }
        if p.takesListOff { payload["listOff"] = listOffDraft }
        if p.takesInsecureTLS {
            payload["insecureTLS"] = insecureTLSDraft
            payload["http1"] = http1Draft
        }
        if p.bothAuth {
            payload["authHeader"] = authHeaderDraft
        }
        if let rate = Double(priceRateDraft.trimmingCharacters(in: .whitespacesAndNewlines)), rate > 0 {
            payload["priceRate"] = rate
        } else {
            payload["priceRate"] = NSNull()
        }
        if let cc = Int(maxConcurrencyDraft.trimmingCharacters(in: .whitespacesAndNewlines)) {
            payload["maxConcurrency"] = cc
        } else {
            payload["maxConcurrency"] = NSNull()
        }
        let maTrimmed = maxAccountsDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if maTrimmed.isEmpty {
            payload["maxAccounts"] = NSNull()
        } else if let ma = Int(maTrimmed), (0...1000).contains(ma) {
            payload["maxAccounts"] = ma
        } else {
            store.showToast("同时启用号数须为 0–1000 的整数（留空为不限）")
            return
        }
        if let rpm = Int(maxRPMDraft.trimmingCharacters(in: .whitespacesAndNewlines)) {
            payload["maxRPM"] = rpm
        } else {
            payload["maxRPM"] = NSNull()
        }

        _ = await store.saveProviderPayload(payload, toast: "已保存供应商高级设置")
    }

    private func toggleRow(title: String, subtitle: String? = nil, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(MagpieTheme.ink)
                if let sub = subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: 11.5))
                        .foregroundColor(MagpieTheme.textMuted)
                }
            }
            Spacer()
            MagpieToggle(isOn: isOn)
        }
    }

    private func protocolPickerRow(selected: Binding<String>, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(MagpieTheme.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(protocolOptions, id: \.id) { opt in
                        let active = selected.wrappedValue == opt.id
                        Button(opt.title) { selected.wrappedValue = opt.id }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(active ? MagpieTheme.onInk : MagpieTheme.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(active ? MagpieTheme.ink : MagpieTheme.canvas)
                            .clipShape(Capsule())
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
