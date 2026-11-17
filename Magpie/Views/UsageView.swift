import SwiftUI

struct UsageView: View {
    @ObservedObject var store: GatewayStore
    @State private var showingAutomation = false
    @State private var showingContextTune = false
    @State private var confirmClearUsage = false

    private let periods: [(id: String, title: String)] = [
        ("today", "今日"),
        ("7d", "7天"),
        ("30d", "30天"),
        ("all", "全部")
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("用量与额度")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(MagpieTheme.ink)
                        Text(TimeZone.current.identifier)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(MagpieTheme.textMuted)
                    }
                    Spacer()
                    Button(store.isLoadingUsage || store.isLoadingQuotas ? "刷新中" : "刷新") {
                        Task {
                            await store.refreshUsage()
                            await store.refreshQuotas(asked: true, all: true)
                        }
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
                    .disabled(store.isLoadingUsage)
                }

                periodBar

                if store.activeServer == nil {
                    MinimalSection {
                        Text("连接 magpie web 实例后，可在此查看跨端用量统计与各账号 5h/7d 额度窗口。")
                            .font(.system(size: 13))
                            .foregroundColor(MagpieTheme.textSecondary)
                    }
                } else {
                    HStack(spacing: 8) {
                        Button("签到与热身") { showingAutomation = true }
                            .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
                        Button("上下文调优 (原生)") { showingContextTune = true }
                            .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
                        Spacer()
                        Button("清空当前统计") { confirmClearUsage = true }
                            .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))
                    }
                    usageSummarySection
                    UsageTrendView(series: store.usageSummary?.series ?? [])
                    quotasSection
                    if let summary = store.usageSummary {
                        if !summary.models.isEmpty {
                            breakdownSection(title: "按模型统计", rows: Array(summary.models.prefix(8)))
                        }
                        if !summary.agents.isEmpty {
                            breakdownSection(title: "按客户端统计", rows: Array(summary.agents.prefix(6)))
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 100)
        }
        .sheet(isPresented: $showingAutomation) { UsageAutomationView(store: store) }
        .sheet(isPresented: $showingContextTune) { ContextTuneView(store: store) }
        .alert("清空当前用量统计视图？", isPresented: $confirmClearUsage) {
            Button("清空", role: .destructive) {
                Task {
                    try? await store.client.clearUsage()
                    await store.refreshUsage()
                    store.showToast("已清空当前用量统计视图")
                }
            }
            Button("取消", role: .cancel) {}
        }
        .onAppear {
            if store.activeServer != nil {
                if store.usageSummary == nil {
                    Task { await store.refreshUsage() }
                }
                if store.quotas.isEmpty {
                    Task { await store.refreshQuotas(asked: true, all: false) }
                }
            }
        }
        .refreshable {
            await store.refreshUsage()
            await store.refreshQuotas(asked: true, all: true)
        }
    }

    private var periodBar: some View {
        HStack(spacing: 8) {
            ForEach(periods, id: \.id) { item in
                let selected = store.usagePeriod == item.id
                Button(item.title) {
                    Task { await store.refreshUsage(period: item.id) }
                }
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(selected ? MagpieTheme.surface : MagpieTheme.textSecondary)
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .background(selected ? MagpieTheme.ink : MagpieTheme.surface)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(MagpieTheme.hairline, lineWidth: selected ? 0 : 1))
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var usageSummarySection: some View {
        let u = store.usageSummary
        return MinimalSection(title: "汇总指标", trailingText: u?.bucket ?? "") {
            HStack(spacing: 0) {
                metricCell(value: "\(u?.calls ?? 0)", label: "调用")
                metricCell(value: "\(u?.errors ?? 0)", label: "错误")
                metricCell(value: formatTokens((u?.input ?? 0) + (u?.output ?? 0)), label: "Tokens")
                metricCell(value: String(format: "$%.2f", u?.cost ?? 0), label: "费用")
            }

            if let u = u, (u.cacheRead > 0 || u.timed > 0) {
                Rectangle().fill(MagpieTheme.hairline).frame(height: 1)
                HStack {
                    let avgTTFT = u.timed > 0 ? Int(u.ttftMs / Int64(u.timed)) : 0
                    Text("缓存读取 \(formatTokens(u.cacheRead)) · 缓存写入 \(formatTokens(u.cacheWrite))")
                        .font(.system(size: 12))
                        .foregroundColor(MagpieTheme.textSecondary)
                    Spacer()
                    if avgTTFT > 0 {
                        Text("均首字 \(avgTTFT) ms")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundColor(MagpieTheme.textMuted)
                    }
                }
            }
        }
    }

    private var quotasSection: some View {
        MinimalSection(
            title: "订阅额度与余额窗口",
            trailingText: store.isLoadingQuotas ? "探测中…" : "\(store.quotas.count) 张"
        ) {
            if store.quotas.isEmpty {
                Text("暂无订阅或余额窗口信息")
                    .font(.system(size: 13))
                    .foregroundColor(MagpieTheme.textMuted)
            } else {
                ForEach(Array(store.quotas.enumerated()), id: \.element.id) { idx, q in
                    if idx > 0 {
                        Rectangle().fill(MagpieTheme.hairline).frame(height: 1)
                    }
                    quotaCard(q)
                }
            }
        }
    }

    private func quotaCard(_ q: RemoteUsageQuota) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(q.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(MagpieTheme.ink)
                        if let plan = q.plan, !plan.isEmpty {
                            MagpieTag(text: plan)
                        }
                    }
                    if let user = q.user, !user.isEmpty {
                        Text(user)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundColor(MagpieTheme.textMuted)
                    }
                }
                Spacer()
                if let bal = q.balance, !bal.isEmpty {
                    Text(bal)
                        .font(.system(size: 13.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(MagpieTheme.ink)
                }
                Button("刷新") {
                    Task { await store.refreshSingleQuota(provider: q.provider, user: q.user) }
                }
                .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))
            }

            if let err = q.pluginError ?? q.error, !err.isEmpty {
                Text(err)
                    .font(.system(size: 11.5))
                    .foregroundColor(MagpieTheme.err)
            }

            ForEach(q.windows) { w in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(w.name)
                            .font(.system(size: 12))
                            .foregroundColor(MagpieTheme.textSecondary)
                        Spacer()
                        if let display = w.display, !display.isEmpty {
                            Text(display)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundColor(MagpieTheme.ink)
                        } else if !w.text {
                            Text(String(format: "已用 %.0f%%", w.used))
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundColor(MagpieTheme.ink)
                        }
                    }
                    if !w.text && !w.unlimited {
                        MagpieProgressBar(ratio: w.used / 100.0)
                    }
                }
            }
        }
    }

    private func breakdownSection(title: String, rows: [RemoteUsageGroup]) -> some View {
        MinimalSection(title: title) {
            ForEach(Array(rows.enumerated()), id: \.element.uniqueID) { idx, row in
                if idx > 0 {
                    Rectangle().fill(MagpieTheme.hairline).frame(height: 1)
                }
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name.isEmpty ? row.id : row.name)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(MagpieTheme.ink)
                            .lineLimit(1)
                        if let sub = row.sub, !sub.isEmpty {
                            Text(sub)
                                .font(.system(size: 11.5))
                                .foregroundColor(MagpieTheme.textMuted)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(row.calls) 次 · \(formatTokens(row.input + row.output))")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundColor(MagpieTheme.textSecondary)
                        Text(String(format: "$%.3f", row.cost))
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundColor(MagpieTheme.ink)
                    }
                }
            }
        }
    }

    private func metricCell(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundColor(MagpieTheme.ink)
            Text(label)
                .font(.system(size: 11.5))
                .foregroundColor(MagpieTheme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        }
        if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        }
        return "\(count)"
    }
}
