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
        precondition(agyRestProvider.effectiveMaxAccounts == nil && agyRestProvider.maxAccountsSummary == "不限 (null)")

        let fourAcctProvider = try decode(RemoteProvider.self, #"{"id":"antigravity","name":"Antigravity","routing":"weight","maxAccounts":2,"pluginAccounts":2,"account":{"agent":"antigravity","user":"a@gmail.com","logins":[{"agent":"antigravity","user":"a@gmail.com","active":true,"on":true},{"agent":"antigravity","user":"b@gmail.com","active":false,"on":true},{"agent":"antigravity","user":"c@gmail.com","active":false,"on":true},{"agent":"antigravity","user":"d@gmail.com","active":false,"on":true}]},"accountNames":{"c@gmail.com":"主力3号"},"accountWeights":{"a@gmail.com":2,"c@gmail.com":4},"accountRests":{"b@gmail.com":[{"why":"rate","status":429,"until":"2026-11-18T01:00:00+08:00","rate":true,"key":"antigravity#b@gmail.com"}]}}"#)
        precondition(fourAcctProvider.account?.logins.count == 4, "Must decode N >= 4 accounts without truncation")
        precondition(fourAcctProvider.accountNames["c@gmail.com"] == "主力3号")
        precondition(fourAcctProvider.accountWeights["c@gmail.com"] == 4)
        precondition(fourAcctProvider.effectiveMaxAccounts == 2 && fourAcctProvider.maxAccountsSummary == "同时上限 2 个")

        let zeroUnlimited = try decode(RemoteProvider.self, #"{"id":"codex","name":"Codex","maxAccounts":0,"pluginAccounts":2}"#)
        precondition(zeroUnlimited.effectiveMaxAccounts == nil && zeroUnlimited.maxAccountsSummary == "不限 (0)")

        let maxAccPayload = preservedProviderPayload(current: ["id": "antigravity", "headers": ["X-Test": "1"], "chosen": ["gemini-2.5-pro"], "accountWeights": ["c@gmail.com": 4], "maxAccounts": 2], changes: ["maxAccounts": NSNull()])
        precondition(maxAccPayload["maxAccounts"] is NSNull)
        precondition((maxAccPayload["accountWeights"] as? [String: Int])?["c@gmail.com"] == 4)

        // OAuth callback URL normalization, http-only + port/path preflight & real 400 mapping tests
        let screenshotSample = "localhost:54321/callback?state=LU"
        let normalizedSample = OAuthCallbackHelper.normalize(screenshotSample)
        precondition(normalizedSample == "http://localhost:54321/callback?state=LU", "Expected http:// prefix for sample, got \(normalizedSample)")

        let expectedGoogle = OAuthCallbackHelper.ExpectedCallbackTarget.from(
            authURL: "https://accounts.google.com/o/oauth2/v2/auth?client_id=demo&redirect_uri=http%3A%2F%2F127.0.0.1%3A54321%2Fcallback&state=s1",
            callbackPort: nil
        )
        precondition(expectedGoogle.ports == [54321] && expectedGoogle.paths == ["/callback"], "Expected port 54321 and /callback")
        precondition(OAuthCallbackHelper.validate(normalizedSample, expected: expectedGoogle) == nil, "Normalized sample must pass port/path preflight")
        precondition(OAuthCallbackHelper.detectedCallbackURL(from: screenshotSample, expected: expectedGoogle) == "http://localhost:54321/callback?state=LU")

        let expectedCodeArts = OAuthCallbackHelper.ExpectedCallbackTarget.from(
            authURL: "https://auth.huaweicloud.com/authui/login?service=https%3A%2F%2Fcodearts.ap-southeast-1.huaweicloud.com%2Fportal%2Fauthorize%3Fport%3D37093",
            callbackPort: nil,
            requiresQuery: false
        )
        precondition(expectedCodeArts.ports == [37093] && expectedCodeArts.paths.isEmpty)

        let normCases: [(String, String, Bool)] = [
            ("  \u{3000}localhost:13035/oauth-callback?state=LU\n\t ", "http://localhost:13035/oauth-callback?state=LU", true),
            ("\"localhost:13035/oauth-callback?state=LU\"", "http://localhost:13035/oauth-callback?state=LU", true),
            ("\u{201C}127.0.0.1:54321/callback?code=abc&state=s1\u{201D}", "http://127.0.0.1:54321/callback?code=abc&state=s1", true),
            ("\u{2018}[::1]:1455/auth/callback?code=xyz\u{2019}", "http://[::1]:1455/auth/callback?code=xyz", true),
            ("`'https://magpie.example.com/oauth/callback?code=1'`", "https://magpie.example.com/oauth/callback?code=1", false),
            ("192.168.1.50:8080/oauth-callback?code=9", "http://192.168.1.50:8080/oauth-callback?code=9", false),
            ("dev-box.local:3430/callback?state=ok", "http://dev-box.local:3430/callback?state=ok", false),
            ("localhost:13035/callback?next=https://accounts.google.com", "http://localhost:13035/callback?next=https://accounts.google.com", true),
            ("   \u{3000}\n  ", "", false)
        ]
        for (rawInput, expected, shouldBeValid) in normCases {
            let actual = OAuthCallbackHelper.normalize(rawInput)
            precondition(actual == expected, "Normalize mismatch for \(rawInput): expected \(expected), got \(actual)")
            if shouldBeValid {
                precondition(OAuthCallbackHelper.validate(actual) == nil, "Expected valid URL for \(expected)")
            } else if !actual.isEmpty {
                precondition(OAuthCallbackHelper.validate(actual) != nil, "Expected invalid URL for \(expected)")
            }
        }

        let invalidInputs: [(String, OAuthCallbackHelper.ExpectedCallbackTarget?, String)] = [
            ("", nil, "请粘贴"),
            ("example.com/oauth-callback?code=1", nil, "http://"),
            ("https://localhost:54321/callback?code=1&state=s1", expectedGoogle, "只支持 http://"),
            ("ftp://localhost:13035/oauth-callback?code=1", nil, "http://"),
            ("http:///oauth-callback?code=1", nil, "主机名"),
            ("http://192.168.1.50:8080/oauth-callback?code=9", nil, "主机名应为"),
            ("localhost:54321", expectedGoogle, "缺少回调路径"),
            ("http://localhost:13035/callback?code=1&state=s1", expectedGoogle, "端口不匹配"),
            ("http://localhost/callback?code=1&state=s1", expectedGoogle, "缺少端口号"),
            ("http://localhost:54321/oauth-callback?code=1&state=s1", expectedGoogle, "回调路径不匹配"),
            ("http://localhost:54321/callback", expectedGoogle, "缺少查询参数"),
            ("http://localhost:13035/oauth callback?state=LU", nil, "空格")
        ]
        for (rawInvalid, expectedTarget, expectedFragment) in invalidInputs {
            let norm = OAuthCallbackHelper.normalize(rawInvalid)
            let err = OAuthCallbackHelper.validate(norm, expected: expectedTarget)
            precondition(err != nil && err!.contains(expectedFragment), "Validation for \(rawInvalid) -> \(norm) expected fragment \(expectedFragment), got \(String(describing: err))")
        }

        precondition(OAuthCallbackHelper.detectedCallbackURL(from: "https://localhost:54321/callback?code=1&state=s1", expected: expectedGoogle) == nil)
        precondition(OAuthCallbackHelper.detectedCallbackURL(from: "http://localhost:13035/callback?code=1&state=s1", expected: expectedGoogle) == nil)
        precondition(OAuthCallbackHelper.detectedCallbackURL(from: "https://www.google.com/search?q=magpie") == nil)

        // Real Go backend error strings (v0.1.3226 / HEAD)
        let mapped1 = OAuthCallbackHelper.mapServerCallbackError(
            statusCode: 400,
            message: "paste the whole address the browser ended on, starting with http://"
        )
        precondition(mapped1.summary.contains("http://") && mapped1.rawDetail == "paste the whole address the browser ended on, starting with http://")

        let mapped2 = OAuthCallbackHelper.mapServerCallbackError(
            statusCode: 400,
            message: "that address isn't from this sign-in: paste the one its browser tab ended on"
        )
        precondition(mapped2.summary.contains("不属于当前这次登录会话") && mapped2.rawDetail != nil)

        let mapped3 = OAuthCallbackHelper.mapServerCallbackError(
            statusCode: 400,
            message: "that address didn't finish the sign-in; start it again"
        )
        precondition(mapped3.summary.contains("未能完成登录") && mapped3.rawDetail != nil)

        let mapped4 = OAuthCallbackHelper.mapServerCallbackError(
            statusCode: 400,
            message: "this sign-in is over; start it again"
        )
        precondition(mapped4.summary.contains("已结束或已失效") && mapped4.rawDetail != nil)

        let mapped4b = OAuthCallbackHelper.mapServerCallbackError(
            statusCode: 400,
            message: "no such sign-in"
        )
        precondition(mapped4b.summary.contains("已结束或已失效"))

        // Phase 2: AccountErrorAggregator & RemoteKeyRest(error/failures)
        let errProviders = try decode([RemoteProvider].self, #"[{"id":"codex","name":"Codex","account":{"agent":"codex","user":"ok@x.com","logins":[{"agent":"codex","user":"ok@x.com","active":true,"on":true,"seen":"2026-11-17T10:00:00+08:00"},{"agent":"codex","user":"bad@x.com","active":false,"on":true,"lapsed":"refresh_token_revoked","seen":"2026-11-17T20:15:00+08:00"}]}},{"id":"antigravity","name":"Antigravity","account":{"agent":"antigravity","user":"a@gmail.com","logins":[{"agent":"antigravity","user":"a@gmail.com","active":true,"on":true},{"agent":"antigravity","user":"b@gmail.com","active":false,"on":true,"seen":"2026-11-17T21:40:00+08:00"}]},"accountNames":{"b@gmail.com":"二号机"},"accountRests":{"b@gmail.com":[{"why":"rate","status":429,"until":"2026-11-18T02:00:00+08:00","rate":true,"by":"backoff","error":"Too Many Requests","failures":4,"key":"antigravity#b@gmail.com"}]}},{"id":"custom","name":"自建中转","listError":"dial tcp timeout","keyList":[{"id":"k2","name":"备Key","masked":"sk-••02","on":true,"rest":{"why":"quota","status":402,"until":"2026-11-18T08:00:00+08:00","error":"Insufficient credit","failures":2}}]}]"#)
        let aggregated = AccountErrorAggregator.aggregate(providers: errProviders)
        precondition(aggregated.count == 4, "Expected 4 aggregated errors, got \(aggregated.count)")
        precondition(aggregated[0].category == .auth && aggregated[0].accountUser == "bad@x.com" && aggregated[0].targetTab == .keys)
        precondition(aggregated[0].lastFailureAt == "2026-11-17T20:15:00+08:00")
        precondition(aggregated[1].category == .quota && aggregated[1].keyID == "k2" && aggregated[1].failureCount == 2)
        precondition(aggregated[2].category == .rateLimit && aggregated[2].displayName == "二号机" && aggregated[2].failureCount == 4 && aggregated[2].isConsecutive)
        precondition(aggregated[2].rawDetail == "Too Many Requests")
        precondition(aggregated[3].category == .upstream && aggregated[3].providerID == "custom" && aggregated[3].targetTab == .overview)

        // Go zero time must be ignored
        let zeroSeen = try decode([RemoteProvider].self, #"[{"id":"p","name":"P","account":{"agent":"p","logins":[{"agent":"p","user":"u@x.com","lapsed":"expired","seen":"0001-01-01T00:00:00Z"}]}}]"#)
        let zeroAgg = AccountErrorAggregator.aggregate(providers: zeroSeen)
        precondition(zeroAgg.count == 1 && zeroAgg[0].lastFailureAt == nil)

        // Phase 2: UsageDateRange formatting & normalization
        let tz = TimeZone(identifier: "Asia/Shanghai")!
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = tz
        fmt.dateFormat = "yyyy-MM-dd"
        let d1 = fmt.date(from: "2026-11-10")!
        let d2 = fmt.date(from: "2026-11-17")!
        let normalRange = UsageDateRange(startDate: d1, endDate: d2)
        precondition(normalRange.apiPeriodString(timeZone: tz) == "2026-11-10..2026-11-17")
        precondition(normalRange.displayLabel(timeZone: tz) == "2026-11-10 至 2026-11-17")
        let reversedRange = UsageDateRange(startDate: d2, endDate: d1)
        precondition(reversedRange.normalized(timeZone: tz).wasSwapped == true)
        precondition(reversedRange.apiPeriodString(timeZone: tz) == "2026-11-10..2026-11-17")
        let singleDay = UsageDateRange(startDate: d2, endDate: d2)
        precondition(singleDay.apiPeriodString(timeZone: tz) == "2026-11-17..2026-11-17")
        precondition(singleDay.displayLabel(timeZone: tz) == "2026-11-17 当天")

        // Phase 3: QuotaAlertConfig, QuotaAlertEvaluator, QuotaNotificationDeduplicator
        var alertCfg = QuotaAlertConfig()
        precondition(alertCfg.defaultRemainingThresholdPercent == 10)
        alertCfg.setProviderThreshold(25, providerID: "antigravity")
        alertCfg.setAccountThreshold(15, providerID: "antigravity", user: "a@gmail.com")
        precondition(alertCfg.effectiveThreshold(providerID: "antigravity", user: "a@gmail.com") == 15)
        precondition(alertCfg.effectiveThreshold(providerID: "antigravity", user: "b@gmail.com") == 25)
        precondition(alertCfg.effectiveThreshold(providerID: "codex", user: "c@gmail.com") == 10)
        alertCfg.setMuted(true, providerID: "codex", user: "muted@gmail.com")
        precondition(alertCfg.isMuted(providerID: "codex", user: "muted@gmail.com"))

        let alertProviders = try decode([RemoteProvider].self, #"[{"id":"antigravity","name":"Antigravity","routing":"order","account":{"agent":"antigravity","user":"a@gmail.com","logins":[{"agent":"antigravity","user":"a@gmail.com","active":true,"on":true},{"agent":"antigravity","user":"b@gmail.com","active":false,"on":true}]},"accountRests":{"a@gmail.com":[{"why":"rate","status":429,"key":"antigravity#a@gmail.com"}]}}]"#)
        let alertLoginUsage = try decode([String: [String: RemoteLoginQuota]].self, #"{"antigravity":{"a@gmail.com":{"provider":"antigravity","name":"Antigravity","icon":"antigravity-color","user":"a@gmail.com","windows":[{"name":"Gemini 2.5 Flash","used":92.0,"resetsAt":"2026-11-18T12:00:00Z"},{"name":"Gemini 3 Flash","used":92.0,"resetsAt":"2026-11-18T12:00:00Z"},{"name":"5 hours","used":92.0,"capId":"5h","resetsAt":"2026-11-18T12:00:00Z"},{"name":"Unlimited Extra","used":99.0,"unlimited":true}]},"b@gmail.com":{"provider":"antigravity","name":"Antigravity","icon":"antigravity-color","user":"b@gmail.com","windows":[{"name":"5 hours","used":15.0,"capId":"5h"}]}}}"#)

        let evaluatedAlerts = QuotaAlertEvaluator.evaluate(
            providers: alertProviders,
            quotas: [],
            loginUsageByAgent: alertLoginUsage,
            config: alertCfg
        )
        // Multiple model windows on a@gmail.com aggregate into 1 representative alert ("5 hours", 3 low windows), unlimited ignored
        precondition(evaluatedAlerts.count == 1, "Expected 1 aggregated alert, got \(evaluatedAlerts.count)")
        precondition(evaluatedAlerts[0].accountUser == "a@gmail.com")
        precondition(evaluatedAlerts[0].windowName == "5 hours" && evaluatedAlerts[0].affectedWindowCount == 3)
        precondition(abs(evaluatedAlerts[0].remainingPercent - 8.0) < 0.01)
        precondition(evaluatedAlerts[0].recommendedSwitchUser == "b@gmail.com")

        let providerSummaries = QuotaAlertEvaluator.summarizeByProvider(items: evaluatedAlerts, providers: alertProviders, config: alertCfg)
        precondition(providerSummaries.count == 1 && providerSummaries[0].alertingAccountCount == 1)

        // Notification deduplication & hysteresis recovery
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let dRes1 = QuotaNotificationDeduplicator.filterItemsToNotify(items: evaluatedAlerts, history: [:], now: t0, cooldownMinutes: 240)
        precondition(dRes1.toNotify.count == 1)
        let dRes2 = QuotaNotificationDeduplicator.filterItemsToNotify(items: evaluatedAlerts, history: dRes1.updatedHistory, now: t0.addingTimeInterval(600), cooldownMinutes: 240)
        precondition(dRes2.toNotify.isEmpty, "Same reset cycle within cooldown must deduplicate")
        let dResRecovered = QuotaNotificationDeduplicator.filterItemsToNotify(items: [], history: dRes2.updatedHistory, now: t0.addingTimeInterval(1200), cooldownMinutes: 240)
        precondition(dResRecovered.updatedHistory.isEmpty, "Resolved alerts must clear dedup history")

        // Phase 3: AccountSwitchPlanner (subscription & multi-key)
        let switchProviders = try decode([RemoteProvider].self, #"[{"id":"antigravity","name":"Antigravity","routing":"order","account":{"agent":"antigravity","user":"cool@gmail.com","logins":[{"agent":"antigravity","user":"cool@gmail.com","active":true,"on":true},{"agent":"antigravity","user":"lapsed@gmail.com","active":false,"on":true,"lapsed":"expired"},{"agent":"antigravity","user":"low@gmail.com","active":false,"on":true},{"agent":"antigravity","user":"best@gmail.com","active":false,"on":true}]},"accountRests":{"cool@gmail.com":[{"why":"rate","status":429}]}},{"id":"custom","name":"Custom KeyPool","keyList":[{"id":"k1","name":"Primary","masked":"sk-1","active":true,"on":true,"rest":{"why":"rate","status":429}},{"id":"k2","name":"Disabled","masked":"sk-2","active":false,"on":false},{"id":"k3","name":"HealthyBackup","masked":"sk-3","active":false,"on":true,"weight":2}]}]"#)
        let switchUsage = try decode([String: [String: RemoteLoginQuota]].self, #"{"antigravity":{"low@gmail.com":{"provider":"antigravity","name":"Antigravity","icon":"","user":"low@gmail.com","windows":[{"name":"5h","used":85.0}]},"best@gmail.com":{"provider":"antigravity","name":"Antigravity","icon":"","user":"best@gmail.com","windows":[{"name":"5h","used":12.0}]}}}"#)
        let subPlan = AccountSwitchPlanner.plan(for: switchProviders[0], sourceAccountOrKeyID: "cool@gmail.com", loginUsageByAgent: switchUsage)!
        precondition(subPlan.recommended?.id == "best@gmail.com", "Best remaining quota candidate must be recommended first")
        precondition(subPlan.candidates.count == 2 && subPlan.unavailableReasons.count == 1)

        let keyPlan = AccountSwitchPlanner.plan(for: switchProviders[1], sourceAccountOrKeyID: "k1")!
        precondition(keyPlan.recommended?.id == "k3" && keyPlan.unavailableReasons.count == 1)

        // Phase 3: Privacy masking, DeepLink parsing, Widget Snapshot
        precondition(WidgetPrivacyMasker.maskAccountLabel("xiaomosheng66666@gmail.com") == "xi***66@gmail.com")
        precondition(WidgetPrivacyMasker.maskAccountLabel("ab@x.com") == "a***@x.com")
        precondition(WidgetPrivacyMasker.maskAccountLabel("sk-1234567890abcdef") == "sk-1···cdef")
        precondition(WidgetPrivacyMasker.sanitizeServerTitle(name: nil, baseURL: "https://magpie.163ll.com:3430/?k=secret123") == "magpie.163ll.com:3430")

        precondition(MagpieDeepLink.parse(URL(string: "magpie://usage")!) == .usage)
        precondition(MagpieDeepLink.parse(URL(string: "magpie://alerts")!) == .alerts)
        precondition(MagpieDeepLink.parse(URL(string: "magpie://refresh")!) == .refresh)
        precondition(MagpieDeepLink.parse(URL(string: "magpie://providers?id=antigravity&account=xi***66@gmail.com")!) == .providers(providerID: "antigravity", accountHint: "xi***66@gmail.com"))

        let sampleUsage = try decode(RemoteUsageResponse.self, #"{"calls":88,"errors":1,"input":1000,"output":500,"cost":1.25,"bucket":"hour"}"#)
        let snap = MagpieWidgetSnapshotStore.buildSnapshot(
            isConfigured: true,
            isConnected: true,
            serverName: "生产网关",
            serverBaseURL: "https://magpie.163ll.com/?k=DO_NOT_LEAK",
            todayUsage: sampleUsage,
            providers: alertProviders,
            quotas: [],
            loginUsageByAgent: alertLoginUsage,
            alerts: evaluatedAlerts,
            alertThresholdPercent: 10,
            now: t0
        )
        let snapData = try JSONEncoder().encode(snap)
        let snapJSON = String(data: snapData, encoding: .utf8)!
        precondition(!snapJSON.contains("DO_NOT_LEAK"), "Widget snapshot must never contain webKey")
        precondition(!snapJSON.contains("a@gmail.com"), "Widget snapshot must mask raw email addresses")
        precondition(snap.alertCount == 1 && snap.todayCalls == 88 && !snap.isStale(relativeTo: t0.addingTimeInterval(600)))
        precondition(snap.isStale(relativeTo: t0.addingTimeInterval(9000)))

        print("PASS: Phase 3 quota alerts, notification dedup, quick-switch planner & widget snapshot contracts")
        print("PASS: Phase 2 error aggregation & custom usage date range contracts")
        print("PASS: OAuth callback normalization, http-only + port/path preflight & real 400 mapping")
        print("PASS: OAuth sign-in, 19+ platform catalog, plugin prompts, multi-account logins & usage")
        print("PASS: origins, console routes, preserved provider fields, caller budgets")
        print("PASS: routing conditions, shared agent options, group disabled/off compatibility, numeric balance")
        print("PASS: proxies, autobackup, davsync, context tune, model price snake_case keys, and port wrapper")
    }
}
