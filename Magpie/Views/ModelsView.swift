import SwiftUI

struct ModelsView: View {
    @ObservedObject var store: GatewayStore
    @State private var searchText = ""
    @State private var selectedOwner = "全部"
    @State private var testingModel: MagpieModelItem?
    @State private var testPrompt = "请回复一句简短问候，确认模型链路可用。"
    @State private var testRoute = "/v1/chat/completions"
    @State private var isTesting = false
    @State private var testOutput: String?
    @State private var testStatus: (ok: Bool, code: Int, ms: Int)?

    private var owners: [String] {
        let raw = Set(store.models.map { $0.ownedBy })
        return ["全部"] + raw.sorted()
    }

    private var filteredModels: [MagpieModelItem] {
        store.models.filter { item in
            let matchesOwner = (selectedOwner == "全部") || (item.ownedBy == selectedOwner)
            let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let matchesSearch = q.isEmpty || item.id.lowercased().contains(q) || item.ownedBy.lowercased().contains(q)
            return matchesOwner && matchesSearch
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                headerCard

                if let err = store.modelsError {
                    MagpieErrorBanner(
                        title: "拉取 /v1/models 失败",
                        message: err,
                        retryTitle: "重试"
                    ) {
                        Task { await store.fetchModels() }
                    }

                    Button("改用本地网关内置模型列表") {
                        Task { await store.fetchModels(forceLocalFallback: true) }
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
                }

                if !store.models.isEmpty {
                    searchAndFilterCard
                }

                if store.isLoadingModels && store.models.isEmpty {
                    MagpieCard {
                        HStack(spacing: 10) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: MagpieTheme.amber))
                            Text("正在请求 /v1/models …")
                                .font(.system(size: 13.5))
                                .foregroundColor(MagpieTheme.textSecondary)
                        }
                        .padding(.vertical, 8)
                    }
                } else if filteredModels.isEmpty && store.modelsError == nil {
                    MagpieCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(store.models.isEmpty ? "暂无模型数据" : "没有匹配「\(searchText)」的模型")
                                .font(.system(size: 14.5, weight: .bold))
                                .foregroundColor(MagpieTheme.textPrimary)
                            Text(store.models.isEmpty ? "点击上方「刷新」从当前配置或本地网关加载 /v1/models。" : "尝试清空搜索词或切换筛选分组。")
                                .font(.system(size: 12.5))
                                .foregroundColor(MagpieTheme.textSecondary)
                        }
                    }
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredModels) { model in
                            modelRowCard(model)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 100)
        }
        .onAppear {
            if store.models.isEmpty && !store.isLoadingModels {
                Task { await store.fetchModels() }
            }
        }
        .sheet(item: $testingModel) { model in
            modelTestSheet(model)
        }
    }

    private var headerCard: some View {
        MagpieCard(elevated: true) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("模型目录 (/v1/models)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(MagpieTheme.textPrimary)
                    Text(store.modelsSourceLabel)
                        .font(.system(size: 12))
                        .foregroundColor(MagpieTheme.textSecondary)
                }
                Spacer()
                if let ms = store.modelsLatencyMs {
                    MagpieBadge(text: "\(ms) ms", color: MagpieTheme.teal, monospaced: true)
                }
                Button {
                    Task { await store.fetchModels() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise")
                        Text(store.isLoadingModels ? "刷新中" : "刷新")
                    }
                }
                .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
                .disabled(store.isLoadingModels)
            }

            HStack(spacing: 8) {
                MagpieBadge(text: "共 \(store.models.count) 个模型", color: MagpieTheme.amber)
                if let active = store.activeProfile {
                    MagpieBadge(text: "默认: \(active.defaultModel)", color: MagpieTheme.teal, monospaced: true)
                }
            }
        }
    }

    private var searchAndFilterCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13.5))
                    .foregroundColor(MagpieTheme.textMuted)
                TextField("搜索模型 ID（如 claude / gemini / gpt）", text: $searchText)
                    .font(.system(size: 13.5, design: .monospaced))
                    .foregroundColor(MagpieTheme.textPrimary)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(MagpieTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(MagpieTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(MagpieTheme.border, lineWidth: 1)
            )

            if owners.count > 2 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(owners, id: \.self) { owner in
                            let selected = selectedOwner == owner
                            Button(owner) {
                                selectedOwner = owner
                            }
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(selected ? MagpieTheme.canvas : MagpieTheme.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(selected ? MagpieTheme.amber : MagpieTheme.card)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(selected ? MagpieTheme.amber : MagpieTheme.border, lineWidth: 1)
                            )
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func modelRowCard(_ model: MagpieModelItem) -> some View {
        let isDefault = store.activeProfile?.defaultModel == model.id
        return MagpieCard(
            borderColor: isDefault ? MagpieTheme.amber.opacity(0.6) : MagpieTheme.border
        ) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(model.id)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(MagpieTheme.textPrimary)
                        if isDefault {
                            MagpieBadge(text: "默认", color: MagpieTheme.amber)
                        }
                    }
                    HStack(spacing: 6) {
                        MagpieBadge(text: model.ownedBy, color: MagpieTheme.teal)
                        Text(model.source)
                            .font(.system(size: 11))
                            .foregroundColor(MagpieTheme.textMuted)
                    }
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Button("复制 ID") {
                    store.copyToClipboard(model.id, label: "模型 ID")
                }
                .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))

                if store.activeProfile != nil && !isDefault {
                    Button("设为默认") {
                        store.updateActiveDefaultModel(model.id)
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .teal, compact: true))
                }

                Spacer()

                Button("实测请求") {
                    testOutput = nil
                    testStatus = nil
                    testingModel = model
                }
                .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
            }
        }
    }

    private func modelTestSheet(_ model: MagpieModelItem) -> some View {
        ZStack {
            MagpieTheme.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button("关闭") { testingModel = nil }
                        .font(.system(size: 15))
                        .foregroundColor(MagpieTheme.textSecondary)
                    Spacer()
                    Text("接口实测")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(MagpieTheme.textPrimary)
                    Spacer()
                    Color.clear.frame(width: 36, height: 1)
                }
                .padding(16)
                .background(MagpieTheme.card)
                .overlay(Rectangle().fill(MagpieTheme.border).frame(height: 1), alignment: .bottom)

                ScrollView {
                    VStack(spacing: 14) {
                        MagpieCard {
                            HStack {
                                Text("目标模型")
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundColor(MagpieTheme.textSecondary)
                                Spacer()
                                MagpieBadge(text: model.id, color: MagpieTheme.amber, monospaced: true)
                            }

                            Text("本地入口路由")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundColor(MagpieTheme.textSecondary)

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                routeChoice("/v1/chat/completions")
                                routeChoice("/v1/responses")
                                routeChoice("/v1/messages")
                                routeChoice("/v1beta/models/\(model.id):generateContent")
                            }

                            MagpieInputField(
                                label: "测试内容（支持自动隐私脱敏验证）",
                                placeholder: "输入测试提示词…",
                                text: $testPrompt
                            )

                            Button {
                                isTesting = true
                                Task {
                                    let res = await store.runGatewaySmokeTest(
                                        route: testRoute,
                                        prompt: testPrompt,
                                        model: model.id
                                    )
                                    testStatus = (res.ok, res.statusCode, res.latencyMs)
                                    testOutput = res.output
                                    isTesting = false
                                }
                            } label: {
                                Text(isTesting ? "请求发送中…" : "通过 127.0.0.1:3425 发送")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(MagpieButtonStyle(tone: .primary))
                            .disabled(isTesting)
                        }

                        if let st = testStatus, let out = testOutput {
                            MagpieCard(
                                borderColor: st.ok ? MagpieTheme.teal.opacity(0.5) : MagpieTheme.coral.opacity(0.6)
                            ) {
                                HStack {
                                    MagpieBadge(
                                        text: st.ok ? "HTTP \(st.code) 成功" : "HTTP \(st.code) 失败",
                                        color: st.ok ? MagpieTheme.teal : MagpieTheme.coral,
                                        monospaced: true
                                    )
                                    MagpieBadge(text: "\(st.ms) ms", color: MagpieTheme.amber, monospaced: true)
                                    Spacer()
                                }
                                Text(out)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundColor(MagpieTheme.textPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func routeChoice(_ route: String) -> some View {
        let selected = testRoute == route
        return Button {
            testRoute = route
        } label: {
            Text(route)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(selected ? MagpieTheme.canvas : MagpieTheme.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .background(selected ? MagpieTheme.teal : MagpieTheme.input)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(selected ? MagpieTheme.teal : MagpieTheme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
