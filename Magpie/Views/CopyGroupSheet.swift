import SwiftUI

struct CopyGroupSheet: View {
    @ObservedObject var store: GatewayStore
    let group: RemoteRoutingGroup
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var saving = false
    @State private var error: String?

    init(store: GatewayStore, group: RemoteRoutingGroup) {
        self.store = store
        self.group = group
        _name = State(initialValue: group.name + " 副本")
    }

    var body: some View {
        NavigationView {
            Form {
                TextField("副本名称", text: $name)
                Button(saving ? "正在创建…" : "创建副本") {
                    saving = true
                    error = nil
                    let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task {
                        let ok = await store.copyGroup(group, newName: cleanName)
                        saving = false
                        if ok { dismiss() } else { error = store.lastActionError }
                    }
                }.disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let error = error { Text(error).foregroundColor(StatusPalette.err) }
            }
            .navigationTitle("复制路由组")
            .toolbar { Button("取消") { dismiss() }.disabled(saving) }
            .interactiveDismissDisabled(saving)
        }.navigationViewStyle(.stack)
    }
}
