import Foundation

extension MagpieWebClient {

    // MARK: - Provider Detail, Models & Policies (`/api/provider/*`, `/api/providers/*`)

    func saveProviderPayload(_ payload: [String: Any]) async throws -> RemoteProvidersResponse {
        var body = payload
        if payload["new"] as? Bool != true, let id = (payload["from"] ?? payload["id"]) as? String {
            let (data, _) = try await requestData(path: "/api/providers")
            let response = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let current = (response?["providers"] as? [[String: Any]])?.first(where: { $0["id"] as? String == id }) else {
                throw MagpieWebError.decodingError("供应商已改变，请刷新后重新编辑")
            }
            body = preservedProviderPayload(current: current, changes: payload)
        }
        return try await requestJSON(
            RemoteProvidersResponse.self,
            method: "POST",
            path: "/api/provider/save",
            jsonBody: body,
            timeout: 35
        ).value
    }

    func arrangeProviders(order: [String]) async throws -> RemoteProvidersResponse {
        return try await requestJSON(
            RemoteProvidersResponse.self,
            method: "POST",
            path: "/api/providers/arrange",
            jsonBody: ["order": order]
        ).value
    }

    func revealProviderKey(id: String, account: String? = nil, allKeys: Bool = false) async throws -> RemoteProviderKeyRevealResponse {
        var body: [String: Any] = ["id": id]
        if let account = account, !account.isEmpty { body["account"] = account }
        if allKeys { body["allKeys"] = true }
        return try await requestJSON(
            RemoteProviderKeyRevealResponse.self,
            method: "POST",
            path: "/api/provider/key",
            jsonBody: body
        ).value
    }

    func setProviderRouting(id: String, routing: String) async throws -> RemoteProvidersResponse {
        return try await requestJSON(
            RemoteProvidersResponse.self,
            method: "POST",
            path: "/api/provider/route",
            jsonBody: ["id": id, "routing": routing]
        ).value
    }

    func setProviderAffinity(id: String, affinity: String) async throws -> RemoteProvidersResponse {
        return try await requestJSON(
            RemoteProvidersResponse.self,
            method: "POST",
            path: "/api/provider/affinity",
            jsonBody: ["id": id, "affinity": affinity]
        ).value
    }

    func setProviderSink(id: String, sink: Bool) async throws -> RemoteProvidersResponse {
        return try await requestJSON(
            RemoteProvidersResponse.self,
            method: "POST",
            path: "/api/provider/sink",
            jsonBody: ["id": id, "sink": sink]
        ).value
    }

    func setProviderUseFirst(id: String, useFirst: Bool) async throws -> RemoteProvidersResponse {
        return try await requestJSON(
            RemoteProvidersResponse.self,
            method: "POST",
            path: "/api/provider/usefirst",
            jsonBody: ["id": id, "useFirst": useFirst]
        ).value
    }

    func setProviderNoStandIn(id: String, noStandIn: Bool) async throws -> RemoteProvidersResponse {
        return try await requestJSON(
            RemoteProvidersResponse.self,
            method: "POST",
            path: "/api/provider/standin",
            jsonBody: ["id": id, "noStandIn": noStandIn]
        ).value
    }

    func setProviderModelName(id: String, model: String, modelName: String) async throws -> RemoteProvidersResponse {
        return try await requestJSON(
            RemoteProvidersResponse.self,
            method: "POST",
            path: "/api/provider/name",
            jsonBody: ["id": id, "model": model, "modelName": modelName]
        ).value
    }

    func setProviderModelEfforts(id: String, model: String, efforts: [String]) async throws -> RemoteProvidersResponse {
        return try await requestJSON(
            RemoteProvidersResponse.self,
            method: "POST",
            path: "/api/provider/efforts",
            jsonBody: ["id": id, "model": model, "efforts": efforts]
        ).value
    }

    func setProviderModelImages(id: String, model: String, images: Bool?) async throws -> RemoteProvidersResponse {
        var body: [String: Any] = ["id": id, "model": model]
        if let images = images {
            body["images"] = images
        }
        return try await requestJSON(
            RemoteProvidersResponse.self,
            method: "POST",
            path: "/api/provider/images",
            jsonBody: body
        ).value
    }

    func setAccountModels(id: String, account: String, allow: [String]) async throws -> RemoteProvidersResponse {
        return try await requestJSON(
            RemoteProvidersResponse.self,
            method: "POST",
            path: "/api/provider/accountmodels",
            jsonBody: ["id": id, "account": account, "allow": allow]
        ).value
    }

