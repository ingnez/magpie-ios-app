import SwiftUI
import UIKit

struct CallerKeysView: View {
    @ObservedObject var store: GatewayStore
    @Environment(\.dismiss) private var dismiss
    @State private var creating = false
    @State private var editing: RemoteCallerKey?
    @State private var pendingAction: String?
    @State private var actionKey: RemoteCallerKey?
    @State private var secret: String?
    @State private var busy = false

    var body: some View {
        NavigationView {
            List {
                if let secret = secret {
                    Section(header: Text("本次签发的密钥 · 关闭页面后不保留")) {
                        Text(secret).font(.caption.monospaced()).textSelection(.enabled).privacySensitive()
                        Button("复制密钥（2 分钟后失效于剪贴板）") {
                            UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: secret]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)])
                        }
                        Button("隐藏密钥") { self.secret = nil }
                    }
                }
                ForEach(store.callerKeys) { key in
                    Section(header: Text(key.name)) {
                        Text(key.masked).font(.caption.monospaced())
                        Text(key.off ? "已停用" : (key.readOnly ? "仅允许读取统计" : "已启用"))
                        if let used = key.used {
                            Text(String(format: "已用 %lld Token · $%.3f", used.tokens, used.cost)).font(.caption)
                            Text("重置：" + used.reset).font(.caption)
                        }
                        if let limit = key.limit {
                            Text("预算周期：\(limit.period) · \(limit.tokens ?? 0) Token · $\(limit.cost ?? 0)").font(.caption)
                        }
                        Button("编辑名称、模型权限与预算") { editing = key }
                        HStack {
                            Button(key.off ? "启用" : "停用") { run(key.off ? "on-key" : "off-key", key: key) }
                            Spacer()
                            Button("轮换密钥") { actionKey = key; pendingAction = "rotate-key" }
                            Button("删除", role: .destructive) { actionKey = key; pendingAction = "remove-key" }
                        }
                    }
                }
            }
            .disabled(busy)
            .navigationTitle("Caller Keys")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("新增") { creating = true } }
            }
            .refreshable { await refresh() }
        }.navigationViewStyle(.stack)
        .task { await refresh() }
        .sheet(isPresented: $creating) { CallerKeyEditor(store: store, existing: nil) { secret = $0 } }
        .sheet(item: $editing) { key in CallerKeyEditor(store: store, existing: key) { secret = $0 } }
        .confirmationDialog(pendingAction == "remove-key" ? "删除后客户端将无法继续使用此 Key" : "轮换后旧密钥立即失效", isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }), titleVisibility: .visible) {
            Button("确认", role: .destructive) {
                if let action = pendingAction, let key = actionKey { run(action, key: key) }
                pendingAction = nil
            }
            Button("取消", role: .cancel) { pendingAction = nil }
        }
        .onDisappear { secret = nil }
    }
    private func refresh() async {
        do { store.callerKeys = try await store.client.fetchCallerKeys() }
        catch { store.recordActionError(error) }
    }
    private func run(_ action: String, key: RemoteCallerKey) {
        busy = true
        Task {
            defer { busy = false }
            do {
                let response = try await store.client.callerKeyAction(action, payload: ["key": key.id])
                store.callerKeys = response.keys
                if let value = response.secret, !value.isEmpty { secret = value }
            } catch { store.recordActionError(error) }
        }
    }
}

private struct CallerKeyEditor: View {
    @ObservedObject var store: GatewayStore
    let existing: RemoteCallerKey?
    let onSecret: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var models = ""
    @State private var period = "day"
    @State private var tokens = ""
    @State private var cost = ""
    @State private var readOnly = false
    @State private var busy = false
    @State private var error: String?
    @State private var editBudget = false
    @State private var issuedID: String?
    var body: some View {
        NavigationView {
            Form {
                if let error = error { Text(error).foregroundColor(.red) }
                Section(header: Text("基本信息")) {
                    TextField("名称", text: $name)
                    Toggle("仅允许读取统计", isOn: $readOnly)
                }
                Section(header: Text("模型范围"), footer: Text("每行一个 provider/model、provider/* 或 group/id；留空允许全部模型。")) {
                    TextEditor(text: $models).frame(minHeight: 80).font(.caption.monospaced()).autocapitalization(.none)
                }
                if existing != nil {
                    Section(header: Text("预算"), footer: Text("更改预算会更新此 Key 的额度规则。未开启时保留现有的全部额度规则。")) {
                        Toggle("修改额度规则", isOn: $editBudget)
                        if editBudget {
                            Picker("周期", selection: $period) {
                                Text("每日").tag("day"); Text("每周").tag("week"); Text("每月").tag("month")
                            }
                            TextField("Token 上限（0 为不限）", text: $tokens).keyboardType(.numberPad)
                            TextField("美元上限（0 为不限）", text: $cost).keyboardType(.decimalPad)
                        }
                    }
                } else { Text("新建后可继续编辑额度规则。密钥由服务器生成。").font(.caption) }
            }
            .disabled(busy)
            .navigationTitle(existing == nil ? "签发 Caller Key" : "编辑 Caller Key")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
        }.navigationViewStyle(.stack)
        .onAppear {
            if let key = existing {
                name = key.name; models = key.models.joined(separator: "\n"); readOnly = key.readOnly
                period = key.limit?.period ?? "day"
                tokens = String(key.limit?.tokens ?? 0); cost = String(key.limit?.cost ?? 0)
            }
        }
    }
    private func save() {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelIDs = models.split(whereSeparator: { $0 == "\n" || $0 == "," }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var budget: [String: Any]?
        if editBudget {
            guard let tokenLimit = Int64(tokens), tokenLimit >= 0, let costLimit = Double(cost), costLimit.isFinite, costLimit >= 0 else {
                error = "额度须为非负数字"; return
            }
            budget = ["period": period, "tokens": tokenLimit, "cost": costLimit]
        }
        busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                var id = existing?.id ?? issuedID
                if id == nil {
                    let previousIDs = Set(store.callerKeys.map(\.id))
                    let result = try await store.client.callerKeyAction("add-key", payload: ["name": clean, "readOnly": true])
                    store.callerKeys = result.keys
                    if let value = result.secret, !value.isEmpty { onSecret(value) }
                    id = result.keys.first { !previousIDs.contains($0.id) }?.id
                    issuedID = id
                }
                guard let id = id else { throw MagpieWebError.decodingError("服务器未返回新 Key") }
                let before = existing
                if before != nil {
                    let result = try await store.client.callerKeyAction("rename-key", payload: ["key": id, "name": clean])
                    store.callerKeys = result.keys
                }
                let scope = try await store.client.callerKeyAction("models-key", payload: ["key": id, "models": modelIDs])
                store.callerKeys = scope.keys
                do {
                    let access = try await store.client.callerKeyAction("access-key", payload: ["key": id, "readOnly": readOnly])
                    store.callerKeys = access.keys
                }
                if let budget = budget {
                    let result = try await store.client.callerKeyAction("limit-key", payload: ["key": id, "limit": budget])
                    store.callerKeys = result.keys
                }
                dismiss()
            } catch { self.error = error.localizedDescription; store.recordActionError(error) }
        }
    }
}
