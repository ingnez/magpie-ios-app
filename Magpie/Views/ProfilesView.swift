import SwiftUI

struct ProfilesView: View {
    @ObservedObject var store: GatewayStore
    @Binding var presentingNewEditor: Bool

    @State private var editingProfile: ProxyProfile?
    @State private var profilePendingDelete: ProxyProfile?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                headerCard

                if store.profiles.isEmpty {
                    emptyStateCard
                } else {
                    ForEach(store.profiles) { profile in
                        profileCard(profile)
                    }
                }

                if store.activeProfile != nil {
                    Button("切回本地回环模式（暂停转发上游）") {
                        store.deactivateToLocalLoopback()
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 100)
        }
        .sheet(isPresented: $presentingNewEditor) {
            ProfileEditorSheet(store: store, existing: nil)
        }
        .sheet(item: $editingProfile) { profile in
            ProfileEditorSheet(store: store, existing: profile)
        }
        .alert(
            "确认删除该反代配置？",
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
            Text("将永久移除「\(target.name)」(\(target.baseURL))。")
        }
    }

    private var headerCard: some View {
        MagpieCard(elevated: true) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("反代服务器配置库")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(MagpieTheme.textPrimary)
                    Text("支持多套上游独立命名、一键切换与实时连通探测")
                        .font(.system(size: 12))
                        .foregroundColor(MagpieTheme.textSecondary)
                }
                Spacer()
                Button {
                    presentingNewEditor = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                        Text("新建")
                    }
                }
                .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
            }
        }
    }

    private var emptyStateCard: some View {
        MagpieCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("尚未保存任何上游反代配置")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(MagpieTheme.textPrimary)
                Text("添加你的 OpenAI 中转、Anthropic、Gemini 或局域网自建反代节点后，Magpie 会自动校验地址并托管在 127.0.0.1:3425。")
                    .font(.system(size: 12.5))
                    .foregroundColor(MagpieTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    presentingNewEditor = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("立即添加第一套配置")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(MagpieButtonStyle(tone: .primary))
            }
        }
    }

    private func profileCard(_ profile: ProxyProfile) -> some View {
        let isActive = store.activeProfileID == profile.id
        let health = store.healthByProfile[profile.id] ?? .untested

        return MagpieCard(
            elevated: isActive,
            borderColor: isActive ? MagpieTheme.amber.opacity(0.65) : MagpieTheme.border
        ) {
            HStack(alignment: .top, spacing: 10) {
                MagpieStatusLight(kind: health.kind, showPulse: isActive)
                    .padding(.top, 3)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(profile.name)
                            .font(.system(size: 15.5, weight: .bold))
                            .foregroundColor(MagpieTheme.textPrimary)
                        if isActive {
                            MagpieBadge(text: "当前启用", color: MagpieTheme.amber)
                        }
                    }

                    Text(profile.baseURL)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundColor(MagpieTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                latencyPill(health: health)
            }

            HStack(spacing: 6) {
                MagpieBadge(text: profile.targetProtocol.shortBadge, color: MagpieTheme.teal)
                MagpieBadge(text: profile.defaultModel, color: MagpieTheme.textSecondary, monospaced: true)
                MagpieBadge(text: profile.maskedKeyPreview, color: MagpieTheme.textMuted, monospaced: true)
            }

            if health.kind == .failed {
                Text("连接异常：\(health.message)")
                    .font(.system(size: 12))
                    .foregroundColor(MagpieTheme.coral)
                    .fixedSize(horizontal: false, vertical: true)
            } else if health.kind == .connected {
                Text(health.message)
                    .font(.system(size: 12))
                    .foregroundColor(MagpieTheme.teal)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
                .buttonStyle(MagpieButtonStyle(tone: .teal, compact: true))
                .disabled(health.kind == .checking)

                Button("编辑") {
                    editingProfile = profile
                }
                .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))

                Spacer()

                Button {
                    profilePendingDelete = profile
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(MagpieButtonStyle(tone: .danger, compact: true))
            }
        }
    }

    @ViewBuilder
    private func latencyPill(health: ConnectionHealth) -> some View {
        switch health.kind {
        case .connected:
            MagpieBadge(text: "\(health.latencyMs ?? 0) ms", color: MagpieTheme.teal, monospaced: true)
        case .checking:
            MagpieBadge(text: "探测中", color: MagpieTheme.amber)
        case .failed:
            MagpieBadge(text: health.statusCode.map { "HTTP \($0)" } ?? "失败", color: MagpieTheme.coral, monospaced: true)
        default:
            MagpieBadge(text: "未探测", color: MagpieTheme.textMuted)
        }
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
        if rawBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }
        return urlValidation.errorReason
    }

    private var urlHelperText: String? {
        guard case .valid(let normalized) = urlValidation else { return nil }
        if normalized != rawBaseURL.trimmingCharacters(in: .whitespacesAndNewlines) {
            return "保存时将自动规范化为：\(normalized)"
        }
        return "地址格式合法：\(normalized)"
    }

    var body: some View {
        ZStack {
            MagpieTheme.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                sheetHeader

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        if existing == nil {
                            quickTemplateStrip
                        }

                        MagpieCard {
                            MagpieInputField(
                                label: "配置名称",
                                placeholder: "例如：主力 Claude 中转 / 本地 Ollama",
                                text: $name
                            )

                            MagpieInputField(
                                label: "服务器地址（http / https）",
                                placeholder: "https://api.example.com",
                                text: $rawBaseURL,
                                monospaced: true,
                                keyboardType: .URL,
                                errorText: urlErrorText,
                                helperText: urlHelperText
                            )

                            MagpieInputField(
                                label: "API Key / 访问密钥",
                                placeholder: "sk-...",
                                text: $apiKey,
                                isSecure: true,
                                monospaced: true
                            )

                            protocolSelector

                            MagpieInputField(
                                label: "默认模型 ID",
                                placeholder: targetProtocol.suggestedDefaultModel,
                                text: $defaultModel,
                                monospaced: true
                            )

                            HStack {
                                Text("保存后立即切换为当前启用配置")
                                    .font(.system(size: 13))
                                    .foregroundColor(MagpieTheme.textPrimary)
                                Spacer()
                                MagpieToggle(isOn: $activateOnSave, accent: MagpieTheme.amber)
                            }
                            .padding(.top, 4)
                        }

                        if let probeResult = probeResult {
                            probeFeedbackCard(probeResult)
                        }

                        if let saveError = saveError {
                            MagpieErrorBanner(title: "无法保存配置", message: saveError)
                        }

                        HStack(spacing: 10) {
                            Button {
                                runProbe()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: isProbing ? "arrow.triangle.2.circlepath" : "antenna.radiowaves.left.and.right")
                                    Text(isProbing ? "探测中…" : "测试连接")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(MagpieButtonStyle(tone: .teal))
                            .disabled(isProbing)

                            Button {
                                commitSave()
                            } label: {
                                Text(existing == nil ? "保存配置" : "更新配置")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(MagpieButtonStyle(tone: .primary))
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 30)
                }
            }
        }
        .preferredColorScheme(.dark)
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

    private var sheetHeader: some View {
        HStack {
            Button("取消") {
                dismiss()
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(MagpieTheme.textSecondary)

            Spacer()

            Text(existing == nil ? "新建反代配置" : "编辑配置")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(MagpieTheme.textPrimary)

            Spacer()

            Button("保存") {
                commitSave()
            }
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(MagpieTheme.amber)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(MagpieTheme.card)
        .overlay(
            Rectangle()
                .fill(MagpieTheme.border)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private var quickTemplateStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("快速填充模板")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(MagpieTheme.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    templateChip("OpenAI 官方", url: "https://api.openai.com", proto: .openAIChat, model: "gpt-4o")
                    templateChip("Anthropic", url: "https://api.anthropic.com", proto: .anthropicMessages, model: "claude-sonnet-4-5")
                    templateChip("Gemini 官方", url: "https://generativelanguage.googleapis.com", proto: .geminiV1Beta, model: "gemini-2.5-pro")
                    templateChip("本地 OneAPI", url: "http://127.0.0.1:3000", proto: .openAIChat, model: "claude-sonnet-4-5")
                }
            }
        }
    }

    private func templateChip(_ title: String, url: String, proto: MagpieProtocol, model: String) -> some View {
        Button {
            name = title
            rawBaseURL = url
            targetProtocol = proto
            defaultModel = model
            saveError = nil
            probeResult = nil
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(MagpieTheme.textPrimary)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(MagpieTheme.cardElevated)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(MagpieTheme.borderStrong, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var protocolSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("上游目标协议")
                .font(.system(size: 12.5, weight: .semibold))
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
                                .font(.system(size: 12.5, weight: .bold))
                                .foregroundColor(selected ? MagpieTheme.canvas : MagpieTheme.textPrimary)
                            Text(proto.routePath)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundColor(selected ? MagpieTheme.canvas.opacity(0.75) : MagpieTheme.textMuted)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .background(selected ? MagpieTheme.amber : MagpieTheme.input)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(selected ? MagpieTheme.amber : MagpieTheme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func probeFeedbackCard(_ health: ConnectionHealth) -> some View {
        let isOK = health.kind == .connected
        return MagpieCard(
            elevated: true,
            borderColor: isOK ? MagpieTheme.teal.opacity(0.55) : MagpieTheme.coral.opacity(0.6)
        ) {
            HStack(spacing: 8) {
                MagpieStatusLight(kind: health.kind)
                Text(isOK ? "连接探测成功" : "连接探测失败")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundColor(MagpieTheme.textPrimary)
                Spacer()
                if let ms = health.latencyMs {
                    MagpieBadge(text: "\(ms) ms", color: isOK ? MagpieTheme.teal : MagpieTheme.coral, monospaced: true)
                }
            }
            Text(health.message)
                .font(.system(size: 12.5))
                .foregroundColor(isOK ? MagpieTheme.teal : MagpieTheme.coral)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func runProbe() {
        saveError = nil
        isProbing = true
        Task {
            let res = await GatewayStore.executeProbe(
                rawBaseURL: rawBaseURL,
                apiKey: apiKey,
                targetProtocol: targetProtocol
            )
            probeResult = res
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
            store.showToast(existing == nil ? "已保存配置「\(saved.name)」" : "已更新配置「\(saved.name)」")
            dismiss()
        case .failure(let err):
            saveError = err.text
        }
    }
}
