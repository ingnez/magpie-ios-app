import SwiftUI

struct AgentsView: View {
    @ObservedObject var store: GatewayStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedAgent: RemoteAgent?
    @State private var profileName = ""
    @State private var renamingProfile: RemoteProfile?
    @State private var renamedProfile = ""
    @State private var deletingProfile: RemoteProfile?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("管理服务器上接入 Magpie 的客户端及其模型方案。")
                        .font(.footnote).foregroundColor(MagpieTheme.textSecondary)
                    MinimalSection(title: "Agents", trailingText: "\(store.remoteState?.agents.count ?? 0) 个") {
                        Button("重新扫描服务器") { Task { await store.rescanAgents() } }
                        ForEach(store.remoteState?.agents ?? []) { agent in
                            Button { selectedAgent = agent } label: {
                                HStack {
                                    MagpieStatusLight(kind: agent.wired ? .connected : .untested)
                                    VStack(alignment: .leading) {
                                        Text(agent.name).font(.headline)
                                        Text(agent.primaryModelSummary ?? "尚未指定模型").font(.caption)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }.foregroundColor(MagpieTheme.ink).padding(.vertical, 8)
                            }.buttonStyle(.plain)
                        }
                    }
                    MinimalSection(title: "Profiles · 方案") {
                        TextField("新方案名称", text: $profileName)
                        Button("保存当前配置为方案") {
                            Task { if await store.saveProfile(name: profileName) { profileName = "" } }
                        }.disabled(profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        ForEach(store.remoteState?.profiles ?? []) { profile in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(profile.name + (profile.inUse ? " · 当前" : "")).font(.headline)
                                Text(profile.summary).font(.caption).foregroundColor(MagpieTheme.textSecondary)
                                HStack {
                                    Button("应用") { Task { await store.useProfile(name: profile.name) } }
                                    Button("重命名") { renamedProfile = profile.name; renamingProfile = profile }
                                    Spacer()
                                    Button("删除", role: .destructive) { deletingProfile = profile }
                                }
                            }.padding(.vertical, 6)
                        }
                    }
                }.padding(20)
            }
            .background(MagpieTheme.canvas)
            .navigationTitle("Agents 与方案")
            .toolbar { Button("关闭") { dismiss() } }
            .refreshable { await store.refreshStateOnly() }
        }
        .navigationViewStyle(.stack)
        .task { await store.refreshStateOnly() }
        .sheet(item: $selectedAgent) { agent in AgentDetailView(store: store, agentID: agent.id) }
        .sheet(item: $renamingProfile) { profile in
            NavigationView {
                Form {
                    TextField("方案名称", text: $renamedProfile)
                    Button("保存") {
                        Task { if await store.renameProfile(from: profile.name, to: renamedProfile) { renamingProfile = nil } }
                    }.disabled(renamedProfile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.navigationTitle("重命名方案").toolbar { Button("取消") { renamingProfile = nil } }
            }
        }
        .alert("删除方案？", isPresented: Binding(get: { deletingProfile != nil }, set: { if !$0 { deletingProfile = nil } })) {
            Button("删除", role: .destructive) {
                if let p = deletingProfile { Task { await store.deleteProfile(name: p.name) } }
                deletingProfile = nil
            }
            Button("取消", role: .cancel) { deletingProfile = nil }
        }
    }
}

private struct AgentDetailView: View {
    @ObservedObject var store: GatewayStore
    let agentID: String
    @Environment(\.dismiss) private var dismiss
    @State private var pendingAction: String?
    @State private var showingModels = false
    @State private var busy = false
    private var agent: RemoteAgent? { store.remoteState?.agents.first { $0.id == agentID } }

