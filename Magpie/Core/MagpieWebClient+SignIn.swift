import Foundation

extension MagpieWebClient {

    func fetchProvidersWait() async throws -> RemoteProvidersResponse {
        return try await requestJSON(
            RemoteProvidersResponse.self,
            path: "/api/providers",
            queryItems: [URLQueryItem(name: "wait", value: "1")],
            timeout: 25
        ).value
    }

    // MARK: - OAuth Sign-In (`/api/signin/*`, `/api/plugin-signin/*`)

    func startSignIn(
        agent: String,
        site: String? = nil,
        proxy: String? = nil,
        user: String? = nil,
        linkOnly: Bool = true
    ) async throws -> RemoteSignInState {
        var body: [String: Any] = ["agent": agent, "linkOnly": linkOnly]
        if let site = site, !site.isEmpty { body["site"] = site }
        if let proxy = proxy { body["proxy"] = proxy }
        if let user = user, !user.isEmpty { body["user"] = user }
        return try await requestJSON(
            RemoteSignInState.self,
            method: "POST",
            path: "/api/signin",
            jsonBody: body,
            timeout: 30
        ).value
    }

    func getSignInStatus(id: String) async throws -> RemoteSignInState {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return try await requestJSON(
            RemoteSignInState.self,
            path: "/api/signin/\(encoded)",
            timeout: 15
        ).value
    }

    func cancelSignIn(id: String) async throws {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        _ = try await requestData(
            method: "POST",
            path: "/api/signin/\(encoded)/cancel",
            jsonBody: [:]
        )
    }

    func submitSignInCallback(id: String, url: String) async throws {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        _ = try await requestData(
            method: "POST",
            path: "/api/signin/\(encoded)/callback",
            jsonBody: ["url": url],
            timeout: 60
        )
    }

    func addClaudeSetupToken(token: String) async throws -> RemoteClaudeTokenResponse {
        return try await requestJSON(
            RemoteClaudeTokenResponse.self,
            method: "POST",
            path: "/api/signin/claude-token",
            jsonBody: ["token": token],
            timeout: 30
        ).value
    }

    func importSignInAccounts(
        agent: String,
        files: [String],
        accessOnly: Bool = false
    ) async throws -> RemoteSignInImportResponse {
        var body: [String: Any] = ["agent": agent, "files": files]
        if accessOnly { body["accessOnly"] = true }
        return try await requestJSON(
            RemoteSignInImportResponse.self,
            method: "POST",
            path: "/api/signin/import",
            jsonBody: body,
            timeout: 120
        ).value
    }

    func exportSignInAccounts(
        agent: String,
        format: String,
        users: [String]
    ) async throws -> RemoteSignInExportResponse {
        return try await requestJSON(
            RemoteSignInExportResponse.self,
            method: "POST",
            path: "/api/signin/export",
            jsonBody: ["agent": agent, "format": format, "users": users],
            timeout: 60
        ).value
    }

    func pluginSignInPrompt(
        provider: String,
        method: Int,
        inputs: [String: String],
        key: String? = nil,
        value: String? = nil
    ) async throws -> RemotePluginPromptResponse {
        var body: [String: Any] = [
            "provider": provider,
            "method": method,
            "inputs": inputs
        ]
        if let key = key, !key.isEmpty {
            body["key"] = key
            body["value"] = value ?? ""
        }
        return try await requestJSON(
            RemotePluginPromptResponse.self,
            method: "POST",
            path: "/api/plugin-signin/prompt",
            jsonBody: body,
            timeout: 45
        ).value
    }

    func startPluginSignIn(
        provider: String,
        method: Int,
        inputs: [String: String],
        key: String? = nil,
        proxy: String? = nil,
        user: String? = nil
    ) async throws -> RemoteSignInState {
        var body: [String: Any] = [
            "provider": provider,
            "method": method,
            "inputs": inputs
        ]
        if let key = key { body["key"] = key }
        if let proxy = proxy { body["proxy"] = proxy }
        if let user = user, !user.isEmpty { body["user"] = user }
        return try await requestJSON(
            RemoteSignInState.self,
            method: "POST",
            path: "/api/plugin-signin",
            jsonBody: body,
            timeout: 45
        ).value
    }

    // MARK: - Login Accounts & Usage (`/api/login/*`, `/api/provider/*`, `/api/codex/daemon/*`)

    func fetchLoginUsage(agent: String) async throws -> [String: RemoteLoginQuota] {
        return try await requestJSON(
            [String: RemoteLoginQuota].self,
            path: "/api/login/usage",
            queryItems: [URLQueryItem(name: "agent", value: agent)],
            timeout: 25
        ).value
    }

    func loginAction(_ action: String, agent: String, user: String) async throws -> RemoteProvidersResponse {
        let allowed = ["switch", "forget", "on", "off", "access-only", "renewed"]
        guard allowed.contains(action) else {
            throw MagpieWebError.invalidURL("不支持的账号操作")
        }
        return try await requestJSON(
            RemoteProvidersResponse.self,
            method: "POST",
            path: "/api/login/\(action)",
            jsonBody: ["agent": agent, "user": user],
            timeout: 30
        ).value
    }

