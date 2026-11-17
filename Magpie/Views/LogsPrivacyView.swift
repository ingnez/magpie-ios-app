import SwiftUI

struct LogsPrivacyView: View {
    @ObservedObject var store: GatewayStore
    @State private var logFilter: LogFilter = .all
    @State private var expandedLogID: UUID?
    @State private var sampleInput: String = "测试密钥 sk-proj-998877665544，邮箱 admin@hospital.org，手机 13800138000"

    enum LogFilter: String, CaseIterable {
        case all = "全部"
        case errors = "仅报错"
        case masked = "触发脱敏"
    }

    private var filteredLogs: [GatewayLogEntry] {
        store.logs.filter { entry in
            switch logFilter {
            case .all: return true
            case .errors: return entry.outcome == .error || entry.statusCode >= 400
            case .masked: return entry.maskedCount > 0
            }
        }
    }

    private var liveMaskPreview: PrivacyMaskResult {
        PrivacyMasker.maskText(sampleInput, settings: store.privacySettings)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                privacyControlCard
                logsHeaderCard

                if filteredLogs.isEmpty {
                    MagpieCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(store.logs.isEmpty ? "暂无网关请求记录" : "当前筛选条件下无记录")
                                .font(.system(size: 14.5, weight: .bold))
                                .foregroundColor(MagpieTheme.textPrimary)
                            Text("当外部客户端或应用内自检请求 127.0.0.1:3425 的接口时，每次路由转换、延迟、脱敏次数和报错详情都会实时记录在此处。")
                                .font(.system(size: 12))
                                .foregroundColor(MagpieTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredLogs) { entry in
                            logRowCard(entry)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 100)
        }
    }

    // MARK: - Privacy Masking Card

