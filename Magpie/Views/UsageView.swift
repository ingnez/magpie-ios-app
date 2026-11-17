import SwiftUI

struct UsageView: View {
    @ObservedObject var store: GatewayStore
    @State private var showingAutomation = false
    @State private var showingContextTune = false
    @State private var confirmClearUsage = false
    @State private var draftStartDate: Date = UsageDateRange.presetLastDays(7).startDate
    @State private var draftEndDate: Date = UsageDateRange.presetLastDays(7).endDate

    private let periods: [(id: String, title: String)] = [
        ("today", "今日"),
        ("7d", "7天"),
        ("30d", "30天"),
        ("all", "全部"),
        ("custom", "自定义")
    ]

    private var activeCustomRange: UsageDateRange {
        UsageDateRange(startDate: draftStartDate, endDate: draftEndDate)
    }

    private var isUsageEmpty: Bool {
        guard let u = store.usageSummary else { return false }
        return u.calls == 0 && u.series.isEmpty && u.models.isEmpty && u.agents.isEmpty
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Spacing.sectionGap) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("用量与额度")
                            .font(Typography.pageTitle)
                            .foregroundColor(MagpieTheme.ink)
                        Text(TimeZone.current.identifier)
                            .font(Typography.sectionHeaderMono)
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

                if store.usagePeriodPreset == "custom" {
                    customRangeSection
                }

