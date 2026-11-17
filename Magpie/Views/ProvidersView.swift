import SwiftUI

struct ProvidersView: View {
    @ObservedObject var store: GatewayStore
    @State private var sectionTab: ProviderSectionTab = .providers
    @State private var searchText = ""
    @State private var presentingAddSheet = false
    @State private var presentingPriceSheet = false
    @State private var presentingGroupExtras = false
    @State private var testingProviderID: String?
    @State private var testResultsByID: [String: String] = [:]
    @State private var pendingDelete: RemoteProvider?
    @State private var selectedProvider: RemoteProvider?
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
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sectionTab == .providers ? "供应商号池" : "跨供应商路由组")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(MagpieTheme.ink)
                        Text(subtitleText)
                            .font(.system(size: 13))
                            .foregroundColor(MagpieTheme.textSecondary)
                    }
                    Spacer()
                    if sectionTab == .providers {
                        HStack(spacing: 8) {
                            Button("定价") {
                                presentingPriceSheet = true
                            }
                            .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
                            .disabled(store.activeServer == nil)

                            Button("新增") {
                                presentingAddSheet = true
                            }
                            .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
                            .disabled(store.activeServer == nil)
                        }
                    } else {
                        HStack(spacing: 8) {
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
                            .font(.system(size: 13))
                            .foregroundColor(MagpieTheme.textSecondary)
                    }
                } else if sectionTab == .providers {
                    searchField
                    if filteredProviders.isEmpty {
                        MinimalSection {
                            Text(store.providers.isEmpty ? "服务端暂无已配置的供应商" : "没有匹配的供应商或模型")
                                .font(.system(size: 13))
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
                                .font(.system(size: 13))
                                .foregroundColor(MagpieTheme.textSecondary)
                        }
                    } else {
                        ForEach(store.groups) { group in
                            groupCard(group)
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 100)
        }
        .refreshable {
            await store.refreshProviders()
            await store.refreshGroups()
        }
        .sheet(isPresented: $presentingAddSheet) {
            AddProviderSheet(store: store)
        }
        .sheet(isPresented: $presentingPriceSheet) {
            ModelPriceEditorView(store: store)
        }
        .sheet(isPresented: $presentingGroupExtras) {
            GroupExtrasSheet(store: store)
        }
        .sheet(item: $selectedProvider) { provider in
            ProviderDetailSheet(store: store, providerID: provider.id)
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
        HStack(spacing: 8) {
            ForEach(ProviderSectionTab.allCases, id: \.self) { tab in
                let selected = sectionTab == tab
                Button(tab.rawValue) {
                    sectionTab = tab
                }
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(selected ? MagpieTheme.surface : MagpieTheme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(selected ? MagpieTheme.ink : MagpieTheme.surface)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(MagpieTheme.hairline, lineWidth: selected ? 0 : 1))
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundColor(MagpieTheme.textMuted)
            TextField("搜索供应商或模型名…", text: $searchText)
                .font(.system(size: 13.5, design: .monospaced))
                .foregroundColor(MagpieTheme.ink)
                .autocapitalization(.none)
                .disableAutocorrection(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(MagpieTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(MagpieTheme.hairline, lineWidth: 1)
        )
    }

    private func providerCard(_ provider: RemoteProvider) -> some View {
        let isEnabled = !provider.off
        let statusKind: ConnectionStatusKind = provider.off ? .untested : (provider.ready ? .connected : .failed)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                MagpieStatusLight(kind: statusKind)
                Text(provider.name)
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundColor(MagpieTheme.ink)
                Spacer()
                if store.providers.count > 1 {
                    Button("↑") {
                        Task { await store.moveProvider(provider, offset: -1) }
                    }
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundColor(MagpieTheme.textSecondary)
                    .buttonStyle(.plain)

                    Button("↓") {
                        Task { await store.moveProvider(provider, offset: 1) }
                    }
                    .font(.system(size: 11.5, design: .monospaced))
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
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(MagpieTheme.textSecondary)
                .lineLimit(1)

            HStack(spacing: 6) {
                MagpieTag(text: "\(provider.exposed)/\(provider.models.count) 模型")
                if !provider.routing.isEmpty {
                    MagpieTag(text: provider.routing)
                }
                if !provider.keyList.isEmpty {
                    let onKeys = provider.keyList.filter(\.on).count
                    MagpieTag(text: "\(onKeys)/\(provider.keyList.count) Key")
                } else if let masked = provider.key?.masked, !masked.isEmpty {
                    MagpieTag(text: masked, monospaced: true)
                } else if let user = provider.account?.user, !user.isEmpty {
                    MagpieTag(text: user)
                }
            }

            if let err = provider.listError, !err.isEmpty {
                Text(err)
                    .font(.system(size: 11.5))
                    .foregroundColor(MagpieTheme.err)
            }

            if let testOutput = testResultsByID[provider.id] {
                Text(testOutput)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundColor(MagpieTheme.textSecondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MagpieTheme.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Rectangle().fill(MagpieTheme.hairline).frame(height: 1)

            HStack(spacing: 8) {
                Button("管理") { selectedProvider = provider }
                    .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
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

                Spacer()

                Button("删除") {
                    pendingDelete = provider
                }
                .font(.system(size: 12))
                .foregroundColor(MagpieTheme.textMuted)
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(MagpieTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MagpieTheme.hairline, lineWidth: 1)
        )
    }

    private func groupCard(_ group: RemoteRoutingGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                MagpieStatusLight(kind: group.isOff ? .untested : (group.ready ? .connected : .failed))
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundColor(MagpieTheme.ink)
                    Text(group.ref)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(MagpieTheme.textMuted)
                }
                Spacer()
                if !group.auto && store.groups.filter({ !$0.auto }).count > 1 {
                    Button("↑") {
                        Task { await store.moveGroup(group, offset: -1) }
                    }
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundColor(MagpieTheme.textSecondary)
                    .buttonStyle(.plain)

                    Button("↓") {
                        Task { await store.moveGroup(group, offset: 1) }
                    }
                    .font(.system(size: 11.5, design: .monospaced))
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
                    .font(.system(size: 12))
                    .foregroundColor(MagpieTheme.textSecondary)
            }

            HStack(spacing: 6) {
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
                            .font(.system(size: 12, design: .monospaced))
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
        .padding(18)
        .background(MagpieTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
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
                        Text("服务端未返回内置模板").font(.caption).foregroundColor(.secondary)
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
    @Environment(\.dismiss) private var dismiss

    enum CreationMode: String, CaseIterable {
        case custom = "自定义协议地址"
        case preset = "从官方预设选择"
    }

    @State private var mode: CreationMode = .custom
    @State private var selectedPresetID: String = ""
    @State private var name = ""
    @State private var apiKey = ""
    @State private var chatURL = ""
    @State private var anthropicURL = ""
    @State private var responsesURL = ""
    @State private var geminiURL = ""
    @State private var isSaving = false
    @State private var errorMsg: String?

    var body: some View {
        ZStack {
            MagpieTheme.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button("取消") { dismiss() }
                        .font(.system(size: 14))
                        .foregroundColor(MagpieTheme.textSecondary)
                    Spacer()
                    Text("新增远程供应商")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(MagpieTheme.ink)
                    Spacer()
                    Button(isSaving ? "保存中…" : "保存") { commit() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(MagpieTheme.ink)
                        .disabled(isSaving)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
                .background(MagpieTheme.surface)
                .overlay(Rectangle().fill(MagpieTheme.hairline).frame(height: 1), alignment: .bottom)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        if !store.presets.isEmpty {
                            Picker("添加方式", selection: $mode) {
                                ForEach(CreationMode.allCases, id: \.self) { m in
                                    Text(m.rawValue).tag(m)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        if mode == .preset, !store.presets.isEmpty {
                            MinimalSection(title: "选择厂商预设", trailingText: "\(store.presets.count) 个预设") {
                                ForEach(store.presets.prefix(25)) { preset in
                                    Button {
                                        selectedPresetID = preset.id
                                        name = preset.displayTitle
                                        chatURL = preset.chat ?? ""
                                        anthropicURL = preset.anthropic ?? ""
                                        responsesURL = preset.responses ?? ""
                                    } label: {
                                        HStack {
                                            Text(preset.displayTitle)
                                                .font(.system(size: 13.5, weight: .medium))
                                                .foregroundColor(MagpieTheme.ink)
                                            Spacer()
                                            if selectedPresetID == preset.id {
                                                MagpieTag(text: "已选", tone: MagpieTheme.ok)
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
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
                    .padding(22)
                }
            }
        }
        .preferredColorScheme(.light)
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
                    region: preset.regions.first,
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
