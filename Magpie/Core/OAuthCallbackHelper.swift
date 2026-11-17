import Foundation

enum OAuthCallbackHelper {
    static let trimCharacterSet: CharacterSet = {
        var set = CharacterSet.whitespacesAndNewlines
        set.insert(charactersIn: "\u{3000}\u{00A0}\u{200B}\u{FEFF}")
        return set
    }()

    private static let quotePairs: [(Character, Character)] = [
        ("\"", "\""),
        ("'", "'"),
        ("`", "`"),
        ("\u{201C}", "\u{201D}"), // “ ”
        ("\u{2018}", "\u{2019}"), // ‘ ’
        ("\u{201D}", "\u{201D}"), // ” ”
        ("\u{2019}", "\u{2019}"), // ’ ’
        ("\u{FF02}", "\u{FF02}"), // fullwidth ＂ ＂
        ("\u{FF07}", "\u{FF07}")  // fullwidth ＇ ＇
    ]

    /// Pure function that normalizes a user-pasted OAuth callback URL:
    /// - Trims leading/trailing whitespace (including full-width U+3000), newlines, and embedded CR/LF.
    /// - Strips paired English/Chinese quotes and backticks (repeatedly if nested).
    /// - Prepends `http://` when scheme is missing and the input starts with
    ///   `localhost`, `127.0.0.1`, `[::1]`, or a `host:port...` prefix.
    static func normalize(_ raw: String) -> String {
        var value = raw
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: trimCharacterSet)

        var changed = true
        while changed {
            changed = false
            let trimmed = value.trimmingCharacters(in: trimCharacterSet)
            if trimmed != value {
                value = trimmed
                changed = true
            }
            if value.count >= 2, let first = value.first, let last = value.last {
                for (open, close) in quotePairs where first == open && last == close {
                    value = String(value.dropFirst().dropLast()).trimmingCharacters(in: trimCharacterSet)
                    changed = true
                    break
                }
            }
        }

        guard !value.isEmpty else { return "" }

        if !hasURLSchemePrefix(value) {
            if startsWithLoopbackHost(value) || matchesHostPortPrefix(value) {
                value = "http://" + value
            }
        }

        return value
    }

    /// Validates an already-normalized callback URL before sending to the backend.
    /// Returns a human-readable Chinese message when invalid, or `nil` when valid.
    static func validate(_ normalized: String) -> String? {
        if normalized.isEmpty {
            return "请粘贴浏览器地址栏的完整地址"
        }

        if normalized.rangeOfCharacter(from: trimCharacterSet) != nil {
            return "回调地址中不能包含空格，请检查后重新粘贴完整地址"
        }

        guard hasURLSchemePrefix(normalized) else {
            return "地址要以 http:// 开头，请粘贴浏览器地址栏的完整地址"
        }

        guard let components = URLComponents(string: normalized) else {
            return "回调地址格式有误，请粘贴浏览器地址栏的完整地址"
        }

        let scheme = components.scheme?.lowercased() ?? ""
        guard scheme == "http" || scheme == "https" else {
            return "地址要以 http:// 或 https:// 开头（当前为 \(scheme)://），请粘贴浏览器地址栏的完整地址"
        }

        guard let host = components.host, !host.isEmpty else {
            return "回调地址缺少主机名（例如 localhost），请粘贴浏览器地址栏的完整地址"
        }

        guard !components.path.isEmpty else {
            return "请粘贴浏览器地址栏的完整地址（缺少回调路径，例如 /oauth-callback）"
        }

        guard components.url != nil else {
            return "回调地址格式无效，请粘贴浏览器地址栏的完整地址"
        }

        return nil
    }

    /// Normalizes and validates a raw clipboard candidate for the one-tap submit button.
    static func detectedCallbackURL(from rawClipboard: String) -> String? {
        let normalized = normalize(rawClipboard)
        guard validate(normalized) == nil, let components = URLComponents(string: normalized) else {
            return nil
        }
        let host = components.host?.lowercased() ?? ""
        let isLoopback = host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]"
        let hasCallbackSignal = normalized.contains("code=")
            || normalized.contains("state=")
            || components.path.lowercased().contains("callback")
        return (isLoopback || hasCallbackSignal) ? normalized : nil
    }

    /// Maps backend HTTP 400 (or other submission errors) into a clear Chinese message
    /// while preserving the raw server English text for collapsible inspection.
    static func mapServerCallbackError(statusCode: Int, message: String) -> (summary: String, rawDetail: String?) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawDetail = trimmed.isEmpty ? nil : trimmed

        guard statusCode == 400 else {
            let fallback = trimmed.isEmpty ? "HTTP \(statusCode) 请求失败" : "HTTP \(statusCode)：\(trimmed)"
            return (fallback, rawDetail)
        }

        let lower = trimmed.lowercased()
        let summary: String
        if lower.contains("starting with http://") || lower.contains("paste the whole address") {
            summary = "请粘贴浏览器地址栏最终跳转的完整地址（需以 http:// 开头）。"
        } else if lower.contains("missing code") || lower.contains("no code") || lower.contains("code is required") || lower.contains("authorization code") {
            summary = "回调链接缺少授权码（code 参数），请确认复制的是授权完成后的最终跳转地址。"
        } else if lower.contains("state") && (lower.contains("mismatch") || lower.contains("invalid") || lower.contains("missing") || lower.contains("expired") || lower.contains("unknown")) {
            summary = "授权 state 校验未通过或已过期，请取消后重新发起授权并粘贴最新跳转链接。"
        } else if lower.contains("invalid url") || lower.contains("parse") || lower.contains("malformed") || lower.contains("bad url") {
            summary = "服务端无法解析该回调地址，请检查链接是否完整且未被截断。"
        } else if lower.contains("expired") || lower.contains("not waiting") || lower.contains("already") || lower.contains("closed") || lower.contains("canceled") {
            summary = "当前授权会话已结束或已过期，请取消后重新发起登录。"
        } else {
            summary = "服务端未能识别该回调地址（HTTP 400），请确认粘贴了浏览器地址栏的完整链接。"
        }

        return (summary, rawDetail)
    }

    // MARK: - Helpers

    private static func hasURLSchemePrefix(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*://"#, options: .regularExpression) != nil
    }

    private static func startsWithLoopbackHost(_ value: String) -> Bool {
        let lower = value.lowercased()
        for prefix in ["localhost", "127.0.0.1", "[::1]"] {
            if lower == prefix { return true }
            if lower.hasPrefix(prefix) {
                let nextIndex = lower.index(lower.startIndex, offsetBy: prefix.count)
                let nextChar = lower[nextIndex]
                if nextChar == ":" || nextChar == "/" || nextChar == "?" || nextChar == "#" {
                    return true
                }
            }
        }
        return false
    }

    private static func matchesHostPortPrefix(_ value: String) -> Bool {
        let pattern = #"^(\[[0-9A-Fa-f:]+\]|[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)*):([0-9]{1,5})(?:[/?#]|$)"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }
}
