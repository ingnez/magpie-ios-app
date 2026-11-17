import SwiftUI

enum MagpieTab: String, CaseIterable, Identifiable {
    case home
    case providers
    case usage
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "总览"
        case .providers: return "供应商"
        case .usage: return "用量"
        case .privacy: return "隐私与设置"
        }
    }

    var iconName: String {
        switch self {
        case .home: return "circle.grid.2x1"
        case .providers: return "square.stack.3d.up"
        case .usage: return "chart.bar"
        case .privacy: return "slider.horizontal.3"
        }
    }
}

@main
struct MagpieApp: App {
    @StateObject private var store = GatewayStore()
    @AppStorage("magpie.appearance") private var appearancePreference: String = "system"

    private var preferredScheme: ColorScheme? {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-magpie-dark-mode") { return .dark }
        if args.contains("-magpie-light-mode") { return .light }
        switch appearancePreference {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            MagpieRootView(store: store)
                .preferredColorScheme(preferredScheme)
                .accentColor(MagpieTheme.ink)
        }
    }
}

struct MagpieRootView: View {
    @ObservedObject var store: GatewayStore
    @State private var selectedTab: MagpieTab = .home
    @State private var presentingNewServer = false

    var body: some View {
        ZStack(alignment: .bottom) {
            MagpieTheme.canvas
                .ignoresSafeArea()

            VStack(spacing: 0) {
                minimalHeader

                ZStack {
                    switch selectedTab {
                    case .home:
                        DashboardView(
                            store: store,
                            onSwitchTab: { selectedTab = $0 },
                            onOpenNewServer: { presentingNewServer = true }
                        )
                    case .providers:
                        ProvidersView(store: store)
                    case .usage:
                        UsageView(store: store)
                    case .privacy:
                        LogsPrivacyView(
                            store: store,
                            presentingNewServer: $presentingNewServer
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                minimalTabBar
            }

            if let toast = store.toastMessage {
                VStack {
                    toastPill(toast)
                    Spacer()
                }
                .padding(.top, 56)
                .transition(.opacity)
                .zIndex(50)
            }
        }
        .animation(.easeOut(duration: 0.18), value: store.toastMessage)
        .onChange(of: store.pendingAccountJump) { jump in
            if jump != nil {
                selectedTab = .providers
            }
        }
        .sheet(isPresented: $presentingNewServer) {
            ServerEditorSheet(store: store, existing: nil)
        }
    }

    private var minimalHeader: some View {
        HStack(spacing: Spacing.md - 2) {
            MagpieMarkView(size: 24)

            Text("Magpie")
                .font(Typography.sheetTitle)
                .foregroundColor(MagpieTheme.ink)

            Spacer()

            Button {
                presentingNewServer = true
            } label: {
                HStack(spacing: Spacing.xs) {
                    MagpieStatusLight(kind: store.health.kind)
                    Text(store.activeServer?.hostLabel ?? "未连接")
                        .font(Typography.sectionHeaderMono)
                        .foregroundColor(MagpieTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.pageHorizontal)
        .padding(.vertical, Spacing.cardGap)
        .background(MagpieTheme.canvas)
        .overlay(
            Rectangle()
                .fill(MagpieTheme.hairline)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private var minimalTabBar: some View {
        HStack(spacing: 0) {
            ForEach(MagpieTab.allCases) { tab in
                let isSelected = selectedTab == tab
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: Spacing.xxs) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                        Text(tab.title)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    }
                    .foregroundColor(isSelected ? MagpieTheme.ink : MagpieTheme.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tab.\(tab.rawValue)")
            }
        }
        .padding(.horizontal, Spacing.md)
        .background(MagpieTheme.surface)
        .overlay(
            Rectangle()
                .fill(MagpieTheme.hairline)
                .frame(height: 1),
            alignment: .top
        )
    }

    private func toastPill(_ text: String) -> some View {
        Text(text)
            .font(Typography.bodySmallMedium)
            .foregroundColor(MagpieTheme.onInk)
            .padding(.horizontal, Spacing.cardGap)
            .padding(.vertical, Spacing.sm)
            .background(MagpieTheme.ink)
            .clipShape(Capsule())
    }
}
