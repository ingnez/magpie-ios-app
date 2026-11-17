import SwiftUI

struct DashboardView: View {
    @ObservedObject var store: GatewayStore
    let onSwitchTab: (MagpieTab) -> Void
    let onOpenNewProfile: () -> Void

    @State private var isRunningSmoke = false
    @State private var smokeSummary: (ok: Bool, statusCode: Int, latencyMs: Int, output: String)?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                activeConnectionCard

                if let daemonErr = store.statusSnapshot.lastError {
                    MagpieErrorBanner(
                        title: "本地网关监听异常",
                        message: daemonErr,
                        retryTitle: "重试检测"
                    ) {
                        Task { await store.checkLocalDaemon() }
                    }
                } else if store.activeHealth.kind == .failed {
                    MagpieErrorBanner(
                        title: "上游连接失败",
                        message: store.activeHealth.message,
                        retryTitle: "重新探测"
                    ) {
                        Task { await store.probeActiveConnection() }
                    }
                }

                localEndpointCard
                metricsAndShieldCard
                quickExportCard
                liveSmokeTestCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 100)
        }
    }

    // MARK: - Card 1: Active Upstream & Status Light

    private var activeConnectionCard: some View {
        MagpieCard(elevated: true, borderColor: borderForHealth(store.activeHealth.kind)) {
            HStack(alignment: .top, spacing: 10) {
                MagpieStatusLight(kind: store.activeHealth.kind)
                    .padding(.top, 3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(store.activeProfile?.name ?? "本地回环网关模式")
                        .font(.system(size: 16.5, weight: .bold))
                        .foregroundColor(MagpieTheme.textPrimary)

                    if let profile = store.activeProfile {
                        Text(profile.baseURL)
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundColor(MagpieTheme.textSecondary)
                            .lineLimit(1)
                    } else {
                        Text("未选择上游服务器 · 请求将在本地 127.0.0.1:3425 回环响应")
                            .font(.system(size: 12.5))
                            .foregroundColor(MagpieTheme.textSecondary)
                    }
                }

                Spacer(minLength: 6)

                latencyBadgeView
            }

            if let profile = store.activeProfile {
                HStack(spacing: 8) {
                    MagpieBadge(text: profile.targetProtocol.displayName, color: MagpieTheme.amber)
                    MagpieBadge(text: profile.defaultModel, color: MagpieTheme.teal, monospaced: true)
                    Spacer()
                }
            }

            Text(store.activeHealth.message)
                .font(.system(size: 12.5))
                .foregroundColor(textColorForHealth(store.activeHealth.kind))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                if store.activeProfile != nil {
                    Button {
                        Task { await store.probeActiveConnection() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: store.activeHealth.kind == .checking ? "arrow.triangle.2.circlepath" : "waveform.path.ecg")
                            Text(store.activeHealth.kind == .checking ? "探测中…" : "检测连通性")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .teal, compact: true))
                    .disabled(store.activeHealth.kind == .checking)
                } else {
                    Button {
                        onOpenNewProfile()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                            Text("添加反代服务器")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
                }

                Button {
                    onSwitchTab(.profiles)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                        Text(store.profiles.isEmpty ? "配置管理" : "切换配置 (\(store.profiles.count))")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
            }
        }
    }

    @ViewBuilder
    private var latencyBadgeView: some View {
        switch store.activeHealth.kind {
        case .connected:
            let ms = store.activeHealth.latencyMs ?? 0
            let col: Color = ms < 500 ? MagpieTheme.teal : MagpieTheme.warning
            MagpieBadge(text: "\(ms) ms", color: col, monospaced: true)
        case .checking:
            MagpieBadge(text: "测速中", color: MagpieTheme.amber)
        case .failed:
            if let code = store.activeHealth.statusCode {
                MagpieBadge(text: "HTTP \(code)", color: MagpieTheme.coral, monospaced: true)
            } else {
                MagpieBadge(text: "离线", color: MagpieTheme.coral)
            }
        case .localOnly:
            MagpieBadge(text: "LOCAL", color: MagpieTheme.warning, monospaced: true)
        case .untested:
            MagpieBadge(text: "待检测", color: MagpieTheme.textSecondary)
        }
    }

    // MARK: - Card 2: Local Endpoint & Supported Routes

    private var localEndpointCard: some View {
        MagpieCard {
            HStack {
                Text("本地统一网关入口")
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundColor(MagpieTheme.textPrimary)
                Spacer()
                MagpieBadge(
                    text: store.statusSnapshot.daemonOnline ? "127.0.0.1:3425 在线" : "端口离线",
                    color: store.statusSnapshot.daemonOnline ? MagpieTheme.teal : MagpieTheme.coral,
                    monospaced: true
                )
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Base URL")
                        .font(.system(size: 11))
                        .foregroundColor(MagpieTheme.textMuted)
                    Text("http://127.0.0.1:3425/v1")
                        .font(.system(size: 13.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(MagpieTheme.amber)
                }
                Spacer()
                Button("复制") {
                    store.copyToClipboard("http://127.0.0.1:3425/v1", label: "本地端点")
                }
                .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
            }
            .padding(11)
            .background(MagpieTheme.input)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(MagpieTheme.border, lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("已挂载协议接口")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(MagpieTheme.textSecondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    routePill("/v1/chat/completions")
                    routePill("/v1/responses")
                    routePill("/v1/messages")
                    routePill("/v1beta/models/...")
                }
            }
        }
    }

    private func routePill(_ path: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(MagpieTheme.teal)
                .frame(width: 5, height: 5)
            Text(path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(MagpieTheme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(MagpieTheme.input)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Card 3: Metrics & Privacy Shield Toggle

    private var metricsAndShieldCard: some View {
        MagpieCard {
            HStack {
                Text("实时转发与隐私脱敏")
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundColor(MagpieTheme.textPrimary)
                Spacer()
                Button("查看日志") {
                    onSwitchTab(.logs)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(MagpieTheme.amber)
            }

            HStack(spacing: 8) {
                metricBox(value: "\(store.statusSnapshot.requestsHandled)", label: "总请求", color: MagpieTheme.textPrimary)
                metricBox(value: "\(store.statusSnapshot.successCount)", label: "成功", color: MagpieTheme.teal)
                metricBox(value: "\(store.statusSnapshot.errorCount)", label: "失败", color: store.statusSnapshot.errorCount > 0 ? MagpieTheme.coral : MagpieTheme.textSecondary)
                metricBox(value: "\(store.statusSnapshot.maskedItemsCount)", label: "已脱敏", color: MagpieTheme.amber)
            }

            Divider().background(MagpieTheme.border)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("请求出站隐私脱敏护盾")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(MagpieTheme.textPrimary)
                    Text(store.privacySettings.enabled
                         ? "已启用：自动替换 API Key、邮箱、手机号为占位符并在回包时还原"
                         : "已关闭：请求正文将原样转发至上游")
                        .font(.system(size: 11.5))
                        .foregroundColor(MagpieTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                MagpieToggle(isOn: $store.privacySettings.enabled, accent: MagpieTheme.amber)
            }
        }
    }

    private func metricBox(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(MagpieTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(MagpieTheme.input)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Card 4: Quick Client Presets

    private var quickExportCard: some View {
        MagpieCard {
            Text("一键复制下游接入配置")
                .font(.system(size: 14.5, weight: .bold))
                .foregroundColor(MagpieTheme.textPrimary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                Button("SillyTavern 配置") {
                    let model = store.activeProfile?.defaultModel ?? "claude-sonnet-4-5"
                    let json = """
                    {
                      "chat_completion_source": "custom",
                      "custom_url": "http://127.0.0.1:3425/v1",
                      "custom_api_key": "sk-magpie-local",
                      "custom_model": "\(model)"
                    }
                    """
                    store.copyToClipboard(json, label: " SillyTavern 配置")
                }
                .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))

                Button("Claude Code 变量") {
                    let env = """
                    export ANTHROPIC_BASE_URL="http://127.0.0.1:3425"
                    export ANTHROPIC_API_KEY="sk-magpie-local"
                    export OPENAI_BASE_URL="http://127.0.0.1:3425/v1"
                    """
                    store.copyToClipboard(env, label: " Claude Code 环境变量")
                }
                .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))

                Button("Cherry / ChatBox") {
                    store.copyToClipboard("http://127.0.0.1:3425/v1", label: " Cherry / ChatBox 端点")
                }
                .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))

                Button("状态接口 /api/status") {
                    store.copyToClipboard("http://127.0.0.1:3425/api/status", label: "状态接口地址")
                }
                .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
            }
        }
    }

    // MARK: - Card 5: Live Gateway Smoke Test

    private var liveSmokeTestCard: some View {
        MagpieCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("本地网关闭环自检")
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundColor(MagpieTheme.textPrimary)
                    Text("实测 127.0.0.1:3425 路由转换与脱敏链路")
                        .font(.system(size: 11.5))
                        .foregroundColor(MagpieTheme.textSecondary)
                }
                Spacer()
                Button(isRunningSmoke ? "请求中…" : "发起自检") {
                    isRunningSmoke = true
                    Task {
                        let model = store.activeProfile?.defaultModel ?? "gpt-4o"
                        let res = await store.runGatewaySmokeTest(
                            route: "/v1/chat/completions",
                            prompt: "自检测试：我的临时密钥 sk-test-9988776655，邮箱 dev@magpie.local",
                            model: model
                        )
                        smokeSummary = res
                        isRunningSmoke = false
                    }
                }
                .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
                .disabled(isRunningSmoke)
            }

            if let smoke = smokeSummary {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        MagpieBadge(
                            text: smoke.ok ? "HTTP \(smoke.statusCode) 通过" : "HTTP \(smoke.statusCode) 失败",
                            color: smoke.ok ? MagpieTheme.teal : MagpieTheme.coral,
                            monospaced: true
                        )
                        MagpieBadge(text: "\(smoke.latencyMs) ms", color: MagpieTheme.amber, monospaced: true)
                        Spacer()
                    }
                    Text(smoke.output)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(MagpieTheme.textSecondary)
                        .lineLimit(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(MagpieTheme.input)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private func borderForHealth(_ kind: ConnectionStatusKind) -> Color {
        switch kind {
        case .connected: return MagpieTheme.teal.opacity(0.45)
        case .failed: return MagpieTheme.coral.opacity(0.6)
        case .checking: return MagpieTheme.amber.opacity(0.55)
        default: return MagpieTheme.borderStrong
        }
    }

    private func textColorForHealth(_ kind: ConnectionStatusKind) -> Color {
        switch kind {
        case .connected: return MagpieTheme.teal
        case .failed: return MagpieTheme.coral
        case .checking: return MagpieTheme.amber
        case .localOnly: return MagpieTheme.warning
        case .untested: return MagpieTheme.textSecondary
        }
    }
}
