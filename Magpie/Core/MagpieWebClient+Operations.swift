import Foundation

extension MagpieWebClient {

    // MARK: - Caller Keys & Masking (`/api/caller-keys/*`, `/api/masking/*`, `/api/settings/redact-*`)

    func callerKeyAction(_ action: String, payload: [String: Any]) async throws -> RemoteCallerKeyChangeResponse {
        let allowed = [
            "add-key", "rename-key", "off-key", "on-key", "remove-key",
            "rotate-key", "limit-key", "reset-limit-key", "models-key", "access-key"
        ]
        guard allowed.contains(action) else { throw MagpieWebError.invalidURL("不支持的 Key 操作") }
        return try await requestJSON(
            RemoteCallerKeyChangeResponse.self,
            method: "POST",
            path: "/api/caller-keys/\(action)",
            jsonBody: payload
        ).value
    }

    func maskingSent(key: String) async throws -> RemoteMaskingSent {
        try await requestJSON(
            RemoteMaskingSent.self,
            path: "/api/masking/sent",
            queryItems: [URLQueryItem(name: "key", value: key)]
        ).value
    }

    func maskingValues(placeholders: [String]) async throws -> RemoteMaskingValues {
        try await requestJSON(
            RemoteMaskingValues.self,
            method: "POST",
            path: "/api/masking/values",
            jsonBody: ["ps": placeholders]
        ).value
    }

    func updateRedactActions(_ actions: [String: String]) async throws -> RemoteSettingsState {
        try await requestJSON(
            RemoteSettingsState.self,
            method: "POST",
            path: "/api/settings/redact-actions",
            jsonBody: ["actions": actions]
        ).value
    }

    func updateRedactRoute(_ model: String) async throws -> RemoteSettingsState {
        try await requestJSON(
            RemoteSettingsState.self,
            method: "POST",
            path: "/api/settings/redact-route",
            jsonBody: ["model": model]
        ).value
    }

    func fetchPrivacyModel() async throws -> RemotePrivacyModelResponse {
        try await requestJSON(RemotePrivacyModelResponse.self, path: "/api/privacy-model").value
    }

    func updatePrivacyModel(doAction: String, model: String = "", score: Double = 0) async throws -> RemotePrivacyModelResponse {
        var payload: [String: Any] = ["do": doAction]
        if !model.isEmpty { payload["model"] = model }
        if score > 0 { payload["score"] = score }
        return try await requestJSON(
            RemotePrivacyModelResponse.self,
            method: "POST",
            path: "/api/privacy-model",
            jsonBody: payload,
            timeout: 45
        ).value
    }

    func updateRequestArchive(on: Bool) async throws -> RemoteArchiveStateResponse {
        try await requestJSON(
            RemoteArchiveStateResponse.self,
            method: "POST",
            path: "/api/settings/archive",
            jsonBody: ["on": on]
        ).value
    }

    // MARK: - Warmup, Check-ins & Usage Operations (`/api/warm-*`, `/api/usage/*`)

    func warmAccounts(agent: String) async throws -> RemoteWarmResponse {
        try await requestJSON(
            RemoteWarmResponse.self,
            method: "POST",
            path: "/api/warm-all",
            jsonBody: ["agent": agent],
            timeout: 90
        ).value
    }

    func warmSingleAccount(agent: String, user: String) async throws {
        _ = try await requestData(
            method: "POST",
            path: "/api/warm-now",
            jsonBody: ["agent": agent, "user": user],
            timeout: 60
        )
    }

    func checkIn(provider: String) async throws -> [RemoteCheckinResult] {
        let builtins = ["workbuddy", "trae", "minimax", "qoder"]
        let path = builtins.contains(provider) ? "/api/usage/\(provider)-checkin" : "/api/usage/plugin-checkin"
        return try await requestJSON(
            [RemoteCheckinResult].self,
            method: "POST",
            path: path,
            jsonBody: ["provider": provider],
            timeout: 90
        ).value
    }

