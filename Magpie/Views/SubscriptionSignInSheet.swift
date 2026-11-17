import SafariServices
import SwiftUI
import UniformTypeIdentifiers

struct SubscriptionSignInSheet: View {
    enum InitialMode {
        case auto
        case importAccounts
        case exportAccounts
        case claudeToken
        case codexDevice
        case copilotGHE
    }

    @ObservedObject var store: GatewayStore
    let platform: SubscriptionPlatform
    var initialMode: InitialMode = .auto
    var forUser: String? = nil
    var defaultProxy: String? = nil
    var onFinished: ((String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable {
        case riskWarning
        case launcher
        case claudeToken
        case copilotGHE
        case pluginMethodSelect
        case pluginPrompt
        case pluginAPIKey
        case starting
        case waiting
        case importing
        case importForm
        case importResult
        case exportForm
        case exportResult
        case done
        case failed
    }

    @State private var phase: Phase = .launcher
    @State private var selectedProxyMode: String = "" // "", "direct", "@id", "custom"
    @State private var customProxyURL: String = ""
    @State private var selectedSite: String? = nil
    @State private var signInState: RemoteSignInState? = nil
    @State private var errorText: String? = nil
    @State private var isBusy = false
    @State private var pollTask: Task<Void, Never>? = nil

    // Callback / token / GHE drafts
    @State private var callbackInput: String = ""
    @State private var isSubmittingCallback = false
    @State private var claudeTokenInput: String = ""
    @State private var gheHostInput: String = ""

    // Plugin auth drafts
    @State private var selectedPluginMethod: Int = 0
    @State private var pluginInputs: [String: String] = [:]
    @State private var activePluginPrompt: RemotePluginPrompt? = nil
    @State private var pluginPromptInput: String = ""
    @State private var pluginAPIKeyInput: String = ""

    // Import / Export drafts
    @State private var importText: String = ""
    @State private var importFiles: [(name: String, text: String)] = []
    @State private var importAccessOnly: Bool = false
    @State private var importResults: [RemoteImportedAccount] = []
    @State private var showingFileImporter = false

    @State private var exportFormat: String = "sub2api"
    @State private var exportExcludedUsers: Set<String> = []
    @State private var exportResult: RemoteSignInExportResponse? = nil

    // Browser sheet
    @State private var safariURL: IdentifiableURL? = nil

    private struct IdentifiableURL: Identifiable {
        let id = UUID()
        let url: URL
    }

    private var existingProvider: RemoteProvider? {
        store.providers.first(where: { $0.account?.agent == platform.agent })
    }

    private var existingLogins: [RemoteProviderLogin] {
        existingProvider?.account?.logins ?? []
    }

    private var hasExistingLogins: Bool {
        !existingLogins.isEmpty
    }

    private var effectiveProxyValue: String? {
        switch selectedProxyMode {
        case "":
            return nil
        case "direct":
            return "direct"
        case "custom":
            let t = customProxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        default:
            return selectedProxyMode // @id
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                MagpieTheme.canvas.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        headerBanner
                        contentForPhase
                    }
                    .padding(20)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle(forUser != nil ? "重新授权 · \(platform.name)" : platform.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        cancelActiveSignInIfNeeded()
                        dismiss()
                    }
                }
            }
            .onAppear { setupInitialPhase() }
            .onDisappear { pollTask?.cancel() }
            .sheet(item: $safariURL) { item in
                SignInSafariView(url: item.url)
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.json, .plainText, .text],
                allowsMultipleSelection: true
            ) { result in
                handlePickedFiles(result)
            }
        }
        .preferredColorScheme(.light)
    }

    // MARK: - Header

    private var headerBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(platform.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(MagpieTheme.ink)
                if platform.isPluginBacked {
                    MagpieTag(text: "插件", tone: MagpieTheme.info)
                }
                if platform.risk {
                    MagpieTag(text: "注意风控", tone: MagpieTheme.warn)
                }
            }
            Text(platform.subtitle)
                .font(.system(size: 12.5))
                .foregroundColor(MagpieTheme.textSecondary)
            if !platform.plans.isEmpty {
                Text("支持套餐：\(platform.plans)")
                    .font(.system(size: 11.5))
                    .foregroundColor(MagpieTheme.textMuted)
            }
            if let user = forUser, !user.isEmpty {
                Text("目标账号：\(user)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(MagpieTheme.accent)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MagpieTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(MagpieTheme.hairline, lineWidth: 1))
    }

    // MARK: - Phase Router

    @ViewBuilder
    private var contentForPhase: some View {
        switch phase {
        case .riskWarning:
            riskWarningView
        case .launcher:
            launcherView
        case .claudeToken:
            claudeTokenView
        case .copilotGHE:
            copilotGHEView
        case .pluginMethodSelect:
            pluginMethodSelectView
        case .pluginPrompt:
            pluginPromptView
        case .pluginAPIKey:
            pluginAPIKeyView
        case .starting:
            startingView
        case .waiting:
            waitingView
        case .importForm:
            importFormView
        case .importing:
            importingView
        case .importResult:
            importResultView
        case .exportForm:
            exportFormView
        case .exportResult:
            exportResultView
        case .done:
            doneView
        case .failed:
            failedView
        }
    }

    // MARK: - Risk Warning

    private var riskWarningView: some View {
        MinimalSection(title: "账号风控提示") {
            if let hint = platform.hint {
                Text(hint)
                    .font(.system(size: 13))
                    .foregroundColor(MagpieTheme.textSecondary)
            }
            Text(platform.riskNote ?? "该平台可能对官方客户端之外的代理调用进行风控，建议使用可承受风险的账号。")
                .font(.system(size: 13))
                .foregroundColor(MagpieTheme.warn)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("仍然继续授权") {
                    phase = .launcher
                }
                .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))

                if platform.importable {
                    Button("改用导入") {
                        phase = .importForm
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
                }
            }
        }
    }

    // MARK: - Launcher

    private var launcherView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let hint = platform.hint {
                MinimalSection(title: "说明") {
                    Text(hint)
                        .font(.system(size: 12.5))
                        .foregroundColor(MagpieTheme.textSecondary)
                }
            }

            proxyPickerSection

            if !platform.sites.isEmpty {
                MinimalSection(title: "选择登录站点") {
                    ForEach(platform.sites) { site in
                        Button {
                            selectedSite = site.id
                            beginSignInFlow(site: site.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(site.label)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(MagpieTheme.ink)
                                    Text(site.host)
                                        .font(.system(size: 11.5, design: .monospaced))
                                        .foregroundColor(MagpieTheme.textMuted)
                                }
                                Spacer()
                                Image(systemName: "arrow.right.circle.fill")
                                    .foregroundColor(MagpieTheme.accent)
                            }
                            .padding(12)
                            .background(MagpieTheme.canvas)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            } else if let plugin = platform.plugin, !platform.movedToPlugin {
                MinimalSection(title: "选择认证方式") {
                    if plugin.methods.isEmpty {
                        Text("该插件未提供可用登录方式")
                            .font(.system(size: 12.5))
                            .foregroundColor(MagpieTheme.warn)
                    } else {
                        ForEach(Array(plugin.methods.enumerated()), id: \.offset) { idx, method in
                            Button {
                                startPluginFlow(methodIndex: idx)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(method.localizedLabel)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(MagpieTheme.ink)
                                        Text(method.type == "api" ? "API Key / 凭据录入" : "OAuth 授权登录")
                                            .font(.system(size: 11.5))
                                            .foregroundColor(MagpieTheme.textMuted)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(MagpieTheme.textMuted)
                                }
                                .padding(12)
                                .background(MagpieTheme.canvas)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }
                }
            } else {
                MinimalSection(title: "授权方式") {
                    Button {
                        beginSignInFlow(site: nil)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(forUser != nil ? "发起浏览器重新授权 (OAuth)" : "发起浏览器 OAuth 授权登录")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("获取授权链接并在内置浏览器中登录，支持回调 URL 粘贴完成")
                                    .font(.system(size: 11.5))
                                    .opacity(0.85)
                            }
                            Spacer()
                            Image(systemName: "safari")
                        }
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .primary))

                    if platform.supportsCodexDevice {
                        Button("使用设备码登录 (Device Code)") {
                            selectedSite = "device"
                            beginSignInFlow(site: "device")
                        }
                        .buttonStyle(MagpieButtonStyle(tone: .secondary))
                    }

                    if platform.supportsCopilotGHE {
                        Button("使用 GitHub Enterprise (*.ghe.com) 登录") {
                            phase = .copilotGHE
                        }
                        .buttonStyle(MagpieButtonStyle(tone: .secondary))
                    }

                    if platform.supportsClaudeToken {
                        Button("使用 Setup-Token (claude setup-token) 添加") {
                            phase = .claudeToken
                        }
                        .buttonStyle(MagpieButtonStyle(tone: .secondary))
                    }

                    if platform.importable {
                        Button(platform.importTitle ?? "从文件 / 文本导入账号") {
                            phase = .importForm
                        }
                        .buttonStyle(MagpieButtonStyle(tone: .subtle))
                    }

                    if platform.supportsExport && hasExistingLogins {
                        Button("导出已有账号 (Sub2API / CLIProxyAPI)") {
                            phase = .exportForm
                        }
                        .buttonStyle(MagpieButtonStyle(tone: .subtle))
                    }
                }
            }

            if platform.movedToPlugin, let plugin = platform.plugin, plugin.methods.count > 1 {
                MinimalSection(title: "插件其他登录方式") {
                    ForEach(Array(plugin.methods.enumerated()), id: \.offset) { idx, method in
                        Button(method.localizedLabel) {
                            startPluginFlow(methodIndex: idx)
                        }
                        .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))
                    }
                }
            }
        }
    }

    private var proxyPickerSection: some View {
        MinimalSection(title: "授权出口代理（可选）") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    proxyChip(id: "", title: "跟随默认")
                    proxyChip(id: "direct", title: "直连 (direct)")
                    ForEach(store.remoteSettings.proxies) { px in
                        proxyChip(id: "@\(px.id)", title: px.name.isEmpty ? px.id : px.name)
                    }
                    proxyChip(id: "custom", title: "自定义 URL")
                }
            }
            if selectedProxyMode == "custom" {
                MagpieInputField(
                    label: "自定义代理地址",
                    placeholder: "http://127.0.0.1:7890 或 socks5://...",
                    text: $customProxyURL,
                    monospaced: true,
                    keyboardType: .URL
                )
            }
        }
    }

    private func proxyChip(id: String, title: String) -> some View {
        let active = selectedProxyMode == id
        return Button(title) {
            selectedProxyMode = id
        }
        .font(.system(size: 12, weight: active ? .semibold : .medium))
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(active ? MagpieTheme.ink : MagpieTheme.canvas)
        .foregroundColor(active ? .white : MagpieTheme.textSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(MagpieTheme.hairline, lineWidth: active ? 0 : 1))
    }

    // MARK: - Claude Setup-Token

    private var claudeTokenView: some View {
        MinimalSection(title: "通过 setup-token 添加 Claude 账号") {
            Text("粘贴终端运行 `claude setup-token` 生成的 Token。Magpie 仅用它转发请求，不会覆盖本机 Claude Code 的现有登录；由于 token 不携带邮箱与额度信息，账号会按 token 命名。")
                .font(.system(size: 12.5))
                .foregroundColor(MagpieTheme.textSecondary)

            MagpieInputField(
                label: "Setup Token",
                placeholder: "sk-ant-oat01-...",
                text: $claudeTokenInput,
                isSecure: true,
                monospaced: true
            )

            if let err = errorText {
                MagpieErrorBanner(title: "添加失败", message: err)
            }

            HStack(spacing: 10) {
                Button(isBusy ? "提交中..." : "添加账号") {
                    submitClaudeToken()
                }
                .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
                .disabled(isBusy || claudeTokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("返回") {
                    errorText = nil
                    phase = .launcher
                }
                .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
            }
        }
    }

    // MARK: - Copilot GHE

    private var copilotGHEView: some View {
        MinimalSection(title: "GitHub Enterprise (GHE.com) 登录") {
            Text("请输入你的企业 GitHub 域名（例如 acme.ghe.com）；普通 github.com 账号请直接返回使用默认登录。")
                .font(.system(size: 12.5))
                .foregroundColor(MagpieTheme.textSecondary)

            MagpieInputField(
                label: "GHE.com 域名",
                placeholder: "acme.ghe.com",
                text: $gheHostInput,
                monospaced: true,
                keyboardType: .URL
            )

            if let err = errorText {
                MagpieErrorBanner(title: "校验失败", message: err)
            }

            HStack(spacing: 10) {
                Button("发起企业授权") {
                    let clean = gheHostInput
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "https://", with: "", options: .caseInsensitive)
                        .replacingOccurrences(of: "http://", with: "", options: .caseInsensitive)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                        .lowercased()
                    guard clean.hasSuffix(".ghe.com"), clean.count > 8 else {
                        errorText = "请填写有效的 <企业名>.ghe.com 域名"
                        return
                    }
                    errorText = nil
                    selectedSite = clean
                    beginSignInFlow(site: clean)
                }
                .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))

                Button("返回") {
                    errorText = nil
                    phase = .launcher
                }
                .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
            }
        }
    }

    // MARK: - Plugin Flows

    private var pluginMethodSelectView: some View {
        MinimalSection(title: "选择插件登录方式") {
            if let plugin = platform.plugin {
                ForEach(Array(plugin.methods.enumerated()), id: \.offset) { idx, m in
                    Button(m.localizedLabel) {
                        startPluginFlow(methodIndex: idx)
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .secondary))
                }
            }
            Button("返回") { phase = .launcher }
                .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))
        }
    }

    private var pluginPromptView: some View {
        MinimalSection(title: "插件参数确认") {
            if let prompt = activePluginPrompt {
                Text(prompt.localizedMessage)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(MagpieTheme.ink)

                if prompt.type == "select" {
                    ForEach(prompt.options, id: \.value) { opt in
                        Button {
                            submitPluginPromptAnswer(key: prompt.key, value: opt.value)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(opt.localizedLabel)
                                        .font(.system(size: 13.5, weight: .semibold))
                                        .foregroundColor(MagpieTheme.ink)
                                    if let h = opt.localizedHint, !h.isEmpty {
                                        Text(h)
                                            .font(.system(size: 11.5))
                                            .foregroundColor(MagpieTheme.textMuted)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(MagpieTheme.textMuted)
                            }
                            .padding(11)
                            .background(MagpieTheme.canvas)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .disabled(isBusy)
                    }
                } else {
                    MagpieInputField(
                        label: prompt.key,
                        placeholder: prompt.placeholder ?? "",
                        text: $pluginPromptInput,
                        isSecure: prompt.type == "password",
                        monospaced: true
                    )
                    Button(isBusy ? "校验中..." : "下一步") {
                        submitPluginPromptAnswer(key: prompt.key, value: pluginPromptInput)
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
                    .disabled(isBusy)
                }
            }
            if let err = errorText {
                MagpieErrorBanner(title: "输入有误", message: err)
            }
        }
    }

    private var pluginAPIKeyView: some View {
        MinimalSection(title: "输入插件凭据") {
            let method = platform.plugin?.methods[safe: selectedPluginMethod]
            MagpieInputField(
                label: method?.localizedLabel ?? "API Key",
                placeholder: method?.placeholder ?? "sk-...",
                text: $pluginAPIKeyInput,
                isSecure: true,
                monospaced: true
            )
            if let err = errorText {
                MagpieErrorBanner(title: "添加失败", message: err)
            }
            HStack(spacing: 10) {
                Button(isBusy ? "提交中..." : "提交并添加") {
                    submitPluginAPIKey(pluginAPIKeyInput)
                }
                .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
                .disabled(isBusy || pluginAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("返回") { phase = .launcher }
                    .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
            }
        }
    }

    // MARK: - Active Sign-In (Starting / Waiting)

    private var startingView: some View {
        MinimalSection(title: "正在向远端 Magpie 发起授权...") {
            HStack(spacing: 12) {
                ProgressView()
                Text("正在生成 OAuth 会话与 PKCE 参数，请稍候")
                    .font(.system(size: 13))
                    .foregroundColor(MagpieTheme.textSecondary)
            }
        }
    }

    private var waitingView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let st = signInState {
                if st.state == "installing" {
                    MinimalSection(title: "正在安装依赖 CLI") {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("服务端正在安装 \(st.installing ?? platform.name) 官方 CLI，完成后将自动生成授权链接…")
                                .font(.system(size: 12.5))
                                .foregroundColor(MagpieTheme.textSecondary)
                        }
                    }
                } else {
                    if let code = st.code, !code.isEmpty {
                        MinimalSection(title: "设备授权码 (Device Code)") {
                            HStack {
                                Text(code)
                                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                                    .foregroundColor(MagpieTheme.ink)
                                    .textSelection(.enabled)
                                Spacer()
                                Button("复制") {
                                    store.copyToClipboard(code, label: "设备授权码")
                                }
                                .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
                            }
                            Text("打开下方页面后输入以上授权码完成确认，此页面会自动检测登录结果。")
                                .font(.system(size: 12))
                                .foregroundColor(MagpieTheme.textSecondary)
                        }
                    }

                    if !st.url.isEmpty {
                        MinimalSection(title: "第 1 步：打开授权页面") {
                            if let instr = st.instructions, !instr.isEmpty {
                                Text(instr)
                                    .font(.system(size: 12.5))
                                    .foregroundColor(MagpieTheme.textSecondary)
                            }
                            if let url = URL(string: st.url) {
                                Button {
                                    safariURL = IdentifiableURL(url: url)
                                } label: {
                                    HStack {
                                        Image(systemName: "safari.fill")
                                        Text("在内置浏览器中打开授权页")
                                            .font(.system(size: 14, weight: .semibold))
                                    }
                                }
                                .buttonStyle(MagpieButtonStyle(tone: .primary))

                                HStack(spacing: 10) {
                                    Button("系统 Safari 打开") {
                                        UIApplication.shared.open(url)
                                    }
                                    .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))

                                    Button("复制授权链接") {
                                        store.copyToClipboard(st.url, label: "授权链接")
                                    }
                                    .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))
                                }
                            }
                            Text(st.url)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundColor(MagpieTheme.textMuted)
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }
                    }

                    if st.pasteCallback || st.pasteCode || st.pasteKey {
                        MinimalSection(title: st.pasteKey ? "第 2 步：粘贴 Key 完成绑定" : (st.pasteCode ? "第 2 步：粘贴授权码" : "第 2 步：粘贴回调 URL 完成授权")) {
                            if st.pasteKey {
                                Text("如果远端服务器无法接收回调，请在平台控制台生成 API Key 并粘贴到下方。")
                                    .font(.system(size: 12))
                                    .foregroundColor(MagpieTheme.textSecondary)
                                if let ku = st.keysURL, let url = URL(string: ku) {
                                    Button("打开 Key 管理页面") {
                                        safariURL = IdentifiableURL(url: url)
                                    }
                                    .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))
                                }
                            } else if st.pasteCode {
                                Text("授权页面显示授权码后，请复制并粘贴到下方提交。")
                                    .font(.system(size: 12))
                                    .foregroundColor(MagpieTheme.textSecondary)
                            } else {
                                Text("在浏览器登录授权后，页面最终会跳转到 http://localhost:\(st.callbackPort.map(String.init) ?? "...")/callback 并显示无法打开（因 Magpie 运行在远端服务器）。请直接复制浏览器地址栏完整的 http://localhost... 链接并粘贴到下方！")
                                    .font(.system(size: 12))
                                    .foregroundColor(MagpieTheme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            HStack(spacing: 8) {
                                Button("从剪贴板粘贴") {
                                    if let str = UIPasteboard.general.string {
                                        callbackInput = str.trimmingCharacters(in: .whitespacesAndNewlines)
                                    }
                                }
                                .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))

                                if let clip = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                                   clip.contains("code=") || clip.hasPrefix("http://localhost") || clip.hasPrefix("http://127.0.0.1") {
                                    Button("检测到回调链接，一键提交") {
                                        callbackInput = clip
                                        submitCallback()
                                    }
                                    .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
                                    .disabled(isSubmittingCallback)
                                }
                            }

                            MagpieInputField(
                                label: st.pasteKey ? "API Key" : (st.pasteCode ? "授权码" : "回调 URL"),
                                placeholder: st.pasteKey ? "粘贴生成的 Key" : (st.pasteCode ? "粘贴授权码" : "http://localhost:1455/auth/callback?code=...&state=..."),
                                text: $callbackInput,
                                isSecure: st.pasteKey,
                                monospaced: true,
                                keyboardType: st.pasteCallback ? .URL : .default
                            )

                            if let err = errorText {
                                MagpieErrorBanner(title: "回调提交失败", message: err)
                            }

                            Button(isSubmittingCallback ? "正在向服务端校验..." : "提交并完成登录") {
                                submitCallback()
                            }
                            .buttonStyle(MagpieButtonStyle(tone: .primary))
                            .disabled(isSubmittingCallback || callbackInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }

                    HStack(spacing: 10) {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.8)
                            Text("正在轮询授权状态...")
                                .font(.system(size: 12))
                                .foregroundColor(MagpieTheme.textMuted)
                        }
                        Spacer()
                        Button("取消登录") {
                            cancelActiveSignInIfNeeded()
                            phase = .launcher
                        }
                        .buttonStyle(MagpieButtonStyle(tone: .danger, compact: true))
                    }
                }
            }
        }
    }

    // MARK: - Import / Export

    private var importFormView: some View {
        MinimalSection(title: platform.importTitle ?? "导入账号") {
            Text(platform.importIntro ?? "粘贴或选择导出的账号 JSON / Token 文件。")
                .font(.system(size: 12.5))
                .foregroundColor(MagpieTheme.textSecondary)

            if platform.agent == "codex" {
                Toggle("仅保留 Access Token（不自动刷新，不影响原工具登录）", isOn: $importAccessOnly)
                    .font(.system(size: 13))
            }

            HStack(spacing: 8) {
                Button("选择文件 (.json/.txt)") {
                    showingFileImporter = true
                }
                .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))

                Button("从剪贴板粘贴") {
                    if let s = UIPasteboard.general.string {
                        importText = s
                    }
                }
                .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))
            }

            if !importFiles.isEmpty {
                Text("已选文件：\(importFiles.map(\.name).joined(separator: ", "))")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(MagpieTheme.accent)
            }

            TextEditor(text: $importText)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 110)
                .padding(8)
                .background(MagpieTheme.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(MagpieTheme.hairline, lineWidth: 1))

            if let err = errorText {
                MagpieErrorBanner(title: "导入失败", message: err)
            }

            HStack(spacing: 10) {
                Button("开始导入") {
                    runImport()
                }
                .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
                .disabled(importFiles.isEmpty && importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("返回") {
                    errorText = nil
                    phase = .launcher
                }
                .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
            }
        }
    }

    private var importingView: some View {
        MinimalSection(title: "正在校验并导入账号...") {
            HStack(spacing: 10) {
                ProgressView()
                Text("正在向 \(platform.name) 验证凭据并写入远端 Magpie，请稍候")
                    .font(.system(size: 13))
                    .foregroundColor(MagpieTheme.textSecondary)
            }
        }
    }

    private var importResultView: some View {
        MinimalSection(title: "导入完成") {
            ForEach(importResults) { item in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(item.status == "failed" ? MagpieTheme.danger : MagpieTheme.ok)
                        .frame(width: 7, height: 7)
                        .padding(.top, 5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.user.isEmpty ? "第 \(item.file ?? 1) 个条目" : item.user)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(MagpieTheme.ink)
                        Text(importStatusLabel(item.status) + (item.error.map { " · \($0)" } ?? ""))
                            .font(.system(size: 11.5))
                            .foregroundColor(item.status == "failed" ? MagpieTheme.danger : MagpieTheme.textSecondary)
                    }
                }
            }
            HStack(spacing: 10) {
                Button("继续导入") {
                    importText = ""
                    importFiles = []
                    importResults = []
                    phase = .importForm
                }
                .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))

                Button("完成") {
                    onFinished?(platform.agent)
                    dismiss()
                }
                .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
            }
        }
    }

    private var exportFormView: some View {
        MinimalSection(title: "导出账号到服务端目录") {
            Text("导出文件包含实时登录凭据，将由服务端以 0600 权限保存至服务器 Downloads 目录。")
                .font(.system(size: 12.5))
                .foregroundColor(MagpieTheme.warn)

            Picker("导出格式", selection: $exportFormat) {
                Text("Sub2API").tag("sub2api")
                Text("CLIProxyAPI").tag("cliproxyapi")
            }
            .pickerStyle(.segmented)

            ForEach(existingLogins) { login in
                let included = !exportExcludedUsers.contains(login.user)
                Button {
                    if included {
                        exportExcludedUsers.insert(login.user)
                    } else {
                        exportExcludedUsers.remove(login.user)
                    }
                } label: {
                    HStack {
                        Image(systemName: included ? "checkmark.square.fill" : "square")
                            .foregroundColor(included ? MagpieTheme.accent : MagpieTheme.textMuted)
                        Text(login.user)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(MagpieTheme.ink)
                        if let plan = login.plan, !plan.isEmpty {
                            MagpieTag(text: plan)
                        }
                        Spacer()
                    }
                }
            }

            if let err = errorText {
                MagpieErrorBanner(title: "导出失败", message: err)
            }

            HStack(spacing: 10) {
                Button(isBusy ? "导出中..." : "开始导出") {
                    runExport()
                }
                .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
                .disabled(isBusy || existingLogins.allSatisfy { exportExcludedUsers.contains($0.user) })

                Button("返回") { phase = .launcher }
                    .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
            }
        }
    }

    private var exportResultView: some View {
        MinimalSection(title: "导出成功") {
            if let res = exportResult {
                Text("保存路径（服务端）：\(res.path)")
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundColor(MagpieTheme.ink)
                    .textSelection(.enabled)
                if !res.accounts.isEmpty {
                    Text("已导出账号：\(res.accounts.joined(separator: ", "))")
                        .font(.system(size: 12))
                        .foregroundColor(MagpieTheme.ok)
                }
                ForEach(res.skipped) { s in
                    Text("跳过 \(s.user)：\(s.error ?? "")")
                        .font(.system(size: 11.5))
                        .foregroundColor(MagpieTheme.warn)
                }
            }
            Button("完成") { dismiss() }
                .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
        }
    }

    // MARK: - Done / Failed

    private var doneView: some View {
        MinimalSection(title: "授权成功") {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(MagpieTheme.ok)
                VStack(alignment: .leading, spacing: 3) {
                    Text(signInState?.user ?? platform.name)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundColor(MagpieTheme.ink)
                    Text(signInState?.again == true ? "该账号已在号池中，已刷新登录凭证" : "已成功接入 Magpie 号池")
                        .font(.system(size: 12.5))
                        .foregroundColor(MagpieTheme.textSecondary)
                }
            }
            Button("完成并返回") {
                onFinished?(platform.agent)
                dismiss()
            }
            .buttonStyle(MagpieButtonStyle(tone: .primary))
        }
    }

    private var failedView: some View {
        MinimalSection(title: "授权未完成") {
            MagpieErrorBanner(title: "登录失败", message: errorText ?? signInState?.error ?? "未知错误")
            HStack(spacing: 10) {
                Button("重试") {
                    errorText = nil
                    if platform.plugin != nil {
                        startPluginFlow(methodIndex: selectedPluginMethod)
                    } else {
                        beginSignInFlow(site: selectedSite)
                    }
                }
                .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))

                Button("返回调整") {
                    errorText = nil
                    phase = .launcher
                }
                .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
            }
        }
    }

    // MARK: - Actions & Polling

    private func setupInitialPhase() {
        if let p = defaultProxy, !p.isEmpty {
            if p == "direct" || p.hasPrefix("@") {
                selectedProxyMode = p
            } else {
                selectedProxyMode = "custom"
                customProxyURL = p
            }
        }
        switch initialMode {
        case .importAccounts:
            phase = .importForm
        case .exportAccounts:
            phase = .exportForm
        case .claudeToken:
            phase = .claudeToken
        case .codexDevice:
            selectedSite = "device"
            beginSignInFlow(site: "device")
        case .copilotGHE:
            phase = .copilotGHE
        case .auto:
            if platform.risk && forUser == nil && !hasExistingLogins {
                phase = .riskWarning
            } else if platform.sites.isEmpty && platform.plugin != nil && !platform.movedToPlugin && (platform.plugin?.methods.count ?? 0) == 1 {
                phase = .launcher
            } else {
                phase = .launcher
            }
        }
    }

    private func beginSignInFlow(site: String?) {
        if let plugin = platform.plugin {
            let idx = pluginMethodIndex(plugin: plugin, site: site)
            startPluginFlow(methodIndex: idx)
            return
        }
        cancelActiveSignInIfNeeded()
        errorText = nil
        callbackInput = ""
        phase = .starting
        Task {
            do {
                let st = try await store.client.startSignIn(
                    agent: platform.agent,
                    site: site,
                    proxy: effectiveProxyValue,
                    user: forUser,
                    linkOnly: true
                )
                await MainActor.run {
                    self.signInState = st
                    if st.state == "done" {
                        handleSignInCompleted(st)
                    } else if st.state == "failed" {
                        self.errorText = st.error
                        self.phase = .failed
                    } else {
                        self.phase = .waiting
                        self.startPolling(id: st.id)
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorText = error.localizedDescription
                    self.phase = .failed
                }
            }
        }
    }

    private func pluginMethodIndex(plugin: RemotePluginSub, site: String?) -> Int {
        guard let site = site, let siteOpt = platform.sites.first(where: { $0.id == site }) else {
            return 0
        }
        let word = siteOpt.pluginWord ?? siteOpt.label
        if let idx = plugin.methods.firstIndex(where: { $0.label.contains(word) || $0.localizedLabel.contains(word) }) {
            return idx
        }
        return 0
    }

    private func startPluginFlow(methodIndex: Int) {
        guard let plugin = platform.plugin else { return }
        selectedPluginMethod = methodIndex
        pluginInputs = [:]
        activePluginPrompt = nil
        errorText = nil
        isBusy = true
        phase = .starting
        Task {
            do {
                let resp = try await store.client.pluginSignInPrompt(
                    provider: plugin.pid,
                    method: methodIndex,
                    inputs: [:]
                )
                await MainActor.run {
                    isBusy = false
                    handlePluginPromptResponse(resp, plugin: plugin, methodIndex: methodIndex)
                }
            } catch {
                await MainActor.run {
                    isBusy = false
                    errorText = error.localizedDescription
                    phase = .failed
                }
            }
        }
    }

    private func submitPluginPromptAnswer(key: String, value: String) {
        guard let plugin = platform.plugin else { return }
        errorText = nil
        isBusy = true
        Task {
            do {
                let resp = try await store.client.pluginSignInPrompt(
                    provider: plugin.pid,
                    method: selectedPluginMethod,
                    inputs: pluginInputs,
                    key: key,
                    value: value
                )
                await MainActor.run {
                    isBusy = false
                    if let err = resp.error, !err.isEmpty {
                        errorText = err
                    } else {
                        pluginPromptInput = ""
                        handlePluginPromptResponse(resp, plugin: plugin, methodIndex: selectedPluginMethod)
                    }
                }
            } catch {
                await MainActor.run {
                    isBusy = false
                    errorText = error.localizedDescription
                }
            }
        }
    }

    private func handlePluginPromptResponse(
        _ resp: RemotePluginPromptResponse,
        plugin: RemotePluginSub,
        methodIndex: Int
    ) {
        pluginInputs = resp.inputs
        if let prompt = resp.prompt {
            activePluginPrompt = prompt
            pluginPromptInput = ""
            phase = .pluginPrompt
            return
        }
        let method = plugin.methods[safe: methodIndex]
        if method?.type == "api" {
            let noKey = (method?.keyless == true) || (method?.keyAsked == true)
            if noKey {
                submitPluginAPIKey("")
            } else {
                pluginAPIKeyInput = ""
                phase = .pluginAPIKey
            }
            return
        }
        phase = .starting
        Task {
            do {
                let st = try await store.client.startPluginSignIn(
                    provider: plugin.pid,
                    method: methodIndex,
                    inputs: pluginInputs,
                    proxy: effectiveProxyValue,
                    user: forUser
                )
                await MainActor.run {
                    self.signInState = st
                    if st.state == "done" {
                        handleSignInCompleted(st)
                    } else if st.state == "failed" {
                        self.errorText = st.error
                        self.phase = .failed
                    } else {
                        self.phase = .waiting
                        self.startPolling(id: st.id)
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorText = error.localizedDescription
                    self.phase = .failed
                }
            }
        }
    }

    private func submitPluginAPIKey(_ key: String) {
        guard let plugin = platform.plugin else { return }
        errorText = nil
        isBusy = true
        Task {
            do {
                let st = try await store.client.startPluginSignIn(
                    provider: plugin.pid,
                    method: selectedPluginMethod,
                    inputs: pluginInputs,
                    key: key,
                    proxy: effectiveProxyValue,
                    user: forUser
                )
                await MainActor.run {
                    isBusy = false
                    signInState = st
                    handleSignInCompleted(st)
                }
            } catch {
                await MainActor.run {
                    isBusy = false
                    errorText = error.localizedDescription
                }
            }
        }
    }

    private func startPolling(id: String) {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 800_000_000)
                if Task.isCancelled { break }
                do {
                    let st = try await store.client.getSignInStatus(id: id)
                    await MainActor.run {
                        self.signInState = st
                        if st.state == "done" {
                            self.pollTask?.cancel()
                            self.handleSignInCompleted(st)
                        } else if st.state == "failed" {
                            self.pollTask?.cancel()
                            self.errorText = st.error
                            self.phase = .failed
                        } else if st.state == "canceled" {
                            self.pollTask?.cancel()
                            self.phase = .launcher
                        }
                    }
                } catch {
                    // Keep polling across transient hiccups
                }
            }
        }
    }

    private func handleSignInCompleted(_ st: RemoteSignInState) {
        pollTask?.cancel()
        phase = .done
        Task {
            await store.refreshProvidersWaitAndState(forAgent: platform.agent)
        }
    }

    private func submitCallback() {
        guard let id = signInState?.id, !id.isEmpty else { return }
        let raw = callbackInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        isSubmittingCallback = true
        errorText = nil
        Task {
            do {
                try await store.client.submitSignInCallback(id: id, url: raw)
                let st = try await store.client.getSignInStatus(id: id)
                await MainActor.run {
                    isSubmittingCallback = false
                    self.signInState = st
                    if st.state == "done" {
                        handleSignInCompleted(st)
                    } else if st.state == "failed" {
                        self.errorText = st.error
                        self.phase = .failed
                    }
                }
            } catch {
                await MainActor.run {
                    isSubmittingCallback = false
                    self.errorText = error.localizedDescription
                }
            }
        }
    }

    private func submitClaudeToken() {
        let tok = claudeTokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tok.isEmpty else { return }
        isBusy = true
        errorText = nil
        Task {
            do {
                let res = try await store.client.addClaudeSetupToken(token: tok)
                await store.refreshProvidersWaitAndState(forAgent: "claude")
                await MainActor.run {
                    isBusy = false
                    signInState = RemoteSignInState(jsonUser: res.user, agent: "claude")
                    phase = .done
                }
            } catch {
                await MainActor.run {
                    isBusy = false
                    errorText = error.localizedDescription
                }
            }
        }
    }

    private func runImport() {
        var files = importFiles.map(\.text)
        let pasted = importText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !pasted.isEmpty { files.append(pasted) }
        guard !files.isEmpty else { return }
        errorText = nil
        phase = .importing
        Task {
            do {
                let resp = try await store.client.importSignInAccounts(
                    agent: platform.agent,
                    files: files,
                    accessOnly: platform.agent == "codex" && importAccessOnly
                )
                await MainActor.run {
                    store.applyProvidersResponse(resp.providers)
                    store.loginUsageByAgent.removeValue(forKey: platform.agent)
                    importResults = resp.results
                    phase = .importResult
                }
                await store.refreshStateOnly()
            } catch {
                await MainActor.run {
                    errorText = error.localizedDescription
                    phase = .importForm
                }
            }
        }
    }

    private func runExport() {
        let users = existingLogins.map(\.user).filter { !exportExcludedUsers.contains($0) }
        guard !users.isEmpty else { return }
        isBusy = true
        errorText = nil
        Task {
            do {
                let res = try await store.client.exportSignInAccounts(
                    agent: platform.agent,
                    format: exportFormat,
                    users: users
                )
                await MainActor.run {
                    isBusy = false
                    exportResult = res
                    phase = .exportResult
                }
            } catch {
                await MainActor.run {
                    isBusy = false
                    errorText = error.localizedDescription
                }
            }
        }
    }

    private func handlePickedFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            var loaded: [(name: String, text: String)] = []
            for url in urls {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) {
                    loaded.append((name: url.lastPathComponent, text: text))
                }
            }
            importFiles.append(contentsOf: loaded)
        case .failure(let err):
            errorText = err.localizedDescription
        }
    }

    private func cancelActiveSignInIfNeeded() {
        pollTask?.cancel()
        pollTask = nil
        if let st = signInState, (st.state == "waiting" || st.state == "installing"), !st.id.isEmpty {
            let id = st.id
            Task { try? await store.client.cancelSignIn(id: id) }
        }
    }

    private func importStatusLabel(_ status: String) -> String {
        switch status {
        case "added": return "已新增"
        case "updated": return "已更新登录凭证"
        case "exists": return "号池中已存在"
        default: return "未导入"
        }
    }
}

private extension RemoteSignInState {
    init(jsonUser: String, agent: String) {
        let payload: [String: Any] = ["id": "", "agent": agent, "url": "", "state": "done", "user": jsonUser]
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
        self = (try? JSONDecoder().decode(RemoteSignInState.self, from: data))
            ?? (try! JSONDecoder().decode(RemoteSignInState.self, from: Data("{}".utf8)))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private struct SignInSafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
