import Foundation

extension MagpieWebClient {
    func callerKeyAction(_ action: String, payload: [String: Any]) async throws -> RemoteCallerKeyChangeResponse {
        let allowed = ["add-key", "rename-key", "off-key", "on-key", "remove-key", "rotate-key", "limit-key", "reset-limit-key", "models-key", "access-key"]
        guard allowed.contains(action) else { throw MagpieWebError.invalidURL("不支持的 Key 操作") }
        return try await requestJSON(RemoteCallerKeyChangeResponse.self, method: "POST", path: "/api/caller-keys/\(action)", jsonBody: payload).value
    }

    func maskingSent(key: String) async throws -> RemoteMaskingSent {
        try await requestJSON(RemoteMaskingSent.self, path: "/api/masking/sent", queryItems: [URLQueryItem(name: "key", value: key)]).value
    }

    func maskingValues(placeholders: [String]) async throws -> RemoteMaskingValues {
        try await requestJSON(RemoteMaskingValues.self, method: "POST", path: "/api/masking/values", jsonBody: ["ps": placeholders]).value
    }

    func updateRedactActions(_ actions: [String: String]) async throws -> RemoteSettingsState {
        try await requestJSON(RemoteSettingsState.self, method: "POST", path: "/api/settings/redact-actions", jsonBody: ["actions": actions]).value
    }

    func warmAccounts(agent: String) async throws -> RemoteWarmResponse {
        try await requestJSON(RemoteWarmResponse.self, method: "POST", path: "/api/warm-all", jsonBody: ["agent": agent], timeout: 90).value
    }

    func checkIn(provider: String) async throws -> [RemoteCheckinResult] {
        let builtins = ["workbuddy", "trae", "minimax", "qoder"]
        let path = builtins.contains(provider) ? "/api/usage/\(provider)-checkin" : "/api/usage/plugin-checkin"
        return try await requestJSON([RemoteCheckinResult].self, method: "POST", path: path, jsonBody: ["provider": provider], timeout: 90).value
    }

    func updateCheckin(provider: String, on: Bool) async throws -> RemoteSettingsState {
        let builtins = ["workbuddy", "trae", "minimax", "qoder"]
        let path = builtins.contains(provider) ? "/api/settings/\(provider)-checkin" : "/api/settings/plugin-checkin"
        return try await requestJSON(RemoteSettingsState.self, method: "POST", path: path, jsonBody: ["provider": provider, "on": on]).value
    }
}

