import Foundation
import SwiftUI
import UIKit

@MainActor
final class GatewayStore: ObservableObject {
    @Published var profiles: [ProxyProfile] = []
    @Published var activeProfileID: UUID?
    @Published var healthByProfile: [UUID: ConnectionHealth] = [:]
    @Published var statusSnapshot: GatewayStatusSnapshot = MagpieLocalGateway.shared.currentSnapshot()
    @Published var logs: [GatewayLogEntry] = []

    @Published var models: [MagpieModelItem] = []
    @Published var isLoadingModels = false
    @Published var modelsError: String?
    @Published var modelsSourceLabel: String = "未拉取"
    @Published var modelsLatencyMs: Int?

    @Published var privacySettings: PrivacyMaskSettings = PrivacyMaskSettings() {
        didSet {
            savePrivacySettings()
            MagpieLocalGateway.shared.updatePrivacySettings(privacySettings)
        }
    }

    @Published var toastMessage: String?

    private let profilesKey = "magpie.profiles.v2"
    private let activeIDKey = "magpie.activeProfileID.v2"
    private let privacyKey = "magpie.privacySettings.v2"
    private var observerToken: NSObjectProtocol?
    private var toastTask: Task<Void, Never>?

    init() {
        loadPersistedState()
        syncActiveProfileToGateway()
        MagpieLocalGateway.shared.updatePrivacySettings(privacySettings)
        refreshGatewayState()

        observerToken = NotificationCenter.default.addObserver(
            forName: .magpieGatewayDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshGatewayState()
            }
        }
    }

    deinit {
        if let token = observerToken {
            NotificationCenter.default.removeObserver(token)
        }
    }

    var activeProfile: ProxyProfile? {
        guard let id = activeProfileID else { return nil }
        return profiles.first(where: { $0.id == id })
    }

    var activeHealth: ConnectionHealth {
        guard let profile = activeProfile else {
            return ConnectionHealth(
                kind: .localOnly,
                latencyMs: nil,
                statusCode: nil,
                message: "未激活上游配置，当前处于 127.0.0.1:3425 本地回环模式",
                checkedAt: nil
            )
        }
        return healthByProfile[profile.id] ?? .untested
    }

    func showToast(_ message: String) {
        toastTask?.cancel()
        toastMessage = message
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if !Task.isCancelled {
                toastMessage = nil
            }
        }
    }

    func copyToClipboard(_ text: String, label: String) {
        UIPasteboard.general.string = text
        showToast("已复制\(label)")
    }

    func refreshGatewayState() {
        statusSnapshot = MagpieLocalGateway.shared.currentSnapshot()
        logs = MagpieLocalGateway.shared.recentLogs()
    }

    func checkLocalDaemon() async {
        guard let url = URL(string: "http://127.0.0.1:3425/api/status") else { return }
        var req = URLRequest(url: url, timeoutInterval: 3)
        req.httpMethod = "GET"
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                refreshGatewayState()
            }
        } catch {
            statusSnapshot.daemonOnline = false
            statusSnapshot.lastError = "本地网关端口 127.0.0.1:3425 未响应：\(error.localizedDescription)"
        }
    }

    // MARK: - Profile CRUD

    func saveProfile(
        editingID: UUID?,
        name: String,
        rawBaseURL: String,
        apiKey: String,
        targetProtocol: MagpieProtocol,
        defaultModel: String,
        activateImmediately: Bool = true
    ) -> Result<ProxyProfile, ProfileSaveError> {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            return .failure(.message("请填写配置名称（例如：主力中转 / 本地 Ollama）"))
        }

        let urlCheck = URLValidator.validateAndNormalize(rawBaseURL)
        guard case .valid(let normalizedURL) = urlCheck else {
            return .failure(.message(urlCheck.errorReason ?? "服务器地址不合法"))
        }

        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanModel = defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedModel = cleanModel.isEmpty ? targetProtocol.suggestedDefaultModel : cleanModel

        let saved: ProxyProfile
        if let editingID = editingID, let idx = profiles.firstIndex(where: { $0.id == editingID }) {
            var updated = profiles[idx]
            updated.name = trimmedName
            updated.baseURL = normalizedURL
            updated.apiKey = cleanKey
            updated.targetProtocol = targetProtocol
            updated.defaultModel = resolvedModel
            updated.updatedAt = Date()
            profiles[idx] = updated
            saved = updated
            healthByProfile[updated.id] = .untested
        } else {
            let created = ProxyProfile(
                name: trimmedName,
                baseURL: normalizedURL,
                apiKey: cleanKey,
                targetProtocol: targetProtocol,
                defaultModel: resolvedModel
            )
            profiles.insert(created, at: 0)
            saved = created
            healthByProfile[created.id] = .untested
        }

        if activateImmediately || activeProfileID == nil {
            activeProfileID = saved.id
        }

        persistProfiles()
        syncActiveProfileToGateway()
        return .success(saved)
    }

    func activateProfile(_ profile: ProxyProfile) {
        activeProfileID = profile.id
        persistProfiles()
        syncActiveProfileToGateway()
        showToast("已切换至「\(profile.name)」")
        Task {
            await probeConnection(for: profile)
        }
    }

    func deactivateToLocalLoopback() {
        activeProfileID = nil
        persistProfiles()
        syncActiveProfileToGateway()
        showToast("已切回本地回环模式")
    }

    func deleteProfile(_ profile: ProxyProfile) {
        profiles.removeAll { $0.id == profile.id }
        healthByProfile.removeValue(forKey: profile.id)
        if activeProfileID == profile.id {
            activeProfileID = profiles.first?.id
        }
        persistProfiles()
        syncActiveProfileToGateway()
        showToast("已删除「\(profile.name)」")
    }

    func updateActiveDefaultModel(_ modelID: String) {
        guard let activeID = activeProfileID,
              let idx = profiles.firstIndex(where: { $0.id == activeID }) else {
            showToast("请先在「配置」中激活一套反代配置")
            return
        }
        profiles[idx].defaultModel = modelID
        profiles[idx].updatedAt = Date()
        persistProfiles()
        syncActiveProfileToGateway()
        showToast("默认模型已设为 \(modelID)")
    }

    // MARK: - Connection Probe

    func probeActiveConnection() async {
        guard let profile = activeProfile else {
            await checkLocalDaemon()
            return
        }
        await probeConnection(for: profile)
    }

    @discardableResult
    func probeConnection(for profile: ProxyProfile) async -> ConnectionHealth {
        healthByProfile[profile.id] = .checking
        let result = await Self.executeProbe(
            rawBaseURL: profile.baseURL,
            apiKey: profile.apiKey,
            targetProtocol: profile.targetProtocol
        )
        healthByProfile[profile.id] = result
        return result
    }

    static func executeProbe(
        rawBaseURL: String,
        apiKey: String,
        targetProtocol: MagpieProtocol
    ) async -> ConnectionHealth {
        let validation = URLValidator.validateAndNormalize(rawBaseURL)
        guard case .valid(let baseURL) = validation else {
            return ConnectionHealth(
                kind: .failed,
                latencyMs: nil,
                statusCode: nil,
                message: validation.errorReason ?? "服务器地址校验失败",
                checkedAt: Date()
            )
        }

        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let probeURLString: String
        switch targetProtocol {
        case .geminiV1Beta:
            let encoded = cleanKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cleanKey
            probeURLString = "\(baseURL)/v1beta/models?key=\(encoded)"
        default:
            probeURLString = baseURL.hasSuffix("/v1") ? "\(baseURL)/models" : "\(baseURL)/v1/models"
        }

        guard let url = URL(string: probeURLString) else {
            return ConnectionHealth(
                kind: .failed,
                latencyMs: nil,
                statusCode: nil,
                message: "无法构造探测地址：\(probeURLString)",
                checkedAt: Date()
            )
        }

        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "GET"
        switch targetProtocol {
        case .openAIChat, .openAIResponses:
            if !cleanKey.isEmpty { req.setValue("Bearer \(cleanKey)", forHTTPHeaderField: "Authorization") }
        case .anthropicMessages:
            if !cleanKey.isEmpty {
                req.setValue(cleanKey, forHTTPHeaderField: "x-api-key")
                req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            }
        case .geminiV1Beta:
            break
        }

        let start = CFAbsoluteTimeGetCurrent()
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let latency = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000))
            guard let httpResp = response as? HTTPURLResponse else {
                return ConnectionHealth(
                    kind: .failed,
                    latencyMs: latency,
                    statusCode: nil,
                    message: "服务器未返回有效 HTTP 响应",
                    checkedAt: Date()
                )
            }

            if (200..<300).contains(httpResp.statusCode) {
                let modelCount = Self.countModels(in: data)
                let msg = modelCount > 0
                    ? "上游连通正常 · 探测到 \(modelCount) 个可用模型"
                    : "上游接口握手成功（HTTP \(httpResp.statusCode)）"
                return ConnectionHealth(
                    kind: .connected,
                    latencyMs: latency,
                    statusCode: httpResp.statusCode,
                    message: msg,
                    checkedAt: Date()
                )
            } else {
                let errText = MagpieLocalGateway.extractHTTPErrorMessage(statusCode: httpResp.statusCode, data: data)
                return ConnectionHealth(
                    kind: .failed,
                    latencyMs: latency,
                    statusCode: httpResp.statusCode,
                    message: errText,
                    checkedAt: Date()
                )
            }
        } catch {
            let latency = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000))
            return ConnectionHealth(
                kind: .failed,
                latencyMs: latency,
                statusCode: nil,
                message: MagpieLocalGateway.describeNetworkError(error),
                checkedAt: Date()
            )
        }
    }

    private static func countModels(in data: Data) -> Int {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return 0 }
        if let arr = json["data"] as? [[String: Any]] { return arr.count }
        if let arr = json["models"] as? [[String: Any]] { return arr.count }
        return 0
    }

    // MARK: - Models Panel (/v1/models)

    func fetchModels(forceLocalFallback: Bool = false) async {
        isLoadingModels = true
        modelsError = nil
        defer { isLoadingModels = false }

        if let profile = activeProfile, !forceLocalFallback {
            let validation = URLValidator.validateAndNormalize(profile.baseURL)
            guard case .valid(let baseURL) = validation else {
                modelsError = validation.errorReason ?? "当前配置地址无效"
                models = []
                modelsSourceLabel = "地址校验失败"
                return
            }

            let cleanKey = profile.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let urlStr: String
            switch profile.targetProtocol {
            case .geminiV1Beta:
                let encoded = cleanKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cleanKey
                urlStr = "\(baseURL)/v1beta/models?key=\(encoded)"
            default:
                urlStr = baseURL.hasSuffix("/v1") ? "\(baseURL)/models" : "\(baseURL)/v1/models"
            }

            guard let url = URL(string: urlStr) else {
                modelsError = "无效的模型接口 URL：\(urlStr)"
                return
            }

            var req = URLRequest(url: url, timeoutInterval: 15)
            req.httpMethod = "GET"
            switch profile.targetProtocol {
            case .openAIChat, .openAIResponses:
                if !cleanKey.isEmpty { req.setValue("Bearer \(cleanKey)", forHTTPHeaderField: "Authorization") }
            case .anthropicMessages:
                if !cleanKey.isEmpty {
                    req.setValue(cleanKey, forHTTPHeaderField: "x-api-key")
                    req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                }
            case .geminiV1Beta:
                break
            }

            let start = CFAbsoluteTimeGetCurrent()
            do {
                let (data, response) = try await URLSession.shared.data(for: req)
                let latency = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000))
                modelsLatencyMs = latency
                guard let http = response as? HTTPURLResponse else {
                    modelsError = "上游未返回有效 HTTP 响应"
                    return
                }
                guard (200..<300).contains(http.statusCode) else {
                    let msg = MagpieLocalGateway.extractHTTPErrorMessage(statusCode: http.statusCode, data: data)
                    modelsError = msg
                    healthByProfile[profile.id] = ConnectionHealth(
                        kind: .failed,
                        latencyMs: latency,
                        statusCode: http.statusCode,
                        message: msg,
                        checkedAt: Date()
                    )
                    return
                }

                let parsed = Self.parseModelsPayload(data: data, source: profile.name)
                if parsed.isEmpty {
                    modelsError = "上游返回 HTTP \(http.statusCode)，但模型列表为空或字段格式不兼容"
                } else {
                    models = parsed
                    modelsSourceLabel = "上游实时拉取 · \(profile.name)"
                    healthByProfile[profile.id] = ConnectionHealth(
                        kind: .connected,
                        latencyMs: latency,
                        statusCode: http.statusCode,
                        message: "已拉取 \(parsed.count) 个模型 · \(latency) ms",
                        checkedAt: Date()
                    )
                }
                return
            } catch {
                let latency = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000))
                modelsLatencyMs = latency
                let msg = MagpieLocalGateway.describeNetworkError(error)
                modelsError = msg
                healthByProfile[profile.id] = ConnectionHealth(
                    kind: .failed,
                    latencyMs: latency,
                    statusCode: nil,
                    message: msg,
                    checkedAt: Date()
                )
                return
            }
        }

        // Local gateway /v1/models
        guard let localURL = URL(string: "http://127.0.0.1:3425/v1/models") else { return }
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: localURL, timeoutInterval: 5))
            let latency = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000))
            modelsLatencyMs = latency
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                modelsError = "本地网关 /v1/models 返回异常"
                return
            }
            models = Self.parseModelsPayload(data: data, source: "本地网关")
            modelsSourceLabel = forceLocalFallback ? "本地内置模型列表" : "本地网关 /v1/models"
        } catch {
            modelsError = "本地网关 127.0.0.1:3425 不可达：\(error.localizedDescription)"
        }
    }

    private static func parseModelsPayload(data: Data, source: String) -> [MagpieModelItem] {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return []
        }
        if let arr = json["data"] as? [[String: Any]] {
            return arr.compactMap { row in
                guard let id = row["id"] as? String, !id.isEmpty else { return nil }
                let owner = (row["owned_by"] as? String) ?? "upstream"
                return MagpieModelItem(id: id, ownedBy: owner, source: source)
            }.sorted { $0.id < $1.id }
        }
        if let arr = json["models"] as? [[String: Any]] {
            return arr.compactMap { row in
                guard let name = row["name"] as? String, !name.isEmpty else { return nil }
                let clean = name.replacingOccurrences(of: "models/", with: "")
                return MagpieModelItem(id: clean, ownedBy: "google-gemini", source: source)
            }.sorted { $0.id < $1.id }
        }
        return []
    }

    // MARK: - End-to-End Local Gateway Smoke Test

    func runGatewaySmokeTest(route: String, prompt: String, model: String) async -> (ok: Bool, statusCode: Int, latencyMs: Int, output: String) {
        let cleanRoute = route.hasPrefix("/") ? route : "/\(route)"
        guard let url = URL(string: "http://127.0.0.1:3425\(cleanRoute)") else {
            return (false, 0, 0, "无效的本地路由：\(cleanRoute)")
        }

        var req = URLRequest(url: url, timeoutInterval: 65)
        let isGet = (cleanRoute == "/api/status" || cleanRoute == "/v1/models" || cleanRoute == "/api/config")
        req.httpMethod = isGet ? "GET" : "POST"
        if !isGet {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let bodyDict: [String: Any]
            switch cleanRoute {
            case "/v1/messages":
                bodyDict = [
                    "model": model,
                    "max_tokens": 512,
                    "messages": [["role": "user", "content": prompt]]
                ]
            case "/v1/responses":
                bodyDict = [
                    "model": model,
                    "input": prompt
                ]
            default:
                if cleanRoute.hasPrefix("/v1beta/models") {
                    bodyDict = [
                        "contents": [["role": "user", "parts": [["text": prompt]]]]
                    ]
                } else {
                    bodyDict = [
                        "model": model,
                        "messages": [["role": "user", "content": prompt]]
                    ]
                }
            }
            req.httpBody = try? JSONSerialization.data(withJSONObject: bodyDict)
        }

        let start = CFAbsoluteTimeGetCurrent()
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let latency = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000))
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let pretty = Self.prettyJSONString(from: data)
            refreshGatewayState()
            return ((200..<300).contains(code), code, latency, pretty)
        } catch {
            let latency = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000))
            return (false, 0, latency, MagpieLocalGateway.describeNetworkError(error))
        }
    }

    private static func prettyJSONString(from data: Data) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data),
           let formatted = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: formatted, encoding: .utf8) {
            return str
        }
        return String(data: data, encoding: .utf8) ?? "<空响应>"
    }

    func clearLogs() {
        MagpieLocalGateway.shared.clearLogs()
        showToast("已清空请求日志")
    }

    // MARK: - Persistence

    private func loadPersistedState() {
        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: profilesKey),
           let decoded = try? decoder.decode([ProxyProfile].self, from: data) {
            profiles = decoded
        }
        if let idStr = UserDefaults.standard.string(forKey: activeIDKey),
           let uuid = UUID(uuidString: idStr),
           profiles.contains(where: { $0.id == uuid }) {
            activeProfileID = uuid
        } else {
            activeProfileID = profiles.first?.id
        }
        if let pData = UserDefaults.standard.data(forKey: privacyKey),
           let decodedPrivacy = try? decoder.decode(PrivacyMaskSettings.self, from: pData) {
            privacySettings = decodedPrivacy
        }
    }

    private func persistProfiles() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(profiles) {
            UserDefaults.standard.set(data, forKey: profilesKey)
        }
        if let id = activeProfileID {
            UserDefaults.standard.set(id.uuidString, forKey: activeIDKey)
        } else {
            UserDefaults.standard.removeObject(forKey: activeIDKey)
        }
    }

    private func savePrivacySettings() {
        if let data = try? JSONEncoder().encode(privacySettings) {
            UserDefaults.standard.set(data, forKey: privacyKey)
        }
    }

    private func syncActiveProfileToGateway() {
        if let active = activeProfile {
            MagpieLocalGateway.shared.applyUpstreamConfig(
                MagpieUpstreamConfig(
                    baseURL: active.baseURL,
                    apiKey: active.apiKey,
                    targetProtocol: active.targetProtocol.rawValue,
                    defaultModel: active.defaultModel,
                    profileName: active.name
                )
            )
        } else {
            MagpieLocalGateway.shared.applyUpstreamConfig(nil)
        }
    }
}

enum ProfileSaveError: Error {
    case message(String)

    var text: String {
        switch self {
        case .message(let s): return s
        }
    }
}
