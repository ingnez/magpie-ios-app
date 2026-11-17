import XCTest

final class MagpieScreenshotTests: XCTestCase {
    private var fixture: FixtureHTTPServer?
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDown() {
        if let requests = fixture?.requests(), let data = try? JSONSerialization.data(withJSONObject: requests) {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = "UI API requests"; attachment.lifetime = .keepAlways; add(attachment)
        }
        if let trace = fixture?.trace(), let data = try? JSONSerialization.data(withJSONObject: trace) {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = "UI HTTP trace"; attachment.lifetime = .keepAlways; add(attachment)
        }
        if (testRun?.failureCount ?? 0) > 0 {
            let attachment = XCTAttachment(string: XCUIApplication().debugDescription)
            attachment.name = "UI failure hierarchy"; attachment.lifetime = .keepAlways; add(attachment)
        }
        fixture?.stop(); fixture = nil; super.tearDown()
    }
    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    private func tap(_ title: String, app: XCUIApplication, scroll: Bool = false) {
        let matches = app.buttons.matching(identifier: title)
        if !scroll {
            XCTAssertTrue(matches.firstMatch.waitForExistence(timeout: 10), "Missing button: \(title)")
        } else {
            _ = matches.firstMatch.waitForExistence(timeout: 2)
        }
        func visible(_ button: XCUIElement) -> Bool {
            guard button.exists && button.isEnabled else { return false }
            let frame = button.frame
            guard !frame.isEmpty && app.frame.contains(frame) else { return false }
            if scroll && app.buttons["tab.home"].isHittable && app.scrollViews.firstMatch.exists {
                return app.scrollViews.firstMatch.frame.insetBy(dx: 0, dy: 8).contains(frame)
            }
            return true
        }
        if scroll {
            let scroller = app.scrollViews.allElementsBoundByIndex.filter { $0.exists && $0.frame.height > 180 }.last ?? app.scrollViews.firstMatch
            for _ in 0..<18 {
                if matches.allElementsBoundByIndex.contains(where: visible) { break }
                let target = matches.allElementsBoundByIndex.first(where: { !$0.frame.isEmpty }) ?? matches.firstMatch
                let midY = target.exists ? target.frame.midY : app.frame.midY
                let topBound = scroller.exists ? scroller.frame.minY + 12 : app.frame.midY
                if scroller.exists {
                    let start = scroller.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: (target.exists && !target.frame.isEmpty && midY < topBound) ? 0.32 : 0.72))
                    let end = scroller.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: (target.exists && !target.frame.isEmpty && midY < topBound) ? 0.72 : 0.32))
                    start.press(forDuration: 0.03, thenDragTo: end)
                } else if target.exists && !target.frame.isEmpty && midY < app.frame.midY {
                    app.swipeDown()
                } else {
                    app.swipeUp()
                }
            }
            XCTAssertTrue(matches.firstMatch.waitForExistence(timeout: 10), "Missing button after scroll: \(title)")
        }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            matches.allElementsBoundByIndex.contains(where: visible)
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed, "No enabled visible button: \(title)")
        // Sheets expose covered controls too; the last visible match is topmost.
        guard let button = matches.allElementsBoundByIndex.reversed().first(where: visible) else {
            XCTFail("Button disappeared: \(title)"); return
        }
        if button.isHittable { button.tap() }
        else {
            XCTAssertFalse(app.alerts.firstMatch.exists, "Unexpected alert over \(title)")
            button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }
    private func tab(_ id: String, app: XCUIApplication) { tap("tab.\(id)", app: app) }

    func testCaptureAllTabs() throws {
        let server = try FixtureHTTPServer()
        fixture = server
        func payload(_ path: String) -> [String: Any] {
            let row = server.requests().last { $0["path"] as? String == path }
            XCTAssertNotNil(row, "UI must call \(path)")
            return row?["body"] as? [String: Any] ?? [:]
        }
        let app = XCUIApplication()
        app.launch()
        tap("连接 magpie web", app: app)
        let name = app.textFields["例如：家里 NAS / 云服务器"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("演示实例 · 本地测试数据")
        let address = app.textFields["https://your-host:3430/?k=..."]
        address.tap(); address.typeText("http://127.0.0.1:\(server.port)/?k=fixture-only-not-a-real-key")
        shot("01-server-editor-demo")
        tap("保存并连接", app: app)
        XCTAssertTrue(app.staticTexts["1 模型在线"].waitForExistence(timeout: 20))
        shot("02-dashboard-demo")

        tap("Agents 与方案", app: app)
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Claude Code 演示")).firstMatch.waitForExistence(timeout: 10))
        shot("03-agents-and-profiles-demo")
        app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Claude Code 演示")).firstMatch.tap()
        XCTAssertTrue(app.buttons["管理客户端可见模型"].waitForExistence(timeout: 5))
        shot("04-agent-detail-demo")
        tap("关闭", app: app); tap("关闭", app: app)

        tab("providers", app: app)
        let firstManage = app.buttons.matching(identifier: "管理").element(boundBy: 0)
        XCTAssertTrue(firstManage.waitForExistence(timeout: 10), "Missing first 管理 button")
        firstManage.tap()
        shot("05-provider-policy-demo")
        tap("多 Key 号池", app: app)
        shot("06-provider-multikey-demo")
        tap("模型管理", app: app)
        shot("07-provider-models-demo")
        tap("全选", app: app)
        tap("保存选择", app: app, scroll: true)
        tap("高级配置", app: app)
        shot("08-provider-advanced-demo")
        tap("关闭", app: app)
        tap("路由组", app: app)
        shot("09-groups-demo")
        tap("编辑", app: app)
        shot("10-group-editor-demo")
        tap("分流规则", app: app)
        shot("11-group-rules-demo")
        tap("保存", app: app)
        XCTAssertTrue(app.buttons["复制"].waitForExistence(timeout: 10))
        tap("复制", app: app)
        XCTAssertEqual(app.textFields["副本名称"].value as? String, "编程组演示 副本")
        XCTAssertTrue(app.buttons["创建副本"].isEnabled, "The prefilled copy name must enable creation on first presentation")
        shot("12-copy-group-demo")
        tap("创建副本", app: app)
        let copied = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !app.textFields["副本名称"].exists
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [copied], timeout: 15), .completed)

        tab("usage", app: app)
        XCTAssertTrue(app.staticTexts["用量趋势"].waitForExistence(timeout: 10))
        shot("13-usage-trend-demo")
        tap("签到与热身", app: app)
        shot("14-checkin-warmup-demo")
        tap("关闭", app: app)

        tab("privacy", app: app)
        tap("Caller Keys 管理", app: app, scroll: true)
        XCTAssertTrue(app.staticTexts["移动端演示"].waitForExistence(timeout: 10))
        shot("15-caller-keys-demo")
        tap("编辑名称、模型权限与预算", app: app)
        let budgetSwitch = app.switches["修改额度规则"]
        XCTAssertTrue(budgetSwitch.waitForExistence(timeout: 5))
        budgetSwitch.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertTrue(app.textFields["Token 上限（0 为不限）"].waitForExistence(timeout: 10), "Budget controls must actually open before saving")
        shot("16-caller-key-editor-demo")
        tap("保存", app: app)
        tap("关闭", app: app)
        let requests = server.requests()
        let budget = payload("/api/caller-keys/limit-key")["limit"] as? [String: Any]
        XCTAssertEqual(budget?["tokens"] as? Int, 1000000)
        XCTAssertEqual(budget?["period"] as? String, "week")
        let limitIndex = try XCTUnwrap(requests.firstIndex { $0["path"] as? String == "/api/caller-keys/limit-key" })
        let accessIndex = try XCTUnwrap(requests.firstIndex { $0["path"] as? String == "/api/caller-keys/access-key" })
        XCTAssertLessThan(limitIndex, accessIndex, "Budget must be applied before granting caller access")
        tap("正则与敏感词", app: app, scroll: true)
        shot("17-masking-rules-demo")
        tap("关闭", app: app)

        tap("代理池与网络配置", app: app, scroll: true)
        XCTAssertTrue(app.staticTexts["香港节点演示"].waitForExistence(timeout: 10))
        shot("21-native-proxies-manager-demo")
        tap("保存代理分流设置", app: app)
        tap("关闭", app: app)

        tap("备份与云同步管理", app: app, scroll: true)
        XCTAssertTrue(app.buttons["立即同步"].waitForExistence(timeout: 10))
        shot("22-native-backup-davsync-demo")
        tap("立即同步", app: app, scroll: true)
        tap("关闭", app: app)

        tap("上下文与缓存调优", app: app, scroll: true)
        XCTAssertTrue(app.buttons["应用推荐值 (160000)"].waitForExistence(timeout: 10))
        shot("23-native-context-tune-demo")
        tap("应用推荐值 (160000)", app: app)
        tap("关闭", app: app)

        tap("系统通用与告警设置", app: app, scroll: true)
        XCTAssertTrue(app.buttons["保存通用与显示设置"].waitForExistence(timeout: 10))
        shot("24-native-system-settings-demo")
        tap("保存通用与显示设置", app: app, scroll: true)
        tap("关闭", app: app)

        tap("模型自定义定价", app: app, scroll: true)
        XCTAssertTrue(app.buttons["保存自定义定价"].waitForExistence(timeout: 10))
        shot("25-native-model-price-demo")
        tap("保存自定义定价", app: app, scroll: true)
        tap("关闭", app: app)

        tap("查看前后对照", app: app, scroll: true)
        XCTAssertTrue(app.buttons["显示脱敏前对照"].waitForExistence(timeout: 10))
        tap("显示脱敏前对照", app: app)
        XCTAssertTrue(app.staticTexts["联系 demo@example.invalid"].waitForExistence(timeout: 10))
        shot("18-masking-comparison-demo")
        tap("关闭", app: app)
        tap("Sessions", app: app, scroll: true)
        XCTAssertTrue(app.webViews.staticTexts["Cookie 会话验证通过"].waitForExistence(timeout: 60))
        shot("19-console-cookie-integration-demo")
        tap("关闭", app: app)
        tap("上下文调优", app: app, scroll: true)
        XCTAssertTrue(app.webViews.staticTexts["上下文页签选择通过"].waitForExistence(timeout: 60))
        shot("20-console-context-selection-demo")
        tap("关闭", app: app)
        tab("providers", app: app)
        try exerciseOAuthAccounts(app: app, server: server)

        let demoProviderSave = server.requests().last {
            ($0["path"] as? String == "/api/provider/save") &&
            (($0["body"] as? [String: Any])?["id"] as? String == "demo")
        }
        let provider = (demoProviderSave?["body"] as? [String: Any]) ?? [:]
        XCTAssertEqual((provider["headers"] as? [String: String])?["X-Project"], "test")
        XCTAssertEqual(provider["models"] as? [String], ["gpt-demo"])
        XCTAssertEqual((provider["contexts"] as? [String: Int])?["gpt-demo"], 128000)
        let group = payload("/api/groups/save")
        XCTAssertNotNil((group["rules"] as? [[String: Any]])?.first?["where"])
        XCTAssertEqual(payload("/api/groups/copy")["id"] as? String, "coding")
        XCTAssertEqual(payload("/api/groups/copy")["name"] as? String, "编程组演示 副本")
        XCTAssertEqual(payload("/api/masking/values")["ps"] as? [String], ["{{EMAIL_demo}}"])
        XCTAssertNotNil(server.requests().last { $0["path"] as? String == "/api/davsync/now" })
        XCTAssertEqual(payload("/api/tune/apply")["value"] as? String, "160000")
        XCTAssertEqual(payload("/api/model-price")["model"] as? String, "gpt-demo")
        XCTAssertEqual((payload("/api/model-price")["price"] as? [String: Any])?["cache_read"] as? Double, 0.25)
        XCTAssertTrue(
            server.requests().contains {
                ($0["path"] as? String == "/api/settings") &&
                (($0["body"] as? [String: Any])?["proxy"] as? String == "@px-hk")
            },
            "Missing proxy routing POST /api/settings"
        )
        XCTAssertTrue(
            server.requests().contains {
                ($0["path"] as? String == "/api/settings") &&
                (($0["body"] as? [String: Any])?["theme"] != nil)
            },
            "Missing general settings POST /api/settings"
        )
    }

    func testCaptureOAuthAccounts() throws {
        let server = try FixtureHTTPServer()
        fixture = server
        let app = XCUIApplication()
        app.launch()
        tap("连接 magpie web", app: app)
        let name = app.textFields["例如：家里 NAS / 云服务器"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("OAuth 演示实例")
        let address = app.textFields["https://your-host:3430/?k=..."]
        address.tap(); address.typeText("http://127.0.0.1:\(server.port)/?k=fixture-only-not-a-real-key")
        tap("保存并连接", app: app)
        XCTAssertTrue(app.staticTexts["1 模型在线"].waitForExistence(timeout: 20))
        tab("providers", app: app)
        try exerciseOAuthAccounts(app: app, server: server)

        // Verify callback URL normalization, local Chinese validation & HTTP 400 mapping
        let countBefore = server.requests().filter { $0["path"] as? String == "/api/signin/s1/callback" }.count
        tap("OAuth 授权", app: app)
        XCTAssertTrue(app.staticTexts["Antigravity (谷歌反重力)"].waitForExistence(timeout: 10))
        app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Antigravity (谷歌反重力)")).firstMatch.tap()
        if app.buttons["仍然继续授权"].waitForExistence(timeout: 2) {
            tap("仍然继续授权", app: app)
        }
        tap("startOAuthButton", app: app, scroll: true)
        XCTAssertTrue(app.buttons["提交并完成登录"].waitForExistence(timeout: 10))

        func submitAndExpectLocalBlock(input: String, normalizedExpected: String? = nil, fragment: String) {
            let field = app.textFields["oauthCallbackField"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            for _ in 0..<6 where !field.isHittable { app.swipeUp() }
            field.tap()
            field.typeText(input)
            tap("收起键盘", app: app)
            tap("提交并完成登录", app: app, scroll: true)
            if let normalizedExpected {
                XCTAssertEqual(field.value as? String, normalizedExpected)
            }
            XCTAssertTrue(
                app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch.waitForExistence(timeout: 5),
                "Expected local validation fragment: \(fragment)"
            )
            XCTAssertEqual(
                server.requests().filter { $0["path"] as? String == "/api/signin/s1/callback" }.count,
                countBefore,
                "Blocked callback URL (\(input)) must not send a request"
            )
            tap("取消登录", app: app, scroll: true)
            tap("startOAuthButton", app: app, scroll: true)
            XCTAssertTrue(app.buttons["提交并完成登录"].waitForExistence(timeout: 10))
        }

        // 1a) Missing scheme & missing path -> normalizes http:// into field, blocks locally
        submitAndExpectLocalBlock(
            input: "localhost:54321",
            normalizedExpected: "http://localhost:54321",
            fragment: "缺少回调路径"
        )
        // 1b) https:// scheme -> rejected because backend only accepts http://
        submitAndExpectLocalBlock(
            input: "https://127.0.0.1:54321/callback?code=1&state=s1",
            fragment: "只支持 http://"
        )
        // 1c) Port mismatch preflight -> blocked locally before HTTP
        submitAndExpectLocalBlock(
            input: "127.0.0.1:13035/callback?code=1&state=s1",
            fragment: "回调端口不匹配"
        )
        // 1d) Path mismatch preflight -> blocked locally before HTTP
        submitAndExpectLocalBlock(
            input: "127.0.0.1:54321/wrong-path?code=1&state=s1",
            fragment: "回调路径不匹配"
        )

        // 2) Server HTTP 400 (real backend message) -> Chinese mapping + collapsible original English detail
        let cbField400 = app.textFields["oauthCallbackField"]
        XCTAssertTrue(cbField400.waitForExistence(timeout: 5))
        for _ in 0..<6 where !cbField400.isHittable { app.swipeUp() }
        cbField400.tap()
        cbField400.typeText("127.0.0.1:54321/callback?state=trigger-400")
        tap("收起键盘", app: app)
        tap("提交并完成登录", app: app, scroll: true)
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "不属于当前这次登录会话")).firstMatch.waitForExistence(timeout: 10),
            "Expected Chinese mapped 400 error message"
        )
        tap("查看原文细节", app: app, scroll: true)
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "that address isn't from this sign-in")).firstMatch.waitForExistence(timeout: 5),
            "Expected collapsible raw 400 detail"
        )
        shot("29-oauth-callback-400-mapped-demo")

        // 3) Missing http:// on valid localhost callback matching port & path -> auto-prefixed & submitted
        tap("取消登录", app: app, scroll: true)
        tap("startOAuthButton", app: app, scroll: true)
        XCTAssertTrue(app.buttons["提交并完成登录"].waitForExistence(timeout: 10))
        let cbFieldNorm = app.textFields["oauthCallbackField"]
        XCTAssertTrue(cbFieldNorm.waitForExistence(timeout: 5))
        for _ in 0..<6 where !cbFieldNorm.isHittable { app.swipeUp() }
        cbFieldNorm.tap()
        cbFieldNorm.typeText("localhost:54321/callback?code=demo-code&state=LU")
        tap("收起键盘", app: app)
        tap("提交并完成登录", app: app, scroll: true)
        XCTAssertTrue(app.staticTexts["demo4@gmail.com"].waitForExistence(timeout: 10))
        let lastCallback = server.requests().last { $0["path"] as? String == "/api/signin/s1/callback" }
        XCTAssertEqual(
            (lastCallback?["body"] as? [String: Any])?["url"] as? String,
            "http://localhost:54321/callback?code=demo-code&state=LU",
            "Client must prepend http:// to localhost callback before submitting"
        )
        tap("完成并返回", app: app)
    }


    func testCapturePhase2DarkAndFeatures() throws {
        let server = try FixtureHTTPServer()
        fixture = server
        let app = XCUIApplication()
        app.launchArguments = ["-magpie-dark-mode"]
        app.launch()

        tap("连接 magpie web", app: app)
        let name = app.textFields["例如：家里 NAS / 云服务器"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("深色与二期演示")
        let address = app.textFields["https://your-host:3430/?k=..."]
        address.tap(); address.typeText("http://127.0.0.1:\(server.port)/?k=fixture-only-not-a-real-key")
        tap("保存并连接", app: app)
        XCTAssertTrue(app.staticTexts["1 模型在线"].waitForExistence(timeout: 20))
        shot("30-dark-dashboard-demo")

        // Open Error Overview from Dashboard
        tap("dashboardAccountErrorsButton", app: app)
        XCTAssertTrue(app.staticTexts["账号异常总览"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["expired-codex@example.com"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["demo2@gmail.com"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["连续失败 3 次"].waitForExistence(timeout: 5))
        shot("31-dark-account-errors-demo")

        // Click demo2@gmail.com -> jumps straight to Providers -> ProviderDetailSheet -> 多账号号池 -> demo2@gmail.com
        tap("errorAccountRow_demo2@gmail.com", app: app, scroll: true)
        let detailScroller = app.scrollViews["providerDetailScrollView"]
        XCTAssertTrue(detailScroller.waitForExistence(timeout: 10))
        XCTAssertTrue(detailScroller.staticTexts["accountTitle_demo2@gmail.com"].waitForExistence(timeout: 10))
        shot("32-dark-account-pool-jump-demo")
        tap("关闭", app: app)

        // Providers view in Dark Mode
        XCTAssertTrue(app.staticTexts["供应商号池"].waitForExistence(timeout: 5))
        shot("33-dark-providers-demo")

        // OAuth Sign-In sheet in Dark Mode
        tap("OAuth 授权", app: app)
        XCTAssertTrue(app.staticTexts["Antigravity (谷歌反重力)"].waitForExistence(timeout: 10))
        app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Antigravity (谷歌反重力)")).firstMatch.tap()
        if app.buttons["仍然继续授权"].waitForExistence(timeout: 2) {
            tap("仍然继续授权", app: app)
        }
        tap("startOAuthButton", app: app, scroll: true)
        XCTAssertTrue(app.buttons["提交并完成登录"].waitForExistence(timeout: 10))
        shot("34-dark-oauth-signin-demo")
        tap("取消登录", app: app, scroll: true)
        tap("关闭", app: app)

        // Usage page in Dark Mode + Custom Date Range + Empty State
        tab("usage", app: app)
        XCTAssertTrue(app.staticTexts["用量趋势"].waitForExistence(timeout: 10))
        shot("35-dark-usage-today-demo")

        tap("usagePeriod_custom", app: app)
        XCTAssertTrue(app.buttons["applyCustomUsageRangeButton"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["42"].waitForExistence(timeout: 10))
        shot("36-dark-usage-custom-range-demo")

        tap("上月", app: app)
        XCTAssertTrue(app.staticTexts["所选区间暂无用量记录"].waitForExistence(timeout: 10))
        shot("37-dark-usage-custom-empty-demo")

        let customUsageCalled = server.trace().contains { row in
            (row["path"] as? String == "/api/usage") &&
            ((row["query"] as? String ?? "").contains(".."))
        }
        XCTAssertTrue(customUsageCalled, "Custom usage period must query /api/usage?period=YYYY-MM-DD..YYYY-MM-DD")
    }

    private func exerciseOAuthAccounts(app: XCUIApplication, server: FixtureHTTPServer) throws {
        func payload(_ path: String) -> [String: Any] {
            let row = server.requests().last { $0["path"] as? String == path }
            XCTAssertNotNil(row, "UI must call \(path)")
            return row?["body"] as? [String: Any] ?? [:]
        }
        tap("OAuth 授权", app: app)
        XCTAssertTrue(app.staticTexts["Antigravity (谷歌反重力)"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["ChatGPT (Codex)"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Claude"].waitForExistence(timeout: 5))
        shot("26-oauth-platforms-demo")
        app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Antigravity (谷歌反重力)")).firstMatch.tap()
        if app.buttons["仍然继续授权"].waitForExistence(timeout: 2) {
            tap("仍然继续授权", app: app)
        }
        XCTAssertTrue(app.staticTexts["2 个账号"].waitForExistence(timeout: 5))
        tap("startOAuthButton", app: app, scroll: true)
        XCTAssertTrue(app.buttons["提交并完成登录"].waitForExistence(timeout: 10))
        shot("27-antigravity-oauth-demo")
        let cbField = app.textFields["oauthCallbackField"]
        XCTAssertTrue(cbField.waitForExistence(timeout: 5))
        for _ in 0..<6 where !cbField.isHittable { app.swipeUp() }
        cbField.tap()
        cbField.typeText("http://127.0.0.1:54321/callback?code=demo-code&state=s1")
        tap("收起键盘", app: app)
        tap("提交并完成登录", app: app, scroll: true)
        XCTAssertTrue(app.staticTexts["demo3@gmail.com"].waitForExistence(timeout: 10))

        // Repeat OAuth addition without overwriting existing accounts -> add 4th account
        tap("继续添加下一个账号", app: app, scroll: true)
        XCTAssertTrue(app.staticTexts["3 个账号"].waitForExistence(timeout: 10))
        tap("startOAuthButton", app: app, scroll: true)
        XCTAssertTrue(app.buttons["提交并完成登录"].waitForExistence(timeout: 10))
        let cbField2 = app.textFields["oauthCallbackField"]
        XCTAssertTrue(cbField2.waitForExistence(timeout: 5))
        for _ in 0..<6 where !cbField2.isHittable { app.swipeUp() }
        cbField2.tap()
        cbField2.typeText("http://127.0.0.1:54321/callback?code=demo-code-2&state=s1")
        tap("收起键盘", app: app)
        tap("提交并完成登录", app: app, scroll: true)
        XCTAssertTrue(app.staticTexts["demo4@gmail.com"].waitForExistence(timeout: 10))
        tap("完成并返回", app: app)

        let manageButtons = app.buttons.matching(identifier: "管理")
        XCTAssertGreaterThan(manageButtons.count, 1, "Expected second provider (Antigravity)")
        let agyManage = manageButtons.element(boundBy: 1)
        for _ in 0..<4 where !agyManage.isHittable { app.swipeUp() }
        if agyManage.isHittable { agyManage.tap() } else { agyManage.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        tap("多账号号池", app: app)

        // All 4 accounts + refreshed login usage
        XCTAssertTrue(app.staticTexts["demo1@gmail.com"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["demo2@gmail.com"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["demo3@gmail.com"].waitForExistence(timeout: 5))
        let scroller = app.scrollViews["providerDetailScrollView"]
        XCTAssertTrue(scroller.waitForExistence(timeout: 5))
        for _ in 0..<4 where !scroller.staticTexts["accountTitle_demo4@gmail.com"].exists { scroller.swipeUp() }
        XCTAssertTrue(scroller.staticTexts["accountTitle_demo4@gmail.com"].waitForExistence(timeout: 5))

        // Scroll back to top of account pool
        for _ in 0..<4 where !app.buttons["configureMaxAccountsButton"].isHittable { scroller.swipeDown() }

        // Test maxAccounts limit (2) -> exceeded warning + reserve status, then reset to null (unlimited)
        let cfgBtn = app.buttons["configureMaxAccountsButton"]
        for _ in 0..<5 where !cfgBtn.isHittable { scroller.swipeDown() }
        cfgBtn.tap()
        let limitField = app.textFields["maxAccountsLimitField"]
        XCTAssertTrue(limitField.waitForExistence(timeout: 5))
        limitField.tap()
        limitField.typeText("2")
        tap("收起键盘", app: app)
        tap("saveMaxAccountsButton", app: app)
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "已超出同时启用上限（2 个）")).firstMatch.waitForExistence(timeout: 10),
            "Expected exceeded maxAccounts warning banner"
        )
        XCTAssertTrue(app.staticTexts["候补顺延"].waitForExistence(timeout: 5))

        for _ in 0..<5 where !cfgBtn.isHittable { scroller.swipeDown() }
        cfgBtn.tap()
        tap("不限 (null)", app: app)
        tap("saveMaxAccountsButton", app: app)
        let capCleared = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count == 0"),
            object: app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "已超出同时启用上限"))
        )
        XCTAssertEqual(XCTWaiter.wait(for: [capCleared], timeout: 10), .completed)

        // Test weight setting on 3rd account (demo3@gmail.com)
        let settingsButtons = scroller.buttons.matching(identifier: "设置")
        XCTAssertGreaterThanOrEqual(settingsButtons.count, 3)
        let thirdSettings = settingsButtons.element(boundBy: 2)
        for _ in 0..<4 where !thirdSettings.isHittable { scroller.swipeUp() }
        thirdSettings.tap()
        XCTAssertTrue(app.buttons["3x"].waitForExistence(timeout: 5))
        tap("3x", app: app)
        tap("保存权重", app: app)
        tap("关闭", app: app)
        XCTAssertTrue(app.staticTexts["权重 3"].waitForExistence(timeout: 10))

        // Test enable/disable toggle on 4th account (demo4@gmail.com)
        let toggle4 = app.buttons["accountToggle_demo4@gmail.com"]
        for _ in 0..<6 where !toggle4.isHittable { scroller.swipeUp() }
        XCTAssertTrue(toggle4.waitForExistence(timeout: 5))
        toggle4.tap()
        XCTAssertTrue(app.staticTexts["已停用"].waitForExistence(timeout: 10))
        for _ in 0..<6 where !toggle4.isHittable { scroller.swipeUp() }
        toggle4.tap()
        let reEnabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count == 0"),
            object: app.staticTexts.matching(identifier: "已停用")
        )
        XCTAssertEqual(XCTWaiter.wait(for: [reEnabled], timeout: 10), .completed)

        // Switch routing to Rotate & lift rest, then ensure 3+ accounts visible on screen for screenshot
        tap("Rotate 逐轮轮询", app: app, scroll: true)
        XCTAssertTrue(app.staticTexts.matching(identifier: "参与轮询").firstMatch.waitForExistence(timeout: 10))
        if app.buttons["解除冷却"].waitForExistence(timeout: 5) {
            tap("解除冷却", app: app, scroll: true)
            let unrestDone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["解除冷却"])
            XCTAssertEqual(XCTWaiter.wait(for: [unrestDone], timeout: 10), .completed)
        }
        func accountVisible(_ email: String) -> Bool {
            let el = scroller.staticTexts["accountTitle_\(email)"]
            return el.exists && el.isHittable
        }
        for _ in 0..<5 where !accountVisible("demo1@gmail.com") { scroller.swipeDown() }
        XCTAssertTrue(accountVisible("demo1@gmail.com"))
        XCTAssertTrue(accountVisible("demo2@gmail.com"))
        XCTAssertTrue(accountVisible("demo3@gmail.com"))
        shot("28-subscription-multi-account-demo")

        // Verify removing 4th account via alert confirmation
        let removeButtons = scroller.buttons.matching(identifier: "移除")
        XCTAssertGreaterThanOrEqual(removeButtons.count, 4)
        let fourthRemove = removeButtons.element(boundBy: 3)
        for _ in 0..<4 where !fourthRemove.isHittable { scroller.swipeUp() }
        fourthRemove.tap()
        let alertRemove = app.alerts.buttons["移除"]
        XCTAssertTrue(alertRemove.waitForExistence(timeout: 5))
        alertRemove.tap()
        let removedDone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count == 0"),
            object: scroller.staticTexts.matching(identifier: "accountTitle_demo4@gmail.com")
        )
        XCTAssertEqual(XCTWaiter.wait(for: [removedDone], timeout: 10), .completed)

        tap("关闭", app: app)
        let signInReq = payload("/api/signin")
        XCTAssertEqual(signInReq["agent"] as? String, "antigravity")
        XCTAssertEqual(payload("/api/signin/s1/callback")["url"] as? String, "http://127.0.0.1:54321/callback?code=demo-code-2&state=s1")
        XCTAssertEqual(payload("/api/gateway/unrest")["key"] as? String, "antigravity#demo2@gmail.com")
        XCTAssertEqual(payload("/api/provider/route")["routing"] as? String, "rotate")
        XCTAssertEqual(payload("/api/provider/accountweight")["weight"] as? Int, 3)
        XCTAssertEqual((payload("/api/provider/accountweight")["account"] as? String)?.lowercased(), "demo3@gmail.com")
        XCTAssertEqual((payload("/api/login/forget")["user"] as? String)?.lowercased(), "demo4@gmail.com")
        XCTAssertTrue(server.trace().contains { $0["path"] as? String == "/api/login/usage" }, "Must refresh per-account quota usage")
    }

    func testCapturePhase3AlertsSwitchWidget() throws {
        let server = try FixtureHTTPServer(phase3: true)
        fixture = server
        func payload(_ path: String) -> [String: Any] {
            let row = server.requests().last { $0["path"] as? String == path }
            XCTAssertNotNil(row, "UI must call \(path)")
            return row?["body"] as? [String: Any] ?? [:]
        }

        let app = XCUIApplication()
        app.launch()
        tap("连接 magpie web", app: app)
        let name = app.textFields["例如：家里 NAS / 云服务器"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("演示实例 · Phase 3")
        let address = app.textFields["https://your-host:3430/?k=..."]
        address.tap(); address.typeText("http://127.0.0.1:\(server.port)/?k=fixture-only-not-a-real-key")
        tap("保存并连接", app: app)
        XCTAssertTrue(app.staticTexts["1 模型在线"].waitForExistence(timeout: 20))

        // 1. One-tap switch from Account Errors view (rate-limited demo2@gmail.com -> demo1@gmail.com)
        tap("dashboardAccountErrorsButton", app: app)
        XCTAssertTrue(app.staticTexts["账号异常总览"].waitForExistence(timeout: 10))
        tap("quickSwitchFromError_demo2@gmail.com", app: app, scroll: true)
        XCTAssertTrue(app.otherElements["quickSwitchResultBanner"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["undoQuickSwitchButton"].waitForExistence(timeout: 5))
        shot("41-phase3-error-quick-switch-demo")
        tap("undoQuickSwitchButton", app: app)
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !app.buttons["undoQuickSwitchButton"].exists
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 15), .completed)
        tap("关闭", app: app)

        // 2. Open Quota Alerts sheet -> configure threshold 40% so demo2 (38% remaining) triggers alert
        tap("dashboardQuotaAlertsButton", app: app)
        XCTAssertTrue(app.staticTexts["余量预警与桌面组件"].waitForExistence(timeout: 10))
        tap("quotaAlertsSection_rules", app: app)
        let thresholdField = app.textFields["globalAlertThresholdField"]
        XCTAssertTrue(thresholdField.waitForExistence(timeout: 5))
        thresholdField.tap()
        thresholdField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "40")
        tap("收起键盘", app: app)
        tap("saveGlobalAlertThresholdButton", app: app)
        XCTAssertEqual(thresholdField.value as? String, "40")
        shot("42-phase3-alert-rules-demo")

        // 3. Verify alerts grouped by account & by provider, then quick-switch from alert card
        tap("quotaAlertsSection_alerts", app: app)
        XCTAssertTrue(app.otherElements["quotaAlertCard_demo2@gmail.com"].waitForExistence(timeout: 10))
        shot("43-phase3-alerts-by-account-demo")

        tap("alertViewMode_provider", app: app)
        XCTAssertTrue(app.staticTexts["Antigravity (谷歌反重力)"].waitForExistence(timeout: 5))
        shot("44-phase3-alerts-by-provider-demo")

        tap("alertViewMode_account", app: app)
        tap("quickSwitchAlertButton_demo2@gmail.com", app: app, scroll: true)
        XCTAssertTrue(app.otherElements["quickSwitchResultBanner"].waitForExistence(timeout: 10))

        // An applied server change whose response fails must be inspected and recovered.
        tap("undoQuickSwitchButton", app: app)
        let undoDone = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            server.accountOrder("antigravity").first == "demo1@gmail.com" && !app.buttons["undoQuickSwitchButton"].exists
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [undoDone], timeout: 15), .completed)
        server.failNextSwitchAfterApplying()
        tap("quickSwitchAlertButton_demo2@gmail.com", app: app, scroll: true)
        let recovery = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            server.accountOrder("antigravity").first == "demo1@gmail.com"
                && app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "已读回确认原顺序恢复")).firstMatch.exists
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [recovery], timeout: 20), .completed)
        shot("47-phase3-switch-recovery-demo")

        // 4. Verify WidgetKit preview cards + masked account cache + deep link navigation to Usage tab
        tap("quotaAlertsSection_widget", app: app)
        XCTAssertTrue(app.otherElements["widgetPreviewMediumCard"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["widgetPreviewSmallCard"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "de***")).firstMatch.waitForExistence(timeout: 5))
        shot("45-phase3-widget-preview-demo")

        tap("testWidgetDeepLinkUsageButton", app: app, scroll: true)
        XCTAssertTrue(app.staticTexts["用量趋势"].waitForExistence(timeout: 10))
        shot("46-phase3-deeplink-usage-demo")

        // 5. Verify actual API switch call payload
        let switchBody = payload("/api/provider/arrange")
        XCTAssertEqual(switchBody["id"] as? String, "antigravity")
        XCTAssertEqual((switchBody["accountOrder"] as? [String])?.first, "demo1@gmail.com")
        XCTAssertEqual(Set(switchBody["accountOrder"] as? [String] ?? []), Set(["demo1@gmail.com", "demo2@gmail.com", "backup@example.com"]))
        XCTAssertFalse(server.requests().contains { $0["path"] as? String == "/api/login/forget" })
    }

}
