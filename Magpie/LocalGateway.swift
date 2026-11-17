import Foundation
import Darwin

extension Notification.Name {
    static let magpieGatewayDidUpdate = Notification.Name("ai.usemagpie.ios.gatewayDidUpdate")
}

private struct UpstreamForwardResult {
    let statusCode: Int
    let json: [String: Any]?
    let errorMessage: String?
    let latencyMs: Int
}

final class MagpieLocalGateway {
    static let shared = MagpieLocalGateway()

    private let lock = NSLock()
    private var isRunning = false
    private var bindFailedReason: String?
    private var requestCount = 0
    private var successCount = 0
    private var errorCount = 0
    private var maskedItemsCount = 0
    private var upstreamConfig: MagpieUpstreamConfig?
    private var privacySettings = PrivacyMaskSettings()
    private var logs: [GatewayLogEntry] = []
    private let maxLogEntries = 200

    static let fallbackModels: [[String: Any]] = [
        ["id": "claude-sonnet-4-5", "object": "model", "owned_by": "magpie-anthropic"],
        ["id": "claude-opus-4-5", "object": "model", "owned_by": "magpie-anthropic"],
        ["id": "gemini-2.5-pro", "object": "model", "owned_by": "magpie-gemini"],
        ["id": "gemini-2.5-flash", "object": "model", "owned_by": "magpie-gemini"],
        ["id": "deepseek-r1", "object": "model", "owned_by": "magpie-deepseek"],
        ["id": "gpt-4o", "object": "model", "owned_by": "magpie-openai"],
        ["id": "gpt-4.1", "object": "model", "owned_by": "magpie-openai"]
    ]

    private init() {}

    func startIfNeeded() {
        lock.lock()
        guard !isRunning else {
            lock.unlock()
            return
        }
        isRunning = true
        lock.unlock()

        Thread.detachNewThread {
            self.runServerLoop()
        }
    }

    func applyUpstreamConfig(_ cfg: MagpieUpstreamConfig?) {
        lock.lock()
        if var normalized = cfg {
            while normalized.baseURL.hasSuffix("/") {
                normalized.baseURL.removeLast()
            }
            upstreamConfig = normalized
        } else {
            upstreamConfig = nil
        }
        lock.unlock()
        notifyObservers()
    }

    func updatePrivacySettings(_ settings: PrivacyMaskSettings) {
        lock.lock()
        privacySettings = settings
        lock.unlock()
        notifyObservers()
    }

    func currentSnapshot() -> GatewayStatusSnapshot {
        lock.lock()
        let snap = GatewayStatusSnapshot(
            daemonOnline: isRunning && bindFailedReason == nil,
            requestsHandled: requestCount,
            successCount: successCount,
            errorCount: errorCount,
            maskedItemsCount: maskedItemsCount,
            listenAddress: "http://127.0.0.1:3425",
            lastError: bindFailedReason
        )
        lock.unlock()
        return snap
    }

    func recentLogs() -> [GatewayLogEntry] {
        lock.lock()
        let copy = logs
        lock.unlock()
        return copy
    }

    func clearLogs() {
        lock.lock()
        logs.removeAll()
        lock.unlock()
        notifyObservers()
    }