    // MARK: - Multi-Key Pool (`/api/keys/{action}`)

    func addProviderKey(id: String, name: String, key: String, protocol proto: String) async throws -> RemoteProvidersResponse {
        return try await requestJSON(
            RemoteProvidersResponse.self,
            method: "POST",
            path: "/api/keys/add",
            jsonBody: ["id": id, "name": name, "key": key, "protocol": proto],
            timeout: 25
        ).value
    }

    func importProviderKeys(id: String, keysText: String, protocol proto: String) async throws -> RemoteProvidersResponse {
        return try await requestJSON(
            RemoteProvidersResponse.self,
            method: "POST",
            path: "/api/keys/import",
            jsonBody: ["id": id, "key": keysText, "protocol": proto],
            timeout: 25
        ).value
    }

    func toggleProviderKey(id: String, ref: String, on: Bool) async throws -> RemoteProvidersResponse {
        let action = on ? "on" : "off"
        return try await requestJSON(
            RemoteProvidersResponse.self,
            method: "POST",
            path: "/api/keys/\(action)",
            jsonBody: ["id": id, "ref": ref],
            timeout: 25
        ).value
    }

    func useProviderKey(id: String, ref: String) async throws -> RemoteProvidersResponse {
        return try await requestJSON(
            RemoteProvidersResponse.self,
            method: "POST",
            path: "/api/keys/use",
            jsonBody: ["id": id, "ref": ref]
        ).value
    }

    func renameProviderKey(id: String, ref: String, name: String) async throws -> RemoteProvidersResponse {
        return try await requestJSON(
            RemoteProvidersResponse.self,
            method: "POST",
            path: "/api/keys/rename",
            jsonBody: ["id": id, "ref": ref, "name": name]
        ).value
    }

    func replaceProviderKey(id: String, ref: String, key: String) async throws -> RemoteProvidersResponse {
        return try await requestJSON(
            RemoteProvidersResponse.self,
            method: "POST",
            path: "/api/keys/replace",
            jsonBody: ["id": id, "ref": ref, "key": key]
        ).value
    }

    func setProviderKeyWeight(id: String, ref: String, weight: Int) async throws -> RemoteProvidersResponse {
        return try await requestJSON(
            RemoteProvidersResponse.self,
            method: "POST",
            path: "/api/keys/weight",
            jsonBody: ["id": id, "ref": ref, "weight": weight]
        ).value
    }

    func setProviderKeyProtocol(id: String, ref: String, protocol proto: String) async throws -> RemoteProvidersResponse {
        return try await requestJSON(
            RemoteProvidersResponse.self,
            method: "POST",
            path: "/api/keys/protocol",
            jsonBody: ["id": id, "ref": ref, "protocol": proto]
        ).value
    }

    func setProviderKeyPlan(id: String, ref: String, plan: String) async throws -> RemoteProvidersResponse {
        return try await requestJSON(
            RemoteProvidersResponse.self,
            method: "POST",
            path: "/api/keys/plan",
            jsonBody: ["id": id, "ref": ref, "plan": plan],
            timeout: 25
        ).value
    }

    func removeProviderKey(id: String, ref: String) async throws -> RemoteProvidersResponse {
        return try await requestJSON(
            RemoteProvidersResponse.self,
            method: "POST",
            path: "/api/keys/remove",
            jsonBody: ["id": id, "ref": ref]
        ).value
    }

    // MARK: - Routing Groups (`/api/groups/*`)

    func saveGroup(payload: [String: Any]) async throws -> RemoteGroupsResponse {
        return try await requestJSON(
            RemoteGroupsResponse.self,
            method: "POST",
            path: "/api/groups/save",
            jsonBody: payload
        ).value
    }

    func copyGroup(id: String, name: String) async throws -> RemoteGroupsResponse {
        return try await requestJSON(
            RemoteGroupsResponse.self,
            method: "POST",
            path: "/api/groups/copy",
            jsonBody: ["id": id, "name": name]
        ).value
    }

    func deleteGroup(id: String) async throws -> RemoteGroupsResponse {
        return try await requestJSON(
            RemoteGroupsResponse.self,
            method: "POST",
            path: "/api/groups/delete",
            jsonBody: ["id": id]
        ).value
    }

    func shareGroup(id: String) async throws -> RemoteGroupsResponse {
        return try await requestJSON(
            RemoteGroupsResponse.self,
            method: "POST",
            path: "/api/groups/share",
            jsonBody: ["id": id]
        ).value
    }

