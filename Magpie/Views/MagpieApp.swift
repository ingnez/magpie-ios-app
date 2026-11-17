import SwiftUI

enum MagpieTab: String, CaseIterable, Identifiable {
    case home
    case profiles
    case models
    case logs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "总览"
        case .profiles: return "配置"
        case .models: return "模型"
        case .logs: return "日志"
        }
    }

    var iconName: String {
        switch self {
        case .home: return "circle.grid.2x1"
        case .profiles: return "slider.horizontal.3"
        case .models: return "square.stack"
        case .logs: return "text.alignleft"
        }
    }
}

@main
struct MagpieApp: App {
    @StateObject private var store = GatewayStore()

    init() {
        MagpieLocalGateway.shared.startIfNeeded()
    }

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
    @State private var presentingNewProfile = false

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
                            onOpenNewProfile: {
                                selectedTab = .profiles
                                presentingNewProfile = true
                            }
                        )
                    case .profiles:
                        ProfilesView(
                            store: store,
                            presentingNewEditor: $presentingNewProfile
                        )
                    case .models:
                        ModelsView(store: store)
                    case .logs:
                        LogsPrivacyView(store: store)
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
        .onAppear {
            Task {
                await store.checkLocalDaemon()
                if store.activeProfile != nil {
                    await store.probeActiveConnection()
                }
            }
        }
    }

    private var minimalHeader: some View {
        HStack(spacing: 10) {
            MagpieMarkView(size: 24)

            Text("Magpie")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(MagpieTheme.ink)

            Spacer()

            HStack(spacing: 6) {
                MagpieStatusLight(kind: store.statusSnapshot.daemonOnline ? .connected : .failed)
                Text(store.statusSnapshot.daemonOnline ? "127.0.0.1:3425" : "离线")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(MagpieTheme.textSecondary)
            }
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
