import Foundation

struct UpstreamForwardResult {
    let statusCode: Int
    let json: [String: Any]?
    let errorMessage: String?
    let latencyMs: Int
}

enum UpstreamClient {
    static func parseModelsPayload(data: Data, source: String) -> [MagpieModelItem] {
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

    static func probe(
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

        let endpoint = targetProtocol.modelsEndpoint(baseURL: baseURL, apiKey: apiKey)
        guard let url = URL(string: endpoint) else {
            return ConnectionHealth(
                kind: .failed,
                latencyMs: nil,
                statusCode: nil,
                message: "无法构造探测地址：\(endpoint)",
                checkedAt: Date()
            )
        }

        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "GET"
        targetProtocol.applyAuthHeaders(to: &req, apiKey: apiKey)

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
                let count = parseModelsPayload(data: data, source: "probe").count
                let msg = count > 0
                    ? "连通正常 · 探测到 \(count) 个模型"
                    : "握手成功（HTTP \(httpResp.statusCode)）"
                return ConnectionHealth(
                    kind: .connected,
                    latencyMs: latency,
                    statusCode: httpResp.statusCode,
                    message: msg,
                    checkedAt: Date()
                )
            }

            return ConnectionHealth(
                kind: .failed,
                latencyMs: latency,
                statusCode: httpResp.statusCode,
                message: extractHTTPErrorMessage(statusCode: httpResp.statusCode, data: data),
                checkedAt: Date()
            )
        } catch {
            let latency = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000))
            return ConnectionHealth(
                kind: .failed,
                latencyMs: latency,
                statusCode: nil,
                message: describeNetworkError(error),
                checkedAt: Date()
            )
        }
    }

    static func fetchModelsSync(
        baseURL: String,
        apiKey: String,
        targetProto: MagpieProtocol
    ) -> (models: [MagpieModelItem]?, statusCode: Int, errorMessage: String?) {
        let endpoint = targetProto.modelsEndpoint(baseURL: baseURL, apiKey: apiKey)
        guard let url = URL(string: endpoint) else {
            return (nil, 400, "无法构造模型列表地址：\(endpoint)")
        }

        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "GET"
        targetProto.applyAuthHeaders(to: &req, apiKey: apiKey)

        let sem = DispatchSemaphore(value: 0)
        var outModels: [MagpieModelItem]?
        var outCode = 0
        var outErr: String?

        URLSession.shared.dataTask(with: req) { data, response, error in
            defer { sem.signal() }
            if let error = error {
                outErr = describeNetworkError(error)
                return
            }
            guard let httpResp = response as? HTTPURLResponse else {
                outErr = "未收到有效 HTTP 响应"
                return
            }
            outCode = httpResp.statusCode
            guard (200..<300).contains(httpResp.statusCode) else {
                outErr = extractHTTPErrorMessage(statusCode: httpResp.statusCode, data: data)
                return
            }
            guard let data = data else {
                outErr = "上游返回空内容"
                return
            }
            let parsed = parseModelsPayload(data: data, source: "upstream")
            if parsed.isEmpty {
                outErr = "上游返回结构中缺少可用模型字段"
            } else {
                outModels = parsed
            }
        }.resume()

        _ = sem.wait(timeout: .now() + 16)
        return (outModels, outCode, outErr)
    }

    static func forwardSync(
        baseURL: String,
        apiKey: String,
        targetProto: MagpieProtocol,
        model: String,
        payload: [String: Any]
    ) -> UpstreamForwardResult {
        let endpoint = targetProto.chatEndpoint(baseURL: baseURL, model: model, apiKey: apiKey)
        guard let url = URL(string: endpoint),
              let bodyData = try? JSONSerialization.data(withJSONObject: payload) else {
            return UpstreamForwardResult(statusCode: 400, json: nil, errorMessage: "无效的上游地址或请求体", latencyMs: 1)
        }

        var req = URLRequest(url: url, timeoutInterval: 60)
        req.httpMethod = "POST"
        req.httpBody = bodyData
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        targetProto.applyAuthHeaders(to: &req, apiKey: apiKey)

        let start = CFAbsoluteTimeGetCurrent()
        let sem = DispatchSemaphore(value: 0)
        var statusCode = 0
        var resultDict: [String: Any]?
        var errorMsg: String?

        URLSession.shared.dataTask(with: req) { data, response, error in
            defer { sem.signal() }
            if let error = error {
                errorMsg = describeNetworkError(error)
                return
            }
            guard let httpResp = response as? HTTPURLResponse else {
                errorMsg = "未收到有效 HTTP 响应"
                return
            }
            statusCode = httpResp.statusCode
            if (200..<300).contains(httpResp.statusCode) {
                if let data = data,
                   let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                    resultDict = json
                } else {
                    errorMsg = "上游返回 HTTP \(httpResp.statusCode)，但响应体不是合法 JSON"
                }
            } else {
                errorMsg = extractHTTPErrorMessage(statusCode: httpResp.statusCode, data: data)
            }
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
        guard nsErr.domain == NSURLErrorDomain else {
            return error.localizedDescription
        }
        switch nsErr.code {
        case NSURLErrorTimedOut:
            return "连接超时：上游服务器未在规定时间内响应"
        case NSURLErrorCannotFindHost:
            return "域名解析失败，请检查服务器地址"
        case NSURLErrorCannotConnectToHost:
            return "无法建立 TCP 连接，请检查端口或服务状态"
        case NSURLErrorNetworkConnectionLost:
            return "网络连接中断"
        case NSURLErrorNotConnectedToInternet:
            return "当前无可用网络连接"
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate:
            return "TLS 证书校验失败"
        case NSURLErrorUnsupportedURL, NSURLErrorBadURL:
            return "服务器地址格式无效"
        default:
            return "网络错误（\(nsErr.code)）：\(nsErr.localizedDescription)"
        }
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
        case 404: hint = "路径不存在（请核对协议或 Base URL）"
        case 429: hint = "触发上游限流或额度耗尽"
        case 500...599: hint = "上游服务端内部错误"
        default: hint = "上游返回异常状态"
        }

        return detail.isEmpty ? "HTTP \(statusCode)：\(hint)" : "HTTP \(statusCode)（\(hint)）：\(detail)"
    }
}
