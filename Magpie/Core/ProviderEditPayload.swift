import Foundation

/// Provider save replaces several non-optional fields. Carry forward the raw
/// editor fields so changing a model selection doesn't erase headers or maps.
func preservedProviderPayload(current: [String: Any], changes: [String: Any]) -> [String: Any] {
    let editorKeys = [
        "id", "name", "preset", "icon", "chat", "responses", "anthropic", "gemini", "decide", "baseAPI",
        "catalog", "modelsURL", "balanceURL", "balancePath", "website", "keysUrl", "headers", "extraBody",
        "replyHeaders", "passHeaders", "searches", "pinUpstream", "unredacted", "countFree", "billing",
        "nativeCompaction", "magpieUserAgent", "authHeader", "bothAuth", "passUserAgent", "routing", "affinity",
        "sink", "unlisted", "noModels", "bestInFamily", "fallback", "contexts", "modelNames", "modelEfforts",
        "modelImages", "hiddenDrawers", "hiddenVideomakers", "accountProxies", "zhipuTeam", "vertex"
    ]
    var payload: [String: Any] = [:]
    for key in editorKeys { if let value = current[key] { payload[key] = value } }
    payload["models"] = current["chosen"] as? [String] ?? []
    for (key, value) in changes { payload[key] = value }
    return payload
}
