import SwiftUI

struct AccountErrorsView: View {
    @ObservedObject var store: GatewayStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategory: AccountErrorCategory? = nil
    @State private var isRefreshing = false

    private var allItems: [AccountErrorItem] {
        store.accountErrorItems
    }

    private var filteredItems: [AccountErrorItem] {
        guard let cat = selectedCategory else { return allItems }
        return allItems.filter { $0.category == cat }
    }

    private var consecutiveCount: Int {
        allItems.filter(\.isConsecutive).count
    }

    var body: some View {
        NavigationView {
            ZStack {
                MagpieTheme.canvas.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Spacing.sectionGap) {
                        summarySection

                        if let res = store.lastQuickSwitchResult {
                            QuickSwitchResultBanner(store: store, result: res) {
                                store.lastQuickSwitchResult = nil
                            }
                        }

                        if !allItems.isEmpty {
                            categoryFilterBar
                        }

                        if filteredItems.isEmpty {
                            emptyStateSection
                        } else {
                            ForEach(filteredItems) { item in
                                errorCard(item)
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.pageHorizontal)
                    .padding(.top, Spacing.sheetPadding)
                    .padding(.bottom, Spacing.pageBottom)
                }
            }
            .navigationTitle("账号异常总览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .foregroundColor(MagpieTheme.textSecondary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(isRefreshing ? "刷新中" : "刷新") {
                        refreshAll()
                    }
                    .foregroundColor(MagpieTheme.ink)
                    .disabled(isRefreshing)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var summarySection: some View {
        MinimalSection(
            title: "异常状态聚合（只读）",
            trailingText: allItems.isEmpty ? "全员健康" : "\(allItems.count) 项异常"
        ) {
            HStack(spacing: 0) {
                statCell(value: "\(allItems.count)", label: "异常账号", tone: allItems.isEmpty ? StatusPalette.ok : StatusPalette.err)
                statCell(value: "\(consecutiveCount)", label: "连续/退避", tone: consecutiveCount > 0 ? StatusPalette.warn : MagpieTheme.textMuted)
                statCell(
                    value: "\(allItems.filter { $0.category == .auth }.count)",
                    label: "鉴权失效",
                    tone: allItems.contains(where: { $0.category == .auth }) ? StatusPalette.err : MagpieTheme.textMuted
                )
                statCell(
                    value: "\(allItems.filter { $0.category == .rateLimit }.count)",
                    label: "限流冷却",
                    tone: allItems.contains(where: { $0.category == .rateLimit }) ? StatusPalette.warn : MagpieTheme.textMuted
                )
            }

            Text("基于供应商号池、冷却记录与近期追踪汇总；点击任意异常卡片可直接跳转至对应账号。")
                .font(Typography.caption)
                .foregroundColor(MagpieTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                filterPill(title: "全部 (\(allItems.count))", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(AccountErrorCategory.allCases) { cat in
                    let count = allItems.filter { $0.category == cat }.count
                    if count > 0 {
                        filterPill(title: "\(cat.title) (\(count))", isSelected: selectedCategory == cat) {
                            selectedCategory = cat
                        }
                    }
                }
            }
        }
    }

    private func filterPill(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(Typography.bodySmallMedium)
            .foregroundColor(isSelected ? MagpieTheme.onInk : MagpieTheme.textSecondary)
            .padding(.horizontal, Spacing.md + 1)
            .padding(.vertical, Spacing.xs + 1)
            .background(isSelected ? MagpieTheme.ink : MagpieTheme.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(MagpieTheme.hairline, lineWidth: isSelected ? 0 : 1))
            .buttonStyle(.plain)
    }

    private var emptyStateSection: some View {
        MinimalSection {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 18))
                        .foregroundColor(StatusPalette.ok)
                    Text(selectedCategory == nil ? "所有账号运行正常" : "该分类下暂无异常账号")
                        .font(Typography.cardTitle)
                        .foregroundColor(MagpieTheme.ink)
                }
                Text(selectedCategory == nil
                    ? "当前未检测到登录失效、限流冷却或连续失败的账号与 Key。"
                    : "当前筛选类别没有匹配的异常记录，可切换「全部」或点击右上角刷新。")
                    .font(Typography.body)
                    .foregroundColor(MagpieTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if selectedCategory != nil {
                    Button("查看全部异常") {
                        selectedCategory = nil
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
                }
            }
        }
    }

    private func errorCard(_ item: AccountErrorItem) -> some View {
        let tone = categoryTone(item.category)
        let surfaceTone = categorySurface(item.category)
        let provider = store.providers.first(where: { $0.id == item.providerID })
        let switchPlan = provider.flatMap {
            store.quickSwitchPlan(for: $0, sourceID: item.accountUser ?? item.keyID)
        }
        let targetIdentifier = item.accountUser ?? item.keyID ?? item.providerID

        return VStack(alignment: .leading, spacing: Spacing.md) {
            Button {
                store.jumpToAccount(item)
                dismiss()
            } label: {
                VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Circle()
                        .fill(tone)
                        .frame(width: 8, height: 8)
                        .padding(.top, 5)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Spacing.xs) {
                            Text(item.displayName)
                                .font(Typography.rowTitleMono)
                                .foregroundColor(MagpieTheme.ink)
                                .lineLimit(1)
                            MagpieTag(text: item.providerName)
                        }
                        if let sub = item.subtitle {
                            Text(sub)
                                .font(Typography.microMono)
                                .foregroundColor(MagpieTheme.textMuted)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: Spacing.xs)

                    VStack(alignment: .trailing, spacing: Spacing.xxs) {
                        MagpieTag(
                            text: item.category.title,
                            tone: tone,
                            background: surfaceTone
                        )
                        MagpieTag(
                            text: item.isConsecutive ? "连续失败 \(item.failureCount) 次" : "失败 \(item.failureCount) 次",
                            tone: tone,
                            background: surfaceTone
                        )
                    }
                }

                Text(item.reason)
                    .font(Typography.bodySmallMedium)
                    .foregroundColor(tone)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = item.rawDetail, detail != item.reason {
                    Text(detail)
                        .font(Typography.microMono)
                        .foregroundColor(MagpieTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(MagpieTheme.canvas)
                        .clipShape(RoundedRectangle(cornerRadius: Corners.sm, style: .continuous))
                }

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(spacing: Spacing.md) {
                        if let last = AccountErrorAggregator.formatDisplayTimestamp(item.lastFailureAt) {
                            Text("最后失败：\(last)")
                                .font(Typography.microMono)
                                .foregroundColor(MagpieTheme.textSecondary)
                        } else {
                            Text("最后失败：状态接口未返回精确时刻")
                                .font(Typography.micro)
                                .foregroundColor(MagpieTheme.textMuted)
                        }
                        Spacer()
                        if let until = AccountErrorAggregator.formatDisplayTimestamp(item.cooldownUntil) {
                            Text("恢复：\(until)")
                                .font(Typography.microMono)
                                .foregroundColor(MagpieTheme.textMuted)
                        }
                    }

                    if !item.affectedModels.isEmpty {
                        Text("受影响模型：\(item.affectedModels.joined(separator: ", "))")
                            .font(Typography.microMono)
                            .foregroundColor(MagpieTheme.textMuted)
                            .lineLimit(2)
                    }
                }

                Rectangle().fill(MagpieTheme.hairline).frame(height: 1)

                    HStack {
                        Text(item.accountUser != nil ? "定位到多账号号池" : (item.keyID != nil ? "定位到多 Key 号池" : "定位到供应商概况"))
                            .font(Typography.captionMedium)
                            .foregroundColor(MagpieTheme.ink)
                        Spacer()
                        Image(systemName: "arrow.right.circle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(MagpieTheme.ink)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("errorAccountRow_\(targetIdentifier)")

            if item.category == .rateLimit || item.category == .quota {
                if let p = provider, let rec = switchPlan?.recommended {
                    Button(store.isSwitchingAccount ? "切号中…" : "一键切至可用账号：\(rec.displayName)（\(rec.quotaSummary)）") {
                        Task {
                            _ = await store.executeQuickSwitch(
                                provider: p,
                                targetID: rec.id,
                                sourceID: item.accountUser ?? item.keyID
                            )
                        }
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
                    .disabled(store.isSwitchingAccount)
                    .accessibilityIdentifier("quickSwitchFromError_\(targetIdentifier)")
                } else {
                    Text("同平台暂无其他可用账号可切")
                        .font(Typography.caption)
                        .foregroundColor(MagpieTheme.textMuted)
                }
            }
        }
        .padding(Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MagpieTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Corners.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Corners.xl, style: .continuous)
                .stroke(tone.opacity(0.35), lineWidth: 1)
        )
    }

    private func categoryTone(_ category: AccountErrorCategory) -> Color {
        switch category {
        case .auth, .upstream: return StatusPalette.err
        case .rateLimit, .quota: return StatusPalette.warn
        }
    }

    private func categorySurface(_ category: AccountErrorCategory) -> Color {
        switch category {
        case .auth, .upstream: return StatusPalette.errSurface
        case .rateLimit, .quota: return StatusPalette.warnSurface
        }
    }

    private func statCell(value: String, label: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundColor(tone)
            Text(label)
                .font(Typography.micro)
                .foregroundColor(MagpieTheme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func refreshAll() {
        isRefreshing = true
        Task {
            await store.refreshProviders()
            await store.refreshQuotas(asked: true, all: false)
            await store.refreshTraceOnce()
            isRefreshing = false
        }
    }
}
