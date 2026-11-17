# Magpie iOS 1.3.0 管理能力补齐

交付范围采用混合实现：第一、第二批为 SwiftUI 原生页面；第三批在 App 内嵌入运行中的 Magpie 原版管理控制台。第三批没有改写为原生页面。

## 已接入的原生页面

| 范围 | 能力 | 入口 / 源文件 |
|---|---|---|
| 供应商详情 | 概况、连接测试、余额、多 Key 号池、调度策略、粘性、高级配置 | 供应商 → 管理；`ProviderDetailSheet.swift` |
| Key 号池 | 新增、批量导入、启停、优先使用、重命名、替换、权重、协议和限定模型 | 供应商 → 管理 → 多 Key 号池 |
| 模型 | 模型选择、同系列最新、别名、推理档位、图片能力 | 供应商 → 管理 → 模型管理 |
| 路由组 | 新建、编辑、复制、删除、成员顺序、自动归组、规则、超时、上下文 | 供应商 → 路由组；`GroupEditorSheet.swift`、`CopyGroupSheet.swift` |
| Agents | 服务器上的客户端扫描、接入/断开、字段选择、Fast、可见模型、遥测与方案管理 | 总览 → Agents 与方案；`AgentsView.swift` |
| Caller Keys | 新增、改名、启停、轮换、删除、模型范围、只读权限、日/周/月 Token 与美元预算 | 隐私与设置 → Caller Keys 管理；`CallerKeysView.swift` |
| 隐私规则 | 前缀/正则、敏感词、忽略大小写、整词匹配、规则提醒/拦截、白名单、服务端预览 | 隐私与设置 → 正则与敏感词；`MaskingEditors.swift` |
| 脱敏记录 | 发送给上游的内容、显式恢复可用原值、过期占位符提示 | 隐私与设置 → 查看前后对照 |
| 用量 | 请求/Token/费用交互柱图，点按显示数据 | 用量；`UsageTools.swift` |
| 签到热身 | WorkBuddy/Trae/MiniMax/Qoder 与插件签到、自动签到设置、Claude/Codex 热身 | 用量 → 签到与热身 |

## App 内原版控制台

入口：隐私与设置 → 完整管理控制台。由 `RemoteConsoleView.swift` 承载，`ConsoleDestination.swift` 定义入口。

| 功能 | 原版页面参数 |
|---|---|
| 代理池与网络 | `?mode=window&view=settings&tab=network` |
| 备份与同步 | `?mode=window&view=settings&tab=sync` |
| Sessions | `?mode=window&view=sessions` |
| Library | `?mode=window&view=library` |
| Plugins | `?mode=window&view=plugins` |
| 模型定价 | `?mode=window&view=providers`，进入供应商模型定价编辑 |
| 上下文调优 | `?mode=window&view=usage&tab=context`，加载前按原版 `magpie.usageTab=context` 选择上下文页签（原版忽略该 tab 参数） |

控制台继续使用服务器提供的界面和确认流程，下载交给 iOS 分享面板，文件上传沿用 WebKit 选择器。服务器缺少或关闭的原版插件不会被 iOS 客户端补造。

## 数据保护与兼容

- 控制台通过现有客户端重新换取 HttpOnly Cookie，复制至独立、非持久化 WebKit 会话；地址不附带访问密钥 `k`。
- 同源校验包含协议、主机和有效端口，阻止非用户点击的跨站跳转。外链在 Safari 页面打开，不共享管理 Cookie。
- 自签 TLS 放行限于明确配置的实例主机及端口。
- 供应商保存先读取当前编辑字段，保留 headers、contexts、accountModels 等配置；不回写响应中已遮盖的 key/balanceToken 对象。
- 路由组保存保留 `where` 高级条件、原有规则、脱敏策略和推理档位等已有配置。
- 设置补丁每次读取当前设置后再合并，避免旧缓存覆盖别处刚更新的配置。
- 新 Caller Key 先以只读状态创建，应用模型范围后再设置目标权限；失败可重试同一个 Key，避免重复签发。
- 新签发密钥仅保存在当前页面状态；复制使用本机剪贴板并在 120 秒后过期。
- 脱敏原值只有明确点击后才请求；服务器已不记得的部分保留占位符，不伪造原文。

## 可重现的验收命令

模型契约：

```sh
swiftc Magpie/Core/MagpieWebModels.swift Magpie/Core/MagpieOperationModels.swift Magpie/Core/ConsoleDestination.swift Magpie/Core/ProviderEditPayload.swift Tests/ModelContractTests.swift -o /tmp/magpie-contracts
/tmp/magpie-contracts
```

本地接口夹具：

```sh
python3 Tests/mock_server.py
# 在另一终端运行：
python3 Tests/fixture_smoke.py
```

iOS 正式编译和模拟器 UI 检查分别由 `.github/workflows/build-ipa.yml`、`simulator-screenshots.yml` 执行。截图使用 `Tests/mock_server.py` 定义的演示数据，在模拟器测试进程内由 `FixtureHTTPServer.swift` 提供，不代表已连接生产实例。

## 已知边界

- 交付包为 Xcode 正式编译的未签名 IPA，安装真机仍需自行签名。
- 第三批通过原版控制台实现，不能描述为全部原生重写；深层管理能力取决于服务器版本及启用的插件。
- Caller Key 原生额度编辑覆盖日/周/月的 Token/美元规则；修改额度时替换该 Key 的额度规则，页面已提示。复杂多规则额度仍可在原版 Gateway 页面操作。
- 脱敏前对照依赖服务器仍保留发送体及原值映射；重启或过期后可能不可恢复。
- 2026-11-17 在构建宿主机执行 `curl -I --connect-timeout 8 --max-time 12 https://magpie.163ll.com` 返回 `curl: (28) Connection timeout after 8000 ms`，生产实例鉴权、供应商变更及第三批实际业务操作尚未完成在线联调。
- 原版备份导出将加密文件写到服务器的 Downloads，页面显示服务器路径；它本身不是 iPhone 文件下载接口。WebKit 分享面板适用于原版确实返回下载文件的接口。

## 模拟器回归修正

- 截图测试服务在模拟器测试进程内监听独立端口，排除 CI 宿主机回环隔离；登录仍走真实客户端的 Cookie 交换。
- 复制路由组使用独立表单状态，避免父页面首次展示 sheet 时名称已填入、按钮仍取旧空值的问题；提交期间防重复，错误留在当前表单。
- UI 自动化只点击当前可见且启用的按钮，等待复制表单消失后再切换主页面；断言失败立即停止。
- 控制台上下文入口预置非持久化 WebKit 中的原版页签偏好，不注入密钥；模拟器校验 Cookie 共享与上下文页签选择。
