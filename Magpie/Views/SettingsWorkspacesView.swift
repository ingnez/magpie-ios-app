import SwiftUI
import UIKit

// MARK: - 1. Native Proxies & Network Pool Manager (`/api/proxies/*`, `/api/settings/*`)

struct ProxiesManagerView: View {
    @ObservedObject var store: GatewayStore
    @Environment(\.dismiss) private var dismiss

    @State private var globalProxy = ""
    @State private var pluginProxy = ""
    @State private var updateProxy = ""

    @State private var editingProxyID: String?
    @State private var proxyName = ""
    @State private var proxyURL = ""
    @State private var proxyUser = ""
    @State private var proxyPass = ""
    @State private var testStatusText: String?

    @State private var portInput = "3425"
    @State private var bareMode = "off"
    @State private var corsInput = ""
    @State private var githubTokenInput = ""
    @State private var busy = false
    @State private var errorMsg: String?

    var body: some View {
        NavigationView {
            Form {
                if let err = errorMsg {
                    Section {
                        Text(err).foregroundColor(.red).font(.caption)
                    }
                }

                Section(
                    header: Text("代理分流路由 (/api/settings)"),
                    footer: Text("当前生效上游代理：\(store.remoteSettings.proxyNow.isEmpty ? "直连/系统默认" : store.remoteSettings.proxyNow)（来源：\(store.remoteSettings.proxySource.isEmpty ? "默认" : store.remoteSettings.proxySource)）")
                ) {
                    Picker("上游请求代理 (proxy)", selection: $globalProxy) {
                        Text("跟随系统/环境变量").tag("")
                        Text("强制直连 (direct)").tag("direct")
                        ForEach(store.remoteSettings.proxies) { px in
                            Text("命名代理：\(px.name)").tag("@\(px.id)")
                        }
                    }
                    Picker("插件下载代理 (pluginProxy)", selection: $pluginProxy) {
                        Text("跟随上游代理").tag("")
                        Text("强制直连 (direct)").tag("direct")
                        ForEach(store.remoteSettings.proxies) { px in
                            Text("命名代理：\(px.name)").tag("@\(px.id)")
                        }
                    }
                    Picker("应用更新代理 (updateProxy)", selection: $updateProxy) {
                        Text("跟随上游代理").tag("")
                        Text("强制直连 (direct)").tag("direct")
                        ForEach(store.remoteSettings.proxies) { px in
                            Text("命名代理：\(px.name)").tag("@\(px.id)")
                        }
                    }
                    Button("保存代理分流设置") {
                        saveProxyRouting()
                    }
                }

                Section(header: Text("命名代理池 (\(store.remoteSettings.proxies.count)) · /api/proxies/*")) {
                    if store.remoteSettings.proxies.isEmpty {
                        Text("尚未保存任何命名代理").font(.caption).foregroundColor(.secondary)
                    } else {
                        ForEach(store.remoteSettings.proxies) { px in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(px.name).font(.headline)
                                    Spacer()
                                    if px.hasPass {
                                        Text("已设密码").font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                                Text(px.url).font(.caption.monospaced()).foregroundColor(.secondary)
                                if let check = px.check {
                                    Text(check.ok ? "测速通过：\(check.ms ?? 0) ms · \(check.ip ?? "") \(check.loc ?? "")" : "测速失败：\(check.error ?? "未知错误")")
                                        .font(.caption2.monospaced())
                                        .foregroundColor(check.ok ? MagpieTheme.ok : MagpieTheme.err)
                                }
                                HStack(spacing: 14) {
                                    Button("测速") { testExistingProxy(px) }
                                    Button("编辑") {
                                        editingProxyID = px.id
                                        proxyName = px.name
                                        proxyURL = px.url
                                        proxyUser = px.user
                                        proxyPass = ""
                                    }
                                    Spacer()
                                    Button("删除", role: .destructive) {
                                        Task { _ = await store.deleteNamedProxy(id: px.id, name: px.name) }
                                    }
                                }
                                .font(.caption)
                                .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section(header: Text(editingProxyID == nil ? "新增命名代理 (/api/proxies/save)" : "编辑代理：\(proxyName)")) {
                    TextField("代理名称（如 香港节点）", text: $proxyName)
                    TextField("代理地址（如 socks5://127.0.0.1:7890）", text: $proxyURL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("用户名（可选）", text: $proxyUser)
                        .autocapitalization(.none)
                    SecureField(editingProxyID == nil ? "密码（可选）" : "密码（留空保留原密码）", text: $proxyPass)

                    if let status = testStatusText {
                        Text(status).font(.caption.monospaced())
                    }

                    HStack {
                        Button("保存命名代理") {
                            saveProxyEntry()
                        }
                        .disabled(proxyName.trimmingCharacters(in: .whitespaces).isEmpty || proxyURL.trimmingCharacters(in: .whitespaces).isEmpty)

                        Spacer()

                        Button("测试连通性") {
                            testDraftProxy()
                        }
                        .disabled(proxyURL.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .buttonStyle(.borderless)

                    if editingProxyID != nil {
                        Button("取消编辑，切换为新增") {
                            editingProxyID = nil
                            proxyName = ""
                            proxyURL = ""
                            proxyUser = ""
                            proxyPass = ""
                        }
                        .font(.caption)
                    }
                }

                Section(header: Text("网关端口、裸模型 ID 与跨域 (/api/settings/*)")) {
                    HStack {
                        Text("网关端口")
                        Spacer()
                        TextField("3425", text: $portInput)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Button("保存端口") {
                            if let p = Int(portInput), p > 0 && p < 65536 {
                                Task { _ = await store.saveGatewayPort(p) }
                            }
                        }
                        .buttonStyle(.borderless)
                    }

                    Picker("无前缀裸模型 ID (/api/settings/bare-ids)", selection: $bareMode) {
                        Text("仅带 provider/ 前缀").tag("off")
                        Text("同时暴露裸模型 ID").tag("also")
                        Text("仅暴露裸模型 ID").tag("only")
                    }
                    .onChange(of: bareMode) { newValue in
                        updateBareMode(newValue)
                    }

                    TextField("CORS 允许域名（逗号分隔）", text: $corsInput)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    Button("保存 CORS 域名 (/api/settings/cors)") {
                        Task { await store.saveCORSOrigins(corsInput) }
                    }

                    SecureField("GitHub API Token（提升插件/仓库限额）", text: $githubTokenInput)
                        .autocapitalization(.none)
                    Button("保存 GitHub Token (/api/settings/github-token)") {
                        Task {
                            if await store.saveGitHubToken(githubTokenInput) {
                                githubTokenInput = ""
                            }
                        }
                    }
                }
            }
            .disabled(busy)
            .navigationTitle("代理池与网络配置")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear {
                syncFromStore()
            }
        }
        .navigationViewStyle(.stack)
    }

    private func syncFromStore() {
        let s = store.remoteSettings
        globalProxy = s.proxy
        pluginProxy = s.pluginProxy
        updateProxy = s.updateProxy
        portInput = String(s.port)
        corsInput = s.corsOrigins.joined(separator: ", ")
        if s.bareModelIDsOnly {
            bareMode = "only"
        } else if s.bareModelIDs {
            bareMode = "also"
        } else {
            bareMode = "off"
        }
    }

    private func saveProxyRouting() {
        busy = true; errorMsg = nil
        Task {
            defer { busy = false }
            do {
                store.remoteSettings = try await store.client.patchSettings([
                    "proxy": globalProxy,
                    "pluginProxy": pluginProxy,
                    "updateProxy": updateProxy
                ])
                syncFromStore()
                store.showToast("已保存代理分流路由")
            } catch {
                errorMsg = error.localizedDescription
            }
        }
    }

    private func saveProxyEntry() {
        let cleanName = proxyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanURL = proxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUser = proxyUser.trimmingCharacters(in: .whitespacesAndNewlines)
        let passOpt: String? = proxyPass.isEmpty ? nil : proxyPass
        busy = true; errorMsg = nil
        Task {
            defer { busy = false }
            let ok = await store.saveNamedProxy(id: editingProxyID, name: cleanName, url: cleanURL, user: cleanUser, pass: passOpt)
            if ok {
                editingProxyID = nil
                proxyName = ""
                proxyURL = ""
                proxyUser = ""
                proxyPass = ""
                syncFromStore()
            } else {
                errorMsg = store.lastActionError
            }
        }
    }

    private func testExistingProxy(_ px: RemoteSavedProxy) {
        busy = true; errorMsg = nil
        Task {
            defer { busy = false }
            do {
                let res = try await store.client.testProxy(id: px.id)
                testStatusText = res.ok
                    ? "[\(px.name)] 测速通过：\(res.ms ?? 0) ms · \(res.ip ?? "") \(res.loc ?? "")"
                    : "[\(px.name)] 失败：\(res.error ?? "不可达")"
                await store.refreshSettings()
            } catch {
                errorMsg = error.localizedDescription
            }
        }
    }

    private func testDraftProxy() {
        busy = true; errorMsg = nil
        Task {
            defer { busy = false }
            do {
                let res = try await store.client.testProxy(
                    id: editingProxyID,
                    name: proxyName,
                    url: proxyURL.trimmingCharacters(in: .whitespacesAndNewlines),
                    user: proxyUser.trimmingCharacters(in: .whitespacesAndNewlines),
                    pass: proxyPass.isEmpty ? nil : proxyPass
                )
                testStatusText = res.ok
                    ? "测试通过：\(res.ms ?? 0) ms · 出口 \(res.ip ?? "") \(res.loc ?? "")"
                    : "测试失败：\(res.error ?? "未通过代理")"
            } catch {
                errorMsg = error.localizedDescription
            }
        }
    }

    private func updateBareMode(_ mode: String) {
        let on = (mode == "also" || mode == "only")
        let only = (mode == "only")
        Task {
            do {
                store.remoteSettings = try await store.client.updateBareIDs(on: on, only: only)
                store.showToast("已更新裸模型 ID 暴露策略")
            } catch {
                errorMsg = error.localizedDescription
            }
        }
    }
}

// MARK: - 2. Native Backup, AutoBackup & WebDAV/S3/GitHub Sync (`/api/backup/*`, `/api/autobackup/*`, `/api/davsync/*`)

struct BackupSyncView: View {
    @ObservedObject var store: GatewayStore
    @Environment(\.dismiss) private var dismiss

    @State private var davSync = RemoteDavSyncView()
    @State private var autoBackup = RemoteAutoBackupView()

    // DavSync form drafts
    @State private var syncURL = ""
    @State private var syncUser = ""
    @State private var syncPassword = ""
    @State private var syncPassphrase = ""
    @State private var syncKeys = true
    @State private var syncAgents = true
    @State private var syncProviders = true
    @State private var syncSettings = true
    @State private var syncProfiles = true
    @State private var syncLibrary = true
    @State private var syncMemory = true
    @State private var syncUsage = false
    @State private var syncSignIns = false
    @State private var syncAutoMinutes = 15
    @State private var followServer = false

    // AutoBackup form drafts
    @State private var autoOn = true
    @State private var autoHours = 24
    @State private var autoKeep = 7
    @State private var autoSignIns = false
    @State private var autoPassphrase = ""

    // Manual Export/Import
    @State private var exportPass = ""
    @State private var exportKeys = true
    @State private var exportSignIns = false
    @State private var exportResultText: String?

    @State private var importBase64 = ""
    @State private var importPass = ""
    @State private var importResultText: String?

    @State private var busy = false
    @State private var errorMsg: String?

    var body: some View {
        NavigationView {
            Form {
                if let err = errorMsg {
                    Section {
                        Text(err).foregroundColor(.red).font(.caption)
                    }
                }

                Section(
                    header: Text("WebDAV / S3 / GitHub 云同步 (/api/davsync)"),
                    footer: Text(davSync.on ? "当前状态：已开启（\(davSync.kind.uppercased())）· 上次同步：\(davSync.last ?? "刚刚")" : "当前未启用跨端云同步")
                ) {
                    TextField("同步地址（https:// WebDAV、s3:// 或 github://）", text: $syncURL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("用户名 / Access Key ID", text: $syncUser)
                        .autocapitalization(.none)
                    SecureField(davSync.passwordSet ? "服务器密码 / Token（已保存，留空保留）" : "服务器密码 / S3 Secret / GitHub Token", text: $syncPassword)
                    SecureField(davSync.passphraseSet ? "加密口令 Passphrase（已保存，留空保留）" : "端到端加密口令 Passphrase", text: $syncPassphrase)

                    Toggle("包含供应商与路由组", isOn: $syncProviders)
                    Toggle("包含 API Keys 密钥", isOn: $syncKeys)
                    Toggle("包含 Agents 模型绑定", isOn: $syncAgents)
                    Toggle("包含 Profiles 方案与系统设置", isOn: $syncSettings)
                    Toggle("包含 Library 与 Memory", isOn: $syncLibrary)
                    Toggle("跨设备共享用量账单 (usage)", isOn: $syncUsage)

                    Button("保存并立即同步 (/api/davsync/save)") {
                        saveAndSyncWebDAV()
                    }
                    .disabled(syncURL.trimmingCharacters(in: .whitespaces).isEmpty)

                    Picker("自动同步间隔 (/api/davsync/auto)", selection: $syncAutoMinutes) {
                        Text("仅手动").tag(-1)
                        Text("每 3 分钟").tag(3)
                        Text("每 15 分钟").tag(15)
                        Text("每 30 分钟").tag(30)
                        Text("每 60 分钟").tag(60)
                    }
                    .onChange(of: syncAutoMinutes) { mins in
                        runDavAction("auto", payload: ["minutes": mins], toast: "已更新自动同步频率")
                    }

                    Toggle("仅单向跟随服务端 (follow-server)", isOn: $followServer)
                        .onChange(of: followServer) { val in
                            runDavAction("follow-server", payload: ["on": val], toast: val ? "已开启单向跟随服务端" : "已恢复双向同步")
                        }

                    HStack {
                        Button("立即同步") {
                            runDavAction("now", toast: "已完成云端同步")
                        }
                        Spacer()
                        Button("从云端恢复") {
                            runDavAction("restore", toast: "已从云端拉取并恢复配置")
                        }
                        Spacer()
                        Button("上传覆盖") {
                            runDavAction("upload", toast: "已将本机配置上传覆盖云端")
                        }
                        if davSync.on {
                            Spacer()
                            Button("停用", role: .destructive) {
                                runDavAction("off", toast: "已停用云同步")
                            }
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }

                Section(
                    header: Text("服务端定时自动备份 (/api/autobackup)"),
                    footer: Text("备份目录：\(autoBackup.dir.isEmpty ? "~/.config/magpie/auto-backups" : autoBackup.dir)")
                ) {
                    Toggle("开启定时自动备份", isOn: $autoOn)
                    Picker("备份周期", selection: $autoHours) {
                        Text("每 1 小时").tag(1)
                        Text("每 6 小时").tag(6)
                        Text("每 24 小时").tag(24)
                        Text("每 7 天").tag(168)
                    }
                    Picker("保留份数", selection: $autoKeep) {
                        Text("3 份").tag(3)
                        Text("7 份").tag(7)
                        Text("14 份").tag(14)
                        Text("30 份").tag(30)
                    }
                    Toggle("包含订阅与插件登录态 (signIns)", isOn: $autoSignIns)
                    if autoSignIns {
                        SecureField(autoBackup.passphrase ? "登录态加密口令（已设，留空保留）" : "设置登录态加密口令", text: $autoPassphrase)
                    }

                    HStack {
                        Button("保存自动备份策略") {
                            saveAutoBackupConfig()
                        }
                        Spacer()
                        Button("立即备份一次") {
                            triggerAutoBackupNow()
                        }
                    }
                    .buttonStyle(.borderless)

                    if !autoBackup.backups.isEmpty {
                        ForEach(autoBackup.backups) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).font(.caption.monospaced()).lineLimit(1)
                                    Text("\(item.providers) 个供应商 · \(item.size / 1024) KB").font(.caption2).foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("恢复此备份") {
                                    restoreAutoBackupItem(item)
                                }
                                .font(.caption)
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }

                Section(
                    header: Text("加密备份导出 (/api/backup/export)"),
                    footer: Text("将完整配置用口令加密后写入服务器 Downloads 目录。")
                ) {
                    SecureField("设置导出加密口令 Passphrase", text: $exportPass)
                    Toggle("导出 API Keys 与网关密钥", isOn: $exportKeys)
                    Toggle("导出订阅与插件登录态", isOn: $exportSignIns)
                    Button("导出加密备份到服务器") {
                        runExportBackup()
                    }
                    .disabled(exportPass.trimmingCharacters(in: .whitespaces).isEmpty)

                    if let text = exportResultText {
                        Text(text).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }

                Section(header: Text("加密备份导入 (/api/backup/import)")) {
                    TextField("粘贴备份文件 Base64 内容", text: $importBase64)
                        .font(.caption.monospaced())
                        .autocapitalization(.none)
                    SecureField("输入备份解密口令 Passphrase", text: $importPass)
                    Button("解密并恢复备份") {
                        runImportBackup()
                    }
                    .disabled(importBase64.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || importPass.isEmpty)

                    if let text = importResultText {
                        Text(text).font(.caption.monospaced())
                    }
                }
            }
            .disabled(busy)
            .navigationTitle("备份与云同步")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task {
                await loadSyncAndBackup()
            }
        }
        .navigationViewStyle(.stack)
    }

    private func loadSyncAndBackup() async {
        do {
            async let d = store.client.fetchDavSync()
            async let a = store.client.fetchAutoBackup()
            let (dav, auto) = try await (d, a)
            applyDavView(dav)
            applyAutoView(auto)
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    private func applyDavView(_ v: RemoteDavSyncView) {
        davSync = v
        if !v.url.isEmpty { syncURL = v.url }
        if !v.user.isEmpty { syncUser = v.user }
        syncKeys = v.keys
        syncAgents = v.agents
        syncProviders = v.providers
        syncSettings = v.settings
        syncProfiles = v.profiles
        syncLibrary = v.library
        syncMemory = v.memory
        syncUsage = v.usage
        syncSignIns = v.signIns
        syncAutoMinutes = v.auto == 0 ? -1 : v.auto
        followServer = v.followServer
    }

    private func applyAutoView(_ v: RemoteAutoBackupView) {
        autoBackup = v
        autoOn = v.on
        autoHours = v.hours
        autoKeep = v.keep
        autoSignIns = v.signIns
    }

    private func saveAndSyncWebDAV() {
        busy = true; errorMsg = nil
        Task {
            defer { busy = false }
            do {
                let payload: [String: Any] = [
                    "url": syncURL.trimmingCharacters(in: .whitespacesAndNewlines),
                    "user": syncUser.trimmingCharacters(in: .whitespacesAndNewlines),
                    "password": syncPassword,
                    "passphrase": syncPassphrase,
                    "keys": syncKeys,
                    "agents": syncAgents,
                    "providers": syncProviders,
                    "settings": syncSettings,
                    "profiles": syncProfiles,
                    "library": syncLibrary,
                    "memory": syncMemory,
                    "usage": syncUsage,
                    "signIns": syncSignIns
                ]
                let v = try await store.client.davSyncAction("save", payload: payload)
                applyDavView(v)
                syncPassword = ""
                syncPassphrase = ""
                store.showToast("已保存云同步配置并完成同步")
            } catch {
                errorMsg = error.localizedDescription
            }
        }
    }

    private func runDavAction(_ action: String, payload: [String: Any] = [:], toast: String) {
        busy = true; errorMsg = nil
        Task {
            defer { busy = false }
            do {
                let v = try await store.client.davSyncAction(action, payload: payload)
                applyDavView(v)
                store.showToast(toast)
            } catch {
                errorMsg = error.localizedDescription
            }
        }
    }

    private func saveAutoBackupConfig() {
        busy = true; errorMsg = nil
        Task {
            defer { busy = false }
            do {
                var payload: [String: Any] = [
                    "on": autoOn,
                    "hours": autoHours,
                    "keep": autoKeep,
                    "signIns": autoSignIns
                ]
                if !autoPassphrase.isEmpty {
                    payload["passphrase"] = autoPassphrase
                }
                let v = try await store.client.autoBackupAction("set", payload: payload)
                applyAutoView(v)
                autoPassphrase = ""
                store.showToast("已保存自动备份设置")
            } catch {
                errorMsg = error.localizedDescription
            }
        }
    }

    private func triggerAutoBackupNow() {
        busy = true; errorMsg = nil
        Task {
            defer { busy = false }
            do {
                let v = try await store.client.autoBackupAction("now")
                applyAutoView(v)
                store.showToast("已生成最新自动备份")
            } catch {
                errorMsg = error.localizedDescription
            }
        }
    }

    private func restoreAutoBackupItem(_ item: RemoteAutoBackupItem) {
        busy = true; errorMsg = nil
        Task {
            defer { busy = false }
            do {
                let v = try await store.client.autoBackupAction("restore", payload: ["name": item.name])
                applyAutoView(v)
                await store.connectAndRefreshAll()
                store.showToast("已恢复备份「\(item.name)」")
            } catch {
                errorMsg = error.localizedDescription
            }
        }
    }

    private func runExportBackup() {
        busy = true; errorMsg = nil
        Task {
            defer { busy = false }
            do {
                let res = try await store.client.exportBackup(
                    pass: exportPass,
                    keys: exportKeys,
                    library: true,
                    memory: true,
                    signIns: exportSignIns
                )
                exportResultText = "已导出至：\(res.path)（\(res.providers) 供应商 · \(res.profiles) 方案 · \(res.agents) Agents）"
                store.showToast("加密备份已导出")
            } catch {
                errorMsg = error.localizedDescription
            }
        }
    }

    private func runImportBackup() {
        busy = true; errorMsg = nil
        Task {
            defer { busy = false }
            do {
                let res = try await store.client.importBackup(
                    base64Data: importBase64.trimmingCharacters(in: .whitespacesAndNewlines),
                    pass: importPass
                )
                importResultText = "已恢复 \(res.providers) 个供应商、\(res.profiles) 个方案、\(res.agents) 个 Agent"
                await store.connectAndRefreshAll()
                store.showToast("已完成备份导入恢复")
            } catch {
                errorMsg = error.localizedDescription
            }
        }
    }
}

// MARK: - 3. Native Context & Prompt Cache Tuning (`/api/tune/*`, `/api/settings/claude-*`, `/api/settings/full-context`)

struct ContextTuneView: View {
    @ObservedObject var store: GatewayStore
    @Environment(\.dismiss) private var dismiss

    @State private var days = 7
    @State private var tuneState = RemoteTuneState()
    @State private var mainCacheTTL = "5m"
    @State private var subCacheTTL = "5m"
    @State private var claudeAttributionOn = true
    @State private var fullContext = false
    @State private var compactAtInput = "272000"
    @State private var contextCapInput = "0"
    @State private var contextCapAll = false
    @State private var codexAsyncOn = false
    @State private var codexAsyncPercentInput = "65"

    @State private var busy = false
    @State private var errorMsg: String?

    var body: some View {
        NavigationView {
            Form {
                if let err = errorMsg {
                    Section {
                        Text(err).foregroundColor(.red).font(.caption)
                    }
                }

                Section(header: Text("回放分析周期 (/api/tune)")) {
                    Picker("分析天数", selection: $days) {
                        Text("近 7 天").tag(7)
                        Text("近 14 天").tag(14)
                        Text("近 30 天").tag(30)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: days) { _ in
                        Task { await loadTune() }
                    }
                }

                if tuneState.agents.isEmpty {
                    Section(header: Text("智能调优建议")) {
                        Text(tuneState.gateway ? "当前处于纯网关模式，客户端会话文件不在本机。" : "当前周期内暂无足够的客户端会话采样数据。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    ForEach(tuneState.agents) { agentGroup in
                        Section(header: Text("\(agentGroup.agent.uppercased()) 调优建议（\(agentGroup.calls) 次调用）")) {
                            ForEach(agentGroup.advice) { adv in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("\(adv.knob)\(adv.model.map { " · \($0)" } ?? "")")
                                            .font(.headline)
                                        Spacer()
                                        if adv.setting.ours {
                                            Text("已由 Magpie 调优").font(.caption2).foregroundColor(MagpieTheme.ok)
                                        }
                                    }

                                    if let c = adv.compact {
                                        Text("当前压缩阈值：\(c.current) Tokens → 推荐：\(c.best) Tokens")
                                            .font(.caption.monospaced())
                                        Text(String(format: "预计加权成本：%.1f → %.1f", c.cost, c.low))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }

                                    if let t = adv.ttl {
                                        Text("当前缓存 TTL：\(t.current) → 推荐：\(t.best)")
                                            .font(.caption.monospaced())
                                        Text(String(format: "5m 成本 %.1f vs 1h 成本 %.1f", t.short, t.hour))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }

                                    HStack(spacing: 12) {
                                        if let c = adv.compact {
                                            Button("应用推荐值 (\(c.best))") {
                                                applyAdvice(agent: agentGroup.agent, knob: adv.knob, model: adv.model ?? "", value: String(c.best))
                                            }
                                        } else if let t = adv.ttl {
                                            Button("应用推荐缓存 (\(t.best))") {
                                                applyAdvice(agent: agentGroup.agent, knob: adv.knob, model: adv.model ?? "", value: t.best)
                                            }
                                        }

                                        if adv.setting.take {
                                            Button("接管配置") {
                                                takeOver(agent: agentGroup.agent, knob: adv.knob, model: adv.model ?? "")
                                            }
                                        }

                                        if adv.setting.ours {
                                            Button("撤销调优", role: .destructive) {
                                                undoAdvice(agent: agentGroup.agent, knob: adv.knob, model: adv.model ?? "")
                                            }
                                        }
                                    }
                                    .font(.caption)
                                    .buttonStyle(.borderless)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }

                Section(header: Text("Claude Code 缓存与归属签名 (/api/settings/claude-*)")) {
                    Picker("主对话 Prompt 缓存 (cache_ttl)", selection: $mainCacheTTL) {
                        Text("默认 (5m)").tag("5m")
                        Text("长效 (1h)").tag("1h")
                    }
                    .onChange(of: mainCacheTTL) { val in
                        saveClaudeCache(knob: "cache_ttl", value: val)
                    }

                    Picker("子代理 Prompt 缓存 (subagent_cache_ttl)", selection: $subCacheTTL) {
                        Text("默认 (5m)").tag("5m")
                        Text("长效 (1h)").tag("1h")
                    }
                    .onChange(of: subCacheTTL) { val in
                        saveClaudeCache(knob: "subagent_cache_ttl", value: val)
                    }

                    Toggle("附加 Claude Co-Authored-By 提交签名", isOn: $claudeAttributionOn)
                        .onChange(of: claudeAttributionOn) { val in
                            saveClaudeAttribution(val)
                        }
                }

                Section(header: Text("长对话自动压缩与窗口上限 (/api/settings/*)")) {
                    Toggle("使用完整上下文窗口 (fullContext)", isOn: $fullContext)
                    HStack {
                        Text("自动压缩阈值 (compactAt)")
                        Spacer()
                        TextField("272000", text: $compactAtInput)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 110)
                    }
                    Button("保存长对话压缩设置 (/api/settings/full-context)") {
                        saveFullContext()
                    }

                    HStack {
                        Text("全局最大上下文 (contextCap)")
                        Spacer()
                        TextField("0 为不限", text: $contextCapInput)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 110)
                    }
                    Toggle("限制同时作用于手动指定窗口", isOn: $contextCapAll)
                    Button("保存最大上下文限制 (/api/settings/context-cap)") {
                        saveContextCap()
                    }
                }

                Section(header: Text("Codex 后台异步压缩 (/api/settings/codex-async-compact)")) {
                    Toggle("开启 Codex 后台异步压缩", isOn: $codexAsyncOn)
                    HStack {
                        Text("触发窗口占比 (%)")
                        Spacer()
                        TextField("65", text: $codexAsyncPercentInput)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    Button("保存 Codex 异步压缩设置") {
                        saveCodexAsync()
                    }
                }
            }
            .disabled(busy)
            .navigationTitle("上下文与缓存调优")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task {
                syncFromStore()
                await loadTune()
            }
        }
        .navigationViewStyle(.stack)
    }

    private func syncFromStore() {
        let s = store.remoteSettings
        if let main = s.claudeCache.first(where: { $0.knob == "cache_ttl" }), !main.value.isEmpty {
            mainCacheTTL = main.value
        }
        if let sub = s.claudeCache.first(where: { $0.knob == "subagent_cache_ttl" }), !sub.value.isEmpty {
            subCacheTTL = sub.value
        }
        claudeAttributionOn = s.claudeAttribution != "off"
        fullContext = s.fullContext
        compactAtInput = String(s.compactAt > 0 ? s.compactAt : 272000)
        contextCapInput = String(s.contextCap)
        contextCapAll = s.contextCapAll
        codexAsyncOn = s.codexAsyncCompact
        codexAsyncPercentInput = String(s.codexAsyncCompactPercent > 0 ? s.codexAsyncCompactPercent : 65)
    }

    private func loadTune() async {
        do {
            tuneState = try await store.client.fetchTune(days: days)
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    private func applyAdvice(agent: String, knob: String, model: String, value: String) {
        busy = true; errorMsg = nil
        Task {
            defer { busy = false }
            do {
                _ = try await store.client.applyTune(agent: agent, knob: knob, model: model, value: value)
                await loadTune()
                await store.refreshSettings()
                store.showToast("已应用「\(knob)」调优推荐值")
            } catch {
                errorMsg = error.localizedDescription
            }
        }
    }

    private func takeOver(agent: String, knob: String, model: String) {
        busy = true; errorMsg = nil
        Task {
            defer { busy = false }
            do {
                _ = try await store.client.takeOverTune(agent: agent, knob: knob, model: model)
                await loadTune()
                store.showToast("已由 Magpie 接管该项配置")
            } catch {
                errorMsg = error.localizedDescription
            }
        }
    }

    private func undoAdvice(agent: String, knob: String, model: String) {
        busy = true; errorMsg = nil
        Task {
            defer { busy = false }
            do {
                _ = try await store.client.undoTune(agent: agent, knob: knob, model: model)
                await loadTune()
                store.showToast("已撤销调优并恢复原值")
            } catch {
                errorMsg = error.localizedDescription
            }
        }
    }

    private func saveClaudeCache(knob: String, value: String) {
        Task {
            do {
                store.remoteSettings = try await store.client.updateClaudeCache(knob: knob, value: value)
                store.showToast("已更新 Claude 缓存周期")
            } catch {
                errorMsg = error.localizedDescription
            }
        }
    }

    private func saveClaudeAttribution(_ on: Bool) {
        Task {
            do {
                store.remoteSettings = try await store.client.updateClaudeAttribution(on: on)
                store.showToast(on ? "已开启 Claude 提交签名" : "已关闭 Claude 提交签名")
            } catch {
                errorMsg = error.localizedDescription
            }
        }
    }

    private func saveFullContext() {
        let at = Int(compactAtInput) ?? 272000
        busy = true; errorMsg = nil
        Task {
            defer { busy = false }
            do {
                store.remoteSettings = try await store.client.updateFullContext(on: fullContext, at: at)
                store.showToast("已保存长对话压缩配置")
            } catch {
                errorMsg = error.localizedDescription
            }
        }
    }

    private func saveContextCap() {
        let cap = max(0, Int(contextCapInput) ?? 0)
        busy = true; errorMsg = nil
        Task {
            defer { busy = false }
            do {
                _ = try await store.client.updateContextCap(at: cap)
                store.remoteSettings = try await store.client.updateContextCapMode(all: contextCapAll)
                store.showToast("已保存最大上下文窗口上限")
            } catch {
                errorMsg = error.localizedDescription
            }
        }
    }

    private func saveCodexAsync() {
        let pct = max(1, min(100, Int(codexAsyncPercentInput) ?? 65))
        busy = true; errorMsg = nil
        Task {
            defer { busy = false }
            do {
                store.remoteSettings = try await store.client.updateCodexAsyncCompact(on: codexAsyncOn, percent: pct)
                store.showToast("已保存 Codex 后台异步压缩设置")
            } catch {
                errorMsg = error.localizedDescription
            }
        }
    }
}

// MARK: - 4. Native System, Allowances, Alerts, Models & Search Settings (`/api/settings/*`)

struct SystemSettingsEditorView: View {
    @ObservedObject var store: GatewayStore
    @Environment(\.dismiss) private var dismiss

    // General & Appearance
    @State private var theme = "system"
    @State private var lang = "system"
    @State private var currency = "usd"
    @State private var totalCurrency = "usd"
    @State private var chineseUnits = false
    @State private var dayStart = 0
    @State private var colorblind = false
    @State private var reduceMotion = false
    @State private var gatewayMode = ""
    @State private var plainNames = false

    // Allowances & Alerts
    @State private var quotaLeft = false
    @State private var quotaReads = ""
    @State private var usageAlertInput = "80"
    @State private var balanceAlertInput = "5.0"
    @State private var resetReminderInput = "30"
    @State private var turnDoneAlertInput = "60"
    @State private var maskAlert = false

    // Routing, Search & Codex
    @State private var busyLoadInput = "0"
    @State private var disabledModelsInput = ""
    @State private var searchAll = false
    @State private var searchCountInput = "5"
    @State private var searchVendor = "tavily"
    @State private var searchKeyInput = ""
    @State private var codexServiceTier = ""
    @State private var codexAgentsV1 = false
    @State private var codexTitles = ""
    @State private var codexAutoReview = ""

    // Privacy & Archive & Updates
    @State private var redactRouteTo = ""
    @State private var agentTelemetryOff = false
    @State private var noAccountDiscovery = false
    @State private var requestArchiveOn = false
    @State private var privacyModel = RemotePrivacyModelResponse()
    @State private var updateMirrorInput = ""
    @State private var updateChannel = ""
    @State private var noAutoUpdate = false

    @State private var busy = false
    @State private var errorMsg: String?

    var body: some View {
        NavigationView {
            Form {
                if let err = errorMsg {
                    Section {
                        Text(err).foregroundColor(.red).font(.caption)
                    }
                }

                Section(header: Text("通用外观、语言与计价单位 (/api/settings)")) {
                    Picker("主题外观 (theme)", selection: $theme) {
                        Text("跟随系统").tag("system")
                        Text("浅色 (light)").tag("light")
                        Text("深色 (dark)").tag("dark")
                    }
                    Picker("界面语言 (lang)", selection: $lang) {
                        Text("跟随系统").tag("system")
                        Text("简体中文").tag("zh")
                        Text("English").tag("en")
                    }
                    Picker("账单币种 (currency)", selection: $currency) {
                        Text("美元 (USD)").tag("usd")
                        Text("人民币 (CNY)").tag("cny")
                        Text("按供应商原生币种").tag("provider")
                    }
                    Picker("汇总币种 (totalCurrency)", selection: $totalCurrency) {
                        Text("美元 (USD)").tag("usd")
                        Text("人民币 (CNY)").tag("cny")
                    }
                    Picker("每日统计起点 (dayStart)", selection: $dayStart) {
                        ForEach(0..<7, id: \.self) { hour in
                            Text("凌晨 \(hour):00").tag(hour)
                        }
                    }
                    Toggle("中文万/亿数量单位 (chineseUnits)", isOn: $chineseUnits)
                    Toggle("色觉辅助色板 (colorblind)", isOn: $colorblind)
                    Toggle("减弱动态效果 (reduceMotion)", isOn: $reduceMotion)

                    Button("保存通用与显示设置") {
                        saveGeneralSettings()
                    }

                    Picker("Web 网关模式 (/api/settings/gateway-mode)", selection: $gatewayMode) {
                        Text("自动判断").tag("")
                        Text("仅网关模式 (on)").tag("on")
                        Text("完整桌面模式 (off)").tag("off")
                    }
                    .onChange(of: gatewayMode) { mode in
                        Task {
                            do {
                                store.remoteSettings = try await store.client.updateGatewayMode(mode)
                                store.showToast("已更新 Web 网关模式")
                            } catch { errorMsg = error.localizedDescription }
                        }
                    }

                    Toggle("使用简洁模型名称 (/api/settings/plain-names)", isOn: $plainNames)
                        .onChange(of: plainNames) { val in
                            Task {
                                do {
                                    store.remoteSettings = try await store.client.updatePlainNames(on: val)
                                    store.showToast("已更新模型名称显示格式")
                                } catch { errorMsg = error.localizedDescription }
                            }
                        }
                }

                Section(header: Text("套餐额度读取与告警通知 (/api/settings/*)")) {
                    Toggle("额度进度显示为「剩余百分比」 (/api/settings/quota-left)", isOn: $quotaLeft)
                        .onChange(of: quotaLeft) { val in
                            Task {
                                do {
                                    store.remoteSettings = try await store.client.updateQuotaLeft(val)
                                    store.showToast(val ? "已切换为显示剩余额度" : "已切换为显示已用额度")
                                } catch { errorMsg = error.localizedDescription }
                            }
                        }

                    Picker("额度读取时机 (/api/settings/quota-reads)", selection: $quotaReads) {
                        Text("自动按需读取").tag("")
                        Text("仅手动刷新时读取 (asked)").tag("asked")
                    }
                    .onChange(of: quotaReads) { val in
                        Task {
                            do {
                                store.remoteSettings = try await store.client.updateQuotaReads(val)
                                store.showToast("已更新额度读取策略")
                            } catch { errorMsg = error.localizedDescription }
                        }
                    }

                    HStack {
                        Text("订阅额度告警阈值 (%)")
                        Spacer()
                        TextField("80", text: $usageAlertInput)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    HStack {
                        Text("低余额告警阈值 ($)")
                        Spacer()
                        TextField("5.0", text: $balanceAlertInput)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    HStack {
                        Text("额度重置前提醒 (分钟)")
                        Spacer()
                        TextField("30", text: $resetReminderInput)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    HStack {
                        Text("长任务完成提醒 (秒)")
                        Spacer()
                        TextField("60", text: $turnDoneAlertInput)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    Toggle("隐私脱敏命中时发送通知 (maskAlert)", isOn: $maskAlert)

                    Button("保存告警阈值设置") {
                        saveAlertSettings()
                    }
                }

                Section(header: Text("模型路由、联网搜索与 Codex 专项 (/api/settings/*)")) {
                    HStack {
                        Text("高负载模型后置阈值 (%)")
                        Spacer()
                        TextField("0 为关闭", text: $busyLoadInput)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Button("保存") {
                            let val = max(0, Int(busyLoadInput) ?? 0)
                            Task {
                                do {
                                    store.remoteSettings = try await store.client.updateBusyLoad(at: val)
                                    store.showToast("已更新高负载后置阈值")
                                } catch { errorMsg = error.localizedDescription }
                            }
                        }
                        .buttonStyle(.borderless)
                    }

                    TextField("全局禁用模型（逗号分隔，支持通配符）", text: $disabledModelsInput)
                        .autocapitalization(.none)
                    Button("保存禁用模型列表 (/api/settings/disabled-models)") {
                        let list = disabledModelsInput
                            .split(whereSeparator: { $0 == "," || $0 == "\n" })
                            .map { String($0).trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        Task {
                            do {
                                store.remoteSettings = try await store.client.updateDisabledModels(list)
                                store.showToast("已保存禁用模型列表")
                            } catch { errorMsg = error.localizedDescription }
                        }
                    }

                    Toggle("为无搜索能力的模型开启联网搜索 (/api/settings/search-all)", isOn: $searchAll)
                        .onChange(of: searchAll) { val in
                            Task {
                                do {
                                    store.remoteSettings = try await store.client.updateSearchAll(val)
                                    store.showToast(val ? "已开启全局联网搜索兜底" : "已关闭全局联网搜索兜底")
                                } catch { errorMsg = error.localizedDescription }
                            }
                        }

                    HStack {
                        Text("单次搜索结果条数")
                        Spacer()
                        TextField("5", text: $searchCountInput)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                        Button("保存条数") {
                            let n = max(1, min(20, Int(searchCountInput) ?? 5))
                            Task {
                                do {
                                    store.remoteSettings = try await store.client.updateSearchCount(n)
                                    store.showToast("已更新搜索结果条数为 \(n)")
                                } catch { errorMsg = error.localizedDescription }
                            }
                        }
                        .buttonStyle(.borderless)
                    }

                    Picker("新增搜索服务商", selection: $searchVendor) {
                        Text("Tavily").tag("tavily")
                        Text("Brave Search").tag("brave")
                        Text("Exa").tag("exa")
                        Text("Serper").tag("serper")
                        Text("Bocha 博查").tag("bocha")
                    }
                    SecureField("输入搜索 API Key", text: $searchKeyInput)
                        .autocapitalization(.none)
                    Button("保存搜索 API (/api/settings/search-api)") {
                        Task {
                            do {
                                store.remoteSettings = try await store.client.updateSearchAPI(
                                    vendor: searchVendor,
                                    key: searchKeyInput.trimmingCharacters(in: .whitespacesAndNewlines),
                                    on: true
                                )
                                searchKeyInput = ""
                                store.showToast("已配置搜索服务 \(searchVendor)")
                            } catch { errorMsg = error.localizedDescription }
                        }
                    }
                    .disabled(searchKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)

                    Picker("Codex 服务档位 (/api/settings/codex-service-tier)", selection: $codexServiceTier) {
                        Text("跟随客户端请求").tag("")
                        Text("标准档 (default)").tag("default")
                        Text("优先档 (priority)").tag("priority")
                        Text("极速档 (ultrafast)").tag("ultrafast")
                    }
                    .onChange(of: codexServiceTier) { tier in
                        Task {
                            do {
                                store.remoteSettings = try await store.client.updateCodexServiceTier(tier)
                                store.showToast("已更新 Codex 服务档位")
                            } catch { errorMsg = error.localizedDescription }
                        }
                    }

                    Toggle("Codex 多代理协议 v1 兼容 (/api/settings/codex-agents-v1)", isOn: $codexAgentsV1)
                        .onChange(of: codexAgentsV1) { val in
                            Task {
                                do {
                                    store.remoteSettings = try await store.client.updateCodexAgentsV1(val)
                                    store.showToast("已更新 Codex 子代理协议版本")
                                } catch { errorMsg = error.localizedDescription }
                            }
                        }
                }

                Section(header: Text("隐私转交、本地识别模型与归档 (/api/privacy-model, /api/settings/*)")) {
                    TextField("命中隐私时转交受信模型 ID（空为原地脱敏）", text: $redactRouteTo)
                        .autocapitalization(.none)
                    Button("保存隐私转交模型 (/api/settings/redact-route)") {
                        Task {
                            do {
                                store.remoteSettings = try await store.client.updateRedactRoute(redactRouteTo.trimmingCharacters(in: .whitespacesAndNewlines))
                                store.showToast("已更新隐私转交路由模型")
                            } catch { errorMsg = error.localizedDescription }
                        }
                    }

                    Toggle("本地 AI 隐私识别模型 (/api/privacy-model)", isOn: Binding(
                        get: { privacyModel.on },
                        set: { val in
                            Task {
                                do {
                                    privacyModel = try await store.client.updatePrivacyModel(doAction: val ? "on" : "off")
                                    store.showToast(val ? "已开启本地隐私识别模型" : "已关闭本地隐私识别模型")
                                } catch { errorMsg = error.localizedDescription }
                            }
                        }
                    ))

                    Toggle("全局关闭所有 Agent 遥测 (/api/settings/agent-telemetry)", isOn: $agentTelemetryOff)
                        .onChange(of: agentTelemetryOff) { val in
                            Task {
                                do {
                                    store.remoteSettings = try await store.client.updateGlobalAgentTelemetry(off: val)
                                    store.showToast(val ? "已全局关闭 Agent 遥测" : "已恢复 Agent 遥测设置")
                                } catch { errorMsg = error.localizedDescription }
                            }
                        }

                    Toggle("禁止自动扫描本机订阅账号 (/api/settings/account-discovery)", isOn: $noAccountDiscovery)
                        .onChange(of: noAccountDiscovery) { val in
                            Task {
                                do {
                                    store.remoteSettings = try await store.client.updateAccountDiscovery(off: val)
                                    store.showToast("已更新订阅账号自动发现策略")
                                } catch { errorMsg = error.localizedDescription }
                            }
                        }

                    Toggle("保存网关请求载荷归档 (/api/settings/archive)", isOn: $requestArchiveOn)
                        .onChange(of: requestArchiveOn) { val in
                            Task {
                                do {
                                    let res = try await store.client.updateRequestArchive(on: val)
                                    requestArchiveOn = res.on
                                    store.showToast(res.on ? "已开启请求归档" : "已关闭请求归档")
                                } catch { errorMsg = error.localizedDescription }
                            }
                        }
                }

                Section(header: Text("更新通道与 GitHub 镜像 (/api/settings/update-mirror)")) {
                    Picker("更新通道 (updateChannel)", selection: $updateChannel) {
                        Text("全部版本 (默认)").tag("")
                        Text("每日构建 (daily)").tag("daily")
                        Text("稳定版 (stable)").tag("stable")
                    }
                    Toggle("禁止自动检查更新 (noAutoUpdate)", isOn: $noAutoUpdate)
                    TextField("GitHub 下载镜像前缀（可选）", text: $updateMirrorInput)
                        .autocapitalization(.none)
                    Button("保存更新与镜像设置") {
                        saveUpdateSettings()
                    }
                }
            }
            .disabled(busy)
            .navigationTitle("系统通用与告警设置")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task {
                syncFromStore()
                if let pm = try? await store.client.fetchPrivacyModel() {
                    privacyModel = pm
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func syncFromStore() {
        let s = store.remoteSettings
        theme = s.theme
        lang = s.lang
        currency = s.currency
        totalCurrency = s.totalCurrency
        chineseUnits = s.chineseUnits
        dayStart = s.dayStart
        colorblind = s.colorblind
        reduceMotion = s.reduceMotion
        gatewayMode = s.gatewayMode
        plainNames = s.plainNames

        quotaLeft = s.quotaLeft
        quotaReads = s.quotaReads
        usageAlertInput = String(s.usageAlert)
        balanceAlertInput = String(format: "%.1f", s.balanceAlert)
        resetReminderInput = String(s.resetReminder)
        turnDoneAlertInput = String(s.turnDoneAlert)
        maskAlert = s.maskAlert

        busyLoadInput = String(s.busyLoad)
        disabledModelsInput = s.disabledModels.joined(separator: ", ")
        searchAll = s.searchAll
        searchCountInput = String(s.searchCount)
        codexServiceTier = s.codexServiceTier
        codexAgentsV1 = s.codexAgentsV1
        codexTitles = s.codexTitles
        codexAutoReview = s.codexAutoReview

        redactRouteTo = s.redactRouteTo
        agentTelemetryOff = s.agentTelemetryOff
        noAccountDiscovery = s.noAccountDiscovery
        requestArchiveOn = s.requestArchive || s.requestArchiveLocal
        updateMirrorInput = s.updateMirror
        updateChannel = s.updateChannel
        noAutoUpdate = s.noAutoUpdate
    }

    private func saveGeneralSettings() {
        busy = true; errorMsg = nil
        Task {
            defer { busy = false }
            do {
                store.remoteSettings = try await store.client.patchSettings([
                    "theme": theme,
                    "lang": lang,
                    "currency": currency,
                    "totalCurrency": totalCurrency,
                    "chineseUnits": chineseUnits,
                    "dayStart": dayStart,
                    "colorblind": colorblind,
                    "reduceMotion": reduceMotion
                ])
                store.showToast("已保存通用与外观设置")
            } catch {
                errorMsg = error.localizedDescription
            }
        }
    }

    private func saveAlertSettings() {
        busy = true; errorMsg = nil
        Task {
            defer { busy = false }
            do {
                store.remoteSettings = try await store.client.patchSettings([
                    "usageAlert": Int(usageAlertInput) ?? 0,
                    "balanceAlert": Double(balanceAlertInput) ?? 0,
                    "resetReminder": Int(resetReminderInput) ?? 0,
                    "turnDoneAlert": Int(turnDoneAlertInput) ?? 0,
                    "maskAlert": maskAlert
                ])
                store.showToast("已保存额度与告警阈值")
            } catch {
                errorMsg = error.localizedDescription
            }
        }
    }

    private func saveUpdateSettings() {
        busy = true; errorMsg = nil
        Task {
            defer { busy = false }
            do {
                _ = try await store.client.updateUpdateMirror(updateMirrorInput.trimmingCharacters(in: .whitespacesAndNewlines))
                store.remoteSettings = try await store.client.patchSettings([
                    "updateChannel": updateChannel,
                    "noAutoUpdate": noAutoUpdate
                ])
                store.showToast("已保存更新与镜像配置")
            } catch {
                errorMsg = error.localizedDescription
            }
        }
    }
}

// MARK: - 5. Native Model Custom Pricing Editor (`/api/model-price`)

struct ModelPriceEditorView: View {
    @ObservedObject var store: GatewayStore
    var initialModel: String = ""
    @Environment(\.dismiss) private var dismiss

    @State private var modelID = ""
    @State private var inputPrice = "2.5"
    @State private var outputPrice = "10.0"
    @State private var cacheReadPrice = "0.25"
    @State private var cacheWritePrice = "3.125"
    @State private var makerInfo: String?
    @State private var busy = false
    @State private var errorMsg: String?

    var body: some View {
        NavigationView {
            Form {
                if let err = errorMsg {
                    Section {
                        Text(err).foregroundColor(.red).font(.caption)
                    }
                }

                Section(header: Text("选择或输入模型 ID (/api/model-price)")) {
                    TextField("例如：gpt-demo 或 claude-sonnet-4-5", text: $modelID)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    if !store.groupModels.isEmpty {
                        Menu("从已暴露模型快速选择") {
                            ForEach(store.groupModels.prefix(30)) { m in
                                Button(m.id) {
                                    let bare = m.id.contains("/") ? String(m.id.split(separator: "/", maxSplits: 1)[1]) : m.id
                                    modelID = bare
                                    Task { await loadPrice(for: bare) }
                                }
                            }
                        }
                    }

                    Button("查询当前模型定价") {
                        Task { await loadPrice(for: modelID) }
                    }
                    .disabled(modelID.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if let maker = makerInfo {
                    Section(header: Text("官方参考目录价 (models.dev)")) {
                        Text(maker).font(.caption.monospaced())
                    }
                }

                Section(
                    header: Text("自定义价格（美元 / 百万 Tokens）"),
                    footer: Text("后端字段严格按 input、output、cache_read、cache_write 提交。")
                ) {
                    HStack {
                        Text("输入 (input)")
                        Spacer()
                        TextField("2.5", text: $inputPrice)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    HStack {
                        Text("输出 (output)")
                        Spacer()
                        TextField("10.0", text: $outputPrice)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    HStack {
                        Text("缓存读取 (cache_read)")
                        Spacer()
                        TextField("0.25", text: $cacheReadPrice)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    HStack {
                        Text("缓存写入 (cache_write)")
                        Spacer()
                        TextField("3.125", text: $cacheWritePrice)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }

                    Button("保存自定义定价") {
                        saveCustomPrice()
                    }
                    .disabled(modelID.trimmingCharacters(in: .whitespaces).isEmpty)

                    Button("清除自定义定价（恢复默认）", role: .destructive) {
                        clearCustomPrice()
                    }
                    .disabled(modelID.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .disabled(busy)
            .navigationTitle("模型自定义定价")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task {
                let first = initialModel.isEmpty ? "gpt-demo" : initialModel
                modelID = first
                await loadPrice(for: first)
            }
        }
        .navigationViewStyle(.stack)
    }

    private func loadPrice(for rawModel: String) async {
        let clean = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        busy = true; errorMsg = nil
        defer { busy = false }
        do {
            let res = try await store.client.fetchModelPrice(model: clean)
            if let p = res.price ?? res.maker {
                inputPrice = String(p.input)
                outputPrice = String(p.output)
                cacheReadPrice = String(p.cacheRead)
                cacheWritePrice = String(p.cacheWrite)
            }
            if let m = res.maker {
                makerInfo = "Input $\(m.input) · Output $\(m.output) · CacheRead $\(m.cacheRead) · CacheWrite $\(m.cacheWrite)"
            } else {
                makerInfo = nil
            }
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    private func saveCustomPrice() {
        let clean = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let inp = Double(inputPrice),
              let outp = Double(outputPrice),
              let cr = Double(cacheReadPrice),
              let cw = Double(cacheWritePrice) else {
            errorMsg = "请填写合法的非负数字价格"
            return
        }
        busy = true; errorMsg = nil
        Task {
            defer { busy = false }
            do {
                let spec = RemoteModelPriceSpec(input: inp, output: outp, cacheRead: cr, cacheWrite: cw)
                _ = try await store.client.saveModelPrice(model: clean, price: spec)
                store.showToast("已保存「\(clean)」自定义定价")
                dismiss()
            } catch {
                errorMsg = error.localizedDescription
            }
        }
    }

    private func clearCustomPrice() {
        let clean = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        busy = true; errorMsg = nil
        Task {
            defer { busy = false }
            do {
                _ = try await store.client.saveModelPrice(model: clean, price: nil)
                store.showToast("已恢复「\(clean)」默认定价")
                dismiss()
            } catch {
                errorMsg = error.localizedDescription
            }
        }
    }
}
