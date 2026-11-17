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
        case .geminiV1Beta: return "Gemini v1beta"
        }
    }

    var shortBadge: String {
        switch self {
        case .openAIChat: return "OAI Chat"
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
}

struct MagpieUpstreamConfig: Codable, Equatable {
    var baseURL: String
    var apiKey: String
    var targetProtocol: String
    var defaultModel: String
    var profileName: String?
}

struct ProxyProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var baseURL: String
    var apiKey: String
    var targetProtocol: MagpieProtocol
    var defaultModel: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        baseURL: String,
        apiKey: String,
        targetProtocol: MagpieProtocol,
        defaultModel: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.targetProtocol = targetProtocol
        self.defaultModel = defaultModel
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var maskedKeyPreview: String {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "未设置密钥" }
        if trimmed.count <= 8 {
            return String(repeating: "•", count: trimmed.count)
        }
        let prefix = String(trimmed.prefix(5))
        let suffix = String(trimmed.suffix(4))
        return "\(prefix)••••\(suffix)"
    }
}

enum URLValidationResult: Equatable {
    case valid(normalized: String)
    case invalid(reason: String)

    var isValid: Bool {
        if case .valid = self { return true }
        return false
    }

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
            return .invalid(reason: "请输入反代服务器地址（需以 http:// 或 https:// 开头）")
        }

        if trimmed.contains(" ") || trimmed.contains("\t") || trimmed.contains("\n") {
            return .invalid(reason: "服务器地址不能包含空格或换行符")
        }

        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }

        guard let components = URLComponents(string: trimmed) else {
            return .invalid(reason: "URL 格式无法解析，请检查特殊字符或端口格式")
        }

        guard let scheme = components.scheme?.lowercased(), !scheme.isEmpty else {
            return .invalid(reason: "缺少协议头，必须以 http:// 或 https:// 开头")
        }

        guard scheme == "http" || scheme == "https" else {
            return .invalid(reason: "不支持的协议「\(scheme)://」，仅支持 http:// 或 https://")
        }

        guard let host = components.host, !host.isEmpty else {
            return .invalid(reason: "缺少有效的主机域名或 IP（例如 api.example.com 或 127.0.0.1）")
        }

        if host.contains("..") || host.hasPrefix(".") || host.hasSuffix(".") {
            return .invalid(reason: "主机域名格式不合法（\(host)）")
        }

        if let port = components.port, (port < 1 || port > 65535) {
            return .invalid(reason: "端口号必须在 1–65535 之间")
        }

        var normalizedComponents = components
        normalizedComponents.scheme = scheme
        normalizedComponents.host = host.lowercased()
        if normalizedComponents.path == "/" {
            normalizedComponents.path = ""
        } else {
            while normalizedComponents.path.hasSuffix("/") {
                normalizedComponents.path.removeLast()
            }
        }

        guard let finalString = normalizedComponents.string,
              let finalURL = URL(string: finalString),
              finalURL.host != nil else {
            return .invalid(reason: "无法规范化服务器地址，请检查路径与端口")
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
        message: "尚未执行连通性检测",
        checkedAt: nil
    )

    static let checking = ConnectionHealth(
        kind: .checking,
        latencyMs: nil,
        statusCode: nil,
        message: "正在握手探测上游接口…",
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
