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
        ["全部"] + Set(store.models.map(\.ownedBy)).sorted()
    }

    private var filteredModels: [MagpieModelItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.models.filter { item in
            let matchesOwner = (selectedOwner == "全部") || (item.ownedBy == selectedOwner)
            let matchesSearch = q.isEmpty || item.id.lowercased().contains(q) || item.ownedBy.lowercased().contains(q)
            return matchesOwner && matchesSearch
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("模型目录")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(MagpieTheme.ink)
                        Text("\(store.modelsSourceLabel) · 共 \(store.models.count) 个")
                            .font(.system(size: 13))
                            .foregroundColor(MagpieTheme.textSecondary)
                    }
                    Spacer()
                    Button(store.isLoadingModels ? "刷新中" : "刷新") {
                        Task { await store.fetchModels() }
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
                    .disabled(store.isLoadingModels)
                }

                if let err = store.modelsError {
                    MagpieErrorBanner(title: "拉取失败", message: err, retryTitle: "内置列表") {
                        Task { await store.fetchModels(forceLocalFallback: true) }
                    }
                }

                searchBar

                if filteredModels.isEmpty {
                    MinimalSection {
                        Text(store.isLoadingModels ? "正在加载模型…" : "无匹配模型")
                            .font(.system(size: 13.5))
                            .foregroundColor(MagpieTheme.textSecondary)
                    }
                } else {
                    MinimalSection {
                        ForEach(Array(filteredModels.enumerated()), id: \.element.id) { idx, model in
                            if idx > 0 {
                                Rectangle()
                                    .fill(MagpieTheme.hairline)
                                    .frame(height: 1)
                            }
                            modelRow(model)
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
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

    private var searchBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundColor(MagpieTheme.textMuted)
                TextField("搜索模型 ID…", text: $searchText)
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

            if owners.count > 2 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(owners, id: \.self) { owner in
                            let selected = selectedOwner == owner
                            Button(owner) {
                                selectedOwner = owner
                            }
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(selected ? MagpieTheme.surface : MagpieTheme.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(selected ? MagpieTheme.ink : MagpieTheme.surface)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(MagpieTheme.hairline, lineWidth: selected ? 0 : 1))
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func modelRow(_ model: MagpieModelItem) -> some View {
        let isDefault = store.activeProfile?.defaultModel == model.id
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(model.id)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(MagpieTheme.ink)
                    if isDefault {
                        MagpieTag(text: "默认", tone: MagpieTheme.ink)
                    }
                }
                Text(model.ownedBy)
                    .font(.system(size: 11.5))
                    .foregroundColor(MagpieTheme.textMuted)
            }
            Spacer()
            Button("复制") {
                store.copyToClipboard(model.id, label: "模型 ID")
            }
            .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))

            Button("实测") {
                testOutput = nil
                testStatus = nil
                testingModel = model
            }
            .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
        }
    }

    private func modelTestSheet(_ model: MagpieModelItem) -> some View {
        ZStack {
            MagpieTheme.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button("关闭") { testingModel = nil }
                        .font(.system(size: 14))
                        .foregroundColor(MagpieTheme.textSecondary)
                    Spacer()
                    Text(model.id)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(MagpieTheme.ink)
                    Spacer()
                    Color.clear.frame(width: 32, height: 1)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
                .background(MagpieTheme.surface)
                .overlay(Rectangle().fill(MagpieTheme.hairline).frame(height: 1), alignment: .bottom)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        MinimalSection(title: "测试请求") {
                            MagpieInputField(label: "路由", placeholder: "/v1/chat/completions", text: $testRoute, monospaced: true)
                            MagpieInputField(label: "提示词", placeholder: "输入测试内容…", text: $testPrompt)

                            Button(isTesting ? "请求中…" : "发送测试") {
                                isTesting = true
                                Task {
                                    let res = await store.runGatewaySmokeTest(route: testRoute, prompt: testPrompt, model: model.id)
                                    testStatus = (res.ok, res.statusCode, res.latencyMs)
                                    testOutput = res.output
                                    isTesting = false
                                }
                            }
                            .buttonStyle(MagpieButtonStyle(tone: .primary))
                            .disabled(isTesting)
                        }

                        if let st = testStatus, let out = testOutput {
                            MinimalSection(title: "响应结果", trailingText: "HTTP \(st.code) · \(st.ms) ms") {
                                Text(out)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundColor(MagpieTheme.ink)
                            }
                        }
                    }
                    .padding(22)
                }
            }
        }
        .preferredColorScheme(.light)
    }
}