    private var privacyControlCard: some View {
        MagpieCard(elevated: true, borderColor: store.privacySettings.enabled ? MagpieTheme.amber.opacity(0.45) : MagpieTheme.border) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("隐私脱敏引擎")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(MagpieTheme.textPrimary)
                    Text(store.privacySettings.enabled ? "出站前自动替换为恒定占位符，回包时自动还原" : "当前已关闭，明文直通上游")
                        .font(.system(size: 12))
                        .foregroundColor(MagpieTheme.textSecondary)
                }
                Spacer()
                MagpieToggle(isOn: $store.privacySettings.enabled, accent: MagpieTheme.amber)
            }

            if store.privacySettings.enabled {
                Divider().background(MagpieTheme.border)

                VStack(spacing: 10) {
                    ruleToggleRow(
                        title: "API Key / Bearer 密钥",
                        subtitle: "匹配 sk-..., AIza..., ghp_... 与 Bearer Token",
                        isOn: $store.privacySettings.maskAPIKeys
                    )
                    ruleToggleRow(
                        title: "电子邮箱地址",
                        subtitle: "匹配标准 email 格式并替换为 {{EMAIL_n}}",
                        isOn: $store.privacySettings.maskEmails
                    )
                    ruleToggleRow(
                        title: "中国大陆手机号",
                        subtitle: "匹配 11 位手机号码并替换为 {{PHONE_n}}",
                        isOn: $store.privacySettings.maskPhones
                    )
                }

                MagpieInputField(
                    label: "自定义敏感词（逗号分隔）",
                    placeholder: "例如：内部域名, 病人姓名, 工号",
                    text: $store.privacySettings.customKeywordsText
                )

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("脱敏效果实时预览")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(MagpieTheme.textSecondary)
                        Spacer()
                        MagpieBadge(
                            text: "命中 \(liveMaskPreview.count) 处",
                            color: liveMaskPreview.count > 0 ? MagpieTheme.teal : MagpieTheme.textMuted
                        )
                    }

                    TextField("输入含敏感内容的测试文本…", text: $sampleInput)
                        .font(.system(size: 12.5))
                        .foregroundColor(MagpieTheme.textPrimary)
                        .padding(10)
                        .background(MagpieTheme.input)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(MagpieTheme.border, lineWidth: 1)
                        )

                    Text("发往上游：\(liveMaskPreview.maskedText)")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(MagpieTheme.teal)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(MagpieTheme.input)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }
        }
    }

    private func ruleToggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(MagpieTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundColor(MagpieTheme.textMuted)
            }
            Spacer()
            MagpieToggle(isOn: isOn, accent: MagpieTheme.teal)
        }
    }

    // MARK: - Logs List

    private var logsHeaderCard: some View {
        MagpieCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("网关请求日志 (\(filteredLogs.count))")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(MagpieTheme.textPrimary)
                    Text("实时记录本地 127.0.0.1:3425 转发与转换明细")
                        .font(.system(size: 11.5))
                        .foregroundColor(MagpieTheme.textSecondary)
                }
                Spacer()
                if !store.logs.isEmpty {
                    Button("清空") {
                        store.clearLogs()
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .danger, compact: true))
                }
            }

            HStack(spacing: 8) {
                ForEach(LogFilter.allCases, id: \.self) { f in
                    let selected = logFilter == f
                    Button(f.rawValue) {
                        logFilter = f
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(selected ? MagpieTheme.canvas : MagpieTheme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(selected ? MagpieTheme.amber : MagpieTheme.input)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(selected ? MagpieTheme.amber : MagpieTheme.border, lineWidth: 1)
                    )
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
    }

    private func logRowCard(_ entry: GatewayLogEntry) -> some View {
        let isExpanded = expandedLogID == entry.id
        let isError = entry.outcome == .error || entry.statusCode >= 400
        let statusColor: Color = isError ? MagpieTheme.coral : (entry.outcome == .localLoopback ? MagpieTheme.warning : MagpieTheme.teal)

        return MagpieCard(
            borderColor: isError ? MagpieTheme.coral.opacity(0.45) : MagpieTheme.border
        ) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    expandedLogID = isExpanded ? nil : entry.id
                }
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        MagpieBadge(text: "\(entry.method) \(entry.statusCode)", color: statusColor, monospaced: true)
                        Text(entry.path)
                            .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(MagpieTheme.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        MagpieBadge(text: "\(entry.latencyMs) ms", color: MagpieTheme.textSecondary, monospaced: true)
                    }

                    HStack(spacing: 6) {
                        Text("\(entry.inboundProtocol) → \(entry.targetProtocol)")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundColor(MagpieTheme.textSecondary)
                        if !entry.model.isEmpty && entry.model != "-" {
                            MagpieBadge(text: entry.model, color: MagpieTheme.amber, monospaced: true)
                        }
                        if entry.maskedCount > 0 {
                            MagpieBadge(text: "脱敏 \(entry.maskedCount)", color: MagpieTheme.teal)
                        }
                        Spacer()
                        Text(Self.timeFormatter.string(from: entry.timestamp))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(MagpieTheme.textMuted)
                    }

                    if let err = entry.errorMessage, !err.isEmpty {
                        Text(err)
                            .font(.system(size: 12))
                            .foregroundColor(MagpieTheme.coral)
                            .lineLimit(isExpanded ? nil : 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(entry.requestPreview)
                            .font(.system(size: 12))
                            .foregroundColor(MagpieTheme.textMuted)
                            .lineLimit(isExpanded ? nil : 1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().background(MagpieTheme.border)
                VStack(alignment: .leading, spacing: 6) {
                    if !entry.upstreamURL.isEmpty {
                        Text("上游目标：\(entry.upstreamURL)")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundColor(MagpieTheme.textSecondary)
                    }
                    Text("请求摘要：\(entry.requestPreview)")
                        .font(.system(size: 11.5))
                        .foregroundColor(MagpieTheme.textSecondary)
                    Text("响应摘要：\(entry.responsePreview)")
                        .font(.system(size: 11.5))
                        .foregroundColor(isError ? MagpieTheme.coral : MagpieTheme.teal)
                }
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        return df
    }()
}