    func updateCheckin(provider: String, on: Bool) async throws -> RemoteSettingsState {
        let builtins = ["workbuddy", "trae", "minimax", "qoder"]
        let path = builtins.contains(provider) ? "/api/settings/\(provider)-checkin" : "/api/settings/plugin-checkin"
        return try await requestJSON(
            RemoteSettingsState.self,
            method: "POST",
            path: path,
            jsonBody: ["provider": provider, "on": on]
        ).value
    }

    func clearUsage(provider: String = "", model: String = "") async throws {
        _ = try await requestData(
            method: "POST",
            path: "/api/usage/clear",
            jsonBody: ["provider": provider, "model": model]
        )
    }

    func spendCodexReset(provider: String = "codex", user: String, credit: String = "") async throws {
        _ = try await requestData(
            method: "POST",
            path: "/api/usage/codex-reset",
            jsonBody: ["provider": provider, "user": user, "credit": credit],
            timeout: 35
        )
    }

    // MARK: - Named Proxies (`/api/proxies/*`)

    func saveProxy(
        id: String?,
        name: String,
        url: String,
        user: String,
        pass: String?
    ) async throws -> RemoteSettingsState {
        var payload: [String: Any] = [
            "id": id ?? "",
            "name": name,
            "url": url,
            "user": user
        ]
        if let pass = pass {
            payload["pass"] = pass
        }
        return try await requestJSON(
            RemoteSettingsState.self,
            method: "POST",
            path: "/api/proxies/save",
            jsonBody: payload
        ).value
    }

    func deleteProxy(id: String) async throws -> RemoteSettingsState {
        try await requestJSON(
            RemoteSettingsState.self,
            method: "POST",
            path: "/api/proxies/delete",
            jsonBody: ["id": id]
        ).value
    }

    func testProxy(
        id: String?,
        name: String = "",
        url: String = "",
        user: String = "",
        pass: String? = nil
    ) async throws -> RemoteProxyTestResult {
        var payload: [String: Any] = [
            "id": id ?? "",
            "name": name,
            "url": url,
            "user": user
        ]
        if let pass = pass {
            payload["pass"] = pass
        }
        return try await requestJSON(
            RemoteProxyTestResult.self,
            method: "POST",
            path: "/api/proxies/test",
            jsonBody: payload,
            timeout: 25
        ).value
    }

    // MARK: - Backup, AutoBackup & WebDAV/S3/GitHub Sync (`/api/backup/*`, `/api/autobackup/*`, `/api/davsync/*`, `/api/sync`)

    func exportBackup(
        pass: String,
        keys: Bool = true,
        library: Bool = true,
        memory: Bool = true,
        signIns: Bool = false
    ) async throws -> RemoteBackupExportResponse {
        try await requestJSON(
            RemoteBackupExportResponse.self,
            method: "POST",
            path: "/api/backup/export",
            jsonBody: [
                "pass": pass,
                "keys": keys,
                "library": library,
                "memory": memory,
                "signIns": signIns
            ],
            timeout: 45
        ).value
    }

    func importBackup(
        base64Data: String,
        pass: String,
        agents: Bool = true,
        library: Bool = true,
        memory: Bool = true,
        signIns: Bool = true
    ) async throws -> RemoteBackupRestoreResult {
        try await requestJSON(
            RemoteBackupRestoreResult.self,
            method: "POST",
            path: "/api/backup/import",
            jsonBody: [
                "data": base64Data,
                "pass": pass,
                "agents": agents,
                "library": library,
                "memory": memory,
                "signIns": signIns
            ],
            timeout: 60
        ).value
    }

    func fetchAutoBackup() async throws -> RemoteAutoBackupView {
        try await requestJSON(RemoteAutoBackupView.self, path: "/api/autobackup").value
    }

    func autoBackupAction(_ action: String, payload: [String: Any] = [:]) async throws -> RemoteAutoBackupView {
        let allowed = ["set", "now", "restore"]
        guard allowed.contains(action) else { throw MagpieWebError.invalidURL("不支持的自动备份操作") }
        return try await requestJSON(
            RemoteAutoBackupView.self,
            method: "POST",
            path: "/api/autobackup/\(action)",
            jsonBody: payload,
            timeout: 45
        ).value
    }

    func fetchDavSync() async throws -> RemoteDavSyncView {
        try await requestJSON(RemoteDavSyncView.self, path: "/api/davsync").value
    }

