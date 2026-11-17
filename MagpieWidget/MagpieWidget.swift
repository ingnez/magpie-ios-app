import WidgetKit
import SwiftUI
import UIKit

struct MagpieWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: MagpieWidgetSnapshot
}

struct MagpieTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> MagpieWidgetEntry {
        MagpieWidgetEntry(date: Date(), snapshot: Self.previewPlaceholderSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (MagpieWidgetEntry) -> Void) {
        let loaded = MagpieWidgetSnapshotStore.load()
        let snap = context.isPreview && loaded == nil ? Self.previewPlaceholderSnapshot : (loaded ?? .unconfigured)
        completion(MagpieWidgetEntry(date: Date(), snapshot: snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MagpieWidgetEntry>) -> Void) {
        let snap = MagpieWidgetSnapshotStore.load() ?? .unconfigured
        let now = Date()
        let entry = MagpieWidgetEntry(date: now, snapshot: snap)
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: now) ?? now.addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private static var previewPlaceholderSnapshot: MagpieWidgetSnapshot {
        MagpieWidgetSnapshot(
            schemaVersion: 1,
            updatedAt: Date(),
            connectionState: .connected,
            serverTitle: "Magpie 网关",
            todayCalls: 128,
            todayErrors: 0,
            todayTokens: 184_000,
            todayCostUSD: 1.42,
            alertThresholdPercent: 10,
            alertCount: 1,
            coolingCount: 0,
            accounts: [
                MagpieWidgetAccountItem(
                    id: "preview-1",
                    providerID: "antigravity",
                    providerName: "Antigravity",
                    maskedAccount: "xi***66@gmail.com",
                    windowName: "5h",
                    remainingPercent: 8,
                    usedPercent: 92,
                    resetSecs: 1800,
                    isCooling: false,
                    isLapsed: false,
                    isAlerting: true,
                    isActive: true
                ),
                MagpieWidgetAccountItem(
                    id: "preview-2",
                    providerID: "codex",
                    providerName: "Codex",
                    maskedAccount: "xi***66@gmail.com",
                    windowName: "7d",
                    remainingPercent: 67,
                    usedPercent: 33,
                    resetSecs: 14400,
                    isCooling: false,
                    isLapsed: false,
                    isAlerting: false,
                    isActive: true
                )
            ]
        )
    }
}

private enum WidgetPalette {
    static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    static let surface = dynamic(
        light: UIColor(red: 0.99, green: 0.99, blue: 0.98, alpha: 1),
        dark: UIColor(red: 0.09, green: 0.09, blue: 0.085, alpha: 1)
    )
    static let subtle = dynamic(
        light: UIColor(red: 0.94, green: 0.93, blue: 0.91, alpha: 1),
        dark: UIColor(red: 0.16, green: 0.16, blue: 0.15, alpha: 1)
    )
    static let ink = dynamic(
        light: UIColor(red: 0.08, green: 0.08, blue: 0.075, alpha: 1),
        dark: UIColor(red: 0.95, green: 0.95, blue: 0.93, alpha: 1)
    )
    static let secondary = dynamic(
        light: UIColor(red: 0.42, green: 0.42, blue: 0.40, alpha: 1),
        dark: UIColor(red: 0.71, green: 0.70, blue: 0.67, alpha: 1)
    )
    static let muted = dynamic(
        light: UIColor(red: 0.60, green: 0.59, blue: 0.56, alpha: 1),
        dark: UIColor(red: 0.52, green: 0.51, blue: 0.48, alpha: 1)
    )
    static let ok = dynamic(
        light: UIColor(red: 0.086, green: 0.502, blue: 0.290, alpha: 1),
        dark: UIColor(red: 0.204, green: 0.827, blue: 0.600, alpha: 1)
    )
    static let warn = dynamic(
        light: UIColor(red: 0.706, green: 0.325, blue: 0.035, alpha: 1),
        dark: UIColor(red: 0.984, green: 0.749, blue: 0.141, alpha: 1)
    )
    static let err = dynamic(
        light: UIColor(red: 0.725, green: 0.110, blue: 0.110, alpha: 1),
        dark: UIColor(red: 0.973, green: 0.443, blue: 0.443, alpha: 1)
    )
}

struct MagpieWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MagpieWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallView
                    .widgetURL(smallDeepLink)
            default:
                mediumView
                    .widgetURL(defaultMediumDeepLink)
            }
        }
        .modifier(WidgetContainerBackgroundModifier(color: WidgetPalette.surface))
    }

    private var snap: MagpieWidgetSnapshot { entry.snapshot }

    private var isOfflineOrStale: Bool {
        snap.connectionState == .offline || (snap.connectionState == .connected && snap.isStale(relativeTo: entry.date))
    }

    private var smallDeepLink: URL {
        if snap.connectionState == .unconfigured { return MagpieDeepLink.dashboard.url }
        if snap.alertCount > 0 { return MagpieDeepLink.alerts.url }
        return MagpieDeepLink.usage.url
    }

    private var defaultMediumDeepLink: URL {
        if snap.connectionState == .unconfigured { return MagpieDeepLink.dashboard.url }
        return MagpieDeepLink.usage.url
    }

    private var statusColor: Color {
        switch snap.connectionState {
        case .unconfigured: return WidgetPalette.muted
        case .offline: return WidgetPalette.warn
        case .connected:
            if isOfflineOrStale || snap.alertCount > 0 || snap.coolingCount > 0 {
                return WidgetPalette.warn
            }
            return WidgetPalette.ok
        }
    }

    // MARK: - Small Widget

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(snap.serverTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(WidgetPalette.ink)
                    .lineLimit(1)
                Spacer()
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
            }

            if snap.connectionState == .unconfigured {
                Spacer()
                Text("未配置实例")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(WidgetPalette.ink)
                Text("轻点前往连接 Magpie")
                    .font(.system(size: 10.5))
                    .foregroundColor(WidgetPalette.muted)
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(snap.todayCalls) 次调用")
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundColor(WidgetPalette.ink)
                        .lineLimit(1)
                    Text(String(format: "今日 $%.2f · 错 %d", snap.todayCostUSD, snap.todayErrors))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(WidgetPalette.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 2)

                if let top = snap.accounts.first {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(top.maskedAccount)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundColor(WidgetPalette.ink)
                            .lineLimit(1)
                        if let rem = top.remainingPercent {
                            Text(String(format: "%@ 剩 %.0f%%", top.windowName, rem))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(top.isAlerting ? WidgetPalette.warn : WidgetPalette.ok)
                                .lineLimit(1)
                        } else {
                            Text(top.windowName)
                                .font(.system(size: 10))
                                .foregroundColor(WidgetPalette.muted)
                                .lineLimit(1)
                        }
                    }
                } else {
                    Text(isOfflineOrStale ? "离线 · \(formattedTime(snap.updatedAt))" : "更新于 \(formattedTime(snap.updatedAt))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(WidgetPalette.muted)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: - Medium Widget

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(snap.serverTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(WidgetPalette.ink)
                    .lineLimit(1)

                if snap.connectionState == .unconfigured {
                    statusPill("未配置", tone: WidgetPalette.muted)
                } else if isOfflineOrStale {
                    statusPill("离线 \(formattedTime(snap.updatedAt))", tone: WidgetPalette.warn)
                } else if snap.alertCount > 0 {
                    statusPill("预警 \(snap.alertCount)", tone: WidgetPalette.warn)
                } else {
                    statusPill("更新 \(formattedTime(snap.updatedAt))", tone: WidgetPalette.ok)
                }

                Spacer()

                Link(destination: MagpieDeepLink.refresh.url) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(WidgetPalette.secondary)
                        .padding(5)
                        .background(WidgetPalette.subtle)
                        .clipShape(Circle())
                }
            }

            if snap.connectionState == .unconfigured {
                Spacer()
                Text("尚未配置 magpie web 实例")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(WidgetPalette.ink)
                Text("点击卡片连接服务器后，将在此展示今日调用、费用与脱敏后的账号余量。")
                    .font(.system(size: 11))
                    .foregroundColor(WidgetPalette.secondary)
                    .lineLimit(2)
                Spacer()
            } else {
                HStack(alignment: .top, spacing: 12) {
                    Link(destination: MagpieDeepLink.usage.url) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(snap.todayCalls)")
                                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                                .foregroundColor(WidgetPalette.ink)
                            Text("今日调用")
                                .font(.system(size: 10))
                                .foregroundColor(WidgetPalette.muted)
                            Spacer(minLength: 2)
                            Text(String(format: "$%.2f", snap.todayCostUSD))
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundColor(WidgetPalette.ink)
                            Text("错误 \(snap.todayErrors) · \(formatTokens(snap.todayTokens))")
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundColor(WidgetPalette.secondary)
                                .lineLimit(1)
                        }
                        .frame(width: 102, alignment: .leading)
                    }

                    Rectangle()
                        .fill(WidgetPalette.subtle)
                        .frame(width: 1)

                    VStack(alignment: .leading, spacing: 5) {
                        if snap.accounts.isEmpty {
                            Text("暂无已登录账号额度")
                                .font(.system(size: 11))
                                .foregroundColor(WidgetPalette.muted)
                        } else {
                            ForEach(snap.accounts.prefix(3)) { acc in
                                Link(destination: MagpieDeepLink.providers(providerID: acc.providerID, accountHint: nil).url) {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(accountTone(acc))
                                            .frame(width: 5, height: 5)
                                        Text(acc.maskedAccount)
                                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                            .foregroundColor(WidgetPalette.ink)
                                            .lineLimit(1)
                                        Spacer(minLength: 2)
                                        if let rem = acc.remainingPercent {
                                            Text(String(format: "剩 %.0f%%", rem))
                                                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                                .foregroundColor(accountTone(acc))
                                        } else {
                                            Text(acc.isCooling ? "冷却" : acc.windowName)
                                                .font(.system(size: 10))
                                                .foregroundColor(accountTone(acc))
                                                .lineLimit(1)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func statusPill(_ text: String, tone: Color) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .foregroundColor(tone)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(WidgetPalette.subtle)
            .clipShape(Capsule())
    }

    private func accountTone(_ acc: MagpieWidgetAccountItem) -> Color {
        if acc.isLapsed { return WidgetPalette.err }
        if acc.isAlerting || acc.isCooling { return WidgetPalette.warn }
        return WidgetPalette.ok
    }

    private func formattedTime(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: date)
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000.0) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000.0) }
        return "\(count)"
    }
}

private struct WidgetContainerBackgroundModifier: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            content.containerBackground(color, for: .widget)
        } else {
            content.background(color)
        }
    }
}

@main
struct MagpieStatusWidget: Widget {
    let kind: String = MagpieSharedConstants.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MagpieTimelineProvider()) { entry in
            MagpieWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Magpie 额度与用量")
        .description("展示今日调用/费用与脱敏后的账号余量摘要，支持点击直达。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
