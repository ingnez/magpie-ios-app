import Foundation

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
            return .invalid(reason: "请输入 magpie web 地址（以 http:// 或 https:// 开头）")
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
        normalized.query = nil
        normalized.fragment = nil
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

struct ParsedMagpieLink: Equatable {
    let baseURL: String
    let webKey: String?
}

enum MagpieWebLinkParser {
    /// Parses a full `magpie web` startup link such as `https://host:3430/?k=xxxx`
    /// into normalized baseURL + extracted `k` key.
    static func parse(_ rawInput: String) -> ParsedMagpieLink? {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let components = URLComponents(string: trimmed) else {
            return nil
        }
        let extractedKey = components.queryItems?
            .first(where: { $0.name == "k" })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var baseComponents = components
        baseComponents.query = nil
        baseComponents.fragment = nil
        guard let rawBase = baseComponents.string,
              case .valid(let normalized) = URLValidator.validateAndNormalize(rawBase) else {
            return nil
        }
        let cleanKey = (extractedKey?.isEmpty == false) ? extractedKey : nil
        return ParsedMagpieLink(baseURL: normalized, webKey: cleanKey)
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
        message: "尚未连接 magpie web 实例",
        checkedAt: nil
    )

    static let checking = ConnectionHealth(
        kind: .checking,
        latencyMs: nil,
        statusCode: nil,
        message: "正在交换 Cookie 并握手探测…",
        checkedAt: nil
    )
}

struct MagpieServerProfile: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var baseURL: String
    var allowInsecureTLS: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var hostLabel: String {
        guard let url = URL(string: baseURL), let host = url.host else {
            return baseURL
        }
        if let port = url.port {
            return "\(host):\(port)"
        }
        return host
    }
}