    func davSyncAction(_ action: String, payload: [String: Any] = [:]) async throws -> RemoteDavSyncView {
        let allowed = ["save", "now", "off", "auto", "follow-server", "restore", "upload", "undo", "dismiss"]
        guard allowed.contains(action) else { throw MagpieWebError.invalidURL("不支持的云同步操作") }
        return try await requestJSON(
            RemoteDavSyncView.self,
            method: "POST",
            path: "/api/davsync/\(action)",
            jsonBody: payload,
            timeout: 60
        ).value
    }

    func triggerGlobalSync() async throws -> RemoteStateResponse {
        try await requestJSON(
            RemoteStateResponse.self,
            method: "POST",
            path: "/api/sync",
            jsonBody: [:],
            timeout: 45
        ).value
    }

    // MARK: - Context & Cache Tuning (`/api/tune/*`, `/api/settings/claude-*`)

    func fetchTune(days: Int = 7) async throws -> RemoteTuneState {
        try await requestJSON(
            RemoteTuneState.self,
            path: "/api/tune",
            queryItems: [URLQueryItem(name: "days", value: String(days))],
            timeout: 30
        ).value
    }

    func applyTune(agent: String, knob: String, model: String = "", value: String) async throws -> RemoteTuneSetting {
        try await requestJSON(
            RemoteTuneSetting.self,
            method: "POST",
            path: "/api/tune/apply",
            jsonBody: ["agent": agent, "knob": knob, "model": model, "value": value]
        ).value
    }

    func takeOverTune(agent: String, knob: String = "compact", model: String = "") async throws -> RemoteTuneSetting {
        try await requestJSON(
            RemoteTuneSetting.self,
            method: "POST",
            path: "/api/tune/takeover",
            jsonBody: ["agent": agent, "knob": knob, "model": model]
        ).value
    }

    func undoTune(agent: String, knob: String, model: String = "") async throws -> RemoteTuneSetting {
        try await requestJSON(
            RemoteTuneSetting.self,
            method: "POST",
            path: "/api/tune/undo",
            jsonBody: ["agent": agent, "knob": knob, "model": model]
        ).value
    }

    func updateClaudeCache(knob: String, value: String) async throws -> RemoteSettingsState {
        try await requestJSON(
            RemoteSettingsState.self,
            method: "POST",
            path: "/api/settings/claude-cache",
            jsonBody: ["knob": knob, "value": value]
        ).value
    }

    func updateClaudeAttribution(on: Bool) async throws -> RemoteSettingsState {
        try await requestJSON(
            RemoteSettingsState.self,
            method: "POST",
            path: "/api/settings/claude-attribution",
            jsonBody: ["on": on]
        ).value
    }

    // MARK: - Gateway Control (`/api/gateway/*`)

    func takeOverGateway() async throws -> RemoteGatewayFixResponse {
        try await requestJSON(
            RemoteGatewayFixResponse.self,
            method: "POST",
            path: "/api/gateway/take-over",
            jsonBody: [:],
            timeout: 30
        ).value
    }

    func restartGateway() async throws -> RemoteGatewayFixResponse {
        try await requestJSON(
            RemoteGatewayFixResponse.self,
            method: "POST",
            path: "/api/gateway/restart",
            jsonBody: [:],
            timeout: 30
        ).value
    }

    func setGatewayPaused(on: Bool) async throws -> RemoteGatewayPauseResponse {
        try await requestJSON(
            RemoteGatewayPauseResponse.self,
            method: "POST",
            path: "/api/gateway/pause",
            jsonBody: ["on": on],
            timeout: 25
        ).value
    }

    func unrestGatewayKey(key: String) async throws -> Bool {
        try await requestJSON(
            RemoteGatewayUnrestResponse.self,
            method: "POST",
            path: "/api/gateway/unrest",
            jsonBody: ["key": key]
        ).value.lifted
    }

    // MARK: - Model Price (`/api/model-price`)

    func fetchModelPrice(model: String) async throws -> RemoteModelPriceResponse {
        try await requestJSON(
            RemoteModelPriceResponse.self,
            path: "/api/model-price",
            queryItems: [URLQueryItem(name: "model", value: model)]
        ).value
    }