    var body: some View {
        NavigationView {
            Form {
                if let agent = agent {
                    Section(header: Text("服务器上的客户端")) {
                        Text(agent.path).font(.caption.monospaced()).textSelection(.enabled)
                        Text(agent.wired ? "已由 Magpie 管理" : "尚未接入")
                        if agent.cliMissing { Text("服务器未找到对应 CLI").foregroundColor(MagpieTheme.warn) }
                        if let drift = agent.drift {
                            Text(drift.detail).foregroundColor(MagpieTheme.warn)
                            Button("重新应用 Magpie 配置") { pendingAction = "reapply" }
                            Button("保留客户端当前配置") { pendingAction = "keep" }
                        }
                        Button(agent.wired ? "断开接入" : "接入 Magpie") {
                            pendingAction = agent.wired ? "disconnect" : "connect"
                        }
                    }
                    ForEach(agent.fields) { field in
                        Section(header: Text(field.label)) {
                            if field.options.isEmpty {
                                Text(field.value.isEmpty ? "未设置" : field.value).font(.caption)
                            } else {
                                Picker(field.label, selection: Binding(get: { field.value }, set: { value in
                                    Task { _ = await store.setAgentField(agentID: agentID, fieldKey: field.key, value: value) }
                                })) {
                                    if !field.options.contains(where: { $0.value == field.value }) {
                                        Text(field.value.isEmpty ? "默认" : field.value).tag(field.value)
                                    }
                                    ForEach(field.options) { option in Text(option.displayName).tag(option.value) }
                                }
                                if let option = field.options.first(where: { $0.value == field.value }), let fastFor = option.fastFor, let ref = option.ref {
                                    Toggle("Fast", isOn: Binding(get: { option.fast }, set: { on in
                                        Task { _ = await store.toggleAgentFast(agentID: fastFor, ref: ref, fast: on, ultra: false) }
                                    }))
                                    if option.ultraOk {
                                        Toggle("Ultrafast", isOn: Binding(get: { option.ultra }, set: { on in
                                            Task { _ = await store.toggleAgentFast(agentID: fastFor, ref: ref, fast: on || option.fast, ultra: on) }
                                        }))
                                    }
                                }
                            }
                        }
                    }
                    Section {
                        Button("管理客户端可见模型") { showingModels = true }
                        if let telemetry = agent.telemetry {
                            Toggle("关闭遥测", isOn: Binding(get: { telemetry.off }, set: { off in
                                Task { await store.setAgentTelemetry(agent, off: off) }
                            }))
                        }
                        if agent.appRestart != nil { Button("重启服务器上的桌面客户端") { pendingAction = "restart" } }
                    }
                } else { Text("此客户端已不存在") }
            }
            .disabled(busy)
            .navigationTitle(agent?.name ?? agentID)
            .toolbar { Button("关闭") { dismiss() } }
        }.navigationViewStyle(.stack)
        .sheet(isPresented: $showingModels) { AgentModelsView(store: store, agentID: agentID) }
        .confirmationDialog("此操作会修改服务器上的客户端配置", isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }), titleVisibility: .visible) {
            Button("执行") {
                guard let agent = agent, let action = pendingAction else { return }
                pendingAction = nil
                busy = true
                Task {
                    if action == "restart" { await store.restartAgentApp(agent) }
                    else { await store.performAgentAction(agent: agent, action: action) }
                    busy = false
                }
            }
            Button("取消", role: .cancel) { pendingAction = nil }
        }
    }
}

private struct AgentModelsView: View {
    @ObservedObject var store: GatewayStore
    let agentID: String
    @Environment(\.dismiss) private var dismiss
    @State private var response: RemoteAgentModelsResponse?
    @State private var hidden: Set<String> = []
    @State private var only = false
    @State private var ownHidden = false
    @State private var error: String?
    @State private var loading = true
    @State private var search = ""
    var body: some View {
        NavigationView {
            Form {
                if let error = error { Text(error).foregroundColor(StatusPalette.err) }
                if loading { ProgressView() }
                if let response = response {
                    Toggle("仅显示指定模型", isOn: $only)
                    Toggle("隐藏客户端自带模型", isOn: $ownHidden)
                    TextField("搜索模型", text: $search)
                    ForEach(response.models.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.id.localizedCaseInsensitiveContains(search) }) { model in
                        Toggle(model.name, isOn: Binding(get: { !hidden.contains(model.id) }, set: { on in
                            if on { hidden.remove(model.id) } else { hidden.insert(model.id) }
                        }))
                    }
                }
            }
            .navigationTitle("可见模型")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        loading = true
                        Task {
                            let shown = response?.models.filter { !hidden.contains($0.id) }.map(\.id) ?? []
                            switch await store.updateAgentModels(agentID: agentID, hidden: Array(hidden), shown: shown, only: only, ownHidden: ownHidden) {
                            case .success: dismiss()
                            case .failure(let err): error = err.localizedDescription
                            }
                            loading = false
                        }
                    }.disabled(loading || response == nil)
                }
            }
        }.navigationViewStyle(.stack)
        .task {
            switch await store.fetchAgentModels(agentID: agentID) {
            case .success(let res):
                response = res; hidden = Set(res.models.filter(\.hidden).map(\.id)); only = res.only; ownHidden = res.ownHidden
            case .failure(let err): error = err.localizedDescription
            }
            loading = false
        }
    }
}
