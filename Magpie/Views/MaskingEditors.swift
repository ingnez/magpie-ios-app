import SwiftUI

struct MaskingRulesEditor: View {
    @ObservedObject var store: GatewayStore
    @Environment(\.dismiss) private var dismiss
    @State private var kind = ""
    @State private var pattern = ""
    @State private var regex = false
    @State private var action = ""
    @State private var words = ""
    @State private var ignoreCase = false
    @State private var wholeWord = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationView {
            Form {
                if let error = error { Text(error).foregroundColor(.red) }
                Section(header: Text("自定义敏感词")) {
                    TextEditor(text: $words).frame(minHeight: 100)
                    Text("每行一个词").font(.caption)
                    Toggle("忽略大小写", isOn: $ignoreCase)
                    Toggle("整词匹配", isOn: $wholeWord)
                    Button("保存敏感词") {
                        busy = true
                        Task {
                            do {
                                store.remoteSettings = try await store.client.patchSettings([
                                    "redactWords": words.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                                    "redactWordsAnyCase": ignoreCase, "redactWordsWhole": wholeWord
                                ])
                                store.showToast("敏感词已保存")
                            } catch { self.error = error.localizedDescription }
                            busy = false
                        }
                    }
                }
                Section(header: Text("新增规则"), footer: Text("正则使用服务端 Go RE2 语法；服务器校验失败会保留原规则。")) {
                    TextField("分类，如 CORP", text: $kind).autocapitalization(.allCharacters)
                    Toggle("正则表达式", isOn: $regex)
                    TextField(regex ? "正则表达式" : "匹配前缀", text: $pattern).autocapitalization(.none).disableAutocorrection(true)
                    Picker("命中处理", selection: $action) {
                        Text("脱敏").tag(""); Text("提醒").tag("warn"); Text("拦截").tag("block")
                    }
                    Button("添加规则") { addRule() }.disabled(kind.trimmingCharacters(in: .whitespaces).isEmpty || pattern.isEmpty)
                }
                Section(header: Text("已有规则")) {
                    ForEach(store.remoteSettings.redactRules) { rule in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(rule.kind).font(.headline)
                            Text(rule.prefix ?? rule.regex ?? "").font(.caption.monospaced())
                            Picker("命中处理", selection: Binding(get: { store.remoteSettings.redactActions[rule.kind] ?? "" }, set: { value in
                                updateAction(kind: rule.kind, value: value)
                            })) {
                                Text("脱敏").tag(""); Text("提醒").tag("warn"); Text("拦截").tag("block")
                            }
                        }
                    }.onDelete { offsets in
                        var rules = store.remoteSettings.redactRules
                        rules.remove(atOffsets: offsets)
                        Task { await store.saveRedactRules(rules) }
                    }
                }
            }.disabled(busy)
            .navigationTitle("正则与敏感词")
            .toolbar { Button("关闭") { dismiss() } }
        }.navigationViewStyle(.stack)
        .onAppear {
            words = store.remoteSettings.redactWords.joined(separator: "\n")
            ignoreCase = store.remoteSettings.redactWordsAnyCase; wholeWord = store.remoteSettings.redactWordsWhole
        }
    }
    private func updateAction(kind: String, value: String) {
        busy = true
        Task {
            defer { busy = false }
            do {
                var actions = store.remoteSettings.redactActions
                if value.isEmpty { actions.removeValue(forKey: kind) } else { actions[kind] = value }
                store.remoteSettings = try await store.client.updateRedactActions(actions)
            } catch { self.error = error.localizedDescription }
        }
    }
    private func addRule() {
        busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                let label = kind.trimmingCharacters(in: .whitespacesAndNewlines)
                var rules = store.remoteSettings.redactRules
                let rule = RemoteRedactRule(kind: label, prefix: regex ? nil : pattern, regex: regex ? pattern : nil)
                if !rules.contains(rule) { rules.append(rule) }
                store.remoteSettings = try await store.client.updateRedactRules(rules)
                var actions = store.remoteSettings.redactActions
                if !action.isEmpty { actions[label] = action }
                store.remoteSettings = try await store.client.updateRedactActions(actions)
                kind = ""; pattern = ""
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct MaskingRecordDetail: View {
    @ObservedObject var store: GatewayStore
    let record: RemoteMaskingRecord
    @Environment(\.dismiss) private var dismiss
    @State private var sent: String?
    @State private var values: [String: String] = [:]
    @State private var showOriginal = false
    @State private var error: String?
    private var original: String? {
        guard let sent = sent else { return nil }
        return values.keys.sorted { $0.count > $1.count }.reduce(sent) { $0.replacingOccurrences(of: $1, with: values[$1] ?? $1) }
    }
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("\(record.t) · \(record.n) 处命中").font(.caption)
                    if let error = error { Text(error).foregroundColor(.red) }
                    MinimalSection(title: "发送给上游的内容") {
                        Text(sent ?? "服务端未保留内容，或该内容已随重启清除").font(.caption.monospaced()).textSelection(.enabled)
                    }
                    if !showOriginal {
                        Button("显示脱敏前对照") {
                            Task {
                                do {
                                    values = try await store.client.maskingValues(placeholders: record.values.map(\.p)).values
                                    showOriginal = true
                                } catch { self.error = error.localizedDescription }
                            }
                        }.buttonStyle(MagpieButtonStyle(tone: .secondary))
                    } else {
                        MinimalSection(title: "脱敏前 · 服务端仍记得的部分") {
                            Text(original ?? "暂无可恢复内容").font(.caption.monospaced()).textSelection(.enabled).privacySensitive()
                            if values.count < record.values.count { Text("部分原值已过期，对应占位符仍保留。").font(.caption).foregroundColor(MagpieTheme.warn) }
                        }
                        Button("隐藏原文") { values = [:]; showOriginal = false }
                    }
                    MinimalSection(title: "命中明细") {
                        ForEach(record.values) { value in
                            Text("\(value.k) · \(value.p) · \(value.n) 次").font(.caption.monospaced())
                        }
                    }
                }.padding(20)
            }.background(MagpieTheme.canvas)
            .navigationTitle("脱敏前后对照")
            .toolbar { Button("关闭") { dismiss() } }
        }.navigationViewStyle(.stack)
        .task {
            do { sent = try await store.client.maskingSent(key: record.key).body }
            catch { self.error = error.localizedDescription }
        }
        .onDisappear { values = [:]; sent = nil }
    }
}
