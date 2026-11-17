import SwiftUI

struct DashboardView: View {
    @ObservedObject var store: GatewayStore
    let onSwitchTab: (MagpieTab) -> Void
    let onOpenNewProfile: () -> Void

    @State private var isRunningSmoke = false
    @State private var smokeSummary: (ok: Bool, statusCode: Int, latencyMs: Int, output: String)?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26) {
                heroStatusBlock

                if let daemonErr = store.statusSnapshot.lastError {
                    MagpieErrorBanner(
                        title: "本地端口异常",
                        message: daemonErr,
                        retryTitle: "重试"
                    ) {
                        Task { await store.checkLocalDaemon() }
                    }
                } else if store.activeHealth.kind == .failed {
                    MagpieErrorBanner(
                        title: "上游连接异常",
                        message: store.activeHealth.message,
                        retryTitle: "重测"
                    ) {
                        Task { await store.probeActiveConnection() }
                    }
                }

                endpointSection
                metricsAndPrivacySection
                smokeTestSection
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 100)
        }
    }

    // MARK: - Hero Status (Generous Whitespace, No Box Clutter)

    private var heroStatusBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                MagpieStatusLight(kind: store.activeHealth.kind)
                Text(statusHeadline)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(MagpieTheme.textSecondary)
                Spacer()
                if let ms = store.activeHealth.latencyMs {
                    Text("\(ms) ms")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(MagpieTheme.textMuted)
                }
            }

            Text(store.activeProfile?.name ?? "本地回环模式")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(MagpieTheme.ink)

            Text(store.activeProfile?.baseURL ?? "未指定外部上游 · 请求由 127.0.0.1:3425 本地响应")
                .font(.system(size: 13, design: store.activeProfile != nil ? .monospaced : .default))
                .foregroundColor(MagpieTheme.textSecondary)
                .lineLimit(1)

            if let profile = store.activeProfile {
                HStack(spacing: 8) {
                    MagpieTag(text: profile.targetProtocol.displayName)
                    MagpieTag(text: profile.defaultModel, monospaced: true)
                }
            }

            HStack(spacing: 10) {
                if store.activeProfile != nil {
                    Button(store.activeHealth.kind == .checking ? "检测中…" : "检测连通") {
                        Task { await store.probeActiveConnection() }
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
                    .disabled(store.activeHealth.kind == .checking)
                } else {
                    Button("添加配置") {
                        onOpenNewProfile()
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
                }

                Button(store.profiles.isEmpty ? "管理配置" : "切换配置 (\(store.profiles.count))") {
                    onSwitchTab(.profiles)
                }
                .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
            }
            .padding(.top, 2)
        }
        .padding(.bottom, 4)
    }

    private var statusHeadline: String {
        switch store.activeHealth.kind {
        case .connected: return "上游已连通"
        case .checking: return "正在探测上游"
        case .localOnly: return "本地网关就绪"
        case .failed: return "连接失败"
        case .untested: return "待检测"
        }
    }

    // MARK: - Section 1: Local Endpoint & Client Copy

    private var endpointSection: some View {
        MinimalSection(title: "本地网关入口", trailingText: "OpenAI / Claude / Gemini") {
            HStack(spacing: 12) {
                Text("http://127.0.0.1:3425/v1")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(MagpieTheme.ink)
                    .lineLimit(1)
                Spacer()
                Button("复制") {
                    store.copyToClipboard("http://127.0.0.1:3425/v1", label: "本地入口")
                }
                .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))
            }

            Rectangle()
                .fill(MagpieTheme.hairline)
                .frame(height: 1)

            HStack(spacing: 8) {
                Button("SillyTavern") {
                    let model = store.activeProfile?.defaultModel ?? "claude-sonnet-4-5"
                    let json = """
                    {"chat_completion_source":"custom","custom_url":"http://127.0.0.1:3425/v1","custom_api_key":"sk-magpie-local","custom_model":"\(model)"}
                    """
                    store.copyToClipboard(json, label: " SillyTavern 配置")
                }
                .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))

                Button("Claude Code") {
                    let env = "export ANTHROPIC_BASE_URL=\"http://127.0.0.1:3425\"\nexport OPENAI_BASE_URL=\"http://127.0.0.1:3425/v1\""
                    store.copyToClipboard(env, label: "环境变量")
                }
                .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))

                Spacer()

                Text("/v1/messages · /v1/responses")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(MagpieTheme.textMuted)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Section 2: Metrics & Privacy Shield

    private var metricsAndPrivacySection: some View {
        MinimalSection(title: "运行统计与隐私", trailingText: store.privacySettings.enabled ? "脱敏开启" : "直通") {
            HStack(spacing: 0) {
                statCell(value: "\(store.statusSnapshot.requestsHandled)", label: "请求")
                statCell(value: "\(store.statusSnapshot.successCount)", label: "成功")
                statCell(value: "\(store.statusSnapshot.errorCount)", label: "错误")
                statCell(value: "\(store.statusSnapshot.maskedItemsCount)", label: "已脱敏")
            }

            Rectangle()
                .fill(MagpieTheme.hairline)
                .frame(height: 1)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("出站隐私脱敏")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(MagpieTheme.ink)
                    Text("自动掩码密钥、邮箱与手机号，响应时还原")
                        .font(.system(size: 12))
                        .foregroundColor(MagpieTheme.textMuted)
                }
                Spacer()
                MagpieToggle(isOn: $store.privacySettings.enabled)
            }
        }
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundColor(MagpieTheme.ink)
            Text(label)
                .font(.system(size: 11.5))
                .foregroundColor(MagpieTheme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Section 3: Self-Check

    private var smokeTestSection: some View {
        MinimalSection(title: "链路自检") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("本地闭环验证")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(MagpieTheme.ink)
                    Text("校验 3425 端口协议转换与脱敏回显")
                        .font(.system(size: 12))
                        .foregroundColor(MagpieTheme.textMuted)
                }
                Spacer()
                Button(isRunningSmoke ? "自检中…" : "发起自检") {
                    isRunningSmoke = true
                    Task {
                        let model = store.activeProfile?.defaultModel ?? "gpt-4o"
                        smokeSummary = await store.runGatewaySmokeTest(
                            route: "/v1/chat/completions",
                            prompt: "自检测试：密钥 sk-test-9988776655，邮箱 dev@magpie.local",
                            model: model
                        )
                        isRunningSmoke = false
                    }
                }
                .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
                .disabled(isRunningSmoke)
            }

            if let smoke = smokeSummary {
                Rectangle()
                    .fill(MagpieTheme.hairline)
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(smoke.ok ? MagpieTheme.ok : MagpieTheme.err)
                            .frame(width: 6, height: 6)
                        Text("HTTP \(smoke.statusCode) · \(smoke.latencyMs) ms")
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundColor(MagpieTheme.textSecondary)
                    }
                    Text(smoke.output)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(MagpieTheme.textSecondary)
                        .lineLimit(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