    func saveModelPrice(model: String, price: RemoteModelPriceSpec?) async throws -> RemoteModelPriceResponse {
        var payload: [String: Any] = ["model": model]
        if let price = price {
            payload["price"] = price.toDictionary()
        } else {
            payload["price"] = NSNull()
        }
        return try await requestJSON(
            RemoteModelPriceResponse.self,
            method: "POST",
            path: "/api/model-price",
            jsonBody: payload
        ).value
    }

    // MARK: - Dedicated Settings Write Routes (`/api/settings/*`)

    func updatePort(_ port: Int) async throws -> RemoteSettingsState {
        let (data, _) = try await requestData(
            method: "POST",
            path: "/api/settings/port",
            jsonBody: ["port": port]
        )
        if let wrapped = try? JSONDecoder().decode(RemotePortUpdateResponse.self, from: data) {
            return wrapped.settings
        }
        return try JSONDecoder().decode(RemoteSettingsState.self, from: data)
    }

    func updateCORS(_ origins: [String]) async throws -> RemoteSettingsState {
        try await requestJSON(
            RemoteSettingsState.self,
            method: "POST",
            path: "/api/settings/cors",
            jsonBody: ["origins": origins]
        ).value
    }

    func updateGitHubToken(_ token: String) async throws -> RemoteSettingsState {
        try await requestJSON(
            RemoteSettingsState.self,
            method: "POST",
            path: "/api/settings/github-token",
            jsonBody: ["token": token]
        ).value
    }

    func updateGatewayMode(_ mode: String) async throws -> RemoteSettingsState {
        try await requestJSON(
            RemoteSettingsState.self,
            method: "POST",
            path: "/api/settings/gateway-mode",
            jsonBody: ["mode": mode]
        ).value
    }

    func updateQuotaLeft(_ on: Bool) async throws -> RemoteSettingsState {
        try await requestJSON(
            RemoteSettingsState.self,
            method: "POST",
            path: "/api/settings/quota-left",
            jsonBody: ["on": on]
        ).value
    }

    func updateQuotaReads(_ reads: String) async throws -> RemoteSettingsState {
        try await requestJSON(
            RemoteSettingsState.self,
            method: "POST",
            path: "/api/settings/quota-reads",
            jsonBody: ["reads": reads]
        ).value
    }

    func updatePlainNames(on: Bool, mode: String = "") async throws -> RemoteSettingsState {
        try await requestJSON(
            RemoteSettingsState.self,
            method: "POST",
            path: "/api/settings/plain-names",
            jsonBody: ["on": on, "mode": mode]
        ).value
    }

    func updateBareIDs(on: Bool, only: Bool) async throws -> RemoteSettingsState {
        try await requestJSON(
            RemoteSettingsState.self,
            method: "POST",
            path: "/api/settings/bare-ids",
            jsonBody: ["on": on, "only": only]
        ).value
    }

    func updateBusyLoad(at: Int) async throws -> RemoteSettingsState {
        try await requestJSON(
            RemoteSettingsState.self,
            method: "POST",
            path: "/api/settings/busy-load",
            jsonBody: ["at": at]
        ).value
    }

    func updateFullContext(on: Bool, at: Int) async throws -> RemoteSettingsState {
        try await requestJSON(
            RemoteSettingsState.self,
            method: "POST",
            path: "/api/settings/full-context",
            jsonBody: ["on": on, "at": at]
        ).value
    }

    func updateContextCap(at: Int) async throws -> RemoteSettingsState {
        try await requestJSON(
            RemoteSettingsState.self,
            method: "POST",
            path: "/api/settings/context-cap",
            jsonBody: ["at": at]
        ).value
    }

    func updateContextCapMode(all: Bool) async throws -> RemoteSettingsState {
        try await requestJSON(
            RemoteSettingsState.self,
            method: "POST",
            path: "/api/settings/context-cap-mode",
            jsonBody: ["all": all]
        ).value
    }

    func updateDisabledModels(_ models: [String]) async throws -> RemoteSettingsState {
        try await requestJSON(
            RemoteSettingsState.self,
            method: "POST",
            path: "/api/settings/disabled-models",
            jsonBody: ["models": models]
        ).value
    }

