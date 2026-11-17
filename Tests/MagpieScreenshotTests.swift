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
        XCTAssertTrue(matches.firstMatch.waitForExistence(timeout: 10), "Missing button: \(title)")
        func visible(_ button: XCUIElement) -> Bool {
            guard button.isHittable && button.isEnabled else { return false }
            let bottomTab = app.buttons["tab.home"]
            return !scroll || !bottomTab.isHittable || button.frame.maxY <= bottomTab.frame.minY - 12
        }
        if scroll {
            for _ in 0..<12 {
                if matches.allElementsBoundByIndex.contains(where: visible) { break }
                app.swipeUp()
            }
        }
        // Nested sheets expose their covered parent's buttons under the same label.
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            matches.allElementsBoundByIndex.contains(where: visible)
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed, "No enabled visible button: \(title)")
        guard let button = matches.allElementsBoundByIndex.first(where: visible) else {
            XCTFail("Button disappeared: \(title)"); return
        }
        button.tap()
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
        tap("管理", app: app)
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
        let provider = payload("/api/provider/save")
        XCTAssertEqual((provider["headers"] as? [String: String])?["X-Project"], "test")
        XCTAssertEqual(provider["models"] as? [String], ["gpt-demo"])
        XCTAssertEqual((provider["contexts"] as? [String: Int])?["gpt-demo"], 128000)
        let group = payload("/api/groups/save")
        XCTAssertNotNil((group["rules"] as? [[String: Any]])?.first?["where"])
        XCTAssertEqual(payload("/api/groups/copy")["id"] as? String, "coding")
        XCTAssertEqual(payload("/api/groups/copy")["name"] as? String, "编程组演示 副本")
        XCTAssertEqual(payload("/api/masking/values")["ps"] as? [String], ["{{EMAIL_demo}}"])
    }
}
