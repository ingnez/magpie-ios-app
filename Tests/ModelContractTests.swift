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

        let providersResp = try decode(RemoteProvidersResponse.self, #"{"providers":[{"id":"antigravity","name":"Antigravity","account":{"agent":"antigravity","agentName":"Antigravity","user":"a@gmail.com","plan":"Google AI Pro","logins":[{"agent":"antigravity","user":"a@gmail.com","plan":"Google AI Pro","active":true,"on":true},{"agent":"antigravity","user":"b@gmail.com","plan":"free","active":false,"on":true,"lapsed":"expired"}]},"accountProxies":{"a@gmail.com":"@px1"},"keepLogin":true,"capStop":true}],"presets":[],"plugins":[{"id":"claude","pid":"claude-plugin","name":"Claude Plugin","icon":"claude-color","spec":"@magpie/claude","methods":[{"type":"oauth","label":"Browser"}],"signedIn":true,"models":3,"importable":true},{"id":"trae-cn","pid":"trae-cn","name":"Trae CN","icon":"trae","spec":"@magpie/trae","methods":[{"type":"oauth","label":"Browser","labels":{"zh":"浏览器授权"}}],"signedIn":false,"models":3,"importable":false}],"onPlugins":["claude"],"agyMove":["a@gmail.com"],"codexDaemon":"old@example.com"}"#)
        precondition(providersResp.providers.count == 1 && providersResp.providers[0].account?.logins.count == 2)
        precondition(providersResp.providers[0].account?.logins[1].lapsed == "expired")
        precondition(providersResp.providers[0].keepLogin && providersResp.providers[0].capStop)
        precondition(providersResp.plugins.count == 2 && providersResp.plugins[1].methods[0].localizedLabel == "浏览器授权")
        precondition(providersResp.onPlugins == ["claude"] && providersResp.agyMove == ["a@gmail.com"])
        precondition(providersResp.codexDaemon == "old@example.com")

        let signIn = try decode(RemoteSignInState.self, #"{"id":"s1","agent":"antigravity","url":"https://accounts.google.com/o/oauth2/v2/auth?client_id=123","state":"waiting","pasteCallback":true,"callbackPort":54321}"#)
        precondition(signIn.id == "s1" && signIn.pasteCallback && signIn.callbackPort == 54321)

        let promptResp = try decode(RemotePluginPromptResponse.self, #"{"prompt":{"type":"select","key":"region","message":"Select region","messages":{"zh":"选择区域"},"options":[{"label":"Global","value":"global","labels":{"zh":"国际站"}}]},"inputs":{"foo":"bar"}}"#)
        precondition(promptResp.prompt?.localizedMessage == "选择区域" && promptResp.prompt?.options[0].localizedLabel == "国际站")

        let loginUsage = try decode([String: RemoteLoginQuota].self, #"{"a@gmail.com":{"provider":"antigravity","name":"Antigravity","icon":"antigravity-color","plan":"Google AI Pro","user":"a@gmail.com","windows":[{"name":"Gemini","used":35.5,"pool":"Gemini","capId":"gemini"}]}}"#)
        precondition(loginUsage["a@gmail.com"]?.windows.first?.used == 35.5)

        let allSubs = SubscriptionCatalog.allPlatforms(plugins: providersResp.plugins, onPlugins: providersResp.onPlugins)
        precondition(allSubs.builtins.count == 19, "Expected all 19 built-in Magpie OAuth/subscription platforms")
        precondition(allSubs.builtins.contains(where: { $0.agent == "antigravity" }))
        precondition(allSubs.builtins.contains(where: { $0.agent == "codex" }))
        precondition(allSubs.builtins.first(where: { $0.agent == "claude" })?.movedToPlugin == true)
        precondition(allSubs.extraPlugins.count == 1 && allSubs.extraPlugins[0].agent == "trae-cn")

        let marketResp = try decode(RemotePluginListingsResponse.self, #"{"listings":[{"package":"@magpie-community/opencode-zen-free-auth","name":"OpenCode Zen Free","providers":["opencode-zen-free"],"community":true,"summary":{"zh":"免费模型通道"}}]}"#)
        precondition(marketResp.listings.count == 1 && marketResp.listings[0].localizedSummary == "免费模型通道")
        let marketPlatforms = SubscriptionCatalog.communityMarketPlatforms(plugins: providersResp.plugins, onPlugins: providersResp.onPlugins, listings: marketResp.listings)
        precondition(marketPlatforms.contains(where: { $0.agent == "opencode-zen-free" && $0.pluginSpec == "@magpie-community/opencode-zen-free-auth" }))
        precondition(marketPlatforms.contains(where: { $0.agent == "agy-cli" && $0.pluginSpec == "@magpie-community/opencode-agy-cli-auth" }))

        precondition(SubscriptionCatalog.isPriorityRouting(""))
        precondition(SubscriptionCatalog.isPriorityRouting("order"))
        precondition(SubscriptionCatalog.isPriorityRouting("drain"))
        precondition(!SubscriptionCatalog.isPriorityRouting("rotate"))
        precondition(!SubscriptionCatalog.isPriorityRouting("weight"))
        precondition(!SubscriptionCatalog.isPriorityRouting("usage"))

        let agyRestProvider = try decode(RemoteProvider.self, #"{"id":"antigravity","name":"Antigravity","routing":"rotate","account":{"agent":"antigravity","user":"a@gmail.com","logins":[{"agent":"antigravity","user":"a@gmail.com","active":true,"on":true},{"agent":"antigravity","user":"b@gmail.com","active":false,"on":true,"paused":false}]},"accountWeights":{"a@gmail.com":3},"accountRests":{"b@gmail.com":[{"why":"rate","status":429,"until":"2026-11-17T22:15:00+08:00","rate":true,"key":"antigravity#b@gmail.com"}]}}"#)
        precondition(agyRestProvider.routing == "rotate")
        precondition(agyRestProvider.accountWeights["a@gmail.com"] == 3)
        precondition(agyRestProvider.accountRests["b@gmail.com"]?.first?.key == "antigravity#b@gmail.com")

        // OAuth callback URL normalization, validation & HTTP 400 mapping unit tests
        let screenshotSample = "localhost:13035/oauth-callback?state=LU"
        let normalizedSample = OAuthCallbackHelper.normalize(screenshotSample)
        precondition(normalizedSample == "http://localhost:13035/oauth-callback?state=LU", "Expected http:// prefix for screenshot sample, got \(normalizedSample)")
        precondition(OAuthCallbackHelper.validate(normalizedSample) == nil, "Normalized screenshot sample must pass local validation")
        precondition(OAuthCallbackHelper.detectedCallbackURL(from: screenshotSample) == "http://localhost:13035/oauth-callback?state=LU")

        let normCases: [(String, String)] = [
            ("  \u{3000}localhost:13035/oauth-callback?state=LU\n\t ", "http://localhost:13035/oauth-callback?state=LU"),
            ("\"localhost:13035/oauth-callback?state=LU\"", "http://localhost:13035/oauth-callback?state=LU"),
            ("\u{201C}127.0.0.1:54321/callback?code=abc&state=s1\u{201D}", "http://127.0.0.1:54321/callback?code=abc&state=s1"),
            ("\u{2018}[::1]:1455/auth/callback?code=xyz\u{2019}", "http://[::1]:1455/auth/callback?code=xyz"),
            ("`'https://magpie.example.com/oauth/callback?code=1'`", "https://magpie.example.com/oauth/callback?code=1"),
            ("192.168.1.50:8080/oauth-callback?code=9", "http://192.168.1.50:8080/oauth-callback?code=9"),
            ("dev-box.local:3430/callback?state=ok", "http://dev-box.local:3430/callback?state=ok"),
            ("localhost:13035/callback?next=https://accounts.google.com", "http://localhost:13035/callback?next=https://accounts.google.com"),
            ("   \u{3000}\n  ", "")
        ]
        for (rawInput, expected) in normCases {
            let actual = OAuthCallbackHelper.normalize(rawInput)
            precondition(actual == expected, "Normalize mismatch for \(rawInput): expected \(expected), got \(actual)")
            if !expected.isEmpty {
                precondition(OAuthCallbackHelper.validate(actual) == nil, "Expected valid URL for \(expected)")
            }
        }

        let invalidInputs: [(String, String)] = [
            ("", "请粘贴"),
            ("example.com/oauth-callback?code=1", "http://"),
            ("ftp://localhost:13035/oauth-callback", "http://"),
            ("http:///oauth-callback?code=1", "主机名"),
            ("localhost:13035", "缺少回调路径"),
            ("http://localhost:13035?state=LU", "缺少回调路径"),
            ("http://localhost:13035/oauth callback?state=LU", "空格")
        ]
        for (rawInvalid, expectedFragment) in invalidInputs {
            let norm = OAuthCallbackHelper.normalize(rawInvalid)
            let err = OAuthCallbackHelper.validate(norm)
            precondition(err != nil && err!.contains(expectedFragment), "Validation for \(rawInvalid) -> \(norm) expected fragment \(expectedFragment), got \(String(describing: err))")
        }

        precondition(OAuthCallbackHelper.detectedCallbackURL(from: "https://www.google.com/search?q=magpie") == nil)

        let mapped400 = OAuthCallbackHelper.mapServerCallbackError(
            statusCode: 400,
            message: "paste the whole address the browser ended on, starting with http://"
        )
        precondition(mapped400.summary.contains("http://"), "Mapped 400 must guide user in Chinese")
        precondition(mapped400.rawDetail == "paste the whole address the browser ended on, starting with http://", "Raw detail must be preserved")

        let mappedCode = OAuthCallbackHelper.mapServerCallbackError(statusCode: 400, message: "missing code parameter")
        precondition(mappedCode.summary.contains("授权码") && mappedCode.rawDetail == "missing code parameter")

        let mappedState = OAuthCallbackHelper.mapServerCallbackError(statusCode: 400, message: "oauth state mismatch")
        precondition(mappedState.summary.contains("state") && mappedState.rawDetail == "oauth state mismatch")

        print("PASS: OAuth callback normalization, validation & 400 mapping (21 assertions)")
        print("PASS: OAuth sign-in, 19+ platform catalog, plugin prompts, multi-account logins & usage")
        print("PASS: origins, console routes, preserved provider fields, caller budgets")
        print("PASS: routing conditions, shared agent options, group disabled/off compatibility, numeric balance")
        print("PASS: proxies, autobackup, davsync, context tune, model price snake_case keys, and port wrapper")
    }
}
