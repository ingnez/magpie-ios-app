import SwiftUI

struct LogsPrivacyView: View {
    @ObservedObject var store: GatewayStore
    @Binding var presentingNewServer: Bool

    enum SettingsSubTab: String, CaseIterable {
        case all = "全部"
        case privacy = "隐私脱敏"
        case network = "网络与网关"
        case system = "系统与同步"
    }

    @State private var subTab: SettingsSubTab = .all
    @State private var consoleDestination: ConsoleDestination?
    enum WorkspaceSheet: String, Identifiable {
        case callerKeys, rules, proxies, backupSync, contextTune, systemSettings, modelPrice
        var id: String { rawValue }
    }

    @State private var activeWorkspace: WorkspaceSheet?
    @State private var selectedRecord: RemoteMaskingRecord?
    @State private var confirmClearRecords = false
    @State private var editingServer: MagpieServerProfile?
    @State private var serverPendingDelete: MagpieServerProfile?

    @State private var previewInput = "密钥 sk-proj-998877665544，邮箱 admin@hospital.org，手机 13800138000"
    @State private var newRuleKind = ""
    @State private var newRulePrefix = ""
    @State private var allowText = ""

    @State private var allowIPsInput = ""
    @State private var corsInput = ""
    @State private var portInput = "3425"
    @State private var barkServerInput = ""
    @State private var barkKeyInput = ""
    @State private var barkDailyInput = ""

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                Text("隐私与设置")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(MagpieTheme.ink)

                if store.activeServer != nil {
                    subTabPicker
                }

                serversSection

                if store.activeServer != nil {
                    nativeWorkspacesSection

                    if subTab == .all || subTab == .privacy {
                        maskingControlSection
                        maskingPreviewSection
                        maskingRecordsSection
                    }

                    if subTab == .all || subTab == .network {
                        networkAndBarkSection
                    }

                    if subTab == .all || subTab == .system {
                        MinimalSection(title: "完整管理控制台") {
                            Text("在 App 内打开服务器原版页面（已自动注入 HttpOnly 会话 Cookie）")
                                .font(.caption)
                                .foregroundColor(MagpieTheme.textSecondary)
                            ForEach(ConsoleDestination.allCases) { destination in
                                Button(destination.title) { consoleDestination = destination }
                                    .buttonStyle(MagpieButtonStyle(tone: .secondary))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 100)
        }
        .sheet(item: $consoleDestination) { destination in RemoteConsoleView(store: store, destination: destination) }
        .sheet(item: $activeWorkspace) { sheet in
            switch sheet {
            case .callerKeys: CallerKeysView(store: store)
            case .rules: MaskingRulesEditor(store: store)
            case .proxies: ProxiesManagerView(store: store)
            case .backupSync: BackupSyncView(store: store)
            case .contextTune: ContextTuneView(store: store)
            case .systemSettings: SystemSettingsEditorView(store: store)
            case .modelPrice: ModelPriceEditorView(store: store)
            }
        }
        .sheet(item: $selectedRecord) { record in MaskingRecordDetail(store: store, record: record) }
        .alert("清空服务端脱敏记录？", isPresented: $confirmClearRecords) {
            Button("清空", role: .destructive) { Task { await store.clearMaskingRecords() } }
            Button("取消", role: .cancel) {}
        }
        .onAppear {
            syncLocalFieldDrafts()
            if store.activeServer != nil {
                Task {
                    await store.refreshSettings()
                    await store.refreshMaskingData()
                    syncLocalFieldDrafts()
                }
            }
        }
        .refreshable {
            await store.refreshSettings()
            await store.refreshMaskingData()
            syncLocalFieldDrafts()
        }
        .sheet(item: $editingServer) { server in
            ServerEditorSheet(store: store, existing: server)
        }
        .alert(
            "移除服务器？",
            isPresented: Binding(
                get: { serverPendingDelete != nil },
                set: { if !$0 { serverPendingDelete = nil } }
            ),
            presenting: serverPendingDelete
        ) { target in
            Button("移除", role: .destructive) {
                store.deleteServer(target)
                serverPendingDelete = nil
            }
            Button("取消", role: .cancel) {
                serverPendingDelete = nil
            }
        } message: { target in
            Text("将移除服务器「\(target.name)」及其本地保存的密钥。")
        }
    }

    private var subTabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SettingsSubTab.allCases, id: \.self) { item in
                    let selected = subTab == item
                    Button(item.rawValue) {
                        subTab = item
                    }
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(selected ? MagpieTheme.onInk : MagpieTheme.textSecondary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 6)
                    .background(selected ? MagpieTheme.ink : MagpieTheme.surface)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(MagpieTheme.hairline, lineWidth: selected ? 0 : 1))
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var nativeWorkspacesSection: some View {
        MinimalSection(title: "原生管理工作台", trailingText: "可编辑 · 实时写回") {
            HStack(spacing: 8) {
                Button("Caller Keys 管理") { activeWorkspace = .callerKeys }
                Button("正则与敏感词") { activeWorkspace = .rules }
            }
            .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))

