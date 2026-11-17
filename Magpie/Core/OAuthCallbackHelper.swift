import Foundation

enum OAuthCallbackHelper {
    struct ExpectedCallbackTarget: Equatable {
        let ports: Set<Int>
        let paths: Set<String>
        let requiresQuery: Bool

        init(ports: Set<Int> = [], paths: Set<String> = [], requiresQuery: Bool = true) {
            self.ports = ports
            self.paths = paths
            self.requiresQuery = requiresQuery
        }

        static func from(authURL: String?, callbackPort: Int?, requiresQuery: Bool = true) -> ExpectedCallbackTarget {
            var ports: Set<Int> = []
            var paths: Set<String> = []
            if let callbackPort = callbackPort, (1...65535).contains(callbackPort) {
                ports.insert(callbackPort)
            }
            if let authURL = authURL, !authURL.isEmpty {
                extractRedirects(from: authURL, depth: 2, ports: &ports, paths: &paths)
            }
            return ExpectedCallbackTarget(ports: ports, paths: paths, requiresQuery: requiresQuery)
        }

        private static func extractRedirects(
            from urlString: String,
            depth: Int,
            ports: inout Set<Int>,
            paths: inout Set<String>
        ) {
            guard let components = URLComponents(string: urlString),
                  let items = components.queryItems else {
                return
            }
            for item in items {
                guard let value = item.value, !value.isEmpty else { continue }
                if let nested = URLComponents(string: value) {
                    let scheme = nested.scheme?.lowercased() ?? ""
                    if scheme == "http", let host = nested.host, isLoopbackHost(host) {
                        let port = nested.port ?? 80
                        ports.insert(port)
                        if !nested.path.isEmpty {
                            paths.insert(nested.path)
                        }
                        continue
                    }
                    if depth > 1, (scheme == "http" || scheme == "https"), !(nested.host ?? "").isEmpty {
                        extractRedirects(from: value, depth: depth - 1, ports: &ports, paths: &paths)
                        continue
                    }
                }
                if item.name.lowercased().contains("port"),
                   let port = Int(value),
                   (1...65535).contains(port) {
                    ports.insert(port)
                }
            }
        }
    }

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

    /// Validates an already-normalized callback URL against Magpie's real backend rules before sending:
    /// - Scheme must be `http` only (rejects `https://` and other schemes).
    /// - Host must be loopback (`localhost`, `127.0.0.1`, or `::1`).
    /// - Path must be non-empty, and match expected callback path(s) when known.
    /// - Port must match expected callback port(s) when known.
    /// - Query string must be non-empty for built-in callback flows.
    /// Returns a human-readable Chinese message when invalid, or `nil` when valid.
    static func validate(_ normalized: String, expected: ExpectedCallbackTarget? = nil) -> String? {
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
        if scheme == "https" {
            return "回调地址只支持 http:// 开头（当前为 https://），请复制授权完成后跳转到本地 http:// 的完整地址"
        }
        guard scheme == "http" else {
            return "地址要以 http:// 开头（当前为 \(scheme)://），请粘贴浏览器地址栏的完整地址"
        }

        guard let host = components.host, !host.isEmpty else {
            return "回调地址缺少主机名（例如 localhost），请粘贴浏览器地址栏的完整地址"
        }

        guard isLoopbackHost(host) else {
            return "回调地址主机名应为 localhost 或 127.0.0.1（当前为 \(host)），请粘贴授权最终跳转的本地地址"
        }

        if let expected = expected, !expected.ports.isEmpty {
            let expectedList = expected.ports.sorted().map(String.init).joined(separator: " / ")
            if let actualPort = components.port {
                if !expected.ports.contains(actualPort) {
                    return "回调端口不匹配（当前为 \(actualPort)，本次授权端口应为 \(expectedList)），请粘贴本次授权跳转的完整地址"
                }
            } else if !expected.ports.contains(80) {
                return "回调地址缺少端口号（本次授权端口应为 \(expectedList)），请粘贴浏览器地址栏的完整地址"
            }
        }

        guard !components.path.isEmpty else {
            return "请粘贴浏览器地址栏的完整地址（缺少回调路径，例如 /oauth-callback）"
        }

        if let expected = expected, !expected.paths.isEmpty, !expected.paths.contains(components.path) {
            let expectedPaths = expected.paths.sorted().joined(separator: " 或 ")
            return "回调路径不匹配（当前为 \(components.path)，本次授权应为 \(expectedPaths)），请粘贴本次授权跳转的完整地址"
        }

        if expected?.requiresQuery ?? true {
            guard let rawQuery = components.percentEncodedQuery, !rawQuery.isEmpty else {
                return "回调地址缺少查询参数（例如 ?code=...&state=...），请粘贴浏览器地址栏的完整地址"
            }
        }

        guard components.url != nil else {
            return "回调地址格式无效，请粘贴浏览器地址栏的完整地址"
        }

        return nil
    }

