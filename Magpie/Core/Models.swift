import Foundation

enum MagpieProtocol: String, CaseIterable, Codable, Identifiable {
    case openAIChat = "openai-chat"
    case openAIResponses = "openai-responses"
    case anthropicMessages = "anthropic-messages"
    case geminiV1Beta = "gemini-v1beta"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAIChat: return "OpenAI Chat"
        case .openAIResponses: return "OpenAI Responses"
        case .anthropicMessages: return "Anthropic"
        case .geminiV1Beta: return "Gemini"
        }
    }

    var shortBadge: String {
        switch self {
        case .openAIChat: return "Chat"
        case .openAIResponses: return "Responses"
        case .anthropicMessages: return "Claude"
        case .geminiV1Beta: return "Gemini"
        }
    }

    var routePath: String {
        switch self {
        case .openAIChat: return "/v1/chat/completions"
        case .openAIResponses: return "/v1/responses"
        case .anthropicMessages: return "/v1/messages"
        case .geminiV1Beta: return "/v1beta/models/..."
        }
    }

    var suggestedDefaultModel: String {
        switch self {
        case .openAIChat: return "gpt-4o"
        case .openAIResponses: return "gpt-4.1"
        case .anthropicMessages: return "claude-sonnet-4-5"
        case .geminiV1Beta: return "gemini-2.5-pro"
        }
    }

    func modelsEndpoint(baseURL: String, apiKey: String) -> String {
        let base = Self.trimTrailingSlashes(baseURL)
        switch self {
        case .geminiV1Beta:
            let encoded = apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? apiKey
            return "\(base)/v1beta/models?key=\(encoded)"
        default:
            return base.hasSuffix("/v1") ? "\(base)/models" : "\(base)/v1/models"
        }
    }

    func chatEndpoint(baseURL: String, model: String, apiKey: String) -> String {
        let base = Self.trimTrailingSlashes(baseURL)
        switch self {
        case .openAIChat:
            return base.hasSuffix("/v1") ? "\(base)/chat/completions" : "\(base)/v1/chat/completions"
        case .openAIResponses:
            return base.hasSuffix("/v1") ? "\(base)/responses" : "\(base)/v1/responses"
        case .anthropicMessages:
            return base.hasSuffix("/v1") ? "\(base)/messages" : "\(base)/v1/messages"
        case .geminiV1Beta:
            let encoded = apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? apiKey
            return "\(base)/v1beta/models/\(model):generateContent?key=\(encoded)"
        }
    }

    func applyAuthHeaders(to request: inout URLRequest, apiKey: String) {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else { return }
        switch self {
        case .openAIChat, .openAIResponses:
            request.setValue("Bearer \(cleanKey)", forHTTPHeaderField: "Authorization")
        case .anthropicMessages:
            request.setValue(cleanKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .geminiV1Beta:
            break
        }
    }

    private static func trimTrailingSlashes(_ string: String) -> String {
        var result = string.trimmingCharacters(in: .whitespacesAndNewlines)
        while result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }
}

struct MagpieUpstreamConfig: Codable, Equatable {
    var baseURL: String
    var apiKey: String
    var targetProtocol: String
    var defaultModel: String
    var profileName: String?
}

struct ProxyProfile: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var baseURL: String
    var apiKey: String
    var targetProtocol: MagpieProtocol
    var defaultModel: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var maskedKeyPreview: String {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "无密钥" }
        if trimmed.count <= 8 {
            return String(repeating: "•", count: trimmed.count)
        }
        return "\(trimmed.prefix(4))···\(trimmed.suffix(4))"
    }
}

enum URLValidationResult: Equatable {
    case valid(normalized: String)
    case invalid(reason: String)

    var normalizedURL: String? {
        if case .valid(let normalized) = self { return normalized }
        return nil
    }

    var errorReason: String? {
        if case .invalid(let reason) = self { return reason }
        return nil
    }
}

enum URLValidator {
    static func validateAndNormalize(_ rawInput: String) -> URLValidationResult {
        var trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .invalid(reason: "请输入服务器地址（以 http:// 或 https:// 开头）")
        }
        if trimmed.contains(where: { $0.isWhitespace }) {
            return .invalid(reason: "服务器地址不能包含空格或换行")
        }
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }

        guard let components = URLComponents(string: trimmed) else {
            return .invalid(reason: "地址格式无法解析")
        }
        guard let scheme = components.scheme?.lowercased(), !scheme.isEmpty else {
            return .invalid(reason: "缺少协议头（http:// 或 https://）")
        }
        guard scheme == "http" || scheme == "https" else {
            return .invalid(reason: "仅支持 http:// 或 https:// 协议")
        }
        guard let host = components.host, !host.isEmpty else {
            return .invalid(reason: "缺少有效主机名或 IP")
        }
        if host.contains("..") || host.hasPrefix(".") || host.hasSuffix(".") {
            return .invalid(reason: "主机域名格式不合法（\(host)）")
        }
        if let port = components.port, !(1...65535).contains(port) {
            return .invalid(reason: "端口号需在 1–65535 之间")
        }

        var normalized = components
        normalized.scheme = scheme
        normalized.host = host.lowercased()
        if normalized.path == "/" {
            normalized.path = ""
        } else {
            while normalized.path.hasSuffix("/") {
                normalized.path.removeLast()
            }
        }

        guard let finalString = normalized.string,
              let finalURL = URL(string: finalString),
              finalURL.host != nil else {
            return .invalid(reason: "无法规范化服务器地址")
        }
        return .valid(normalized: finalString)
    }
}

enum ConnectionStatusKind: Equatable {
    case untested
    case checking
    case connected
    case localOnly
    case failed
}

struct ConnectionHealth: Equatable {
    var kind: ConnectionStatusKind
    var latencyMs: Int?
    var statusCode: Int?
    var message: String
    var checkedAt: Date?

    static let untested = ConnectionHealth(
        kind: .untested,
        latencyMs: nil,
        statusCode: nil,
        message: "尚未检测连通状态",
        checkedAt: nil
    )

    static let checking = ConnectionHealth(
        kind: .checking,
        latencyMs: nil,
        statusCode: nil,
        message: "正在握手探测…",
        checkedAt: nil
    )
}

struct MagpieModelItem: Identifiable, Hashable, Codable {
    var id: String
    var ownedBy: String
    var source: String
}

struct PrivacyMaskSettings: Codable, Equatable {
    var enabled: Bool = true
    var maskAPIKeys: Bool = true
    var maskEmails: Bool = true
    var maskPhones: Bool = true
    var customKeywordsText: String = ""

    var customKeywords: [String] {
        customKeywordsText
            .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == "，" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

enum GatewayLogOutcome: String, Codable {
    case forwarded = "upstream"
    case localLoopback = "local"
    case error = "error"
}

struct GatewayLogEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var timestamp: Date
    var method: String
    var path: String
    var inboundProtocol: String
    var targetProtocol: String
    var model: String
    var statusCode: Int
    var latencyMs: Int
    var upstreamURL: String
    var maskedCount: Int
    var outcome: GatewayLogOutcome
    var errorMessage: String?
    var requestPreview: String
    var responsePreview: String
}

struct GatewayStatusSnapshot: Equatable {
    var daemonOnline: Bool = false
    var requestsHandled: Int = 0
    var successCount: Int = 0
    var errorCount: Int = 0
    var maskedItemsCount: Int = 0
    var listenAddress: String = "http://127.0.0.1:3425"
    var lastError: String?
}