            HStack(spacing: 8) {
                Button("代理池与网络配置") { activeWorkspace = .proxies }
                Button("备份与云同步管理") { activeWorkspace = .backupSync }
            }
            .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))

            HStack(spacing: 8) {
                Button("上下文与缓存调优") { activeWorkspace = .contextTune }
                Button("系统通用与告警设置") { activeWorkspace = .systemSettings }
            }
            .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))

            HStack(spacing: 8) {
                Button("模型自定义定价") { activeWorkspace = .modelPrice }
            }
            .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
        }
    }

    private func syncLocalFieldDrafts() {
        allowText = store.remoteSettings.redactAllow.joined(separator: ", ")
        allowIPsInput = store.remoteSettings.allowIPs.joined(separator: ", ")
        corsInput = store.remoteSettings.corsOrigins.joined(separator: ", ")
        portInput = String(store.remoteSettings.port)
        if barkServerInput.isEmpty {
            barkServerInput = store.remoteSettings.barkServer
        }
        if barkDailyInput.isEmpty {
            barkDailyInput = store.remoteSettings.barkDaily
        }
    }

    // MARK: - Servers

    private var serversSection: some View {
        MinimalSection(title: "magpie web 实例", trailingText: "\(store.servers.count) 台") {
            if store.servers.isEmpty {
                Text("尚未添加任何 magpie web 实例")
                    .font(.system(size: 13))
                    .foregroundColor(MagpieTheme.textMuted)
            } else {
                ForEach(Array(store.servers.enumerated()), id: \.element.id) { idx, server in
                    if idx > 0 {
                        Rectangle().fill(MagpieTheme.hairline).frame(height: 1)
                    }
                    let isActive = store.activeServerID == server.id
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            MagpieStatusLight(kind: isActive ? store.health.kind : .untested)
                            Text(server.name)
                                .font(.system(size: 14.5, weight: .semibold))
                                .foregroundColor(MagpieTheme.ink)
                            if isActive {
                                MagpieTag(text: "当前", tone: MagpieTheme.ink)
                            }
                            Spacer()
                            if !isActive {
                                Button("切换") {
                                    store.activateServer(server)
                                }
                                .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
                            }
                        }

                        Text(server.baseURL)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(MagpieTheme.textSecondary)
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            MagpieTag(text: KeychainStore.maskedPreview(store.webKey(for: server.id)), monospaced: true)
                            if server.allowInsecureTLS {
                                MagpieTag(text: "自签TLS", tone: MagpieTheme.warn)
                            }
                            Spacer()
                            Button("编辑") {
                                editingServer = server
                            }
                            .font(.system(size: 12))
                            .foregroundColor(MagpieTheme.textSecondary)
                            .buttonStyle(.plain)

                            Button("移除") {
                                serverPendingDelete = server
                            }
                            .font(.system(size: 12))
                            .foregroundColor(MagpieTheme.textMuted)
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Button("添加 magpie web 实例") {
                presentingNewServer = true
            }
            .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
        }
    }

    // MARK: - Remote Masking Controls

    private var maskingControlSection: some View {
        MinimalSection(title: "远程隐私脱敏", trailingText: store.remoteSettings.redact ? "已开启" : "已关闭") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("密钥与凭据脱敏 (redact)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(MagpieTheme.ink)
                    Text("自动掩码 API Key、Token 与私钥并还原响应")
                        .font(.system(size: 11.5))
                        .foregroundColor(MagpieTheme.textMuted)
                }
                Spacer()
                MagpieToggle(
                    isOn: Binding(
                        get: { store.remoteSettings.redact },
                        set: { val in
                            Task { await store.updatePrivacySettingsPatch(["redact": val]) }
                        }
                    )
                )
            }

            Rectangle().fill(MagpieTheme.hairline).frame(height: 1)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("个人信息脱敏 (redactPersonal)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(MagpieTheme.ink)
                    Text("邮箱、手机、证件与银行卡号")
                        .font(.system(size: 11.5))
                        .foregroundColor(MagpieTheme.textMuted)
                }
                Spacer()
                MagpieToggle(
                    isOn: Binding(
                        get: { store.remoteSettings.redactPersonal },
                        set: { val in
                            Task { await store.updatePrivacySettingsPatch(["redactPersonal": val]) }
                        }
                    )
                )
            }

            Rectangle().fill(MagpieTheme.hairline).frame(height: 1)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("保形假密钥 (redactShape)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(MagpieTheme.ink)
                    Text("将 sk_... 替换为同前缀假密钥而非占位符")
                        .font(.system(size: 11.5))
                        .foregroundColor(MagpieTheme.textMuted)
                }
                Spacer()
                MagpieToggle(
                    isOn: Binding(
                        get: { store.remoteSettings.redactShape },
                        set: { val in
                            Task { await store.updatePrivacySettingsPatch(["redactShape": val]) }
                        }
                    )
                )
            }

            Rectangle().fill(MagpieTheme.hairline).frame(height: 1)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("自定义前缀与正则规则 (\(store.remoteSettings.redactRules.count))")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(MagpieTheme.textSecondary)
                    Spacer()
                    Button("打开完整规则编辑器") {
                        activeWorkspace = .rules
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(MagpieTheme.ink)
                    .buttonStyle(.plain)
                }

                ForEach(store.remoteSettings.redactRules) { rule in
                    HStack {
                        MagpieTag(text: rule.kind)
                        Text(rule.prefix ?? rule.regex ?? "")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(MagpieTheme.ink)
                        Spacer()
                        Button("删除") {
                            let next = store.remoteSettings.redactRules.filter { $0.id != rule.id }
                            Task { await store.saveRedactRules(next) }
                        }
                        .font(.system(size: 11.5))
                        .foregroundColor(MagpieTheme.textMuted)
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 8) {
                    TextField("分类如 CORP_KEY", text: $newRuleKind)
                        .font(.system(size: 12.5, design: .monospaced))
                        .padding(8)
                        .background(MagpieTheme.canvas)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    TextField("前缀如 oc_sk_", text: $newRulePrefix)
                        .font(.system(size: 12.5, design: .monospaced))
                        .autocapitalization(.none)
                        .padding(8)
                        .background(MagpieTheme.canvas)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    Button("添加") {
                        let k = newRuleKind.trimmingCharacters(in: .whitespacesAndNewlines)
                        let p = newRulePrefix.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !k.isEmpty, !p.isEmpty else { return }
                        var next = store.remoteSettings.redactRules
                        next.append(RemoteRedactRule(kind: k, prefix: p, regex: nil))
                        newRuleKind = ""
                        newRulePrefix = ""
                        Task { await store.saveRedactRules(next) }
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
                }
            }

            Rectangle().fill(MagpieTheme.hairline).frame(height: 1)

            VStack(alignment: .leading, spacing: 8) {
                MagpieInputField(
                    label: "放行白名单（逗号分隔）",
                    placeholder: "例如：dev@company.com, 10086",
                    text: $allowText,
                    monospaced: true
                )
                Button("保存白名单") {
                    let list = allowText
                        .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == "，" })
                        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    Task { await store.saveRedactAllow(list) }
                }
                .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
            }
        }
    }

    // MARK: - Remote Masking Preview (`/api/masking/preview`)

    private var maskingPreviewSection: some View {
        MinimalSection(title: "服务端脱敏预览", trailingText: "/api/masking/preview") {
            MagpieInputField(
                label: "测试文本",
                placeholder: "输入包含密钥、邮箱或手机号的文本…",
                text: $previewInput
            )

            Button("发送服务端试测") {
                Task { await store.runMaskingPreview(text: previewInput) }
            }
            .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))

            if let preview = store.maskingPreview {
                VStack(alignment: .leading, spacing: 8) {
                    Text("命中 \(preview.hits.count) 处\(preview.off ? "（当前脱敏已关闭）" : "")")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(MagpieTheme.textSecondary)

                    Text(preview.text)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(MagpieTheme.ink)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(MagpieTheme.canvas)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    if !preview.hits.isEmpty {
                        ForEach(preview.hits) { hit in
                            HStack(spacing: 6) {
                                MagpieTag(text: hit.kind)
                                Text("\(hit.by) · \(hit.placeholder)")
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundColor(MagpieTheme.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Masking Records (`/api/masking/records`)

    private var maskingRecordsSection: some View {
        MinimalSection(
            title: "近 7 日脱敏记录 (\(store.maskingRecords.count))",
            trailingText: store.maskingSummary != nil ? "命中 \(store.maskingSummary?.n ?? 0) 处" : nil
        ) {
            if !store.maskingRecords.isEmpty {
                HStack {
                    Spacer()
                    Button("清空服务端记录") {
                        confirmClearRecords = true
                    }
                    .font(.system(size: 12))
                    .foregroundColor(MagpieTheme.textMuted)
                    .buttonStyle(.plain)
                }
            }

            if store.maskingRecords.isEmpty {
                Text("暂无远程脱敏命中记录")
                    .font(.system(size: 13))
                    .foregroundColor(MagpieTheme.textMuted)
            } else {
                ForEach(Array(store.maskingRecords.prefix(15).enumerated()), id: \.element.id) { idx, rec in
                    if idx > 0 {
                        Rectangle().fill(MagpieTheme.hairline).frame(height: 1)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(rec.model ?? rec.what)
                                .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                                .foregroundColor(MagpieTheme.ink)
                                .lineLimit(1)
                            Spacer()
                            if rec.blocked {
                                MagpieTag(text: "已拦截", tone: MagpieTheme.err)
                            } else {
                                MagpieTag(text: "脱敏 \(rec.n) 处")
                            }
                        }
                        Button("查看前后对照") { selectedRecord = rec }
                            .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))
                        if !rec.values.isEmpty {
                            Text(rec.values.map { "\($0.k)(\($0.b))" }.joined(separator: " · "))
                                .font(.system(size: 11.5))
                                .foregroundColor(MagpieTheme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Network, Proxies, Caller Keys & Bark Push

    private var networkAndBarkSection: some View {
        MinimalSection(title: "网关接入、代理池与 Bark 推送", trailingText: store.remoteSettings.lan ? "LAN 开启" : "仅本机") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("局域网共享网关")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(MagpieTheme.ink)
                    Text("允许局域网设备通过 Caller Key 调用网关")
                        .font(.system(size: 11.5))
                        .foregroundColor(MagpieTheme.textMuted)
                }
                Spacer()
                MagpieToggle(
                    isOn: Binding(
                        get: { store.remoteSettings.lan },
                        set: { val in
                            Task { await store.setLANEnabled(val) }
                        }
                    )
                )
            }

            Rectangle().fill(MagpieTheme.hairline).frame(height: 1)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("命名代理池 (\(store.remoteSettings.proxies.count) 个)")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundColor(MagpieTheme.ink)
                    Text("当前上游代理：\(store.remoteSettings.proxy.isEmpty ? "跟随系统" : store.remoteSettings.proxy)")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(MagpieTheme.textSecondary)
                }
                Spacer()
                Button("管理代理池") {
                    activeWorkspace = .proxies
                }
                .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
            }

            Rectangle().fill(MagpieTheme.hairline).frame(height: 1)

            HStack {
                Text("Caller Keys (\(store.callerKeys.count))")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(MagpieTheme.textSecondary)
                Spacer()
                Button("签发与管理") {
                    activeWorkspace = .callerKeys
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(MagpieTheme.ink)
                .buttonStyle(.plain)
            }

            if !store.callerKeys.isEmpty {
                ForEach(store.callerKeys) { ck in
                    Button {
                        activeWorkspace = .callerKeys
                    } label: {
                        HStack {
                            Text(ck.name.isEmpty ? ck.id : ck.name)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundColor(MagpieTheme.ink)
                            Spacer()
                            Text(ck.masked)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundColor(MagpieTheme.textMuted)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10))
                                .foregroundColor(MagpieTheme.textMuted)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Rectangle().fill(MagpieTheme.hairline).frame(height: 1)

            HStack(spacing: 8) {
                MagpieInputField(
                    label: "网关监听端口 (/api/settings/port)",
                    placeholder: "3425",
                    text: $portInput,
                    monospaced: true,
                    keyboardType: .numberPad
                )
                Button("保存端口") {
                    if let p = Int(portInput), p > 0 && p < 65536 {
                        Task { _ = await store.saveGatewayPort(p) }
                    }
                }
                .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
            }

            MagpieInputField(
                label: "IP 白名单（逗号分隔，空为不限制）",
                placeholder: "192.168.1.0/24, 100.64.0.0/10",
                text: $allowIPsInput,
                monospaced: true
            )
            Button("保存 IP 白名单") {
                Task { await store.saveAllowIPs(allowIPsInput) }
            }
            .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))

            MagpieInputField(
                label: "CORS 允许跨域 Origin（逗号分隔）",
                placeholder: "https://chat.example.com",
                text: $corsInput,
                monospaced: true
            )
            Button("保存 CORS 域名") {
                Task { await store.saveCORSOrigins(corsInput) }
            }
            .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))

            Rectangle().fill(MagpieTheme.hairline).frame(height: 1)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Bark iOS 推送")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundColor(MagpieTheme.ink)
                    Spacer()
                    if store.remoteSettings.barkKeySet {
                        MagpieTag(text: "Key 已配置", tone: MagpieTheme.ok)
                    }
                }

                MagpieInputField(label: "Bark 服务端", placeholder: "https://api.day.app", text: $barkServerInput, monospaced: true, keyboardType: .URL)
                MagpieInputField(label: "Device Key", placeholder: store.remoteSettings.barkKeySet ? "已保存（留空则保留）" : "输入 Bark Key", text: $barkKeyInput, isSecure: true, monospaced: true)
                MagpieInputField(label: "每日汇总时间", placeholder: "21:30（可选）", text: $barkDailyInput, monospaced: true)

                HStack(spacing: 10) {
                    Button("保存 Bark") {
                        Task {
                            await store.saveBarkConfig(server: barkServerInput, key: barkKeyInput, daily: barkDailyInput)
                            barkKeyInput = ""
                        }
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))

                    Button("测试推送") {
                        Task { await store.sendBarkTest() }
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))
                }
            }
        }
    }
}