                if store.activeServer == nil {
                    MinimalSection {
                        Text("连接 magpie web 实例后，可在此查看跨端用量统计与各账号 5h/7d 额度窗口。")
                            .font(Typography.body)
                            .foregroundColor(MagpieTheme.textSecondary)
                    }
                } else {
                    HStack(spacing: Spacing.sm) {
                        Button("签到与热身") { showingAutomation = true }
                            .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
                        Button("上下文调优 (原生)") { showingContextTune = true }
                            .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
                        Spacer()
                        Button("清空当前统计") { confirmClearUsage = true }
                            .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))
                    }

                    if let usageErr = store.usageError, !usageErr.isEmpty {
                        MagpieErrorBanner(
                            title: "用量数据获取失败",
                            message: "未能加载所选时段用量：\(usageErr)",
                            retryTitle: "重试"
                        ) {
                            Task { await store.refreshUsage() }
                        }
                    } else if store.isLoadingUsage && store.usageSummary == nil {
                        MinimalSection {
                            HStack(spacing: Spacing.sm) {
                                ProgressView()
                                Text("正在加载所选时段用量统计…")
                                    .font(Typography.body)
                                    .foregroundColor(MagpieTheme.textSecondary)
                            }
                        }
                    } else if isUsageEmpty {
                        emptyUsageSection
                    } else {
                        usageSummarySection
                        UsageTrendView(
                            series: store.usageSummary?.series ?? [],
                            totalCalls: store.usageSummary?.calls ?? 0
                        )
                    }

                    quotasSection

                    if let summary = store.usageSummary, !isUsageEmpty {
                        if !summary.models.isEmpty {
                            breakdownSection(title: "按模型统计", rows: Array(summary.models.prefix(8)))
                        }
                        if !summary.agents.isEmpty {
                            breakdownSection(title: "按客户端统计", rows: Array(summary.agents.prefix(6)))
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.pageHorizontal)
            .padding(.top, Spacing.pageTop)
            .padding(.bottom, Spacing.pageBottom)
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
            draftStartDate = store.customUsageStart
            draftEndDate = store.customUsageEnd
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(periods, id: \.id) { item in
                    let selected = store.usagePeriodPreset == item.id
                    Button(item.title) {
                        if item.id == "custom" {
                            draftStartDate = store.customUsageStart
                            draftEndDate = store.customUsageEnd
                            Task { await store.refreshCustomUsage(start: draftStartDate, end: draftEndDate) }
                        } else {
                            Task { await store.refreshUsage(period: item.id) }
                        }
                    }
                    .font(Typography.bodySmallMedium)
                    .foregroundColor(selected ? MagpieTheme.onInk : MagpieTheme.textSecondary)
                    .padding(.horizontal, Spacing.md + 1)
                    .padding(.vertical, Spacing.xs + 1)
                    .background(selected ? MagpieTheme.ink : MagpieTheme.surface)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(MagpieTheme.hairline, lineWidth: selected ? 0 : 1))
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("usagePeriod_\(item.id)")
                }
            }
        }
    }

    private var customRangeSection: some View {
        let range = activeCustomRange
        let norm = range.normalized()
        return MinimalSection(title: "自定义统计区间", trailingText: range.displayLabel()) {
            HStack(spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("开始日期")
                        .font(Typography.micro)
                        .foregroundColor(MagpieTheme.textMuted)
                    DatePicker("", selection: $draftStartDate, in: ...Date(), displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .accessibilityIdentifier("customUsageStartDate")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("结束日期")
                        .font(Typography.micro)
                        .foregroundColor(MagpieTheme.textMuted)
                    DatePicker("", selection: $draftEndDate, in: ...Date(), displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .accessibilityIdentifier("customUsageEndDate")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if norm.wasSwapped {
                Text("开始日期晚于结束日期，查询时将自动调整为 \(range.displayLabel())。")
                    .font(Typography.caption)
                    .foregroundColor(StatusPalette.warn)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    quickRangeChip("近 3 天", range: UsageDateRange.presetLastDays(3))
                    quickRangeChip("近 14 天", range: UsageDateRange.presetLastDays(14))
                    quickRangeChip("本月", range: UsageDateRange.currentMonth())
                    quickRangeChip("上月", range: previousMonthRange())
                }
            }

            HStack {
                Text("参数：\(range.apiPeriodString())")
                    .font(Typography.nanoMono)
                    .foregroundColor(MagpieTheme.textMuted)
                Spacer()
                Button(store.isLoadingUsage ? "查询中…" : "查询区间") {
                    Task { await store.refreshCustomUsage(start: draftStartDate, end: draftEndDate) }
                }
                .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
                .disabled(store.isLoadingUsage)
                .accessibilityIdentifier("applyCustomUsageRangeButton")
            }
        }
    }

    private func quickRangeChip(_ title: String, range: UsageDateRange) -> some View {
        Button(title) {
            draftStartDate = range.startDate
            draftEndDate = range.endDate
            Task { await store.refreshCustomUsage(start: range.startDate, end: range.endDate) }
        }
        .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))
    }

    private func previousMonthRange() -> UsageDateRange {
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        let currentMonthComps = cal.dateComponents([.year, .month], from: now)
        let thisMonthStart = cal.date(from: currentMonthComps) ?? now
        let prevMonthEnd = cal.date(byAdding: .day, value: -1, to: thisMonthStart) ?? now
        let prevMonthComps = cal.dateComponents([.year, .month], from: prevMonthEnd)
        let prevMonthStart = cal.date(from: prevMonthComps) ?? prevMonthEnd
        return UsageDateRange(startDate: prevMonthStart, endDate: prevMonthEnd)
    }

    private var emptyUsageSection: some View {
        let isCustom = store.usagePeriodPreset == "custom"
        let label = isCustom ? UsageDateRange(startDate: store.customUsageStart, endDate: store.customUsageEnd).displayLabel() : "当前周期"
        return MinimalSection(title: "暂无调用数据", trailingText: isCustom ? store.usagePeriod : "") {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 18))
                        .foregroundColor(StatusPalette.warn)
                    Text(isCustom ? "所选区间暂无用量记录" : "当前统计周期暂无用量记录")
                        .font(Typography.cardTitle)
                        .foregroundColor(MagpieTheme.ink)
                }

                Text(isCustom
                    ? "\(label) 期间未查询到任何 API 请求或 Token 消耗。你可以调整起止日期，或切回「7天」「全部」查看其他时段。"
                    : "该统计时段内尚未产生模型调用，或统计视图刚被清空。")
                    .font(Typography.body)
                    .foregroundColor(MagpieTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Spacing.sm) {
                    Button("查看全部历史") {
                        Task { await store.refreshUsage(period: "all") }
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))

                    Button("重新查询") {
                        Task { await store.refreshUsage() }
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("usageEmptyStateCard")
        }
    }

    private var usageSummarySection: some View {
        let u = store.usageSummary
        let trailing = store.usagePeriodPreset == "custom"
            ? UsageDateRange(startDate: store.customUsageStart, endDate: store.customUsageEnd).displayLabel()
            : (u?.bucket ?? "")
        return MinimalSection(title: "汇总指标", trailingText: trailing) {
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
                        .font(Typography.sectionHeader)
                        .foregroundColor(MagpieTheme.textSecondary)
                    Spacer()
                    if avgTTFT > 0 {
                        Text("均首字 \(avgTTFT) ms")
                            .font(Typography.captionMono)
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
                    .font(Typography.body)
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
        VStack(alignment: .leading, spacing: Spacing.sm + 2) {
            HStack(spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Spacing.xs) {
                        Text(q.name)
                            .font(Typography.bodyMedium)
                            .foregroundColor(MagpieTheme.ink)
                        if let plan = q.plan, !plan.isEmpty {
                            MagpieTag(text: plan)
                        }
                    }
                    if let user = q.user, !user.isEmpty {
                        Text(user)
                            .font(Typography.captionMono)
                            .foregroundColor(MagpieTheme.textMuted)
                    }
                }
                Spacer()
                if let bal = q.balance, !bal.isEmpty {
                    Text(bal)
                        .font(Typography.rowTitleMono)
                        .foregroundColor(MagpieTheme.ink)
                }
                Button("刷新") {
                    Task { await store.refreshSingleQuota(provider: q.provider, user: q.user) }
                }
                .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))
            }

            if let err = q.pluginError ?? q.error, !err.isEmpty {
                Text(err)
                    .font(Typography.caption)
                    .foregroundColor(StatusPalette.err)
            }

            ForEach(q.windows) { w in
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack {
                        Text(w.name)
                            .font(Typography.sectionHeader)
                            .foregroundColor(MagpieTheme.textSecondary)
                        Spacer()
                        if let display = w.display, !display.isEmpty {
                            Text(display)
                                .font(Typography.captionMono)
                                .foregroundColor(MagpieTheme.ink)
                        } else if w.unlimited {
                            Text("不限量")
                                .font(Typography.caption)
                                .foregroundColor(StatusPalette.ok)
                        } else if !w.text {
                            Text(String(format: "已用 %.0f%%", w.used))
                                .font(Typography.captionMono)
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
                HStack(spacing: Spacing.sm + 2) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name.isEmpty ? row.id : row.name)
                            .font(Typography.bodyMono)
                            .foregroundColor(MagpieTheme.ink)
                            .lineLimit(1)
                        if let sub = row.sub, !sub.isEmpty {
                            Text(sub)
                                .font(Typography.caption)
                                .foregroundColor(MagpieTheme.textMuted)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(row.calls) 次 · \(formatTokens(row.input + row.output))")
                            .font(Typography.captionMono)
                            .foregroundColor(MagpieTheme.textSecondary)
                        Text(String(format: "$%.3f", row.cost))
                            .font(Typography.captionMono)
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
                .font(Typography.caption)
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