    private func notifyObservers() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .magpieGatewayDidUpdate, object: nil)
        }
    }

    private func appendLog(_ entry: GatewayLogEntry, isSuccess: Bool) {
        lock.lock()
        if isSuccess {
            successCount += 1
        } else {
            errorCount += 1
        }
        maskedItemsCount += entry.maskedCount
        logs.insert(entry, at: 0)
        if logs.count > maxLogEntries {
            logs.removeLast(logs.count - maxLogEntries)
        }
        lock.unlock()
        notifyObservers()
    }

    private func runServerLoop() {
        signal(SIGPIPE, SIG_IGN)
        let srv = socket(AF_INET, SOCK_STREAM, 0)
        guard srv >= 0 else {
            lock.lock()
            bindFailedReason = "无法创建本地监听 Socket（errno=\(errno)）"
            isRunning = false
            lock.unlock()
            notifyObservers()
            return
        }

        var yes: Int32 = 1
        setsockopt(srv, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(srv, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(3425).bigEndian
        addr.sin_addr = in_addr(s_addr: UInt32(0x7f000001).bigEndian)

        let bindRes = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(srv, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindRes == 0, listen(srv, 64) == 0 else {
            let err = errno
            close(srv)
            lock.lock()
            bindFailedReason = "本地端口 127.0.0.1:3425 绑定失败（errno=\(err)）"
            isRunning = false
            lock.unlock()
            notifyObservers()
            return
        }

        notifyObservers()

        while true {
            let client = accept(srv, nil, nil)
            if client < 0 { continue }
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
            DispatchQueue.global(qos: .userInitiated).async {
                self.handleConnection(client: client)
                close(client)
            }
        }
    }

    private func handleConnection(client: Int32) {
        let startTime = CFAbsoluteTimeGetCurrent()
        guard let rawRequest = readHTTPRequest(client: client) else { return }

        if rawRequest.method == "OPTIONS" {
            sendJSON(client: client, status: "204 No Content", bodyData: Data())
            return
        }

        lock.lock()
        requestCount += 1
        let count = requestCount
        let sCount = successCount
        let eCount = errorCount
        let mCount = maskedItemsCount
        let savedUpstream = upstreamConfig
        let currentPrivacy = privacySettings
        lock.unlock()

        let path = rawRequest.path.components(separatedBy: "?").first ?? rawRequest.path

        if rawRequest.method == "GET" && (path == "/health" || path == "/api/status") {
            let statusPayload: [String: Any] = [
                "status": "ok",
                "app": "Magpie iOS Reverse Proxy Gateway",
                "version": "2.0.0",
                "listen": "http://127.0.0.1:3425",
                "native_daemon": true,
                "requests_handled": count,
                "success_count": sCount,
                "error_count": eCount,
                "masked_items_count": mCount,
                "privacy_masking_enabled": currentPrivacy.enabled,
                "active_profile": savedUpstream?.profileName ?? "未配置上游（本地回环）",
                "active_base_url": savedUpstream?.baseURL ?? "",
                "protocols": [
                    "openai-chat",
                    "openai-responses",
                    "anthropic-messages",
                    "gemini-v1beta"
                ]
            ]
            sendDict(client: client, status: "200 OK", dict: statusPayload)
            return
        }

        if rawRequest.method == "GET" && path == "/api/config" {
            let cfgPayload: [String: Any] = [
                "configured": savedUpstream != nil,
                "baseURL": savedUpstream?.baseURL ?? "",
                "targetProtocol": savedUpstream?.targetProtocol ?? MagpieProtocol.openAIChat.rawValue,
                "defaultModel": savedUpstream?.defaultModel ?? "",
                "profileName": savedUpstream?.profileName ?? "",
                "privacyMaskingEnabled": currentPrivacy.enabled
            ]
            sendDict(client: client, status: "200 OK", dict: cfgPayload)
            return
        }

        if rawRequest.method == "POST" && path == "/api/config" {
            if var cfg = try? JSONDecoder().decode(MagpieUpstreamConfig.self, from: rawRequest.body) {
                if !cfg.baseURL.isEmpty {
                    let validation = URLValidator.validateAndNormalize(cfg.baseURL)
                    switch validation {
                    case .valid(let normalized):
                        cfg.baseURL = normalized
                    case .invalid(let reason):
                        sendDict(client: client, status: "400 Bad Request", dict: ["ok": false, "error": reason])
                        return
                    }
                }
                applyUpstreamConfig(cfg)
                let elapsed = max(1, Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000))
                appendLog(
                    GatewayLogEntry(
                        id: UUID(),
                        timestamp: Date(),
                        method: "POST",
                        path: path,
                        inboundProtocol: "config",
                        targetProtocol: cfg.targetProtocol,
                        model: cfg.defaultModel,
                        statusCode: 200,
                        latencyMs: elapsed,
                        upstreamURL: cfg.baseURL,
                        maskedCount: 0,
                        outcome: .localLoopback,
                        errorMessage: nil,
                        requestPreview: "更新配置: \(cfg.profileName ?? cfg.baseURL)",
                        responsePreview: "已应用 \(cfg.targetProtocol)"
                    ),
                    isSuccess: true
                )
                sendDict(client: client, status: "200 OK", dict: [
                    "ok": true,
                    "baseURL": cfg.baseURL,
                    "targetProtocol": cfg.targetProtocol,
                    "defaultModel": cfg.defaultModel
                ])
            } else {
                sendDict(client: client, status: "400 Bad Request", dict: ["ok": false, "error": "无效的 JSON 配置载荷"])
            }
            return
        }

        if rawRequest.method == "GET" && path == "/api/logs" {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let currentLogs = recentLogs()
            if let data = try? encoder.encode(currentLogs) {
                sendJSON(client: client, status: "200 OK", bodyData: data)
            } else {
                sendDict(client: client, status: "200 OK", dict: ["logs": []])
            }
            return
        }

        if rawRequest.method == "DELETE" && path == "/api/logs" {
            clearLogs()
            sendDict(client: client, status: "200 OK", dict: ["ok": true])
            return
        }

        if rawRequest.method == "GET" && path == "/v1/models" {
            handleModelsRoute(client: client, path: path, savedUpstream: savedUpstream, startTime: startTime)
            return
        }

        if rawRequest.method == "POST" && path == "/v1/chat/completions" {
            handleTranslationRoute(
                client: client,
                inbound: .openAIChat,
                path: path,
                headers: rawRequest.headers,
                body: rawRequest.body,
                savedUpstream: savedUpstream,
                privacy: currentPrivacy,
                startTime: startTime
            )
            return
        }

        if rawRequest.method == "POST" && path == "/v1/responses" {
            handleTranslationRoute(
                client: client,
                inbound: .openAIResponses,
                path: path,
                headers: rawRequest.headers,
                body: rawRequest.body,
                savedUpstream: savedUpstream,
                privacy: currentPrivacy,
                startTime: startTime
            )
            return
        }

        if rawRequest.method == "POST" && path == "/v1/messages" {
            handleTranslationRoute(
                client: client,
                inbound: .anthropicMessages,
                path: path,
                headers: rawRequest.headers,
                body: rawRequest.body,
                savedUpstream: savedUpstream,
                privacy: currentPrivacy,
                startTime: startTime
            )
            return
        }

        if rawRequest.method == "POST" && path.hasPrefix("/v1beta/models") {
            handleTranslationRoute(
                client: client,
                inbound: .geminiV1Beta,
                path: path,
                headers: rawRequest.headers,
                body: rawRequest.body,
                savedUpstream: savedUpstream,
                privacy: currentPrivacy,
                startTime: startTime
            )
            return
        }

        let elapsed = max(1, Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000))
        appendLog(
            GatewayLogEntry(
                id: UUID(),
                timestamp: Date(),
                method: rawRequest.method,
                path: path,
                inboundProtocol: "unknown",
                targetProtocol: "-",
                model: "-",
                statusCode: 404,
                latencyMs: elapsed,
                upstreamURL: savedUpstream?.baseURL ?? "",
                maskedCount: 0,
                outcome: .error,
                errorMessage: "未匹配到路由 \(path)",
                requestPreview: "\(rawRequest.method) \(path)",
                responsePreview: "404 Unknown route"
            ),
            isSuccess: false
        )
        sendDict(client: client, status: "404 Not Found", dict: ["error": "Unknown route", "path": path])
    }

    private func handleModelsRoute(
        client: Int32,
        path: String,
        savedUpstream: MagpieUpstreamConfig?,
        startTime: CFAbsoluteTime
    ) {
        if let upstream = savedUpstream, !upstream.baseURL.isEmpty {
            let proto = MagpieProtocol(rawValue: upstream.targetProtocol) ?? .openAIChat
            let res = fetchUpstreamModelsSync(baseURL: upstream.baseURL, apiKey: upstream.apiKey, targetProto: proto)
            if let models = res.models, !models.isEmpty {
                let dataArray: [[String: Any]] = models.map { item in
                    ["id": item.id, "object": "model", "owned_by": item.ownedBy]
                }
                let elapsed = max(1, Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000))
                appendLog(
                    GatewayLogEntry(
                        id: UUID(),
                        timestamp: Date(),
                        method: "GET",
                        path: path,
                        inboundProtocol: "models",
                        targetProtocol: proto.rawValue,
                        model: "-",
                        statusCode: 200,
                        latencyMs: elapsed,
                        upstreamURL: upstream.baseURL,
                        maskedCount: 0,
                        outcome: .forwarded,
                        errorMessage: nil,
                        requestPreview: "拉取上游模型列表",
                        responsePreview: "返回 \(models.count) 个模型"
                    ),
                    isSuccess: true
                )
                sendDict(client: client, status: "200 OK", dict: [
                    "object": "list",
                    "source": "upstream",
                    "data": dataArray
                ])
                return
            } else {
                let elapsed = max(1, Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000))
                let errMsg = res.errorMessage ?? "上游模型列表返回为空"
                appendLog(
                    GatewayLogEntry(
                        id: UUID(),
                        timestamp: Date(),
                        method: "GET",
                        path: path,
                        inboundProtocol: "models",
                        targetProtocol: proto.rawValue,
                        model: "-",
                        statusCode: res.statusCode > 0 ? res.statusCode : 502,
                        latencyMs: elapsed,
                        upstreamURL: upstream.baseURL,
                        maskedCount: 0,
                        outcome: .error,
                        errorMessage: errMsg,
                        requestPreview: "拉取上游模型列表",
                        responsePreview: errMsg
                    ),
                    isSuccess: false
                )
                sendDict(client: client, status: "200 OK", dict: [
                    "object": "list",
                    "source": "local_fallback",
                    "upstream_error": errMsg,
                    "data": Self.fallbackModels
                ])
                return
            }
        }

        let elapsed = max(1, Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000))
        appendLog(
            GatewayLogEntry(
                id: UUID(),
                timestamp: Date(),
                method: "GET",
                path: path,
                inboundProtocol: "models",
                targetProtocol: "local",
                model: "-",
                statusCode: 200,
                latencyMs: elapsed,
                upstreamURL: "local://127.0.0.1:3425",
                maskedCount: 0,
                outcome: .localLoopback,
                errorMessage: nil,
                requestPreview: "获取本地内置模型列表",
                responsePreview: "返回 \(Self.fallbackModels.count) 个内置模型"
            ),
            isSuccess: true
        )
        sendDict(client: client, status: "200 OK", dict: [
            "object": "list",
            "source": "local_builtin",
            "data": Self.fallbackModels
        ])
    }

    private func handleTranslationRoute(
        client: Int32,
        inbound: MagpieProtocol,
        path: String,
        headers: [String: String],
        body: Data,
        savedUpstream: MagpieUpstreamConfig?,
        privacy: PrivacyMaskSettings,
        startTime: CFAbsoluteTime
    ) {
        guard let inboundJSON = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else {
            let elapsed = max(1, Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000))
            appendLog(
                GatewayLogEntry(
                    id: UUID(),
                    timestamp: Date(),
                    method: "POST",
                    path: path,
                    inboundProtocol: inbound.rawValue,
                    targetProtocol: "-",
                    model: "-",
                    statusCode: 400,
                    latencyMs: elapsed,
                    upstreamURL: savedUpstream?.baseURL ?? "",
                    maskedCount: 0,
                    outcome: .error,
                    errorMessage: "请求体不是合法的 JSON",
                    requestPreview: String(data: body.prefix(160), encoding: .utf8) ?? "<binary>",
                    responsePreview: "400 Bad Request"
                ),
                isSuccess: false
            )
            sendDict(client: client, status: "400 Bad Request", dict: ["error": ["message": "Request body must be valid JSON"]])
            return
        }

        let rawCanonicalChat = ProtocolTranslator.toCanonicalOpenAIChat(from: inbound, payload: inboundJSON, path: path)
        let model = (rawCanonicalChat["model"] as? String)
            ?? savedUpstream?.defaultModel
            ?? "magpie-local-gateway"

        let userMessages = (rawCanonicalChat["messages"] as? [[String: Any]]) ?? []
        let originalPreview = extractLastUserPreview(from: userMessages)

        // Apply Privacy Masking before sending upstream or running local echo
        let maskedTuple = PrivacyMasker.maskJSONObject(rawCanonicalChat, settings: privacy)
        let canonicalChat = (maskedTuple.masked as? [String: Any]) ?? rawCanonicalChat
        let replacements = maskedTuple.replacements
        let maskedCount = maskedTuple.count

        let upstreamURL = headers["x-magpie-upstream-url"] ?? savedUpstream?.baseURL
        let upstreamProtoRaw = headers["x-magpie-upstream-protocol"] ?? savedUpstream?.targetProtocol ?? inbound.rawValue
        let targetProto = MagpieProtocol(rawValue: upstreamProtoRaw) ?? inbound
        let upstreamKey = headers["x-magpie-upstream-key"] ?? savedUpstream?.apiKey

        if let base = upstreamURL, !base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let key = upstreamKey ?? ""
            if key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let elapsed = max(1, Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000))
                let errMsg = "当前已指定上游地址（\(base)），但未配置 API Key，无法转发请求。"
                appendLog(
                    GatewayLogEntry(
                        id: UUID(),
                        timestamp: Date(),
                        method: "POST",
                        path: path,
                        inboundProtocol: inbound.rawValue,
                        targetProtocol: targetProto.rawValue,
                        model: model,
                        statusCode: 401,
                        latencyMs: elapsed,
                        upstreamURL: base,
                        maskedCount: maskedCount,
                        outcome: .error,
                        errorMessage: errMsg,
                        requestPreview: originalPreview,
                        responsePreview: errMsg
                    ),
                    isSuccess: false
                )
                sendDict(client: client, status: "401 Unauthorized", dict: [
                    "error": [
                        "message": errMsg,
                        "type": "magpie_missing_api_key"
                    ]
                ])
                return
            }

            var outboundPayload = ProtocolTranslator.fromCanonicalOpenAIChat(canonicalChat, to: targetProto)
            outboundPayload["stream"] = false

            let forwardResult = forwardUpstream(
                baseURL: base,
                apiKey: key,
                targetProto: targetProto,
                model: model,
                payload: outboundPayload
            )

            if (200..<300).contains(forwardResult.statusCode), let forwardedJSON = forwardResult.json {
                let canonicalResp = ProtocolTranslator.responseToCanonicalOpenAIChat(from: targetProto, payload: forwardedJSON, model: model)
                let unmaskedCanonical = (PrivacyMasker.unmaskJSONObject(canonicalResp, replacements: replacements) as? [String: Any]) ?? canonicalResp
                let clientResp = ProtocolTranslator.responseFromCanonicalOpenAIChat(unmaskedCanonical, to: inbound, model: model)
                let respText = extractAssistantPreview(from: unmaskedCanonical)

                appendLog(
                    GatewayLogEntry(
                        id: UUID(),
                        timestamp: Date(),
                        method: "POST",
                        path: path,
                        inboundProtocol: inbound.rawValue,
                        targetProtocol: targetProto.rawValue,
                        model: model,
                        statusCode: forwardResult.statusCode,
                        latencyMs: forwardResult.latencyMs,
                        upstreamURL: base,
                        maskedCount: maskedCount,
                        outcome: .forwarded,
                        errorMessage: nil,
                        requestPreview: originalPreview,
                        responsePreview: respText
                    ),
                    isSuccess: true
                )
                sendDict(client: client, status: httpStatusString(for: forwardResult.statusCode), dict: clientResp)
                return
            } else {
                let errCode = forwardResult.statusCode > 0 ? forwardResult.statusCode : 502
                let errMsg = forwardResult.errorMessage ?? "上游请求失败（HTTP \(errCode)）"
                appendLog(
                    GatewayLogEntry(
                        id: UUID(),
                        timestamp: Date(),
                        method: "POST",
                        path: path,
                        inboundProtocol: inbound.rawValue,
                        targetProtocol: targetProto.rawValue,
                        model: model,
                        statusCode: errCode,
                        latencyMs: forwardResult.latencyMs,
                        upstreamURL: base,
                        maskedCount: maskedCount,
                        outcome: .error,
                        errorMessage: errMsg,
                        requestPreview: originalPreview,
                        responsePreview: errMsg
                    ),
                    isSuccess: false
                )
                sendDict(client: client, status: httpStatusString(for: errCode), dict: [
                    "error": [
                        "message": errMsg,
                        "type": "magpie_upstream_error",
                        "upstream_status": errCode
                    ]
                ])
                return
            }
        }

        // No upstream configured: explicit local loopback mode
        let maskedMessages = (canonicalChat["messages"] as? [[String: Any]]) ?? []
        let lastMaskedContent = (maskedMessages.last?["content"] as? String) ?? ""
        let localText = "[Magpie 本地回环] 入口=\(inbound.rawValue) → 目标=\(targetProto.rawValue)，模型=\(model)。" +
            (maskedCount > 0 ? "已触发隐私脱敏 \(maskedCount) 处（发送到上游前将为占位符：\(lastMaskedContent)）。" : "当前未启用上游反代地址，返回本地诊断回显。")
        let canonicalLocal: [String: Any] = [
            "id": "chatcmpl-magpie-ios",
            "object": "chat.completion",
            "created": Int(Date().timeIntervalSince1970),
            "model": model,
            "choices": [[
                "index": 0,
                "message": [
                    "role": "assistant",
                    "content": localText
                ],
                "finish_reason": "stop"
            ]],
            "usage": [
                "prompt_tokens": max(1, lastMaskedContent.count / 4),
                "completion_tokens": 36,
                "total_tokens": max(1, lastMaskedContent.count / 4) + 36
            ]
        ]

        let formatted = ProtocolTranslator.responseFromCanonicalOpenAIChat(canonicalLocal, to: inbound, model: model)
        let elapsed = max(1, Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000))
        appendLog(
            GatewayLogEntry(
                id: UUID(),
                timestamp: Date(),
                method: "POST",
                path: path,
                inboundProtocol: inbound.rawValue,
                targetProtocol: targetProto.rawValue,
                model: model,
                statusCode: 200,
                latencyMs: elapsed,
                upstreamURL: "local://127.0.0.1:3425",
                maskedCount: maskedCount,
                outcome: .localLoopback,
                errorMessage: nil,
                requestPreview: originalPreview,
                responsePreview: localText
            ),
            isSuccess: true
        )
        sendDict(client: client, status: "200 OK", dict: formatted)
    }

    private func fetchUpstreamModelsSync(
        baseURL: String,
        apiKey: String,
        targetProto: MagpieProtocol
    ) -> (models: [MagpieModelItem]?, statusCode: Int, errorMessage: String?) {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/+$", with: "", options: .regularExpression)

        let endpoint: String
        switch targetProto {
        case .geminiV1Beta:
            let encodedKey = apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? apiKey
            endpoint = "\(trimmed)/v1beta/models?key=\(encodedKey)"
        default:
            endpoint = trimmed.hasSuffix("/v1") ? "\(trimmed)/models" : "\(trimmed)/v1/models"
        }

        guard let url = URL(string: endpoint) else {
            return (nil, 400, "无法构造模型列表地址：\(endpoint)")
        }

        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "GET"
        switch targetProto {
        case .openAIChat, .openAIResponses:
            if !apiKey.isEmpty { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        case .anthropicMessages:
            if !apiKey.isEmpty {
                req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            }
        case .geminiV1Beta:
            break
        }

        let sem = DispatchSemaphore(value: 0)
        var outModels: [MagpieModelItem]?
        var outCode = 0
        var outErr: String?

        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error {
                outErr = Self.describeNetworkError(error)
                sem.signal()
                return
            }
            guard let httpResp = response as? HTTPURLResponse else {
                outErr = "未收到有效 HTTP 响应"
                sem.signal()
                return
            }
            outCode = httpResp.statusCode
            guard (200..<300).contains(httpResp.statusCode) else {
                outErr = Self.extractHTTPErrorMessage(statusCode: httpResp.statusCode, data: data)
                sem.signal()
                return
            }
            guard let data = data,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                outErr = "上游返回内容不是有效 JSON"
                sem.signal()
                return
            }

            if let dataArr = json["data"] as? [[String: Any]] {
                outModels = dataArr.compactMap { row in
                    guard let id = row["id"] as? String, !id.isEmpty else { return nil }
                    let owner = (row["owned_by"] as? String) ?? "upstream"
                    return MagpieModelItem(id: id, ownedBy: owner, source: "upstream")
                }
            } else if let geminiArr = json["models"] as? [[String: Any]] {
                outModels = geminiArr.compactMap { row in
                    guard let rawName = row["name"] as? String, !rawName.isEmpty else { return nil }
                    let cleanName = rawName.replacingOccurrences(of: "models/", with: "")
                    return MagpieModelItem(id: cleanName, ownedBy: "google-gemini", source: "upstream")
                }
            } else {
                outErr = "上游返回结构中缺少 data 或 models 字段"
            }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 16)
        return (outModels, outCode, outErr)
    }

    private func forwardUpstream(
        baseURL: String,
        apiKey: String,
        targetProto: MagpieProtocol,
        model: String,
        payload: [String: Any]
    ) -> UpstreamForwardResult {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }

        let endpointPath: String
        switch targetProto {
        case .openAIChat:
            endpointPath = trimmed.hasSuffix("/v1") ? "\(trimmed)/chat/completions" : "\(trimmed)/v1/chat/completions"
        case .openAIResponses:
            endpointPath = trimmed.hasSuffix("/v1") ? "\(trimmed)/responses" : "\(trimmed)/v1/responses"
        case .anthropicMessages:
            endpointPath = trimmed.hasSuffix("/v1") ? "\(trimmed)/messages" : "\(trimmed)/v1/messages"
        case .geminiV1Beta:
            let encodedKey = apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? apiKey
            endpointPath = "\(trimmed)/v1beta/models/\(model):generateContent?key=\(encodedKey)"
        }

        guard let url = URL(string: endpointPath),
              let bodyData = try? JSONSerialization.data(withJSONObject: payload) else {
            return UpstreamForwardResult(statusCode: 400, json: nil, errorMessage: "无效的上游 URL 或请求载荷", latencyMs: 1)
        }

        var req = URLRequest(url: url, timeoutInterval: 60)
        req.httpMethod = "POST"
        req.httpBody = bodyData
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        switch targetProto {
        case .openAIChat, .openAIResponses:
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .anthropicMessages:
            req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .geminiV1Beta:
            break
        }

        let start = CFAbsoluteTimeGetCurrent()
        let sem = DispatchSemaphore(value: 0)
        var statusCode = 0
        var resultDict: [String: Any]?
        var errorMsg: String?

        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error {
                errorMsg = Self.describeNetworkError(error)
                sem.signal()
                return
            }
            guard let httpResp = response as? HTTPURLResponse else {
                errorMsg = "未收到有效 HTTP 响应"
                sem.signal()
                return
            }
            statusCode = httpResp.statusCode
            if (200..<300).contains(httpResp.statusCode) {
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    resultDict = json
                } else {
                    errorMsg = "上游返回 HTTP \(httpResp.statusCode)，但响应体不是合法 JSON"
                }
            } else {
                errorMsg = Self.extractHTTPErrorMessage(statusCode: httpResp.statusCode, data: data)
            }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 65)

        let elapsed = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000))
        if statusCode == 0 && errorMsg == nil {
            errorMsg = "请求上游超时（超过 65 秒无响应）"
        }
        return UpstreamForwardResult(statusCode: statusCode, json: resultDict, errorMessage: errorMsg, latencyMs: elapsed)
    }

    static func describeNetworkError(_ error: Error) -> String {
        let nsErr = error as NSError
        if nsErr.domain == NSURLErrorDomain {
            switch nsErr.code {
            case NSURLErrorTimedOut:
                return "连接超时：上游服务器未在规定时间内响应"
            case NSURLErrorCannotFindHost:
                return "域名解析失败（DNS 无法找到主机），请检查服务器地址拼写"
            case NSURLErrorCannotConnectToHost:
                return "无法建立 TCP 连接：请检查端口号或确认服务已启动"
            case NSURLErrorNetworkConnectionLost:
                return "网络连接意外中断"
            case NSURLErrorNotConnectedToInternet:
                return "设备当前无可用网络连接"
            case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate:
                return "TLS/HTTPS 证书校验失败，请检查证书或尝试核对协议"
            case NSURLErrorUnsupportedURL, NSURLErrorBadURL:
                return "服务器地址格式无效"
            default:
                return "网络请求错误（\(nsErr.code)）：\(nsErr.localizedDescription)"
            }
        }
        return error.localizedDescription
    }

    static func extractHTTPErrorMessage(statusCode: Int, data: Data?) -> String {
        var detail = ""
        if let data = data {
            if let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                if let errObj = json["error"] as? [String: Any], let msg = errObj["message"] as? String {
                    detail = msg
                } else if let msg = json["message"] as? String {
                    detail = msg
                } else if let msg = json["error"] as? String {
                    detail = msg
                }
            } else if let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                detail = String(raw.prefix(180))
            }
        }

        let hint: String
        switch statusCode {
        case 401: hint = "鉴权失败（API Key 无效或缺失）"
        case 403: hint = "拒绝访问（无权限或风控拦截）"
        case 404: hint = "接口路径不存在（请核对目标协议或 Base URL 是否重复包含 /v1）"
        case 429: hint = "触发上游限流或额度耗尽"
        case 500...599: hint = "上游服务端内部错误"
        default: hint = "上游返回异常状态"
        }

        if detail.isEmpty {
            return "HTTP \(statusCode)：\(hint)"
        }
        return "HTTP \(statusCode)（\(hint)）：\(detail)"
    }

    private func httpStatusString(for code: Int) -> String {
        switch code {
        case 200: return "200 OK"
        case 201: return "201 Created"
        case 204: return "204 No Content"
        case 400: return "400 Bad Request"
        case 401: return "401 Unauthorized"
        case 403: return "403 Forbidden"
        case 404: return "404 Not Found"
        case 429: return "429 Too Many Requests"
        case 500: return "500 Internal Server Error"
        case 502: return "502 Bad Gateway"
        case 503: return "503 Service Unavailable"
        case 504: return "504 Gateway Timeout"
        default: return "\(code) Status"
        }
    }

    private func extractLastUserPreview(from messages: [[String: Any]]) -> String {
        guard let last = messages.last else { return "(空消息)" }
        if let str = last["content"] as? String {
            return String(str.prefix(120))
        }
        return "(结构化消息)"
    }

    private func extractAssistantPreview(from canonical: [String: Any]) -> String {
        if let choices = canonical["choices"] as? [[String: Any]],
           let first = choices.first,
           let msg = first["message"] as? [String: Any],
           let text = msg["content"] as? String {
            return String(text.prefix(160))
        }
        return "(已返回结构化响应)"
    }

    private struct ParsedHTTPRequest {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    private func readHTTPRequest(client: Int32) -> ParsedHTTPRequest? {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        let separator = Data([0x0d, 0x0a, 0x0d, 0x0a])
        var headerRange: Range<Data.Index>?

        while headerRange == nil {
            let n = read(client, &chunk, chunk.count)
            if n <= 0 { break }
            buffer.append(contentsOf: chunk[0..<n])
            headerRange = buffer.range(of: separator)
            if buffer.count > 1_048_576 { break }
        }

        guard let hRange = headerRange else { return nil }
        let headerData = buffer.subdata(in: 0..<hRange.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if let idx = line.firstIndex(of: ":") {
                let k = line[..<idx].trimmingCharacters(in: .whitespaces).lowercased()
                let v = line[line.index(after: idx)...].trimmingCharacters(in: .whitespaces)
                headers[k] = v
            }
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        var body = buffer.subdata(in: hRange.upperBound..<buffer.count)
        while body.count < contentLength {
            let n = read(client, &chunk, chunk.count)
            if n <= 0 { break }
            body.append(contentsOf: chunk[0..<n])
        }
        if body.count > contentLength && contentLength >= 0 {
            body = body.subdata(in: 0..<contentLength)
        }

        return ParsedHTTPRequest(method: parts[0], path: parts[1], headers: headers, body: body)
    }

    private func sendDict(client: Int32, status: String, dict: [String: Any]) {
        let data = (try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted])) ?? Data("{}".utf8)
        sendJSON(client: client, status: status, bodyData: data)
    }

    private func sendJSON(client: Int32, status: String, bodyData: Data) {
        let header = "HTTP/1.1 \(status)\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(bodyData.count)\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type, Authorization, x-api-key, anthropic-version, x-magpie-upstream-url, x-magpie-upstream-protocol, x-magpie-upstream-key\r\nConnection: close\r\n\r\n"
        var full = Data(header.utf8)
        full.append(bodyData)
        full.withUnsafeBytes { rawBuf in
            guard let base = rawBuf.baseAddress else { return }
            var sent = 0
            while sent < full.count {
                let n = write(client, base.advanced(by: sent), full.count - sent)
                if n <= 0 { break }
                sent += n
            }
        }
    }
}

