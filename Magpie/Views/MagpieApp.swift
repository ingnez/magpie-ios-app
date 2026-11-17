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

    var body: some Scene {
        WindowGroup {
            MagpieRootView(store: store)
                .preferredColorScheme(.light)
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
            }

            minimalTabBar

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
        .sheet(isPresented: $presentingNewServer) {
            ServerEditorSheet(store: store, existing: nil)
        }
    }

    private var minimalHeader: some View {
        HStack(spacing: 10) {
            MagpieMarkView(size: 24)

            Text("Magpie")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(MagpieTheme.ink)

            Spacer()

            Button {
                presentingNewServer = true
            } label: {
                HStack(spacing: 6) {
                    MagpieStatusLight(kind: store.health.kind)
                    Text(store.activeServer?.hostLabel ?? "未连接")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(MagpieTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
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
                    VStack(spacing: 4) {
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
            }
        }
        .padding(.horizontal, 12)
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
            .font(.system(size: 12.5, weight: .medium))
            .foregroundColor(MagpieTheme.surface)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(MagpieTheme.ink)
            .clipShape(Capsule())
    }
}
