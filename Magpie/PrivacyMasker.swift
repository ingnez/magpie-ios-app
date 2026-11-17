import Foundation

struct PrivacyMaskResult {
    var maskedText: String
    var replacements: [String: String] // placeholder -> original
    var count: Int
}

enum PrivacyMasker {
    private static let apiKeyPatterns: [String] = [
        "sk-[A-Za-z0-9_-]{8,}",
        "AIza[0-9A-Za-z_-]{16,}",
        "ghp_[A-Za-z0-9]{16,}",
        "Bearer\\s+[A-Za-z0-9._-]{12,}"
    ]

    private static let emailPattern = "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
    private static let phonePattern = "(?<!\\d)1[3-9]\\d{9}(?!\\d)"

    static func maskText(
        _ input: String,
        settings: PrivacyMaskSettings,
        existingReplacements: [String: String] = [:],
        startingIndex: Int = 1
    ) -> PrivacyMaskResult {
        guard settings.enabled, !input.isEmpty else {
            return PrivacyMaskResult(maskedText: input, replacements: existingReplacements, count: 0)
        }

        var output = input
        var map = existingReplacements
        var reverseLookup: [String: String] = [:]
        for (placeholder, original) in map {
            reverseLookup[original] = placeholder
        }
        var nextIndex = startingIndex
        var totalHits = 0

        func replaceMatches(pattern: String, tag: String) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
            let nsString = output as NSString
            let range = NSRange(location: 0, length: nsString.length)
            let matches = regex.matches(in: output, options: [], range: range)
            if matches.isEmpty { return }

            var mutable = output
            for match in matches.reversed() {
                guard let swiftRange = Range(match.range, in: mutable) else { continue }
                let secret = String(mutable[swiftRange])
                if secret.hasPrefix("{{") && secret.hasSuffix("}}") { continue }

                let placeholder: String
                if let existing = reverseLookup[secret] {
                    placeholder = existing
                } else {
                    placeholder = "{{\(tag)_\(nextIndex)}}"
                    nextIndex += 1
                    map[placeholder] = secret
                    reverseLookup[secret] = placeholder
                }
                mutable.replaceSubrange(swiftRange, with: placeholder)
                totalHits += 1
            }
            output = mutable
        }

        if settings.maskAPIKeys {
            for pat in apiKeyPatterns {
                replaceMatches(pattern: pat, tag: "API_KEY")
            }
        }

        if settings.maskEmails {
            replaceMatches(pattern: emailPattern, tag: "EMAIL")
        }

        if settings.maskPhones {
            replaceMatches(pattern: phonePattern, tag: "PHONE")
        }

        for keyword in settings.customKeywords {
            let escaped = NSRegularExpression.escapedPattern(for: keyword)
            replaceMatches(pattern: escaped, tag: "SECRET")
        }

        return PrivacyMaskResult(maskedText: output, replacements: map, count: totalHits)
    }

    static func maskJSONObject(_ value: Any, settings: PrivacyMaskSettings) -> (masked: Any, replacements: [String: String], count: Int) {
        guard settings.enabled else {
            return (value, [:], 0)
        }
        var replacements: [String: String] = [:]
        var totalCount = 0
        var nextIdx = 1

        func walk(_ node: Any, keyName: String?) -> Any {
            if let str = node as? String {
                // Skip model names and role identifiers
                if keyName == "model" || keyName == "role" || keyName == "type" || keyName == "object" {
                    return str
                }
                let res = maskText(str, settings: settings, existingReplacements: replacements, startingIndex: nextIdx)
                replacements = res.replacements
                nextIdx = replacements.count + 1
                totalCount += res.count
                return res.maskedText
            } else if let arr = node as? [Any] {
                return arr.map { walk($0, keyName: keyName) }
            } else if let dict = node as? [String: Any] {
                var out: [String: Any] = [:]
                for (k, v) in dict {
                    out[k] = walk(v, keyName: k)
                }
                return out
            }
            return node
        }

        let masked = walk(value, keyName: nil)
        return (masked, replacements, totalCount)
    }

    static func unmaskText(_ text: String, replacements: [String: String]) -> String {
        guard !replacements.isEmpty, !text.isEmpty else { return text }
        var output = text
        for (placeholder, original) in replacements {
            output = output.replacingOccurrences(of: placeholder, with: original)
        }
        return output
    }

    static func unmaskJSONObject(_ value: Any, replacements: [String: String]) -> Any {
        guard !replacements.isEmpty else { return value }
        if let str = value as? String {
            return unmaskText(str, replacements: replacements)
        } else if let arr = value as? [Any] {
            return arr.map { unmaskJSONObject($0, replacements: replacements) }
        } else if let dict = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (k, v) in dict {
                out[k] = unmaskJSONObject(v, replacements: replacements)
            }
            return out
        }
        return value
    }
}
