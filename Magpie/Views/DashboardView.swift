import SwiftUI

struct DashboardView: View {
    @ObservedObject var store: GatewayStore
    let onSwitchTab: (MagpieTab) -> Void
    let onOpenNewServer: () -> Void

    @State private var traceMode: TraceDisplayMode = .live
    @State private var selectedRoute: RemoteRoute?

    enum TraceDisplayMode: String, CaseIterable {
        case live = "实时追踪"
        case history = "历史记录"
    }

    private var displayedRoutes: [RemoteRoute] {
        traceMode == .live ? store.traceRoutes : store.historyRoutes
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                heroStatusBlock

                if store.activeServer == nil {
                    onboardingCard
                } else if store.health.kind == .failed {
                    MagpieErrorBanner(
                        title: "magpie web 连接失败",
                        message: store.health.message,
                        retryTitle: "重试"
                    ) {
                        Task { await store.connectAndRefreshAll() }
                    }
                } else {
                    gatewayOverviewSection
                    traceSection
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 100)
        }
        .refreshable {
            await store.connectAndRefreshAll()
        }
        .sheet(item: $selectedRoute) { route in
            RouteDetailSheet(store: store, route: route)
        }
    }

    // MARK: - Hero Status

    private var heroStatusBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                MagpieStatusLight(kind: store.health.kind)
                Text(statusHeadline)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(MagpieTheme.textSecondary)
                Spacer()
                if let ms = store.health.latencyMs {
                    Text("\(ms) ms")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(MagpieTheme.textMuted)
                }
            }

            Text(store.activeServer?.name ?? "未连接远程实例")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(MagpieTheme.ink)

            Text(store.activeServer?.baseURL ?? "添加运行中的 magpie web 地址与密钥 k 即可远程控制")
                .font(.system(size: 13, design: store.activeServer != nil ? .monospaced : .default))
                .foregroundColor(MagpieTheme.textSecondary)
                .lineLimit(1)

            if store.activeServer != nil {
                HStack(spacing: 8) {
                    if !store.remoteSettings.version.isEmpty {
                        MagpieTag(text: "v\(store.remoteSettings.version)", monospaced: true)
                    }
                    if let state = store.remoteState {
                        MagpieTag(text: "\(state.served) 模型在线")
                    }
                    if store.remoteSettings.lan {
                        MagpieTag(text: "LAN 已共享", tone: MagpieTheme.ok)
                    }
                    if store.remoteSettings.redact {
                        MagpieTag(text: "脱敏已开启", tone: MagpieTheme.ink)
                    }
                }
            }

            HStack(spacing: 10) {
                if store.activeServer != nil {
                    Button(store.isConnecting ? "连接中…" : "刷新状态") {
                        Task { await store.connectAndRefreshAll() }
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
                    .disabled(store.isConnecting)

                    Button("添加实例") {
                        onOpenNewServer()
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
                } else {
                    Button("连接 magpie web") {
                        onOpenNewServer()
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
                }

                Button("供应商 (\(store.providers.count))") {
                    onSwitchTab(.providers)
                }
                .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
            }
            .padding(.top, 2)
        }
        .padding(.bottom, 4)
    }

    private var statusHeadline: String {
        switch store.health.kind {
        case .connected:
            return store.isLiveTraceActive ? "已直连 · 实时追踪中" : "已直连 magpie web"
        case .checking:
            return "正在交换 Cookie 握手…"
        case .failed:
            return "连接异常"
        case .localOnly, .untested:
            return "等待配置实例"
        }
    }

    private var onboardingCard: some View {
        MinimalSection(title: "开始使用", trailingText: "Option A · 远程客户端") {
            Text("Magpie iOS 已重构为远程原生管理端，直连服务器上运行的 magpie web 接口（默认端口 3430）。")
                .font(.system(size: 13.5))
                .foregroundColor(MagpieTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("支持特性：")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(MagpieTheme.textSecondary)
                Text("• 粘贴带 ?k= 的启动链接自动解析地址与密钥\n• Cookie 会话维持与 HTTP 401 自动续签\n• 实时路由追踪、供应商/路由组控制、用量与脱敏规则")
                    .font(.system(size: 12))
                    .foregroundColor(MagpieTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("立即添加服务器") {
                onOpenNewServer()
            }
            .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
        }
    }

    // MARK: - Gateway & Totals Overview

    private var gatewayOverviewSection: some View {
        MinimalSection(
            title: "网关与实时汇总",
            trailingText: store.gatewayStatus?.running == true ? "运行中" : "未接管网关"
        ) {
            HStack(spacing: 0) {
                statCell(value: "\(store.traceTotals.requests)", label: "总请求")
                statCell(value: "\(store.traceTotals.rerouted)", label: "故障切换")
                statCell(value: "\(store.traceTotals.errors)", label: "错误")
                statCell(value: "\(store.providers.filter { !$0.off && $0.ready }.count)", label: "活跃源")
            }

            if let gw = store.gatewayStatus, !gw.url.isEmpty {
                Rectangle().fill(MagpieTheme.hairline).frame(height: 1)

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("网关地址")
                            .font(.system(size: 11.5))
                            .foregroundColor(MagpieTheme.textMuted)
                        Text(gw.publicURL ?? gw.url)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(MagpieTheme.ink)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("复制") {
                        store.copyToClipboard(gw.publicURL ?? gw.url, label: "网关地址")
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))
                }
            }
        }
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundColor(MagpieTheme.ink)
            Text(label)
                .font(.system(size: 11.5))
                .foregroundColor(MagpieTheme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Live Trace & History

    private var traceSection: some View {
        MinimalSection(
            title: "请求路由流",
            trailingText: traceMode == .live ? "seq \(store.traceSeq)" : "\(displayedRoutes.count) 条"
        ) {
            HStack(spacing: 8) {
                ForEach(TraceDisplayMode.allCases, id: \.self) { mode in
                    let selected = traceMode == mode
                    Button(mode.rawValue) {
                        traceMode = mode
                        if mode == .history {
                            Task { await store.loadHistory(day: store.selectedHistoryDay.isEmpty ? nil : store.selectedHistoryDay) }
                        } else {
                            store.startLiveTraceIfNeeded()
                        }
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

                if traceMode == .live {
                    Button(store.isLiveTraceActive ? "暂停" : "监听") {
                        if store.isLiveTraceActive {
                            store.stopLiveTrace()
                        } else {
                            store.startLiveTraceIfNeeded()
                        }
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))
                } else if !store.historyDays.isEmpty {
                    Menu {
                        ForEach(store.historyDays, id: \.self) { day in
                            Button(day) {
                                store.selectedHistoryDay = day
                                Task { await store.loadHistory(day: day) }
                            }
                        }
                    } label: {
                        Text(store.selectedHistoryDay.isEmpty ? "选择日期" : store.selectedHistoryDay)
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundColor(MagpieTheme.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(MagpieTheme.surfaceSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
            }

            if displayedRoutes.isEmpty {
                Text(traceMode == .live ? "暂无实时路由请求，等待网关新流量…" : "该日期暂无路由历史")
                    .font(.system(size: 13))
                    .foregroundColor(MagpieTheme.textMuted)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(displayedRoutes.prefix(40).enumerated()), id: \.element.id) { idx, route in
                    if idx > 0 {
                        Rectangle().fill(MagpieTheme.hairline).frame(height: 1)
                    }
                    routeRow(route)
                }
            }
        }
    }

    private func routeRow(_ route: RemoteRoute) -> some View {
        Button {
            selectedRoute = route
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(!route.done ? MagpieTheme.warn : (route.isError ? MagpieTheme.err : MagpieTheme.ok))
                        .frame(width: 6, height: 6)
                    Text(route.model.isEmpty ? "unknown" : route.model)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(MagpieTheme.ink)
                        .lineLimit(1)
                    Spacer()
                    Text(route.done ? "HTTP \(route.status) · \(route.ms)ms" : "流式输出中…")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(route.isError ? MagpieTheme.err : MagpieTheme.textMuted)
                }

                HStack(spacing: 6) {
                    if !route.agent.isEmpty {
                        MagpieTag(text: route.agent)
                    }
                    if !route.provider.isEmpty {
                        MagpieTag(text: "→ \(route.provider)")
                    }
                    if route.tries.count > 1 {
                        MagpieTag(text: "重试 \(route.tries.count) 次", tone: MagpieTheme.warn)
                    }
                    if let masked = route.masked, masked.n > 0 {
                        MagpieTag(text: "脱敏 \(masked.n)", tone: MagpieTheme.ink)
                    }
                    Spacer()
                    if route.priced && route.cost > 0 {
                        Text(String(format: "$%.4f", route.cost))
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundColor(MagpieTheme.textSecondary)
                    }
                }

                if let errText = route.fail ?? route.error, !errText.isEmpty {
                    Text(errText)
                        .font(.system(size: 11.5))
                        .foregroundColor(MagpieTheme.err)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct RouteDetailSheet: View {
    @ObservedObject var store: GatewayStore
    let route: RemoteRoute
    @Environment(\.dismiss) private var dismiss

    @State private var detail: RemoteGatewayCallDetail?
    @State private var detailError: String?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            MagpieTheme.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button("关闭") { dismiss() }
                        .font(.system(size: 14))
                        .foregroundColor(MagpieTheme.textSecondary)
                    Spacer()
                    Text("路由 #\(route.id)")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(MagpieTheme.ink)
                    Spacer()
                    Color.clear.frame(width: 32, height: 1)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
                .background(MagpieTheme.surface)
                .overlay(Rectangle().fill(MagpieTheme.hairline).frame(height: 1), alignment: .bottom)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        MinimalSection(title: "路由摘要", trailingText: route.done ? "HTTP \(route.status)" : "进行中") {
                            detailLine("模型", route.model)
                            detailLine("供应商", route.provider.isEmpty ? "-" : route.provider)
                            detailLine("客户端", route.agent.isEmpty ? "-" : route.agent)
                            detailLine("耗时 / TTFT", "\(route.ms) ms / \(route.ttft) ms")
                            detailLine("Tokens", "总 \(route.tokens) · 输出 \(route.out)")
                            if let keyName = route.callerKeyName, !keyName.isEmpty {
                                detailLine("Caller Key", keyName)
                            }
                        }

                        if !route.tries.isEmpty {
                            MinimalSection(title: "尝试链路 (\(route.tries.count))") {
                                ForEach(Array(route.tries.enumerated()), id: \.element.uniqueID) { idx, t in
                                    if idx > 0 {
                                        Rectangle().fill(MagpieTheme.hairline).frame(height: 1)
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(t.id)
                                                .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                                                .foregroundColor(MagpieTheme.ink)
                                            Spacer()
                                            Text("HTTP \(t.status) · \(t.ms) ms")
                                                .font(.system(size: 11.5, design: .monospaced))
                                                .foregroundColor(MagpieTheme.textMuted)
                                        }
                                        if let msg = t.fail ?? t.error, !msg.isEmpty {
                                            Text(msg)
                                                .font(.system(size: 11.5))
                                                .foregroundColor(MagpieTheme.err)
                                        }
                                    }
                                }
                            }
                        }

                        MinimalSection(title: "请求 / 响应载荷", trailingText: isLoading ? "读取中…" : "/api/gateway/call") {
                            if let err = detailError {
                                Text(err)
                                    .font(.system(size: 12))
                                    .foregroundColor(MagpieTheme.textMuted)
                            } else if let detail = detail {
                                if let reqBody = detail.requestBody, !reqBody.isEmpty {
                                    Text("Request Body")
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundColor(MagpieTheme.textSecondary)
                                    Text(reqBody)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(MagpieTheme.ink)
                                        .padding(10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(MagpieTheme.canvas)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                if let respBody = detail.responseBody, !respBody.isEmpty {
                                    Text("Response Body")
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundColor(MagpieTheme.textSecondary)
                                    Text(respBody)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(MagpieTheme.ink)
                                        .padding(10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(MagpieTheme.canvas)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                            }
                        }
                    }
                    .padding(22)
                }
            }
        }
        .preferredColorScheme(.light)
        .onAppear {
            Task {
                switch await store.fetchCallDetail(routeID: route.id) {
                case .success(let d): detail = d
                case .failure(let err): detailError = err.errorDescription
                }
                isLoading = false
            }
        }
    }

    private func detailLine(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k)
                .font(.system(size: 12.5))
                .foregroundColor(MagpieTheme.textSecondary)
            Spacer()
            Text(v)
                .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                .foregroundColor(MagpieTheme.ink)
                .lineLimit(1)
        }
    }
}
