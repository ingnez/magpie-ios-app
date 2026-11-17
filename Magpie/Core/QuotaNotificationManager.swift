import Foundation
import UserNotifications
import BackgroundTasks
import UIKit
#if canImport(WidgetKit)
import WidgetKit
#endif

enum MagpieBackgroundConstants {
    static let refreshTaskIdentifier = "ai.usemagpie.ios.refresh"
}

enum NotificationAuthState: String, Equatable {
    case notDetermined
    case denied
    case authorized
    case provisional

    var label: String {
        switch self {
        case .notDetermined: return "未请求权限"
        case .denied: return "系统已关闭（需前往系统设置开启）"
        case .authorized: return "已授权"
        case .provisional: return "临时静默授权"
        }
    }
}

@MainActor
final class QuotaNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = QuotaNotificationManager()

    var onSelectDeepLink: ((URL) -> Void)?

    private var isProcessing = false
    private let dedupKey = "magpie.quota.notification.history.v1"

    private override init() {
        super.init()
    }

    func configureDelegate() {
        UNUserNotificationCenter.current().delegate = self
    }

    func currentAuthState() async -> NotificationAuthState {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .ephemeral:
            return .authorized
        case .provisional:
            return .provisional
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }

    func requestAuthorization() async -> (granted: Bool, state: NotificationAuthState) {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            let state = await currentAuthState()
            return (granted, state)
        } catch {
            let state = await currentAuthState()
            return (false, state)
        }
    }

    func processAlerts(
        _ items: [QuotaAlertItem],
        serverID: UUID?,
        config: QuotaAlertConfig
    ) async -> Int {
        guard config.enabled && config.notificationsEnabled && !isProcessing else { return 0 }
        isProcessing = true
        defer { isProcessing = false }
        let state = await currentAuthState()
        guard state == .authorized || state == .provisional else { return 0 }

        let history = loadHistory(for: serverID)
        let result = QuotaNotificationDeduplicator.filterItemsToNotify(
            items: items,
            history: history,
            now: Date(),
            cooldownMinutes: config.cooldownMinutes
        )
        var deliveredHistory = history

        guard !result.toNotify.isEmpty else {
            saveHistory(result.updatedHistory, for: serverID)
            return 0
        }

        let center = UNUserNotificationCenter.current()
        var delivered = 0
        for item in result.toNotify.prefix(5) {
            let content = UNMutableNotificationContent()
            let remainingStr = String(format: "%.0f%%", item.remainingPercent)
            content.title = "Magpie 余量\(item.severity.title)：\(item.providerName)"
            var body = "\(WidgetPrivacyMasker.maskAccountLabel(item.accountUser ?? item.accountDisplayName)) · \(item.windowName) 剩余 \(remainingStr)（阈值 \(item.thresholdPercent)%）"
            if let rec = item.recommendedSwitchDisplay {
                body += "，可一键切至「\(WidgetPrivacyMasker.maskAccountLabel(rec))」"
            }
            content.body = body
            content.sound = .default
            let targetURL = MagpieDeepLink.providers(providerID: item.providerID, accountHint: item.accountUser).url.absoluteString
            content.userInfo = ["deepLink": targetURL]

            let req = UNNotificationRequest(
                identifier: "magpie.quota.\(Data(item.id.utf8).base64EncodedString())",
                content: content,
                trigger: nil
            )
            do {
                try await center.add(req)
                delivered += 1
                deliveredHistory[item.id] = result.updatedHistory[item.id]
            } catch {
                // Best effort; ignore single scheduling error
            }
        }
        let active = Set(items.map(\.id))
        deliveredHistory = deliveredHistory.filter { active.contains($0.key) }
        saveHistory(deliveredHistory, for: serverID)
        return delivered
    }

    func sendTestNotification() async -> Result<Void, Error> {
        let state = await currentAuthState()
        if state == .notDetermined {
            let res = await requestAuthorization()
            if !res.granted {
                return .failure(NSError(domain: "MagpieNotification", code: 1, userInfo: [NSLocalizedDescriptionKey: "未授予系统通知权限"]))
            }
        } else if state == .denied {
            return .failure(NSError(domain: "MagpieNotification", code: 2, userInfo: [NSLocalizedDescriptionKey: "系统通知权限已关闭，请前往系统设置开启"]))
        }

        let content = UNMutableNotificationContent()
        content.title = "Magpie 本地余量预警测试"
        content.body = "客户端本地预警通道正常（仅在 App 前台活跃或系统后台刷新窗口内检测；锁屏实时推送需配置服务端 Bark）。"
        content.sound = .default
        content.userInfo = ["deepLink": MagpieDeepLink.alerts.url.absoluteString]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let req = UNNotificationRequest(identifier: "magpie.quota.test.\(UUID().uuidString)", content: content, trigger: trigger)
        do {
            try await UNUserNotificationCenter.current().add(req)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func resetDeduplicationHistory(for serverID: UUID?) {
        UserDefaults.standard.removeObject(forKey: storageKey(for: serverID))
    }

    func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let raw = response.notification.request.content.userInfo["deepLink"] as? String
        if let raw = raw, let url = URL(string: raw) {
            Task { @MainActor in
                self.onSelectDeepLink?(url)
            }
        }
        completionHandler()
    }

    // MARK: - History Persistence

    private func storageKey(for serverID: UUID?) -> String {
        "\(dedupKey).\(serverID?.uuidString ?? "default")"
    }

    private func loadHistory(for serverID: UUID?) -> [String: QuotaNotificationHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey(for: serverID)) else { return [:] }
        return (try? JSONDecoder().decode([String: QuotaNotificationHistoryEntry].self, from: data)) ?? [:]
    }

    private func saveHistory(_ history: [String: QuotaNotificationHistoryEntry], for serverID: UUID?) {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: storageKey(for: serverID))
        }
    }
}

// MARK: - Background App Refresh Registration

enum MagpieBackgroundRefresh {
    private static var isRegistered = false
    static var handler: (() async -> Bool)?

    static func register() {
        guard !isRegistered else { return }
        isRegistered = true
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: MagpieBackgroundConstants.refreshTaskIdentifier,
            using: nil
        ) { task in
            guard let appRefreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            scheduleNext()
            let workTask = Task {
                let ok = await handler?() ?? false
                appRefreshTask.setTaskCompleted(success: ok)
            }
            appRefreshTask.expirationHandler = {
                workTask.cancel()
            }
        }
    }

    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: MagpieBackgroundConstants.refreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

final class MagpieAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        MagpieBackgroundRefresh.register()
        return true
    }
}