enum ProtocolTranslator {
    static func toCanonicalOpenAIChat(from proto: MagpieProtocol, payload: [String: Any], path: String) -> [String: Any] {
        switch proto {
        case .openAIChat:
            return payload

        case .openAIResponses:
            var messages: [[String: Any]] = []
            if let instructions = payload["instructions"] as? String, !instructions.isEmpty {
                messages.append(["role": "system", "content": instructions])
            }
            if let inputStr = payload["input"] as? String {
                messages.append(["role": "user", "content": inputStr])
            } else if let inputArr = payload["input"] as? [[String: Any]] {
                for item in inputArr {
                    let role = (item["role"] as? String) ?? "user"
                    let content = extractText(item["content"])
                    messages.append(["role": role, "content": content])
                }
            }
            return [
                "model": (payload["model"] as? String) ?? "gpt-4o",
                "messages": messages,
                "max_tokens": payload["max_output_tokens"] ?? 2048
            ]

        case .anthropicMessages:
            var messages: [[String: Any]] = []
            if let system = payload["system"] as? String, !system.isEmpty {
                messages.append(["role": "system", "content": system])
            }
            if let anthropicMsgs = payload["messages"] as? [[String: Any]] {
                for msg in anthropicMsgs {
                    let role = (msg["role"] as? String) ?? "user"
                    let content = extractText(msg["content"])
                    messages.append(["role": role, "content": content])
                }
            }
            var out: [String: Any] = [
                "model": (payload["model"] as? String) ?? "claude-sonnet-4-5",
                "messages": messages
            ]
            if let maxTokens = payload["max_tokens"] { out["max_tokens"] = maxTokens }
            if let temp = payload["temperature"] { out["temperature"] = temp }
            return out

        case .geminiV1Beta:
            var messages: [[String: Any]] = []
            if let sysInst = payload["systemInstruction"] as? [String: Any] {
                let sysText = extractGeminiParts(sysInst["parts"])
                if !sysText.isEmpty {
                    messages.append(["role": "system", "content": sysText])
                }
            }
            if let contents = payload["contents"] as? [[String: Any]] {
                for c in contents {
                    let rawRole = (c["role"] as? String) ?? "user"
                    let role = (rawRole == "model") ? "assistant" : rawRole
                    let text = extractGeminiParts(c["parts"])
                    messages.append(["role": role, "content": text])
                }
            }
            let modelFromPath = path
                .replacingOccurrences(of: "/v1beta/models/", with: "")
                .components(separatedBy: ":").first ?? "gemini-2.5-pro"
            return [
                "model": modelFromPath.isEmpty ? "gemini-2.5-pro" : modelFromPath,
                "messages": messages
            ]
        }
    }

