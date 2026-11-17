import SwiftUI

struct LogsPrivacyView: View {
    @ObservedObject var store: GatewayStore
    @State private var logFilter: LogFilter = .all
    @State private var expandedLogID: UUID?
    @State private var sampleInput: String = "密钥 sk-proj-998877665544，邮箱 admin@hospital.org，手机 13800138000"

    enum LogFilter: String, CaseIterable {
        case all = "全部"
        case errors = "错误"
        case masked = "脱敏"
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
            VStack(alignment: .leading, spacing: 24) {
                Text("隐私与日志")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(MagpieTheme.ink)

                privacySection
                logsSection
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 100)
        }
    }

    private var privacySection: some View {
        MinimalSection(title: "隐私脱敏规则", trailingText: store.privacySettings.enabled ? "已开启" : "已关闭") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("双向脱敏引擎")
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundColor(MagpieTheme.ink)
                    Text("出站替换为占位符，响应自动还原")
                        .font(.system(size: 12))
                        .foregroundColor(MagpieTheme.textMuted)
                }
                Spacer()
                MagpieToggle(isOn: $store.privacySettings.enabled)
            }

            if store.privacySettings.enabled {
                Rectangle().fill(MagpieTheme.hairline).frame(height: 1)

                ruleRow("API 密钥与 Token", isOn: $store.privacySettings.maskAPIKeys)
                ruleRow("电子邮箱地址", isOn: $store.privacySettings.maskEmails)
                ruleRow("手机号码", isOn: $store.privacySettings.maskPhones)

                MagpieInputField(
                    label: "自定义敏感词（逗号分隔）",
                    placeholder: "例如：内部域名, 姓名",
                    text: $store.privacySettings.customKeywordsText
                )

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("脱敏预览")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(MagpieTheme.textSecondary)
                        Spacer()
                        Text("命中 \(liveMaskPreview.count) 处")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundColor(MagpieTheme.textMuted)
                    }
                    Text(liveMaskPreview.maskedText)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(MagpieTheme.textSecondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(MagpieTheme.canvas)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    private func ruleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13.5))
                .foregroundColor(MagpieTheme.ink)
            Spacer()
            MagpieToggle(isOn: isOn)
        }
    }

    private var logsSection: some View {
        MinimalSection(title: "请求日志 (\(filteredLogs.count))") {
            HStack(spacing: 6) {
                ForEach(LogFilter.allCases, id: \.self) { f in
                    let selected = logFilter == f
                    Button(f.rawValue) {
                        logFilter = f
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(selected ? MagpieTheme.surface : MagpieTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(selected ? MagpieTheme.ink : MagpieTheme.canvas)
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
                }
                Spacer()
                if !store.logs.isEmpty {
                    Button("清空") {
                        store.clearLogs()
                    }
                    .font(.system(size: 12))
                    .foregroundColor(MagpieTheme.textMuted)
                    .buttonStyle(.plain)
                }
            }

            if filteredLogs.isEmpty {
                Text("暂无请求记录")
                    .font(.system(size: 13))
                    .foregroundColor(MagpieTheme.textMuted)
                    .padding(.vertical, 6)
            } else {
                ForEach(Array(filteredLogs.enumerated()), id: \.element.id) { idx, entry in
                    if idx > 0 {
                        Rectangle().fill(MagpieTheme.hairline).frame(height: 1)
                    }
                    logRow(entry)
                }
            }
        }
    }

    private func logRow(_ entry: GatewayLogEntry) -> some View {
        let isExpanded = expandedLogID == entry.id
        let isError = entry.outcome == .error || entry.statusCode >= 400

        return VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    expandedLogID = isExpanded ? nil : entry.id
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(isError ? MagpieTheme.err : MagpieTheme.ok)
                            .frame(width: 6, height: 6)
                        Text("\(entry.method) \(entry.path)")
                            .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                            .foregroundColor(MagpieTheme.ink)
                            .lineLimit(1)
                        Spacer()
                        Text("\(entry.statusCode) · \(entry.latencyMs) ms")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundColor(MagpieTheme.textMuted)
                    }

                    Text(entry.errorMessage ?? entry.requestPreview)
                        .font(.system(size: 12))
                        .foregroundColor(isError ? MagpieTheme.err : MagpieTheme.textSecondary)
                        .lineLimit(isExpanded ? nil : 1)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(entry.responsePreview)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundColor(MagpieTheme.textMuted)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MagpieTheme.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }
}