    func updateGlobalAgentTelemetry(off: Bool) async throws -> RemoteSettingsState {
        try await requestJSON(
            RemoteSettingsState.self,
            method: "POST",
            path: "/api/settings/agent-telemetry",
            jsonBody: ["off": off]
        ).value
    }

    func updateAccountDiscovery(off: Bool) async throws -> RemoteSettingsState {
        try await requestJSON(
            RemoteSettingsState.self,
            method: "POST",
            path: "/api/settings/account-discovery",
            jsonBody: ["off": off]
        ).value
    }

    func updateUpdateMirror(_ mirror: String) async throws -> RemoteSettingsState {
        try await requestJSON(
            RemoteSettingsState.self,
            method: "POST",
            path: "/api/settings/update-mirror",
            jsonBody: ["mirror": mirror]
        ).value
    }

    func updateSearchAll(_ on: Bool) async throws -> RemoteSettingsState {
        try await requestJSON(
            RemoteSettingsState.self,
            method: "POST",
            path: "/api/settings/search-all",
            jsonBody: ["on": on]
        ).value
    }

    func updateSearchCount(_ count: Int) async throws -> RemoteSettingsState {
        try await requestJSON(
            RemoteSettingsState.self,
            method: "POST",
            path: "/api/settings/search-count",
            jsonBody: ["n": count]
        ).value
    }

    func updateSearchAPI(
        vendor: String,
        key: String = "",
        url: String = "",
        on: Bool? = nil,
        remove: Bool = false
    ) async throws -> RemoteSettingsState {
        var payload: [String: Any] = ["vendor": vendor, "key": key, "url": url, "remove": remove]
        if let on = on { payload["on"] = on }
        return try await requestJSON(
            RemoteSettingsState.self,
            method: "POST",
            path: "/api/settings/search-api",
            jsonBody: payload
        ).value
    }

    func updateCodexServiceTier(_ tier: String) async throws -> RemoteSettingsState {
        try await requestJSON(
            RemoteSettingsState.self,
            method: "POST",
            path: "/api/settings/codex-service-tier",
            jsonBody: ["tier": tier]
        ).value
    }

    func updateCodexAgentsV1(_ on: Bool) async throws -> RemoteSettingsState {
        try await requestJSON(
            RemoteSettingsState.self,
            method: "POST",
            path: "/api/settings/codex-agents-v1",
            jsonBody: ["on": on]
        ).value
    }

    func updateCodexTitles(_ model: String) async throws -> RemoteSettingsState {
        try await requestJSON(
            RemoteSettingsState.self,
            method: "POST",
            path: "/api/settings/codex-titles",
            jsonBody: ["model": model]
        ).value
    }

    func updateCodexDescriptions(_ model: String) async throws -> RemoteSettingsState {
        try await requestJSON(
            RemoteSettingsState.self,
            method: "POST",
            path: "/api/settings/codex-descriptions",
            jsonBody: ["model": model]
        ).value
    }

    func updateCodexPredictions(_ model: String) async throws -> RemoteSettingsState {
        try await requestJSON(
            RemoteSettingsState.self,
            method: "POST",
            path: "/api/settings/codex-predictions",
            jsonBody: ["model": model]
        ).value
    }

    func updateCodexAutoReview(_ model: String) async throws -> RemoteSettingsState {
        try await requestJSON(
            RemoteSettingsState.self,
            method: "POST",
            path: "/api/settings/codex-auto-review",
            jsonBody: ["model": model]
        ).value
    }

    func updateCodexAsyncCompact(on: Bool, percent: Int) async throws -> RemoteSettingsState {
        try await requestJSON(
            RemoteSettingsState.self,
            method: "POST",
            path: "/api/settings/codex-async-compact",
            jsonBody: ["on": on, "percent": percent]
        ).value
    }

    func updateCodexResetLead(minutes: Int) async throws -> RemoteSettingsState {
        try await requestJSON(
            RemoteSettingsState.self,
            method: "POST",
            path: "/api/settings/codex-reset-lead",
            jsonBody: ["minutes": minutes]
        ).value
    }
}
