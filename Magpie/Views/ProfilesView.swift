import SwiftUI

struct ProfilesView: View {
    @ObservedObject var store: GatewayStore
    @Binding var presentingNewEditor: Bool

    @State private var editingProfile: ProxyProfile?
    @State private var profilePendingDelete: ProxyProfile?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("反代配置")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(MagpieTheme.ink)
                        Text(store.profiles.isEmpty ? "尚未添加上游节点" : "共 \(store.profiles.count) 个节点 · 点击即可切换")
                            .font(.system(size: 13))
                            .foregroundColor(MagpieTheme.textSecondary)
                    }
                    Spacer()
                    Button("新建") {
                        presentingNewEditor = true
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
                }

                if store.profiles.isEmpty {
                    emptyStateBlock
                } else {
                    VStack(spacing: 12) {
                        ForEach(store.profiles) { profile in
                            profileRow(profile)
                        }
                    }
                }

                if store.activeProfile != nil {
                    Button("切回本地回环模式") {
                        store.deactivateToLocalLoopback()
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 100)
        }
        .sheet(isPresented: $presentingNewEditor) {
            ProfileEditorSheet(store: store, existing: nil)
        }
        .sheet(item: $editingProfile) { profile in
            ProfileEditorSheet(store: store, existing: profile)
        }
        .alert(
            "删除配置？",
            isPresented: Binding(
                get: { profilePendingDelete != nil },
                set: { if !$0 { profilePendingDelete = nil } }
            ),
            presenting: profilePendingDelete
        ) { target in
            Button("删除", role: .destructive) {
                store.deleteProfile(target)
                profilePendingDelete = nil
            }
            Button("取消", role: .cancel) {
                profilePendingDelete = nil
            }
        } message: { target in
            Text("将移除「\(target.name)」。")
        }
    }

    private var emptyStateBlock: some View {
        MinimalSection {
            Text("暂无上游服务器")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(MagpieTheme.ink)
            Text("添加 OpenAI、Anthropic、Gemini 或自建反代地址后，所有客户端均可统一通过 127.0.0.1:3425 接入。")
                .font(.system(size: 13))
                .foregroundColor(MagpieTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("添加第一套配置") {
                presentingNewEditor = true
            }
            .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
            .padding(.top, 2)
        }
    }

    private func profileRow(_ profile: ProxyProfile) -> some View {
        let isActive = store.activeProfileID == profile.id
        let health = store.healthByProfile[profile.id] ?? .untested

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                MagpieStatusLight(kind: health.kind)
                Text(profile.name)
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundColor(MagpieTheme.ink)
                if isActive {
                    MagpieTag(text: "当前使用", tone: MagpieTheme.ink)
                }
                Spacer()
                if let ms = health.latencyMs {
                    Text("\(ms) ms")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(MagpieTheme.textMuted)
                }
            }

            Text(profile.baseURL)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundColor(MagpieTheme.textSecondary)
                .lineLimit(1)

            HStack(spacing: 6) {
                MagpieTag(text: profile.targetProtocol.displayName)
                MagpieTag(text: profile.defaultModel, monospaced: true)
                MagpieTag(text: profile.maskedKeyPreview, monospaced: true)
            }

            if health.kind == .failed {
                Text(health.message)
                    .font(.system(size: 12))
                    .foregroundColor(MagpieTheme.err)
            }

            Rectangle()
                .fill(MagpieTheme.hairline)
                .frame(height: 1)

            HStack(spacing: 8) {
                if !isActive {
                    Button("启用") {
                        store.activateProfile(profile)
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
                }

                Button(health.kind == .checking ? "测速中…" : "测速") {
                    Task { await store.probeConnection(for: profile) }
                }
                .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
                .disabled(health.kind == .checking)

                Button("编辑") {
                    editingProfile = profile
                }
                .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))

                Spacer()

                Button("删除") {
                    profilePendingDelete = profile
                }
                .font(.system(size: 12.5))
                .foregroundColor(MagpieTheme.textMuted)
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(MagpieTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isActive ? MagpieTheme.ink : MagpieTheme.hairline, lineWidth: isActive ? 1.2 : 1)
        )
    }
}

struct ProfileEditorSheet: View {
    @ObservedObject var store: GatewayStore
    let existing: ProxyProfile?
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var rawBaseURL: String = ""
    @State private var apiKey: String = ""
    @State private var targetProtocol: MagpieProtocol = .openAIChat
    @State private var defaultModel: String = ""
    @State private var activateOnSave: Bool = true

    @State private var saveError: String?
    @State private var probeResult: ConnectionHealth?
    @State private var isProbing: Bool = false

    private var urlValidation: URLValidationResult {
        URLValidator.validateAndNormalize(rawBaseURL)
    }

    private var urlErrorText: String? {
        rawBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : urlValidation.errorReason
    }

    private var urlHelperText: String? {
        guard case .valid(let normalized) = urlValidation else { return nil }
        return normalized
    }

