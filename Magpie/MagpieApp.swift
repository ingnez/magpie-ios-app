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
        case .home: return "bolt.horizontal.circle"
        case .profiles: return "server.rack"
        case .models: return "square.stack.3d.up"
        case .logs: return "shield.lefthalf.filled"
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
                .preferredColorScheme(.dark)
                .accentColor(MagpieTheme.amber)
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
                topBar

                ZStack {
                    switch selectedTab {
                    case .home:
                        DashboardView(
                            store: store,
                            onSwitchTab: { tab in selectedTab = tab },
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

            customBottomDock

            if let toast = store.toastMessage {
                VStack {
                    toastBanner(toast)
                    Spacer()
                }
                .padding(.top, 58)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(50)
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.toastMessage)
        .onAppear {
            Task {
                await store.checkLocalDaemon()
                if store.activeProfile != nil {
                    await store.probeActiveConnection()
                }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            MagpieMarkView(size: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text("Magpie 网关")
                    .font(.system(size: 16.5, weight: .bold))
                    .foregroundColor(MagpieTheme.textPrimary)
                Text("iOS Native Reverse Proxy")
                    .font(.system(size: 11))
                    .foregroundColor(MagpieTheme.textMuted)
            }

            Spacer()

            HStack(spacing: 6) {
                MagpieStatusLight(kind: store.statusSnapshot.daemonOnline ? .connected : .failed)
                Text(store.statusSnapshot.daemonOnline ? "3425 在线" : "端口异常")
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(store.statusSnapshot.daemonOnline ? MagpieTheme.teal : MagpieTheme.coral)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(MagpieTheme.card)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(store.statusSnapshot.daemonOnline ? MagpieTheme.teal.opacity(0.35) : MagpieTheme.coral.opacity(0.45), lineWidth: 1)
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(MagpieTheme.canvas.opacity(0.95))
        .overlay(
            Rectangle()
                .fill(MagpieTheme.border)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private var customBottomDock: some View {
        HStack(spacing: 6) {
            ForEach(MagpieTab.allCases) { tab in
                let isSelected = selectedTab == tab
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 17, weight: isSelected ? .bold : .medium))
                        Text(tab.title)
                            .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                    }
                    .foregroundColor(isSelected ? MagpieTheme.canvas : MagpieTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(isSelected ? MagpieTheme.amber : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(MagpieTheme.cardElevated.opacity(0.97))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(MagpieTheme.borderStrong, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.45), radius: 14, y: 6)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func toastBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(MagpieTheme.amber)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(MagpieTheme.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(MagpieTheme.cardElevated)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(MagpieTheme.amber.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 10, y: 4)
    }
}