    /// Normalizes and validates a raw clipboard candidate for the one-tap submit button.
    static func detectedCallbackURL(from rawClipboard: String, expected: ExpectedCallbackTarget? = nil) -> String? {
        let normalized = normalize(rawClipboard)
        guard validate(normalized, expected: expected) == nil,
              let components = URLComponents(string: normalized) else {
            return nil
        }
        let hasCallbackSignal = normalized.contains("code=")
            || normalized.contains("state=")
            || components.path.lowercased().contains("callback")
        return hasCallbackSignal ? normalized : nil
    }

    /// Maps Magpie backend HTTP 400 callback errors (and other HTTP errors) into clear Chinese guidance
    /// aligned with the real Go backend error strings, while preserving the raw server detail.
    static func mapServerCallbackError(statusCode: Int, message: String) -> (summary: String, rawDetail: String?) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawDetail = trimmed.isEmpty ? nil : trimmed

        guard statusCode == 400 else {
            let fallback = trimmed.isEmpty ? "HTTP \(statusCode) 请求失败" : "HTTP \(statusCode)：\(trimmed)"
            return (fallback, rawDetail)
        }

        let lower = trimmed.lowercased()
        let summary: String
        if lower.contains("paste the whole address the browser ended on, starting with http://") {
            summary = "请粘贴浏览器最终跳转的完整地址（须以 http:// 开头并包含查询参数）。"
        } else if lower.contains("paste the code claude's page shows") {
            summary = "请粘贴 Claude 页面显示的授权码，或浏览器最终跳转的完整 http:// 地址。"
        } else if lower.contains("that address isn't from this sign-in") {
            summary = "该地址不属于当前这次登录会话（端口、路径或 state 不匹配），请粘贴本次授权标签页最终跳转的地址。"
        } else if lower.contains("that address didn't finish the sign-in") {
            summary = "该回调地址未能完成登录（可能缺少 code 授权码或参数无效），请确认粘贴最终跳转完整地址或取消后重新登录。"
        } else if lower.contains("this sign-in is over")
            || lower.contains("the sign-in is over")
            || lower.contains("no such sign-in")
            || lower.contains("isn't waiting for that address any more")
            || lower.contains("the sign-in was canceled") {
            summary = "当前授权会话已结束或已失效，请取消后重新发起登录。"
        } else if lower.contains("can't be finished from a pasted address") {
            summary = "当前登录方式不支持通过粘贴回调地址完成，请按页面提示完成授权。"
        } else if lower.contains("the sign-in is still finishing") {
            summary = "登录仍在完成中，请稍候查看账号列表是否已新增。"
        } else if lower.contains("access_denied") {
            summary = "授权已被拒绝或取消（access_denied），请重新发起授权并确认同意。"
        } else if !trimmed.isEmpty {
            summary = "服务端回调校验未通过（HTTP 400），请展开下方原文查看具体原因，或取消后重新发起登录。"
        } else {
            summary = "服务端未能识别该回调地址（HTTP 400），请确认粘贴了浏览器地址栏的完整链接。"
        }

        return (summary, rawDetail)
    }

    // MARK: - Helpers

    static func isLoopbackHost(_ host: String) -> Bool {
        let lower = host.lowercased()
        return lower == "localhost" || lower == "127.0.0.1" || lower == "::1" || lower == "[::1]"
    }

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