    static func fromCanonicalOpenAIChat(_ chat: [String: Any], to proto: MagpieProtocol) -> [String: Any] {
        let messages = (chat["messages"] as? [[String: Any]]) ?? []
        let model = (chat["model"] as? String) ?? "claude-sonnet-4-5"

        switch proto {
        case .openAIChat:
            return chat

        case .openAIResponses:
            let inputItems: [[String: Any]] = messages.map { m in
                ["role": m["role"] ?? "user", "content": extractText(m["content"])]
            }
            return [
                "model": model,
                "input": inputItems,
                "max_output_tokens": chat["max_tokens"] ?? 2048
            ]

        case .anthropicMessages:
            var systemPrompts: [String] = []
            var converted: [[String: Any]] = []
            for m in messages {
                let role = (m["role"] as? String) ?? "user"
                let text = extractText(m["content"])
                if role == "system" {
                    systemPrompts.append(text)
                } else {
                    converted.append([
                        "role": role == "assistant" ? "assistant" : "user",
                        "content": [["type": "text", "text": text]]
                    ])
                }
            }
            var out: [String: Any] = [
                "model": model,
                "max_tokens": chat["max_tokens"] ?? 4096,
                "messages": converted
            ]
            if !systemPrompts.isEmpty {
                out["system"] = systemPrompts.joined(separator: "\n\n")
            }
            return out

        case .geminiV1Beta:
            var systemParts: [[String: Any]] = []
            var contents: [[String: Any]] = []
            for m in messages {
                let role = (m["role"] as? String) ?? "user"
                let text = extractText(m["content"])
                if role == "system" {
                    systemParts.append(["text": text])
                } else {
                    contents.append([
                        "role": role == "assistant" ? "model" : "user",
                        "parts": [["text": text]]
                    ])
                }
            }
            var out: [String: Any] = ["contents": contents]
            if !systemParts.isEmpty {
                out["systemInstruction"] = ["parts": systemParts]
            }
            return out
        }
    }

