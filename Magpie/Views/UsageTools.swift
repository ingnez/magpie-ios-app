import SwiftUI

struct UsageTrendView: View {
    let series: [RemoteUsagePoint]
    @State private var metric = "calls"
    @State private var selected: Int?
    private func amount(_ point: RemoteUsagePoint) -> Double {
        switch metric {
        case "tokens": return Double(point.input + point.output)
        case "cost": return point.cost
        default: return Double(point.calls)
        }
    }
    var body: some View {
        MinimalSection(title: "用量趋势") {
            Picker("指标", selection: $metric) {
                Text("请求数").tag("calls"); Text("Token").tag("tokens"); Text("费用").tag("cost")
            }.pickerStyle(.segmented)
            if series.isEmpty { Text("本周期暂无用量").font(.caption) }
            else {
                let maximum = max(series.map(amount).max() ?? 0, 1)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(Array(series.enumerated()), id: \.offset) { index, point in
                            Button { selected = index } label: {
                                VStack(spacing: 4) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(selected == index ? MagpieTheme.ok : MagpieTheme.ink)
                                        .frame(height: max(2, CGFloat(amount(point) / maximum) * 120))
                                    Text(point.label.isEmpty ? String(point.time.suffix(5)) : point.label)
                                        .font(.system(size: 9)).lineLimit(1)
                                }.frame(width: 32)
                            }.buttonStyle(.plain).accessibilityLabel("\(point.label) \(amount(point))")
                        }
                    }.frame(height: 145, alignment: .bottom)
                }
                if let index = selected, series.indices.contains(index) {
                    let point = series[index]
                    Text(String(format: "%@ · %d 请求 · %d Token · $%.4f", point.label.isEmpty ? point.time : point.label, point.calls, point.input + point.output, point.cost))
                        .font(.caption.monospaced()).textSelection(.enabled)
                } else { Text("点按柱形查看具体用量").font(.caption).foregroundColor(MagpieTheme.textSecondary) }
            }
        }
    }
}

struct UsageAutomationView: View {
    @ObservedObject var store: GatewayStore
    @Environment(\.dismiss) private var dismiss
    @State private var output = ""
    @State private var busy = false
    @State private var confirmWarm: String?
    @State private var pluginProvider = ""
    @State private var automatic = false
    @State private var provider = "workbuddy"
    private let checkins = [("workbuddy", "WorkBuddy"), ("trae", "Trae CN"), ("minimax", "MiniMax"), ("qoder", "Qoder")]

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("手动签到")) {
                    ForEach(checkins, id: \.0) { item in
                        Button("\(item.1) 立即签到") { checkIn(item.0) }
                    }
                    TextField("其他插件的供应商 ID", text: $pluginProvider).autocapitalization(.none)
                    Button("插件签到") { checkIn(pluginProvider) }.disabled(pluginProvider.isEmpty)
                }
                Section(header: Text("自动签到")) {
                    Picker("供应商", selection: $provider) { ForEach(checkins, id: \.0) { item in Text(item.1).tag(item.0) } }
                    Toggle("开启自动签到", isOn: $automatic)
                    Button("保存自动签到设置") {
                        busy = true
                        Task {
                            defer { busy = false }
                            do {
                                store.remoteSettings = try await store.client.updateCheckin(provider: provider, on: automatic)
                                output = automatic ? "已开启自动签到" : "已关闭自动签到"
                            } catch { output = error.localizedDescription }
                        }
                    }
                }
                Section(header: Text("热身"), footer: Text("在服务器执行，可能消耗订阅额度。")) {
                    Button("Claude 账号热身") { confirmWarm = "claude" }
                    Button("Codex 账号热身") { confirmWarm = "codex" }
                }
                if !output.isEmpty { Section(header: Text("结果")) { Text(output).font(.caption.monospaced()).textSelection(.enabled) } }
            }
            .disabled(busy)
            .navigationTitle("签到与热身")
            .toolbar { Button("关闭") { dismiss() } }
        }.navigationViewStyle(.stack)
        .confirmationDialog("执行账号热身，可能消耗额度", isPresented: Binding(get: { confirmWarm != nil }, set: { if !$0 { confirmWarm = nil } }), titleVisibility: .visible) {
            Button("执行热身") {
                guard let agent = confirmWarm else { return }
                confirmWarm = nil; busy = true
                Task {
                    defer { busy = false }
                    do {
                        let result = try await store.client.warmAccounts(agent: agent)
                        output = result.results.isEmpty ? "没有需要热身的账号" : result.results.map { "\($0.user ?? "账号")：\($0.error ?? $0.skip ?? "已热身")" }.joined(separator: "\n")
                        await store.refreshQuotas()
                    } catch { output = error.localizedDescription }
                }
            }
            Button("取消", role: .cancel) { confirmWarm = nil }
        }
    }
    private func checkIn(_ provider: String) {
        busy = true
        Task {
            defer { busy = false }
            do {
                let results = try await store.client.checkIn(provider: provider)
                output = results.isEmpty ? "没有可签到的账号" : results.map { "\($0.user ?? "账号")：\($0.msg ?? $0.outcome)" }.joined(separator: "\n")
                await store.refreshQuotas()
            } catch { output = error.localizedDescription }
        }
    }
}