    func importGroup(text: String, replace: Bool = false) async throws -> RemoteGroupsResponse {
        return try await requestJSON(
            RemoteGroupsResponse.self,
            method: "POST",
            path: "/api/groups/import",
            jsonBody: ["text": text, "replace": replace]
        ).value
    }

    func createGroupFromTemplate(kind: String, name: String) async throws -> RemoteGroupsResponse {
        return try await requestJSON(
            RemoteGroupsResponse.self,
            method: "POST",
            path: "/api/groups/template",
            jsonBody: ["kind": kind, "name": name]
        ).value
    }

    func setAutoGroups(on: Bool) async throws -> RemoteGroupsResponse {
        return try await requestJSON(
            RemoteGroupsResponse.self,
            method: "POST",
            path: "/api/groups/found",
            jsonBody: ["on": on]
        ).value
    }

    func setGroupDefaults(sink: Bool, firstToken: Int, patience: Int) async throws -> RemoteGroupsResponse {
        return try await requestJSON(
            RemoteGroupsResponse.self,
            method: "POST",
            path: "/api/groups/defaults",
            jsonBody: ["sink": sink, "firstToken": firstToken, "patience": patience]
        ).value
    }

    func arrangeGroups(order: [String]) async throws -> RemoteGroupsResponse {
        return try await requestJSON(
            RemoteGroupsResponse.self,
            method: "POST",
            path: "/api/groups/arrange",
            jsonBody: ["order": order]
        ).value
    }

    // MARK: - Agents & Profiles (`/api/set`, `/api/agents/*`, `/api/agent-models/*`, `/api/agent-fast`, `/api/profile/*`)

    func setAgentField(agent: String, field: String, value: String) async throws -> RemoteStateResponse {
        return try await requestJSON(
            RemoteStateResponse.self,
            method: "POST",
            path: "/api/set",
            jsonBody: ["agent": agent, "field": field, "value": value]
        ).value
    }

    func agentAction(id: String, action: String) async throws -> RemoteStateResponse {
        return try await requestJSON(
            RemoteStateResponse.self,
            method: "POST",
            path: "/api/agents/\(action)/\(id)",
            jsonBody: [:]
        ).value
    }

    func rescanAgents() async throws -> RemoteStateResponse {
        return try await requestJSON(
            RemoteStateResponse.self,
            method: "POST",
            path: "/api/agents/rescan",
            jsonBody: [:],
            timeout: 30
        ).value
    }

    func restartAgentApp(id: String) async throws -> RemoteStateResponse {
        return try await requestJSON(
            RemoteStateResponse.self,
            method: "POST",
            path: "/api/agents/restart/\(id)",
            jsonBody: [:],
            timeout: 45
        ).value
    }

    func setAgentTelemetry(id: String, off: Bool) async throws -> RemoteStateResponse {
        return try await requestJSON(
            RemoteStateResponse.self,
            method: "POST",
            path: "/api/agents/telemetry/\(id)",
            jsonBody: ["off": off]
        ).value
    }

    func fetchAgentModels(id: String) async throws -> RemoteAgentModelsResponse {
        return try await requestJSON(
            RemoteAgentModelsResponse.self,
            path: "/api/agent-models/\(id)"
        ).value
    }

    func updateAgentModels(
        id: String,
        hidden: [String]? = nil,
        shown: [String]? = nil,
        only: Bool? = nil,
        ownHidden: Bool? = nil
    ) async throws -> RemoteAgentModelsResponse {
        var body: [String: Any] = [:]
        if let hidden = hidden { body["hidden"] = hidden }
        if let shown = shown { body["shown"] = shown }
        if let only = only { body["only"] = only }
        if let ownHidden = ownHidden { body["ownHidden"] = ownHidden }
        return try await requestJSON(
            RemoteAgentModelsResponse.self,
            method: "POST",
            path: "/api/agent-models/\(id)",
            jsonBody: body
        ).value
    }

    func setAgentFast(agentID: String, ref: String, fast: Bool, ultra: Bool) async throws -> RemoteAgentFastResponse {
        return try await requestJSON(
            RemoteAgentFastResponse.self,
            method: "POST",
            path: "/api/agent-fast",
            jsonBody: ["for": agentID, "ref": ref, "fast": fast, "ultra": ultra]
        ).value
    }

    func profileAction(_ action: String, name: String, to: String? = nil) async throws -> RemoteStateResponse {
        var body: [String: Any] = ["name": name]
        if let to = to { body["to"] = to }
        return try await requestJSON(
            RemoteStateResponse.self,
            method: "POST",
            path: "/api/profile/\(action)",
            jsonBody: body
        ).value
    }
}
