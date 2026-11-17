import Foundation

/// Provider save replaces several non-optional fields. Carry forward the raw
/// editor fields so changing a model selection doesn't erase headers or maps.
func preservedProviderPayload(current: [String: Any], changes: [String: Any]) -> [String: Any] {
    let editorKeys = [
        "accountCaps", "accountConcurrency", "accountModels", "accountNames", "accountProxies", "accountWeights",
        "accountWindowAmounts", "accountWindowCaps", "affinity", "anthropic", "authHeader", "balanceMethod",
        "balancePath", "balanceURL", "baseAPI", "bestInFamily", "billing", "capCareful",
        "capStop", "catalog", "chat", "clientCert", "clientKey", "contexts",
        "countFree", "decide", "extraBody", "fallback", "gemini", "headers",
        "hiddenDrawers", "hiddenVideomakers", "http1", "icon", "iconFrom", "id",
        "imageFilesOff", "insecureTLS", "keepLogin", "keepLoginAs", "keepSelf", "keyPriceRates",
        "keysUrl", "limitRestOff", "listOff", "maxAccounts", "maxConcurrency", "maxRPM",
        "modelsURL", "name", "nativeCompaction", "noBalanceProbe", "noModels", "noStandIn",
        "off", "passErrors", "passHeaders", "pinUpstream", "preset", "priceRate",
        "proxy", "queueLimit", "queueWait", "rateWindows", "replyHeaders", "resolve",
        "responses", "restartApp", "routing", "searches", "serverCA", "serverPin",
        "sink", "socket", "switchOnly", "thisDevice", "unlisted", "unredacted",
        "upstreamProviders", "useFirst", "vertex", "website", "zhipuTeam",
    ]
    var payload: [String: Any] = [:]
    for key in editorKeys { if let value = current[key] { payload[key] = value } }
    payload["models"] = current["chosen"] as? [String] ?? []
    for (key, value) in changes { payload[key] = value }
    return payload
}
