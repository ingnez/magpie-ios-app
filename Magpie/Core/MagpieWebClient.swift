import Foundation

enum MagpieWebError: LocalizedError, Equatable {
    case notConfigured
    case invalidURL(String)
    case missingWebKey
    case unauthorized(String)
    case httpError(statusCode: Int, message: String)
    case decodingError(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "尚未配置 magpie web 服务器"
        case .invalidURL(let reason):
            return reason
        case .missingWebKey:
            return "缺少访问密钥 k，请填写 magpie web 启动链接中的 k 或环境变量 MAGPIE_WEB_KEY"
        case .unauthorized(let msg):
            return msg
        case .httpError(let code, let msg):
            return msg.isEmpty ? "HTTP \(code) 请求失败" : "HTTP \(code)：\(msg)"
        case .decodingError(let msg):
            return "响应数据解析失败：\(msg)"
        case .networkError(let msg):
            return msg
        }
    }
}

private final class MagpieSessionDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let allowInsecureTLS: Bool

    init(allowInsecureTLS: Bool) {
        self.allowInsecureTLS = allowInsecureTLS
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if allowInsecureTLS,
           challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }
}

/// Native iOS client for `yetone/magpie`'s `magpie web` HTTP API (`/api/*`).
///
/// Authentication & security contract (per `internal/gui/web.go`):
/// - Does NOT send `Authorization: Bearer` on `/api/*`. Instead exchanges `k` for the
///   server-issued HttpOnly cookie (`magpie_web_<listeningPort>`) via `GET /api/state?k=<key>`
///   (server returns `Set-Cookie` + `303 See Other` to `/api/state`).
/// - Does NOT send `Origin` or cross-site `Sec-Fetch-Site` headers, keeping Go's
///   `http.NewCrossOriginProtection()` (`webOwnPage`) satisfied.
/// - On HTTP `401` (for example when the cookie expired or `magpie web` restarted with a new key),
///   triggers one serialized re-authentication with the stored `k` and retries the request once.
actor MagpieWebClient {
    private var server: MagpieServerProfile?
    private var webKey: String = ""
    private var session: URLSession
    private var sessionDelegate: MagpieSessionDelegate
    private var isAuthenticating = false
    private var authWaiters: [CheckedContinuation<Void, Error>] = []
    private var lastRawSettings: [String: Any]?

    init() {
        let delegate = MagpieSessionDelegate(allowInsecureTLS: false)
        self.sessionDelegate = delegate
        self.session = Self.makeSession(delegate: delegate)
    }

    private static func makeSession(delegate: MagpieSessionDelegate) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    func configure(server: MagpieServerProfile?, webKey: String) {
        let cleanKey = webKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let needsNewSession = (self.server?.id != server?.id)
            || (self.server?.baseURL != server?.baseURL)
            || (self.server?.allowInsecureTLS != server?.allowInsecureTLS)
            || (self.webKey != cleanKey)

        self.server = server
        self.webKey = cleanKey
        self.lastRawSettings = nil

        if needsNewSession {
            self.session.invalidateAndCancel()
            let delegate = MagpieSessionDelegate(allowInsecureTLS: server?.allowInsecureTLS ?? false)
            self.sessionDelegate = delegate
            self.session = Self.makeSession(delegate: delegate)
        }
    }

    func currentCookieCount() -> Int {
        guard let base = server?.baseURL, let url = URL(string: base) else { return 0 }
        return session.configuration.httpCookieStorage?.cookies(for: url)?.count ?? 0
    }

    func consoleSession() async throws -> (base: URL, cookies: [HTTPCookie], insecureTLS: Bool) {
        try await ensureAuthenticated(forceRefresh: true)
        guard let profile = server, let base = URL(string: profile.baseURL) else { throw MagpieWebError.notConfigured }
        let cookies = session.configuration.httpCookieStorage?.cookies(for: base) ?? []
        return (base, cookies.filter { $0.name.hasPrefix("magpie_web_") }, profile.allowInsecureTLS)
    }

    // MARK: - Auth & Cookie Exchange

    /// Exchanges `k` for the `magpie_web_<port>` cookie via `GET /api/state?k=<key>`
    /// (with `POST /_magpie/sign-in` available as fallback). Serialized so concurrent
    /// 401s only perform one sign-in round trip.
    func ensureAuthenticated(forceRefresh: Bool = false) async throws {
        guard let server = server else { throw MagpieWebError.notConfigured }
        guard !webKey.isEmpty else { throw MagpieWebError.missingWebKey }

        if !forceRefresh,
           let baseURL = URL(string: server.baseURL),
           let cookies = session.configuration.httpCookieStorage?.cookies(for: baseURL),
           cookies.contains(where: { $0.name.hasPrefix("magpie_web_") }) {
            return
        }

        if isAuthenticating {
            try await withCheckedThrowingContinuation { continuation in
                authWaiters.append(continuation)
            }
            return
        }

        isAuthenticating = true
        do {
            try await performCookieExchange(server: server, key: webKey)
            isAuthenticating = false
            let waiters = authWaiters
            authWaiters.removeAll()
            for w in waiters { w.resume(returning: ()) }
        } catch {
            isAuthenticating = false
            let waiters = authWaiters
            authWaiters.removeAll()
            for w in waiters { w.resume(throwing: error) }
            throw error
        }
    }

    private func performCookieExchange(server: MagpieServerProfile, key: String) async throws {
        guard var components = URLComponents(string: server.baseURL) else {
            throw MagpieWebError.invalidURL("服务器地址无法解析")
        }
        let basePath = components.path == "/" ? "" : components.path
        components.path = basePath + "/api/state"
        components.queryItems = [URLQueryItem(name: "k", value: key)]
        guard let exchangeURL = components.url else {
            throw MagpieWebError.invalidURL("无法构造鉴权请求地址")
        }

        var req = URLRequest(url: exchangeURL, timeoutInterval: 15)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")

        let (data, response) = try await executeRaw(req)
        if response.statusCode == 401 {
            let bodyText = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let msg = bodyText.isEmpty
                ? "访问密钥 k 无效，请核对 magpie web 启动链接中的 k"
                : "密钥 k 校验未通过（HTTP 401）：\(bodyText)"
            throw MagpieWebError.unauthorized(msg)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw MagpieWebError.httpError(
                statusCode: response.statusCode,
                message: Self.extractErrorMessage(from: data, statusCode: response.statusCode)
            )
        }

        // Fallback check: if an upstream proxy stripped the cookie on GET redirect,
        // explicitly post the form to `/_magpie/sign-in` (`key=<key>&back=/api/state`).
        if let baseURL = URL(string: server.baseURL),
           (session.configuration.httpCookieStorage?.cookies(for: baseURL) ?? []).isEmpty {
            try await signInWithForm(server: server, key: key)
        }
    }

    private func signInWithForm(server: MagpieServerProfile, key: String) async throws {
        guard let url = buildURL(base: server.baseURL, path: "/_magpie/sign-in") else {
            throw MagpieWebError.invalidURL("无法构造登录表单地址")
        }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var bodyItems = URLComponents()
        bodyItems.queryItems = [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "back", value: "/api/state")
        ]
        req.httpBody = bodyItems.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await executeRaw(req)
        if response.statusCode == 401 {
            throw MagpieWebError.unauthorized("密钥 k 无效，Cookie 交换失败（HTTP 401）")
        }
        guard (200..<400).contains(response.statusCode) else {
            throw MagpieWebError.httpError(
                statusCode: response.statusCode,
                message: Self.extractErrorMessage(from: data, statusCode: response.statusCode)
            )
        }
    }

    // MARK: - Core HTTP Pipeline with 401 Auto-Renewal

    func requestData(
        method: String = "GET",
        path: String,
        queryItems: [URLQueryItem] = [],
        jsonBody: Any? = nil,
        timeout: TimeInterval = 20
    ) async throws -> (Data, HTTPURLResponse) {
        guard let server = server else { throw MagpieWebError.notConfigured }
        try await ensureAuthenticated(forceRefresh: false)

        let urlRequest = try makeRequest(
            base: server.baseURL,
            method: method,
            path: path,
            queryItems: queryItems,
            jsonBody: jsonBody,
            timeout: timeout
        )

        let (data, response) = try await executeRaw(urlRequest)
        if response.statusCode == 401 {
            // Cookie missing, cleared, or server restarted with a new key:
            // exchange `k` once more and retry the request.
            try await ensureAuthenticated(forceRefresh: true)
            let retryRequest = try makeRequest(
                base: server.baseURL,
                method: method,
                path: path,
                queryItems: queryItems,
                jsonBody: jsonBody,
                timeout: timeout
            )
            let (retryData, retryResponse) = try await executeRaw(retryRequest)
            if retryResponse.statusCode == 401 {
                let serverMsg = String(data: retryData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                throw MagpieWebError.unauthorized(
                    serverMsg.isEmpty
                        ? "会话已失效且自动续签失败（HTTP 401），请更新密钥 k"
                        : "HTTP 401 鉴权失效：\(serverMsg)"
                )
            }
            guard (200..<300).contains(retryResponse.statusCode) else {
                throw MagpieWebError.httpError(
                    statusCode: retryResponse.statusCode,
                    message: Self.extractErrorMessage(from: retryData, statusCode: retryResponse.statusCode)
                )
            }
            return (retryData, retryResponse)
        }

        guard (200..<300).contains(response.statusCode) else {
            throw MagpieWebError.httpError(
                statusCode: response.statusCode,
                message: Self.extractErrorMessage(from: data, statusCode: response.statusCode)
            )
        }
        return (data, response)
    }

    func requestJSON<T: Decodable>(
        _ type: T.Type,
        method: String = "GET",
        path: String,
        queryItems: [URLQueryItem] = [],
        jsonBody: Any? = nil,
        timeout: TimeInterval = 20
    ) async throws -> (value: T, response: HTTPURLResponse) {
        let (data, response) = try await requestData(
            method: method,
            path: path,
            queryItems: queryItems,
            jsonBody: jsonBody,
            timeout: timeout
        )
        do {
            let decoded = try JSONDecoder().decode(T.self, from: data)
            return (decoded, response)
        } catch {
            throw MagpieWebError.decodingError("\(path): \(error.localizedDescription)")
        }
    }

    private func makeRequest(
        base: String,
        method: String,
        path: String,
        queryItems: [URLQueryItem],
        jsonBody: Any?,
        timeout: TimeInterval
    ) throws -> URLRequest {
        guard let url = buildURL(base: base, path: path, queryItems: queryItems) else {
            throw MagpieWebError.invalidURL("无法构造接口地址：\(path)")
        }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        if let jsonBody = jsonBody {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        }
        return req
    }

    private func buildURL(base: String, path: String, queryItems: [URLQueryItem] = []) -> URL? {
        guard var components = URLComponents(string: base) else { return nil }
        let basePath = components.path == "/" ? "" : components.path
        let cleanPath = path.hasPrefix("/") ? path : "/\(path)"
        components.path = basePath + cleanPath
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        return components.url
    }

    private func executeRaw(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw MagpieWebError.networkError("服务器未返回有效的 HTTP 响应")
            }
            return (data, http)
        } catch let webErr as MagpieWebError {
            throw webErr
        } catch {
            throw MagpieWebError.networkError(Self.describeNetworkError(error))
        }
    }

    // MARK: - Typed `/api/*` Endpoints

    func probeAndFetchState(forceReauth: Bool = true) async throws -> (state: RemoteStateResponse, latencyMs: Int) {
        let start = CFAbsoluteTimeGetCurrent()
        if forceReauth {
            try await ensureAuthenticated(forceRefresh: true)
        }
        let (state, _) = try await requestJSON(RemoteStateResponse.self, path: "/api/state")
        let latency = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000))
        return (state, latency)
    }

    func fetchState(last: Bool = false) async throws -> RemoteStateResponse {
        let query = last ? [URLQueryItem(name: "last", value: "1")] : []
        return try await requestJSON(RemoteStateResponse.self, path: "/api/state", queryItems: query).value
    }

    func fetchProviders(last: Bool = false) async throws -> RemoteProvidersResponse {
        let query = last ? [URLQueryItem(name: "last", value: "1")] : []
        return try await requestJSON(RemoteProvidersResponse.self, path: "/api/providers", queryItems: query).value
    }

    func setProviderEnabled(id: String, enabled: Bool) async throws -> RemoteProvidersResponse {
        let action = enabled ? "on" : "off"
        return try await requestJSON(
            RemoteProvidersResponse.self,
            method: "POST",
            path: "/api/provider/\(action)",
            jsonBody: ["id": id]
        ).value
    }

    func testProvider(id: String) async throws -> [RemoteDetectionResult] {
        return try await requestJSON(
            RemoteProviderTestResponse.self,
            method: "POST",
            path: "/api/provider/test",
            jsonBody: ["id": id],
            timeout: 30
        ).value.results
    }

    func refreshProviderModels(id: String) async throws -> RemoteProviderModelsRefreshResponse {
        return try await requestJSON(
            RemoteProviderModelsRefreshResponse.self,
            method: "POST",
            path: "/api/provider/models",
            jsonBody: ["id": id],
            timeout: 35
        ).value
    }

    func refreshProviderBalance(id: String) async throws -> RemoteProviderBalanceResponse {
        return try await requestJSON(
            RemoteProviderBalanceResponse.self,
            method: "POST",
            path: "/api/provider/balance",
            jsonBody: ["id": id],
            timeout: 25
        ).value
    }

    func saveCustomProvider(
        id: String?,
        name: String,
        key: String,
        chat: String,
        anthropic: String,
        responses: String,
        gemini: String
    ) async throws -> RemoteProvidersResponse {
        var payload: [String: Any] = [
            "name": name,
            "key": key,
            "chat": chat,
            "anthropic": anthropic,
            "responses": responses,
            "gemini": gemini
        ]
        if let id = id, !id.isEmpty {
            payload["id"] = id
        } else {
            payload["new"] = true
        }
        return try await requestJSON(
            RemoteProvidersResponse.self,
            method: "POST",
            path: "/api/provider/save",
            jsonBody: payload,
            timeout: 30
        ).value
    }

    func deleteProvider(id: String) async throws -> RemoteProvidersResponse {
        return try await requestJSON(
            RemoteProvidersResponse.self,
            method: "POST",
            path: "/api/providers/delete",
            jsonBody: ["ids": [id]]
        ).value
    }

    func fetchGroups() async throws -> RemoteGroupsResponse {
        return try await requestJSON(RemoteGroupsResponse.self, path: "/api/groups").value
    }

    func switchGroup(id: String, on: Bool) async throws -> RemoteGroupsResponse {
        return try await requestJSON(
            RemoteGroupsResponse.self,
            method: "POST",
            path: "/api/groups/switch",
            jsonBody: ["id": id, "on": on]
        ).value
    }

    func pickGroupMember(id: String, member: String) async throws -> RemoteGroupsResponse {
        return try await requestJSON(
            RemoteGroupsResponse.self,
            method: "POST",
            path: "/api/groups/pick",
            jsonBody: ["id": id, "pick": member]
        ).value
    }

    func fetchTrace(after seq: Int64, wait: Bool) async throws -> RemoteTraceResponse {
        var query: [URLQueryItem] = []
        if seq > 0 {
            query.append(URLQueryItem(name: "after", value: String(seq)))
        }
        if wait {
            query.append(URLQueryItem(name: "wait", value: "1"))
        }
        return try await requestJSON(
            RemoteTraceResponse.self,
            path: "/api/gateway/trace",
            queryItems: query,
            timeout: wait ? 35 : 15
        ).value
    }

    func fetchHistory(day: String? = nil) async throws -> RemoteHistoryResponse {
        var query: [URLQueryItem] = []
        if let day = day, !day.isEmpty {
            query.append(URLQueryItem(name: "day", value: day))
        }
        return try await requestJSON(RemoteHistoryResponse.self, path: "/api/gateway/history", queryItems: query).value
    }

    func fetchCallDetail(routeID: Int64) async throws -> RemoteGatewayCallDetail {
        return try await requestJSON(
            RemoteGatewayCallDetail.self,
            path: "/api/gateway/call",
            queryItems: [URLQueryItem(name: "route", value: String(routeID))]
        ).value
    }

    func fetchUsage(period: String) async throws -> RemoteUsageResponse {
        let query = [
            URLQueryItem(name: "period", value: period),
            URLQueryItem(name: "tz", value: TimeZone.current.identifier)
        ]
        return try await requestJSON(RemoteUsageResponse.self, path: "/api/usage", queryItems: query).value
    }

    func fetchQuotas(asked: Bool, all: Bool = false) async throws -> (quotas: [RemoteUsageQuota], isReading: Bool) {
        var query: [URLQueryItem] = []
        if asked {
            query.append(URLQueryItem(name: "asked", value: "1"))
        }
        if all {
            query.append(URLQueryItem(name: "all", value: "1"))
        }
        let result = try await requestJSON([RemoteUsageQuota].self, path: "/api/usage/quotas", queryItems: query)
        let reading = result.response.value(forHTTPHeaderField: "X-Magpie-Reading") == "1"
        return (result.value, reading)
    }

    func refreshQuota(provider: String, user: String?) async throws -> [RemoteUsageQuota] {
        var query = [URLQueryItem(name: "provider", value: provider)]
        if let user = user, !user.isEmpty {
            query.append(URLQueryItem(name: "user", value: user))
        }
        return try await requestJSON(
            [RemoteUsageQuota].self,
            method: "POST",
            path: "/api/usage/quotas/refresh",
            queryItems: query,
            jsonBody: [:],
            timeout: 35
        ).value
    }

    func fetchSettings() async throws -> RemoteSettingsState {
        let (data, _) = try await requestData(path: "/api/settings")
        if let rawDict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            lastRawSettings = rawDict
        }
        do {
            return try JSONDecoder().decode(RemoteSettingsState.self, from: data)
        } catch {
            throw MagpieWebError.decodingError("/api/settings: \(error.localizedDescription)")
        }
    }

    /// Reads current `/api/settings` (when uncached), merges only changed fields so
    /// desktop/unrelated preferences are preserved (`prefsKeep`), and posts to `POST /api/settings`.
    func patchSettings(_ patch: [String: Any]) async throws -> RemoteSettingsState {
        let (rawData, _) = try await requestData(path: "/api/settings")
        guard var base = try JSONSerialization.jsonObject(with: rawData) as? [String: Any] else {
            throw MagpieWebError.decodingError("无法读取现有设置，已取消保存")
        }
        for (k, v) in patch {
            base[k] = v
        }
        // Remove read-only `settingsJSON` extras before POSTing `settings.Settings`
        let readOnlyKeys = [
            "version", "dir", "portable", "gateway", "addrEnv", "nameEnv", "log",
            "builtins", "panelKeys", "jsRoutings", "onNetwork", "allowIPsEnv",
            "allowIPsFromEnv", "mtlsCerts", "mtlsErr", "joinOn", "publicURL",
            "publicKind", "wsl", "web", "gatewayOn", "gatewayWhy", "gatewayPaused",
            "barkKeySet"
        ]
        for key in readOnlyKeys {
            base.removeValue(forKey: key)
        }

        let (data, _) = try await requestData(method: "POST", path: "/api/settings", jsonBody: base)
        if let rawDict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            lastRawSettings = rawDict
        }
        do {
            return try JSONDecoder().decode(RemoteSettingsState.self, from: data)
        } catch {
            throw MagpieWebError.decodingError("POST /api/settings: \(error.localizedDescription)")
        }
    }

    func updateLAN(on: Bool, newKey: Bool = false) async throws -> RemoteSettingsState {
        return try await requestJSON(
            RemoteSettingsState.self,
            method: "POST",
            path: "/api/settings/lan",
            jsonBody: ["on": on, "newKey": newKey]
        ).value
    }

    func updateAllowIPs(_ ips: [String]) async throws -> RemoteSettingsState {
        return try await requestJSON(
            RemoteSettingsState.self,
            method: "POST",
            path: "/api/settings/allowips",
            jsonBody: ["ips": ips]
        ).value
    }

    func updateBark(server: String?, key: String?, daily: String?) async throws -> RemoteSettingsState {
        var payload: [String: Any] = [:]
        if let server = server { payload["server"] = server }
        if let key = key { payload["key"] = key }
        if let daily = daily { payload["daily"] = daily }
        return try await requestJSON(
            RemoteSettingsState.self,
            method: "POST",
            path: "/api/settings/bark",
            jsonBody: payload
        ).value
    }

    func testBark() async throws {
        _ = try await requestData(method: "POST", path: "/api/bark/test", jsonBody: [:], timeout: 25)
    }

    func previewMasking(text: String) async throws -> RemoteMaskingPreview {
        return try await requestJSON(
            RemoteMaskingPreview.self,
            method: "POST",
            path: "/api/masking/preview",
            jsonBody: ["text": text]
        ).value
    }

    func fetchMaskingSummary(days: Int = 7) async throws -> RemoteMaskingSummary {
        return try await requestJSON(
            RemoteMaskingSummary.self,
            path: "/api/masking/summary",
            queryItems: [URLQueryItem(name: "days", value: String(days))]
        ).value
    }

    func fetchMaskingRecords(before: Int64? = nil, limit: Int = 50, blockedOnly: Bool = false) async throws -> RemoteMaskingRecordsPage {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let before = before {
            query.append(URLQueryItem(name: "before", value: String(before)))
        }
        if blockedOnly {
            query.append(URLQueryItem(name: "blocked", value: "1"))
        }
        return try await requestJSON(RemoteMaskingRecordsPage.self, path: "/api/masking/records", queryItems: query).value
    }

    func updateRedactRules(_ rules: [RemoteRedactRule]) async throws -> RemoteSettingsState {
        let rawRules = rules.map { rule -> [String: String] in
            var item: [String: String] = ["kind": rule.kind]
            if let prefix = rule.prefix, !prefix.isEmpty { item["prefix"] = prefix }
            if let regex = rule.regex, !regex.isEmpty { item["regex"] = regex }
            return item
        }
        return try await requestJSON(
            RemoteSettingsState.self,
            method: "POST",
            path: "/api/settings/redact-rules",
            jsonBody: ["rules": rawRules]
        ).value
    }

    func updateRedactAllow(_ allow: [String]) async throws -> RemoteSettingsState {
        return try await requestJSON(
            RemoteSettingsState.self,
            method: "POST",
            path: "/api/settings/redact-allow",
            jsonBody: ["allow": allow]
        ).value
    }

    func clearMaskingRecords() async throws {
        _ = try await requestData(method: "POST", path: "/api/masking/clear", jsonBody: [:])
    }

    func fetchCallerKeys() async throws -> [RemoteCallerKey] {
        return try await requestJSON(RemoteCallerKeysResponse.self, path: "/api/caller-keys").value.keys
    }

    // MARK: - Error Helpers

    private static func extractErrorMessage(from data: Data, statusCode: Int) -> String {
        if let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            if let err = json["error"] as? String, !err.isEmpty { return err }
            if let msg = json["message"] as? String, !msg.isEmpty { return msg }
            if let errObj = json["error"] as? [String: Any], let msg = errObj["message"] as? String { return msg }
        }
        if let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            return String(raw.prefix(200))
        }
        switch statusCode {
        case 401: return "鉴权失败或 Cookie 已过期"
        case 403: return "请求被拒绝（请检查同源防护、IP 白名单或 mTLS 证书）"
        case 404: return "接口不存在（请确认服务端为最新版 magpie web）"
        default: return "服务端返回异常状态"
        }
    }

    private static func describeNetworkError(_ error: Error) -> String {
        let nsErr = error as NSError
        guard nsErr.domain == NSURLErrorDomain else {
            return error.localizedDescription
        }
        switch nsErr.code {
        case NSURLErrorTimedOut:
            return "连接超时：magpie web 未在规定时间内响应"
        case NSURLErrorCannotFindHost:
            return "域名解析失败，请检查服务器地址"
        case NSURLErrorCannotConnectToHost:
            return "无法建立连接，请检查服务器 IP、端口或防火墙"
        case NSURLErrorNetworkConnectionLost:
            return "网络连接中断"
        case NSURLErrorNotConnectedToInternet:
            return "当前设备无可用网络连接"
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate:
            return "TLS 证书校验失败（如使用自签证书，可在服务器设置中开启「允许自签名 HTTPS」）"
        case NSURLErrorCancelled:
            return "请求已取消"
        default:
            return "网络错误（\(nsErr.code)）：\(nsErr.localizedDescription)"
        }
    }
}
