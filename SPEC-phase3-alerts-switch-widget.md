# Spec: Magpie iOS Phase 3 — 余量预警 · 一键切号 · 桌面组件 (V1)

Status: approved-by-user-direction

## 1. Objective
在 `feature/ui-phase2` (`8284a12`) 基线上增量交付三项高频能力，保留既有 N 账号动态池、`maxAccounts` 空/0 不限、深色模式、异常总览、自定义用量区间与 OAuth 回调校验：

1. **余量预警（Quota Alert）**
   - 可配置剩余额度阈值（默认 `10%`，支持全局默认 + 按供应商 / 按账号单独覆写与静音）。
   - 支持按账号与按供应商两种视图聚合展示预警条目与剩余百分比。
   - 在用户显式开启本地预警通知或点击请求权限时，合理调用 `UNUserNotificationCenter` 请求授权；按 `serverID + provider + account + window + resetBucket` 与恢复滞回（`remaining > threshold + 5%`）去重，避免重复刷屏。
   - 真实标注 iOS 后台刷新限制：客户端本地通知依赖前台刷新与系统不定期调度的 `BGAppRefreshTask`，不等同于服务端秒级实时推送；如需锁屏实时推送，需依赖 Magpie 服务端 Bark（`/api/settings/bark`）或未来 APNs 推送通道，UI 内提供直达 Bark 配置的入口。

2. **一键切号（One-Tap Account Switch）**
   - 当账号限流冷却（`accountRests` / `429`）、余量低或失效时，提供便捷切换至**同平台其他可用账号 / Key** 的操作与明确反馈。
   - 使用核实存在的服务端接口：
     - 订阅账号池：`POST /api/provider/arrange`（将目标账号置顶为 `#1`）+ `POST /api/login/switch`（`{"agent","user"}` 切换当前活跃账号）；失败时尝试按快照顺位回滚并报告每步真实状态，**绝不覆盖、删除或重置既有账号**。
     - 多 Key 号池：`POST /api/keys/use`（`{"id","ref"}` 将可用 Key 设为优先）；支持切回原账号/Key。
   - 不擅自修改生产供应商 `routing` 策略或服务端路由组配置；服务端自动故障转移仍由网关现有策略负责，客户端清晰展示当前调度模式及可用候选账号排序。

3. **WidgetKit 桌面组件（MagpieWidget Extension）**
   - 新增 `MagpieWidget` App Extension target 与 App Group（`group.ai.usemagpie.ios`），由主 App 在连接/刷新时写入脱敏共享快照 `MagpieWidgetSnapshot`。
   - 展示当天调用/费用/Tokens 摘要与账号/供应商余量及预警角标（支持小号 `.systemSmall`、中号 `.systemMedium`）。
   - 支持离线/缓存过期提示、未配置引导，以及 `magpie://usage`、`magpie://alerts`、`magpie://providers?id=...`、`magpie://refresh` 点击深链。
   - **安全边界**：App Group 共享缓存严禁写入 `webKey`、Cookie、API Key、OAuth Token 或明文凭据；账号邮箱在共享快照中默认脱敏（如 `de***@gmail.com`）。

## 2. Commands
- 契约测试（macOS runner）：
  `swiftc Magpie/Core/*.swift Tests/ModelContractTests.swift -o /tmp/magpie-contracts && /tmp/magpie-contracts`
- 生成工程与编译未签名 IPA（GitHub Actions `xcode-27`）：
  `xcodegen generate --spec project.yml && xcodebuild -project Magpie.xcodeproj -scheme Magpie -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO clean build`
- 扩展包校验：
  `test -d build/DerivedData/Build/Products/Release-iphoneos/Magpie.app/PlugIns/MagpieWidget.appex`
- 模拟器 UI 测试与截图（GitHub Actions `xcode-27`）：
  `xcodebuild test -project Magpie.xcodeproj -scheme Magpie -destination "platform=iOS Simulator,id=${SIM_UDID}" -only-testing:"MagpieUITests/MagpieScreenshotTests/<method>"`

## 3. Project Structure (Additions)
- `Magpie/Core/SharedWidgetSnapshot.swift` — 共享快照模型、App Group 读写与邮箱脱敏工具（双 target 共享）。
- `Magpie/Core/QuotaAlertEngine.swift` — 余量预警配置、多维度阈值覆写、按账号/供应商评估与去重通知状态管理。
- `Magpie/Core/AccountSwitchPlanner.swift` — 同平台可用账号/Key 排序规划与切换结果模型（纯函数可单测）。
- `Magpie/Core/GatewayStore+Phase3.swift` — 一键切号执行（含回滚）、预警刷新、通知触发、BGTask 注册与深链路由。
- `Magpie/Views/QuotaAlertsSheet.swift` — 余量预警规则配置（全局+按供应商/账号）、按账号/供应商预警列表、iOS 后台刷新说明与桌面组件预览页。
- `MagpieWidget/MagpieWidget.swift`、`MagpieWidget/Info.plist`、`MagpieWidget/MagpieWidget.entitlements` — WidgetKit 桌面组件实现与配置。
- `Tests/ModelContractTests.swift`、`Tests/mock_server.py`、`Tests/MagpieScreenshotTests.swift` — 新增 Phase 3 契约测试与模拟端到端 UI 测试。

## 4. Boundaries
- **Always**：新逻辑编写纯函数测试并在 `xcode-27` 跑通契约测试 + UI 测试 + 无签名 Release 构建；所有展示数值来源于真实状态或明确标注的离线/演示数据。
- **Ask First**：任何修改生产服务端配置/路由/删除账号/停服操作必须先获确认。
- **Never**：不把 `webKey`/Token 写入 App Group；不把本地通知伪称为服务端实时推送；不在 Linux 容器交叉编译 `.ipa`；不修改 `main` 分支。

## 5. Success Criteria
1. `ModelContractTests` 新增覆盖预警评估/去重/阈值覆写、一键切号候选排序、邮箱脱敏、深链解析与 Widget 快照编解码，全部通过。
2. `MagpieWidget` 作为真实 `app-extension` target 编入 `Magpie.xcodeproj` 并包含在 `Magpie.app/PlugIns/MagpieWidget.appex` 与 `Magpie-unsigned.ipa` 中，Release 构建 exit 0。
3. 模拟器 UI 测试（含深色/浅色与模拟数据）覆盖：修改余量阈值并按账号/供应商查看预警、从限流/预警账号一键切号并验证 `/api/provider/arrange` + `/api/login/switch` 调用与可撤销反馈、App 内桌面组件快照脱敏预览与深链跳转。

## 6. Out of Scope (Deferred to V2)
- 服务端 APNs 推送证书与后端推送网关改造（当前通过服务端已有 Bark + 客户端本地通知实现）。
- Widget Extension 内直接持有 `webKey` 发起直连请求（V1 为保护密钥边界仅读取主 App 写入的 App Group 脱敏快照）。
