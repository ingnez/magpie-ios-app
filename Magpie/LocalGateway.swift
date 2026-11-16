import Foundation
import Darwin

enum MagpieProtocol: String {
    case openAIChat = "openai-chat"
    case openAIResponses = "openai-responses"
    case anthropicMessages = "anthropic-messages"
    case geminiV1Beta = "gemini-v1beta"
}

struct MagpieUpstreamConfig: Codable {
    var baseURL: String
    var apiKey: String
    var targetProtocol: String
    var defaultModel: String
}

final class MagpieLocalGateway {
    static let shared = MagpieLocalGateway()

    private let lock = NSLock()
    private var isRunning = false
    private var requestCount = 0
    private var upstreamConfig: MagpieUpstreamConfig?

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

    private func runServerLoop() {
        signal(SIGPIPE, SIG_IGN)
        let srv = socket(AF_INET, SOCK_STREAM, 0)
        guard srv >= 0 else { return }

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
            close(srv)
            return
        }

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
        guard let rawRequest = readHTTPRequest(client: client) else { return }

        if rawRequest.method == "OPTIONS" {
            sendJSON(client: client, status: "204 No Content", bodyData: Data())
            return
        }

        lock.lock()
        requestCount += 1
        let count = requestCount
        let savedUpstream = upstreamConfig
        lock.unlock()

        let path = rawRequest.path.components(separatedBy: "?").first ?? rawRequest.path

        if rawRequest.method == "GET" && (path == "/health" || path == "/api/status") {
            let statusPayload: [String: Any] = [
                "status": "ok",
                "app": "Magpie iOS Reverse Proxy Gateway",
                "version": "1.2.0",
                "listen": "http://127.0.0.1:3425",
                "native_daemon": true,
                "requests_handled": count,
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

        if rawRequest.method == "GET" && path == "/v1/models" {
            let models: [[String: Any]] = [
                ["id": "claude-sonnet-4-5", "object": "model", "owned_by": "magpie-anthropic"],
                ["id": "claude-opus-4-5", "object": "model", "owned_by": "magpie-anthropic"],
                ["id": "gemini-2.5-pro", "object": "model", "owned_by": "magpie-gemini"],
                ["id": "gemini-2.5-flash", "object": "model", "owned_by": "magpie-gemini"],
                ["id": "deepseek-r1", "object": "model", "owned_by": "magpie-deepseek"],
                ["id": "gpt-4o", "object": "model", "owned_by": "magpie-openai"],
                ["id": "group/opus-anywhere", "object": "model", "owned_by": "magpie-router"],
                ["id": "group/sillytavern-rp", "object": "model", "owned_by": "magpie-router"]
            ]
            sendDict(client: client, status: "200 OK", dict: ["object": "list", "data": models])
            return
        }

        if rawRequest.method == "POST" && path == "/api/config" {
            if let cfg = try? JSONDecoder().decode(MagpieUpstreamConfig.self, from: rawRequest.body) {
                lock.lock()
                upstreamConfig = cfg
                lock.unlock()
                sendDict(client: client, status: "200 OK", dict: ["ok": true, "targetProtocol": cfg.targetProtocol])
            } else {
                sendDict(client: client, status: "400 Bad Request", dict: ["error": "Invalid config JSON"])
            }
            return
        }

        if rawRequest.method == "POST" && path == "/v1/chat/completions" {
            handleTranslationRoute(
                client: client,
                inbound: .openAIChat,
                path: path,
                headers: rawRequest.headers,
                body: rawRequest.body,
                savedUpstream: savedUpstream
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
                savedUpstream: savedUpstream
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
                savedUpstream: savedUpstream
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
                savedUpstream: savedUpstream
            )
            return
        }

        sendDict(client: client, status: "404 Not Found", dict: ["error": "Unknown route", "path": path])
    }

    private func handleTranslationRoute(
        client: Int32,
        inbound: MagpieProtocol,
        path: String,
        headers: [String: String],
        body: Data,
        savedUpstream: MagpieUpstreamConfig?
    ) {
        guard let inboundJSON = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else {
            sendDict(client: client, status: "400 Bad Request", dict: ["error": "Request body must be valid JSON"])
            return
        }

        let canonicalChat = ProtocolTranslator.toCanonicalOpenAIChat(from: inbound, payload: inboundJSON, path: path)
        let model = (canonicalChat["model"] as? String) ?? "magpie-local-gateway"

        let upstreamURL = headers["x-magpie-upstream-url"] ?? savedUpstream?.baseURL
        let upstreamProtoRaw = headers["x-magpie-upstream-protocol"] ?? savedUpstream?.targetProtocol ?? inbound.rawValue
        let targetProto = MagpieProtocol(rawValue: upstreamProtoRaw) ?? inbound
        let upstreamKey = headers["x-magpie-upstream-key"] ?? savedUpstream?.apiKey

        if let base = upstreamURL, !base.isEmpty, let key = upstreamKey, !key.isEmpty {
            let outboundPayload = ProtocolTranslator.fromCanonicalOpenAIChat(canonicalChat, to: targetProto)
            if let forwarded = forwardUpstream(baseURL: base, apiKey: key, targetProto: targetProto, model: model, payload: outboundPayload) {
                let canonicalResp = ProtocolTranslator.responseToCanonicalOpenAIChat(from: targetProto, payload: forwarded, model: model)
                let clientResp = ProtocolTranslator.responseFromCanonicalOpenAIChat(canonicalResp, to: inbound, model: model)
                sendDict(client: client, status: "200 OK", dict: clientResp)
                return
            }
        }

        let userMessages = (canonicalChat["messages"] as? [[String: Any]]) ?? []
        let lastContent = (userMessages.last?["content"] as? String) ?? ""
        let localText = "[Magpie iOS 127.0.0.1:3425 已连通] 入口协议=\(inbound.rawValue), 目标协议=\(targetProto.rawValue), 模型=\(model)。已验证请求结构（消息数=\(userMessages.count), 末句长度=\(lastContent.count)）。配置上游 URL/Key 后将通过 URLSession 实时转发。"
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
                "prompt_tokens": max(1, lastContent.count / 4),
                "completion_tokens": 32,
                "total_tokens": max(1, lastContent.count / 4) + 32
            ]
        ]

        let formatted = ProtocolTranslator.responseFromCanonicalOpenAIChat(canonicalLocal, to: inbound, model: model)
        sendDict(client: client, status: "200 OK", dict: formatted)
    }

    private func forwardUpstream(
        baseURL: String,
        apiKey: String,
        targetProto: MagpieProtocol,
        model: String,
        payload: [String: Any]
    ) -> [String: Any]? {
        let trimmed = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let endpointPath: String
        switch targetProto {
        case .openAIChat:
            endpointPath = "\(trimmed)/v1/chat/completions"
        case .openAIResponses:
            endpointPath = "\(trimmed)/v1/responses"
        case .anthropicMessages:
            endpointPath = "\(trimmed)/v1/messages"
        case .geminiV1Beta:
            endpointPath = "\(trimmed)/v1beta/models/\(model):generateContent?key=\(apiKey)"
        }

        guard let url = URL(string: endpointPath),
              let bodyData = try? JSONSerialization.data(withJSONObject: payload) else {
            return nil
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

        let sem = DispatchSemaphore(value: 0)
        var resultDict: [String: Any]?
        URLSession.shared.dataTask(with: req) { data, _, _ in
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                resultDict = json
            }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 65)
        return resultDict
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
