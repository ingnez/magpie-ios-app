import Foundation

@main
struct ModelContractTests {
    static func main() throws {
        func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
            try JSONDecoder().decode(type, from: Data(json.utf8))
        }
        let rule = try decode(RemoteGroupRule.self, #"{"use":"p/m","where":[{"field":"model","op":"eq","value":"gpt"}]}"#)
        precondition(rule.toDictionary()["where"] != nil, "Editing a routing group must preserve advanced conditions")
        let state = try decode(RemoteStateResponse.self, #"{"agents":[{"id":"claude","fields":[{"key":"model","list":1}]}],"optionLists":[[0,99,-1]],"options":[{"value":"group/main","fastFor":"*"}]}"#)
        precondition(state.agents[0].fields[0].options.count == 1)
        precondition(state.agents[0].fields[0].options[0].fastFor == "claude")
        let groups = try decode(RemoteGroupsResponse.self, #"{"groups":[{"id":"a","off":["p/m"],"disabled":true},{"id":"legacy","off":true}]}"#)
        precondition(groups.groups[0].offMembers == ["p/m"] && groups.groups[0].disabled)
        precondition(groups.groups[1].disabled)
        let balance = try decode(RemoteProviderBalanceResponse.self, #"{"ok":true,"amount":1.25}"#)
        precondition(balance.amount == "1.2500")
        let base = URL(string: "https://example.com:443/magpie")!
        precondition(sameConsoleOrigin(URL(string: "https://example.com/path")!, base))
        precondition(!sameConsoleOrigin(URL(string: "http://example.com/path")!, base))
        precondition(!sameConsoleOrigin(URL(string: "https://example.com:8443/")!, base))
        precondition(!sameConsoleOrigin(URL(string: "https://evil.example/path")!, base))
        let console = ConsoleDestination.backup.url(base: base)!
        precondition(URLComponents(url: console, resolvingAgainstBaseURL: false)?.path == "/magpie/" && console.query!.contains("tab=sync"))
        precondition(!console.query!.contains("k="))
        let payload = preservedProviderPayload(current: ["headers": ["X-Custom": "test"], "contexts": ["m": 200000], "chosen": ["m"], "key": ["masked": "hidden"], "models": [["id": "m"]]], changes: ["name": "Renamed"])
        precondition((payload["headers"] as? [String: String])?["X-Custom"] == "test")
        precondition(payload["key"] == nil && payload["models"] as? [String] == ["m"])
        precondition(payload["name"] as? String == "Renamed")
        let key = try decode(RemoteCallerKey.self, #"{"id":"k","limit":{"period":"week","tokens":500000},"used":{"period":"week","tokens":100,"cost":0.01,"reset":"2026-11-23"}}"#)
        precondition(key.limit?.tokens == 500000 && key.used?.tokens == 100)
        let settings = try decode(RemoteSettingsState.self, #"{"workbuddyCheckin":true,"qoderCheckin":false,"proxy":"@px1","proxies":[{"id":"px1","name":"HK Proxy","url":"socks5://127.0.0.1:7890","hasPass":true,"uses":[{"where":"global"}],"check":{"ok":true,"ms":42,"ip":"1.2.3.4","loc":"HK"}}],"corsOrigins":["https://app.example.com"],"usageAlert":85,"balanceAlert":5.5,"quotaLeft":true,"quotaReads":"asked","busyLoad":75,"contextCap":200000,"fullContext":false,"compactAt":272000}"#)
        precondition(settings.automaticCheckins["workbuddy"] == true && settings.automaticCheckins["qoder"] == false)
        precondition(settings.proxy == "@px1" && settings.proxies.count == 1 && settings.proxies[0].check?.ms == 42)
        precondition(settings.corsOrigins == ["https://app.example.com"] && settings.usageAlert == 85 && settings.quotaLeft && settings.quotaReads == "asked")
        precondition(settings.busyLoad == 75 && settings.contextCap == 200000 && settings.compactAt == 272000)

        let autoBackup = try decode(RemoteAutoBackupView.self, #"{"on":true,"hours":24,"keep":7,"dir":"~/.config/magpie/auto-backups","backups":[{"name":"magpie-20261117-120000-auto.json","made":"2026-11-17T12:00:00Z","reason":"auto","size":4096,"providers":3,"library":true}]}"#)
        precondition(autoBackup.on && autoBackup.hours == 24 && autoBackup.backups.count == 1 && autoBackup.backups[0].providers == 3)

        let davSync = try decode(RemoteDavSyncView.self, #"{"on":true,"url":"https://dav.jianguoyun.com/dav/magpie","user":"demo@example.com","passwordSet":true,"passphraseSet":true,"keys":true,"agents":true,"kind":"webdav","auto":15,"followServer":false}"#)
        precondition(davSync.on && davSync.kind == "webdav" && davSync.auto == 15 && davSync.passwordSet)

        let tune = try decode(RemoteTuneState.self, #"{"days":7,"gateway":false,"agents":[{"agent":"claude","calls":120,"advice":[{"knob":"compact","model":"claude-sonnet-4-5","setting":{"value":"200000","source":"long","ours":true},"compact":{"model":"claude-sonnet-4-5","current":200000,"window":200000,"best":160000,"cost":12.5,"low":9.8}}]}]}"#)
        precondition(tune.agents.count == 1 && tune.agents[0].advice[0].compact?.best == 160000)

        let modelPrice = try decode(RemoteModelPriceResponse.self, #"{"model":"gpt-demo","price":{"input":2.5,"output":10.0,"cache_read":0.25,"cache_write":3.125}}"#)
        precondition(modelPrice.price?.cacheRead == 0.25 && modelPrice.price?.cacheWrite == 3.125)
        precondition((modelPrice.price?.toDictionary()["cache_read"] as? Double) == 0.25)

        let portWrap = try decode(RemotePortUpdateResponse.self, #"{"settings":{"port":3426,"lan":true},"port":{"ok":true}}"#)
        precondition(portWrap.settings.port == 3426 && portWrap.settings.lan == true)

        print("PASS: origins, console routes, preserved provider fields, caller budgets")
        print("PASS: routing conditions, shared agent options, group disabled/off compatibility, numeric balance")
        print("PASS: proxies, autobackup, davsync, context tune, model price snake_case keys, and port wrapper")
    }
}
