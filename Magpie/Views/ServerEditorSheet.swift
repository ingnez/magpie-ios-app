import SwiftUI

struct ServerEditorSheet: View {
    @ObservedObject var store: GatewayStore
    let existing: MagpieServerProfile?
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var rawURL: String = ""
    @State private var webKey: String = ""
    @State private var allowInsecureTLS: Bool = false
    @State private var activateOnSave: Bool = true
    @State private var saveError: String?

    private var parsedPreview: ParsedMagpieLink? {
        MagpieWebLinkParser.parse(rawURL)
    }

    private var urlErrorText: String? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if parsedPreview != nil { return nil }
        return URLValidator.validateAndNormalize(trimmed).errorReason
    }

    private var urlHelperText: String? {
        if let parsed = parsedPreview {
            if let extracted = parsed.webKey {
                return "已自动识别地址 \(parsed.baseURL) 与密钥 k（\(KeychainStore.maskedPreview(extracted))）"
            }
            return parsed.baseURL
        }
        return "可直接粘贴 magpie web 启动时打印的完整带 ?k= 链接"
    }

    var body: some View {
        ZStack {
            MagpieTheme.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button("取消") { dismiss() }
                        .font(.system(size: 14))
                        .foregroundColor(MagpieTheme.textSecondary)
                    Spacer()
                    Text(existing == nil ? "连接 magpie web" : "编辑服务器")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(MagpieTheme.ink)
                    Spacer()
                    Button("保存并连接") { commitSave() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(MagpieTheme.ink)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
                .background(MagpieTheme.surface)
                .overlay(Rectangle().fill(MagpieTheme.hairline).frame(height: 1), alignment: .bottom)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        MinimalSection(title: "实例连接信息") {
                            MagpieInputField(
                                label: "实例备注名称",
                                placeholder: "例如：家里 NAS / 云服务器",
                                text: $name
                            )

                            MagpieInputField(
                                label: "magpie web 地址或启动链接",
                                placeholder: "https://your-host:3430/?k=...",
                                text: $rawURL,
                                monospaced: true,
                                keyboardType: .URL,
                                errorText: urlErrorText,
                                helperText: urlHelperText
                            )


                            MagpieInputField(
                                label: "访问密钥 k（MAGPIE_WEB_KEY）",
                                placeholder: existing == nil ? "不少于 16 位字符或 32 位 hex" : "留空则保留已保存密钥",
                                text: $webKey,
                                isSecure: true,
                                monospaced: true,
                                helperText: "通过 ?k= 交换服务端 HttpOnly Cookie（magpie_web_<port>），密钥仅保存在本机 Keychain"
                            )

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("允许自签名 HTTPS 证书")
                                        .font(.system(size: 13.5))
                                        .foregroundColor(MagpieTheme.ink)
                                    Text("内网或私有 CA 签发的 TLS 证书可开启")
                                        .font(.system(size: 11.5))
                                        .foregroundColor(MagpieTheme.textMuted)
                                }
                                Spacer()
                                MagpieToggle(isOn: $allowInsecureTLS)
                            }

                            if existing != nil {
                                HStack {
                                    Text("保存后立即切换连接")
                                        .font(.system(size: 13.5))
                                        .foregroundColor(MagpieTheme.ink)
                                    Spacer()
                                    MagpieToggle(isOn: $activateOnSave)
                                }
                            }
                        }

                        if let err = saveError {
                            MagpieErrorBanner(title: "无法保存", message: err)
                        }

                        MinimalSection(title: "鉴权说明", trailingText: "webGuard") {
                            Text("1. 服务端默认监听 3430 端口，未设置环境变量 MAGPIE_WEB_KEY 时每次启动会生成随机 32 位密钥。\n2. 客户端先请求 /api/state?k=<key> 换取 HttpOnly Cookie，后续所有 /api/* 请求仅携带 Cookie，不发送 Authorization: Bearer。\n3. 遇到 HTTP 401 时会自动使用当前 k 重新签发 Cookie 并重试。")
                                .font(.system(size: 12))
                                .foregroundColor(MagpieTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(22)
                }
            }
        }
        .preferredColorScheme(.light)
        .onAppear {
            if let existing = existing {
                name = existing.name
                rawURL = existing.baseURL
                allowInsecureTLS = existing.allowInsecureTLS
                activateOnSave = (store.activeServerID == existing.id)
                webKey = store.webKey(for: existing.id)
            }
        }
    }

    private func commitSave() {
        saveError = nil
        let result = store.saveServer(
            editingID: existing?.id,
            name: name,
            rawAddressOrLink: rawURL,
            rawWebKey: webKey,
            allowInsecureTLS: allowInsecureTLS,
            activateImmediately: activateOnSave
        )
        switch result {
        case .success(let saved):
            store.showToast("已保存「\(saved.name)」")
            dismiss()
        case .failure(let err):
            saveError = err.text
        }
    }
}