    func arrangeProviderAccounts(id: String, accountOrder: [String]) async throws -> RemoteProvidersResponse {
        return try await requestJSON(
            RemoteProvidersResponse.self,
            method: "POST",
            path: "/api/provider/arrange",
            jsonBody: ["id": id, "accountOrder": accountOrder]
        ).value
    }

    func setAccountName(id: String, account: String, alias: String) async throws -> RemoteProvidersResponse {
        return try await requestJSON(
            RemoteProvidersResponse.self,
            method: "POST",
            path: "/api/provider/accountname",
            jsonBody: ["id": id, "account": account, "alias": alias]
        ).value
    }

    func setAccountCap(id: String, account: String, cap: Int) async throws -> RemoteProvidersResponse {
        return try await requestJSON(
            RemoteProvidersResponse.self,
            method: "POST",
            path: "/api/provider/accountcap",
            jsonBody: ["id": id, "account": account, "cap": cap]
        ).value
    }

    func setAccountWeight(id: String, account: String, weight: Int) async throws -> RemoteProvidersResponse {
        return try await requestJSON(
            RemoteProvidersResponse.self,
            method: "POST",
            path: "/api/provider/accountweight",
            jsonBody: ["id": id, "account": account, "weight": weight]
        ).value
    }

    func setAccountConcurrency(id: String, account: String, limit: Int?) async throws -> RemoteProvidersResponse {
        var body: [String: Any] = ["id": id, "account": account]
        if let limit = limit {
            body["limit"] = limit
        } else {
            body["limit"] = NSNull()
        }
        return try await requestJSON(
            RemoteProvidersResponse.self,
            method: "POST",
            path: "/api/provider/accountconcurrency",
            jsonBody: body
        ).value
    }

    func setProviderKeepLogin(id: String, keepLogin: Bool, keepLoginAs: String? = nil) async throws -> RemoteProvidersResponse {
        var body: [String: Any] = ["id": id, "keepLogin": keepLogin]
        if let keepLoginAs = keepLoginAs, !keepLoginAs.isEmpty {
            body["keepLoginAs"] = keepLoginAs
        }
        return try await requestJSON(
            RemoteProvidersResponse.self,
            method: "POST",
            path: "/api/provider/keeplogin",
            jsonBody: body
        ).value
    }

    func setProviderSwitchOnly(id: String, switchOnly: Bool) async throws -> RemoteProvidersResponse {
        return try await requestJSON(
            RemoteProvidersResponse.self,
            method: "POST",
            path: "/api/provider/switchonly",
            jsonBody: ["id": id, "switchOnly": switchOnly]
        ).value
    }

    func setProviderRestartApp(id: String, restartApp: Bool) async throws -> RemoteProvidersResponse {
        return try await requestJSON(
            RemoteProvidersResponse.self,
            method: "POST",
            path: "/api/provider/restartapp",
            jsonBody: ["id": id, "restartApp": restartApp]
        ).value
    }

    func setProviderCapStop(id: String, capStop: Bool) async throws -> RemoteProvidersResponse {
        return try await requestJSON(
            RemoteProvidersResponse.self,
            method: "POST",
            path: "/api/provider/capstop",
            jsonBody: ["id": id, "capStop": capStop]
        ).value
    }

    func setProviderCapCareful(id: String, capCareful: Bool) async throws -> RemoteProvidersResponse {
        return try await requestJSON(
            RemoteProvidersResponse.self,
            method: "POST",
            path: "/api/provider/capcareful",
            jsonBody: ["id": id, "capCareful": capCareful]
        ).value
    }

    func restoreExcludedProvider(id: String) async throws -> RemoteProvidersResponse {
        return try await requestJSON(
            RemoteProvidersResponse.self,
            method: "POST",
            path: "/api/provider/show",
            jsonBody: ["id": id]
        ).value
    }

    func forgetExcludedProvider(id: String) async throws -> RemoteProvidersResponse {
        return try await requestJSON(
            RemoteProvidersResponse.self,
            method: "POST",
            path: "/api/provider/forget",
            jsonBody: ["id": id]
        ).value
    }

    func moveAntigravityToAgy() async throws -> RemoteProvidersResponse {
        return try await requestJSON(
            RemoteProvidersResponse.self,
            method: "POST",
            path: "/api/provider/toagy",
            jsonBody: [:],
            timeout: 120
        ).value
    }

    func codexDaemonAction(_ action: String) async throws -> RemoteProvidersResponse {
        let allowed = ["restart", "dismiss", "dismiss-app", "dismiss-projects", "restart-app"]
        guard allowed.contains(action) else {
            throw MagpieWebError.invalidURL("不支持的 Codex 后台操作")
        }
        return try await requestJSON(
            RemoteProvidersResponse.self,
            method: "POST",
            path: "/api/codex/daemon/\(action)",
            jsonBody: [:],
            timeout: 60
        ).value
    }
}