    var body: some View {
        ZStack {
            MagpieTheme.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button("取消") { dismiss() }
                        .font(.system(size: 14))
                        .foregroundColor(MagpieTheme.textSecondary)
                    Spacer()
                    Text(existing == nil ? "新建配置" : "编辑配置")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(MagpieTheme.ink)
                    Spacer()
                    Button("保存") { commitSave() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(MagpieTheme.ink)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
                .background(MagpieTheme.surface)
                .overlay(Rectangle().fill(MagpieTheme.hairline).frame(height: 1), alignment: .bottom)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        if existing == nil {
                            templateBar
                        }

                        MinimalSection {
                            MagpieInputField(
                                label: "名称",
                                placeholder: "例如：主力 Claude / 本地节点",
                                text: $name
                            )

                            MagpieInputField(
                                label: "服务器地址",
                                placeholder: "https://api.example.com",
                                text: $rawBaseURL,
                                monospaced: true,
                                keyboardType: .URL,
                                errorText: urlErrorText,
                                helperText: urlHelperText
                            )

                            MagpieInputField(
                                label: "API Key",
                                placeholder: "sk-...",
                                text: $apiKey,
                                isSecure: true,
                                monospaced: true
                            )

                            protocolSelector

                            MagpieInputField(
                                label: "默认模型",
                                placeholder: targetProtocol.suggestedDefaultModel,
                                text: $defaultModel,
                                monospaced: true
                            )

                            HStack {
                                Text("保存后设为当前启用")
                                    .font(.system(size: 13))
                                    .foregroundColor(MagpieTheme.ink)
                                Spacer()
                                MagpieToggle(isOn: $activateOnSave)
                            }
                        }

                        if let probeResult = probeResult {
                            MinimalSection {
                                HStack(spacing: 8) {
                                    MagpieStatusLight(kind: probeResult.kind)
                                    Text(probeResult.message)
                                        .font(.system(size: 12.5))
                                        .foregroundColor(probeResult.kind == .connected ? MagpieTheme.ok : MagpieTheme.err)
                                }
                            }
                        }

                        if let saveError = saveError {
                            MagpieErrorBanner(title: "无法保存", message: saveError)
                        }

                        HStack(spacing: 10) {
                            Button(isProbing ? "测试中…" : "测试连接") {
                                runProbe()
                            }
                            .buttonStyle(MagpieButtonStyle(tone: .secondary))
                            .disabled(isProbing)

                            Button("保存配置") {
                                commitSave()
                            }
                            .buttonStyle(MagpieButtonStyle(tone: .primary))
                        }
                    }
                    .padding(22)
                }
            }
        }
        .preferredColorScheme(.light)
        .onAppear {
            if let existing = existing {
                name = existing.name
                rawBaseURL = existing.baseURL
                apiKey = existing.apiKey
                targetProtocol = existing.targetProtocol
                defaultModel = existing.defaultModel
                activateOnSave = (store.activeProfileID == existing.id)
            } else {
                defaultModel = targetProtocol.suggestedDefaultModel
            }
        }
    }

    private var templateBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                templateChip("OpenAI", url: "https://api.openai.com", proto: .openAIChat, model: "gpt-4o")
                templateChip("Anthropic", url: "https://api.anthropic.com", proto: .anthropicMessages, model: "claude-sonnet-4-5")
                templateChip("Gemini", url: "https://generativelanguage.googleapis.com", proto: .geminiV1Beta, model: "gemini-2.5-pro")
                templateChip("本地节点", url: "http://127.0.0.1:3000", proto: .openAIChat, model: "claude-sonnet-4-5")
            }
        }
    }

    private func templateChip(_ title: String, url: String, proto: MagpieProtocol, model: String) -> some View {
        Button(title) {
            name = title
            rawBaseURL = url
            targetProtocol = proto
            defaultModel = model
            saveError = nil
            probeResult = nil
        }
        .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
    }

    private var protocolSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("上游协议")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(MagpieTheme.textSecondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(MagpieProtocol.allCases) { proto in
                    let selected = targetProtocol == proto
                    Button {
                        targetProtocol = proto
                        if defaultModel.isEmpty || MagpieProtocol.allCases.map(\.suggestedDefaultModel).contains(defaultModel) {
                            defaultModel = proto.suggestedDefaultModel
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(proto.displayName)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundColor(selected ? MagpieTheme.surface : MagpieTheme.ink)
                            Text(proto.routePath)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundColor(selected ? MagpieTheme.surface.opacity(0.75) : MagpieTheme.textMuted)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(selected ? MagpieTheme.ink : MagpieTheme.canvas)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func runProbe() {
        saveError = nil
        isProbing = true
        Task {
            probeResult = await UpstreamClient.probe(
                rawBaseURL: rawBaseURL,
                apiKey: apiKey,
                targetProtocol: targetProtocol
            )
            isProbing = false
        }
    }

    private func commitSave() {
        saveError = nil
        let result = store.saveProfile(
            editingID: existing?.id,
            name: name,
            rawBaseURL: rawBaseURL,
            apiKey: apiKey,
            targetProtocol: targetProtocol,
            defaultModel: defaultModel,
            activateImmediately: activateOnSave
        )
        switch result {
        case .success(let saved):
            if let probeResult = probeResult {
                store.healthByProfile[saved.id] = probeResult
            } else if activateOnSave {
                Task { await store.probeConnection(for: saved) }
            }
            store.showToast("已保存「\(saved.name)」")
            dismiss()
        case .failure(let err):
            saveError = err.text
        }
    }
}
