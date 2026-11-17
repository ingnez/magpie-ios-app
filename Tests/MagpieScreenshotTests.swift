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

        let provider = payload("/api/provider/save")
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
        tap("完成并返回", app: app)

        let manageButtons = app.buttons.matching(identifier: "管理")
        XCTAssertGreaterThan(manageButtons.count, 1, "Expected second provider (Antigravity)")
        let agyManage = manageButtons.element(boundBy: 1)
        for _ in 0..<4 where !agyManage.isHittable { app.swipeUp() }
        if agyManage.isHittable { agyManage.tap() } else { agyManage.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        XCTAssertTrue(app.buttons["多账号号池"].waitForExistence(timeout: 10))
        tap("多账号号池", app: app)
        XCTAssertTrue(app.staticTexts["demo1@gmail.com"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["demo2@gmail.com"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["demo3@gmail.com"].waitForExistence(timeout: 5))
        tap("Rotate 逐轮轮询", app: app, scroll: true)
        XCTAssertTrue(app.staticTexts.matching(identifier: "参与轮询").firstMatch.waitForExistence(timeout: 10))
        if app.buttons["解除冷却"].waitForExistence(timeout: 5) {
            tap("解除冷却", app: app, scroll: true)
            let unrestDone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["解除冷却"])
            XCTAssertEqual(XCTWaiter.wait(for: [unrestDone], timeout: 10), .completed)
        }
        shot("28-subscription-multi-account-demo")
        tap("关闭", app: app)
        let signInReq = payload("/api/signin")
        XCTAssertEqual(signInReq["agent"] as? String, "antigravity")
        XCTAssertEqual(payload("/api/signin/s1/callback")["url"] as? String, "http://127.0.0.1:54321/callback?code=demo-code&state=s1")
        XCTAssertEqual(payload("/api/gateway/unrest")["key"] as? String, "antigravity#demo2@gmail.com")
        XCTAssertEqual(payload("/api/provider/route")["routing"] as? String, "rotate")

    }

}