    static func responseToCanonicalOpenAIChat(from proto: MagpieProtocol, payload: [String: Any], model: String) -> [String: Any] {
        switch proto {
        case .openAIChat:
            return payload

        case .openAIResponses:
            var text = (payload["output_text"] as? String) ?? ""
            if text.isEmpty, let outputs = payload["output"] as? [[String: Any]] {
                for item in outputs {
                    if let contentArr = item["content"] as? [[String: Any]] {
                        for block in contentArr {
                            if let t = block["text"] as? String { text += t }
                        }
                    }
                }
            }
            return makeCanonicalResponse(text: text, model: model)

        case .anthropicMessages:
            let text = extractText(payload["content"])
            return makeCanonicalResponse(text: text, model: (payload["model"] as? String) ?? model)

        case .geminiV1Beta:
            var text = ""
            if let candidates = payload["candidates"] as? [[String: Any]],
               let first = candidates.first,
               let content = first["content"] as? [String: Any] {
                text = extractGeminiParts(content["parts"])
            }
            return makeCanonicalResponse(text: text, model: model)
        }
    }

    static func responseFromCanonicalOpenAIChat(_ canonical: [String: Any], to proto: MagpieProtocol, model: String) -> [String: Any] {
        let text: String
        if let choices = canonical["choices"] as? [[String: Any]],
           let first = choices.first,
           let msg = first["message"] as? [String: Any] {
            text = extractText(msg["content"])
        } else {
            text = ""
        }

        switch proto {
        case .openAIChat:
            return canonical

        case .openAIResponses:
            return [
                "id": "resp_magpie_ios",
                "object": "response",
                "model": model,
                "output_text": text,
                "output": [[
                    "type": "message",
                    "role": "assistant",
                    "content": [["type": "output_text", "text": text]]
                ]]
            ]

        case .anthropicMessages:
            return [
                "id": "msg_magpie_ios",
                "type": "message",
                "role": "assistant",
                "model": model,
                "content": [["type": "text", "text": text]],
                "stop_reason": "end_turn",
                "usage": ["input_tokens": 16, "output_tokens": 32]
            ]

        case .geminiV1Beta:
            return [
                "candidates": [[
                    "content": [
                        "role": "model",
                        "parts": [["text": text]]
                    ],
                    "finishReason": "STOP"
                ]]
            ]
        }
    }

    private static func makeCanonicalResponse(text: String, model: String) -> [String: Any] {
        return [
            "id": "chatcmpl-magpie-ios",
            "object": "chat.completion",
            "created": Int(Date().timeIntervalSince1970),
            "model": model,
            "choices": [[
                "index": 0,
                "message": ["role": "assistant", "content": text],
                "finish_reason": "stop"
            ]]
        ]
    }

    private static func extractText(_ value: Any?) -> String {
        if let str = value as? String { return str }
        if let arr = value as? [[String: Any]] {
            return arr.compactMap { $0["text"] as? String }.joined()
        }
        return ""
    }

    private static func extractGeminiParts(_ value: Any?) -> String {
        guard let parts = value as? [[String: Any]] else { return "" }
        return parts.compactMap { $0["text"] as? String }.joined()
    }
}
