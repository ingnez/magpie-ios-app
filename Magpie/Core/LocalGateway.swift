import Foundation
import Darwin

extension Notification.Name {
    static let magpieGatewayDidUpdate = Notification.Name("ai.usemagpie.ios.gatewayDidUpdate")
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
            sendDict(client: client, status: "200 OK", dict: [
                "status": "ok",
                "app": "Magpie iOS Reverse Proxy Gateway",
                "version": "2.1.0",
                "listen": "http://127.0.0.1:3425",
                "native_daemon": true,
                "requests_handled": count,
                "success_count": sCount,
                "error_count": eCount,
                "masked_items_count": mCount,
                "privacy_masking_enabled": currentPrivacy.enabled,
                "active_profile": savedUpstream?.profileName ?? "本地回环模式",
                "active_base_url": savedUpstream?.baseURL ?? "",
                "protocols": MagpieProtocol.allCases.map(\.rawValue)
            ])
            return
        }

        if rawRequest.method == "GET" && path == "/api/config" {
            sendDict(client: client, status: "200 OK", dict: [
                "configured": savedUpstream != nil,
                "baseURL": savedUpstream?.baseURL ?? "",
                "targetProtocol": savedUpstream?.targetProtocol ?? MagpieProtocol.openAIChat.rawValue,
                "defaultModel": savedUpstream?.defaultModel ?? "",
                "profileName": savedUpstream?.profileName ?? "",
                "privacyMaskingEnabled": currentPrivacy.enabled
            ])
            return
        }

        if rawRequest.method == "POST" && path == "/api/config" {
            handleConfigUpdate(client: client, path: path, body: rawRequest.body, startTime: startTime)
            return
        }

        if rawRequest.method == "GET" && path == "/api/logs" {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(recentLogs()) {
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

        if rawRequest.method == "POST", let inbound = matchInboundProtocol(path: path) {
            handleTranslationRoute(
                client: client,
                inbound: inbound,
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

    private func matchInboundProtocol(path: String) -> MagpieProtocol? {
        switch path {
        case "/v1/chat/completions": return .openAIChat
        case "/v1/responses": return .openAIResponses
        case "/v1/messages": return .anthropicMessages
        default:
            return path.hasPrefix("/v1beta/models") ? .geminiV1Beta : nil
        }
    }

    private func handleConfigUpdate(client: Int32, path: String, body: Data, startTime: CFAbsoluteTime) {
        guard var cfg = try? JSONDecoder().decode(MagpieUpstreamConfig.self, from: body) else {
            sendDict(client: client, status: "400 Bad Request", dict: ["ok": false, "error": "无效的 JSON 配置载荷"])
            return
        }
        if !cfg.baseURL.isEmpty {
            switch URLValidator.validateAndNormalize(cfg.baseURL) {
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
    }

    private func handleModelsRoute(
        client: Int32,
        path: String,
        savedUpstream: MagpieUpstreamConfig?,
        startTime: CFAbsoluteTime
    ) {
        if let upstream = savedUpstream, !upstream.baseURL.isEmpty {
            let proto = MagpieProtocol(rawValue: upstream.targetProtocol) ?? .openAIChat
            let res = UpstreamClient.fetchModelsSync(baseURL: upstream.baseURL, apiKey: upstream.apiKey, targetProto: proto)
            let elapsed = max(1, Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000))
            if let models = res.models, !models.isEmpty {
                let dataArray: [[String: Any]] = models.map { item in
                    ["id": item.id, "object": "model", "owned_by": item.ownedBy]
                }
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
            }

            let errMsg = res.errorMessage ?? "上游模型列表为空"
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
        let model = (rawCanonicalChat["model"] as? String) ?? savedUpstream?.defaultModel ?? "magpie-local-gateway"
        let userMessages = (rawCanonicalChat["messages"] as? [[String: Any]]) ?? []
        let originalPreview = extractLastUserPreview(from: userMessages)

        let maskedTuple = PrivacyMasker.maskJSONObject(rawCanonicalChat, settings: privacy)
        let canonicalChat = (maskedTuple.masked as? [String: Any]) ?? rawCanonicalChat
        let replacements = maskedTuple.replacements
        let maskedCount = maskedTuple.count

        let upstreamURL = headers["x-magpie-upstream-url"] ?? savedUpstream?.baseURL
        let upstreamProtoRaw = headers["x-magpie-upstream-protocol"] ?? savedUpstream?.targetProtocol ?? inbound.rawValue
        let targetProto = MagpieProtocol(rawValue: upstreamProtoRaw) ?? inbound
        let upstreamKey = headers["x-magpie-upstream-key"] ?? savedUpstream?.apiKey

        if let base = upstreamURL, !base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let key = (upstreamKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if key.isEmpty {
                let elapsed = max(1, Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000))
                let errMsg = "已指定上游地址（\(base)），但未配置 API Key"
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
                    "error": ["message": errMsg, "type": "magpie_missing_api_key"]
                ])
                return
            }

            var outboundPayload = ProtocolTranslator.fromCanonicalOpenAIChat(canonicalChat, to: targetProto)
            outboundPayload["stream"] = false

            let forwardResult = UpstreamClient.forwardSync(
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
            }

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
                "error": ["message": errMsg, "type": "magpie_upstream_error", "upstream_status": errCode]
            ])
            return
        }

        let maskedMessages = (canonicalChat["messages"] as? [[String: Any]]) ?? []
        let lastMaskedContent = (maskedMessages.last?["content"] as? String) ?? ""
        let localText = "[Magpie 本地回环] \(inbound.rawValue) → \(targetProto.rawValue) · \(model)。" +
            (maskedCount > 0 ? "已触发脱敏 \(maskedCount) 处（\(lastMaskedContent)）。" : "未启用上游配置，返回本地回环诊断。")
        let canonicalLocal = ProtocolTranslator.makeCanonicalResponse(text: localText, model: model)
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
        guard let last = messages.last, let str = last["content"] as? String else { return "(结构化消息)" }
        return String(str.prefix(120))
    }

    private func extractAssistantPreview(from canonical: [String: Any]) -> String {
        if let choices = canonical["choices"] as? [[String: Any]],
           let first = choices.first,
           let msg = first["message"] as? [String: Any],
           let text = msg["content"] as? String {
            return String(text.prefix(160))
        }
        return "(结构化响应)"
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

        guard let hRange = headerRange,
              let headerString = String(data: buffer.subdata(in: 0..<hRange.lowerBound), encoding: .utf8) else {
            return nil
        }

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
