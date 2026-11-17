import Foundation

extension GatewayStore {

    // MARK: - Provider Creation, Editing & Ordering

    func addPresetProvider(
        preset: RemotePreset,
        name: String,
        key: String,
        region: RemotePresetRegion?,
        customEndpoint: String
    ) async -> Bool {
        var payload: [String: Any] = [
            "id": preset.id,
            "name": name.isEmpty ? preset.name : name,
            "preset": preset.id,
            "key": key,
            "new": true
        ]
        if let region = region {
            if let chat = region.chat, !chat.isEmpty { payload["chat"] = chat }
            if let responses = region.responses, !responses.isEmpty { payload["responses"] = responses }
            if let anthropic = region.anthropic, !anthropic.isEmpty { payload["anthropic"] = anthropic }
        } else if !customEndpoint.isEmpty {
            payload["chat"] = customEndpoint
        }
        do {
            let resp = try await client.saveProviderPayload(payload)
            applyProvidersResponse(resp)
            await refreshGroups()
            await refreshStateOnly()
            showToast("已添加「\(name.isEmpty ? preset.name : name)」")
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func saveProviderPayload(_ payload: [String: Any], toast: String = "已保存供应商配置") async -> Bool {
        do {
            let resp = try await client.saveProviderPayload(payload)
            applyProvidersResponse(resp)
            await refreshGroups()
            await refreshStateOnly()
            showToast(toast)
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func moveProvider(_ provider: RemoteProvider, offset: Int) async {
        guard let idx = providers.firstIndex(where: { $0.id == provider.id }) else { return }
        let target = idx + offset
        guard target >= 0 && target < providers.count else { return }
        var order = providers.map(\.id)
        order.swapAt(idx, target)
        do {
            let resp = try await client.arrangeProviders(order: order)
            applyProvidersResponse(resp)
            showToast("已调整「\(provider.name)」排序")
        } catch {
            recordActionError(error)
        }
    }

    func revealProviderKey(id: String, account: String? = nil, allKeys: Bool = false) async -> String? {
        do {
            let res = try await client.revealProviderKey(id: id, account: account, allKeys: allKeys)
            return res.key
        } catch {
            recordActionError(error)
            return nil
        }
    }

    func updateProviderRouting(_ provider: RemoteProvider, routing: String) async {
        do {
            let resp = try await client.setProviderRouting(id: provider.id, routing: routing)
            applyProvidersResponse(resp)
            showToast("已更新调度策略")
        } catch {
            recordActionError(error)
        }
    }

    func updateProviderAffinity(_ provider: RemoteProvider, affinity: String) async {
        do {
            let resp = try await client.setProviderAffinity(id: provider.id, affinity: affinity)
            applyProvidersResponse(resp)
            showToast("已更新会话粘性")
        } catch {
            recordActionError(error)
        }
    }

    func updateProviderSink(_ provider: RemoteProvider, sink: Bool) async {
        do {
            let resp = try await client.setProviderSink(id: provider.id, sink: sink)
            applyProvidersResponse(resp)
            showToast(sink ? "已开启限流沉底" : "已关闭限流沉底")
        } catch {
            recordActionError(error)
        }
    }

    func updateProviderUseFirst(_ provider: RemoteProvider, useFirst: Bool) async {
        do {
            let resp = try await client.setProviderUseFirst(id: provider.id, useFirst: useFirst)
            applyProvidersResponse(resp)
            showToast(useFirst ? "已设为优先使用" : "已取消优先使用")
        } catch {
            recordActionError(error)
        }
    }

    func updateProviderNoStandIn(_ provider: RemoteProvider, noStandIn: Bool) async {
        do {
            let resp = try await client.setProviderNoStandIn(id: provider.id, noStandIn: noStandIn)
            applyProvidersResponse(resp)
            showToast(noStandIn ? "已禁止作为他源兜底" : "已允许作为他源兜底")
        } catch {
            recordActionError(error)
        }
    }

    func updateProviderModelName(providerID: String, modelID: String, name: String) async -> Bool {
        do {
            let resp = try await client.setProviderModelName(id: providerID, model: modelID, modelName: name)
            applyProvidersResponse(resp)
            await refreshStateOnly()
            showToast("已更新模型别名")
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func updateProviderModelEfforts(providerID: String, modelID: String, efforts: [String]) async -> Bool {
        do {
            let resp = try await client.setProviderModelEfforts(id: providerID, model: modelID, efforts: efforts)
            applyProvidersResponse(resp)
            await refreshStateOnly()
            showToast("已更新模型思考档位")
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func updateProviderModelImages(providerID: String, modelID: String, images: Bool?) async -> Bool {
        do {
            let resp = try await client.setProviderModelImages(id: providerID, model: modelID, images: images)
            applyProvidersResponse(resp)
            await refreshStateOnly()
            showToast("已更新图片能力设置")
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func updateAccountModels(providerID: String, account: String, allow: [String]) async -> Bool {
        do {
            let resp = try await client.setAccountModels(id: providerID, account: account, allow: allow)
            applyProvidersResponse(resp)
            showToast("已更新该 Key 限定模型")
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    // MARK: - Multi-Key Pool Actions

    func addProviderKey(providerID: String, name: String, key: String, protocol proto: String) async -> Bool {
        do {
            let resp = try await client.addProviderKey(id: providerID, name: name, key: key, protocol: proto)
            applyProvidersResponse(resp)
            showToast("已添加 Key")
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func importProviderKeys(providerID: String, keysText: String, protocol proto: String) async -> Bool {
        do {
            let resp = try await client.importProviderKeys(id: providerID, keysText: keysText, protocol: proto)
            applyProvidersResponse(resp)
            showToast("已完成批量导入 Key")
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func toggleProviderKey(providerID: String, ref: String, on: Bool) async {
        do {
            let resp = try await client.toggleProviderKey(id: providerID, ref: ref, on: on)
            applyProvidersResponse(resp)
            showToast(on ? "已启用 Key" : "已停用 Key")
        } catch {
            recordActionError(error)
        }
    }

    func useProviderKey(providerID: String, ref: String) async {
        do {
            let resp = try await client.useProviderKey(id: providerID, ref: ref)
            applyProvidersResponse(resp)
            showToast("已设为优先使用 Key")
        } catch {
            recordActionError(error)
        }
    }

    func renameProviderKey(providerID: String, ref: String, name: String) async -> Bool {
        do {
            let resp = try await client.renameProviderKey(id: providerID, ref: ref, name: name)
            applyProvidersResponse(resp)
            showToast("已重命名 Key")
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func replaceProviderKey(providerID: String, ref: String, key: String) async -> Bool {
        do {
            let resp = try await client.replaceProviderKey(id: providerID, ref: ref, key: key)
            applyProvidersResponse(resp)
            showToast("已替换 Key 密钥")
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func setProviderKeyWeight(providerID: String, ref: String, weight: Int) async -> Bool {
        do {
            let resp = try await client.setProviderKeyWeight(id: providerID, ref: ref, weight: weight)
            applyProvidersResponse(resp)
            showToast("已更新权重为 \(max(1, weight))")
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func setProviderKeyProtocol(providerID: String, ref: String, protocol proto: String) async {
        do {
            let resp = try await client.setProviderKeyProtocol(id: providerID, ref: ref, protocol: proto)
            applyProvidersResponse(resp)
            showToast("已更新 Key 绑定协议")
        } catch {
            recordActionError(error)
        }
    }

    func removeProviderKey(providerID: String, ref: String) async {
        do {
            let resp = try await client.removeProviderKey(id: providerID, ref: ref)
            applyProvidersResponse(resp)
            showToast("已移除 Key")
        } catch {
            recordActionError(error)
        }
    }

    // MARK: - Routing Groups Actions

    func saveGroup(payload: [String: Any], toast: String = "已保存路由组") async -> Bool {
        do {
            let resp = try await client.saveGroup(payload: payload)
            applyGroupsResponse(resp)
            await refreshStateOnly()
            showToast(toast)
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func copyGroup(_ group: RemoteRoutingGroup, newName: String) async -> Bool {
        do {
            let resp = try await client.copyGroup(id: group.id, name: newName)
            applyGroupsResponse(resp)
            await refreshStateOnly()
            showToast("已复制路由组「\(newName)」")
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func deleteGroup(_ group: RemoteRoutingGroup) async {
        do {
            let resp = try await client.deleteGroup(id: group.id)
            applyGroupsResponse(resp)
            await refreshStateOnly()
            showToast("已删除路由组「\(group.name)」")
        } catch {
            recordActionError(error)
        }
    }

    func shareGroup(_ group: RemoteRoutingGroup) async -> String? {
        do {
            let resp = try await client.shareGroup(id: group.id)
            if let text = resp.shared, !text.isEmpty {
                return text
            }
            showToast("服务端未返回分享文本")
            return nil
        } catch {
            recordActionError(error)
            return nil
        }
    }

    func importGroup(text: String, replace: Bool) async -> Bool {
        do {
            let resp = try await client.importGroup(text: text, replace: replace)
            applyGroupsResponse(resp)
            await refreshStateOnly()
            showToast("已导入路由组")
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func createGroupFromTemplate(_ tpl: RemoteGroupTemplate, name: String) async -> Bool {
        do {
            let resp = try await client.createGroupFromTemplate(kind: tpl.kind, name: name)
            applyGroupsResponse(resp)
            await refreshStateOnly()
            showToast("已从模板创建「\(name)」")
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func toggleAutoGroups(_ on: Bool) async {
        do {
            let resp = try await client.setAutoGroups(on: on)
            applyGroupsResponse(resp)
            await refreshStateOnly()
            showToast(on ? "已开启同名自动归组" : "已关闭同名自动归组")
        } catch {
            recordActionError(error)
        }
    }

    func saveGroupDefaults(sink: Bool, firstToken: Int, patience: Int) async -> Bool {
        do {
            let resp = try await client.setGroupDefaults(sink: sink, firstToken: firstToken, patience: patience)
            applyGroupsResponse(resp)
            showToast("已更新路由组全局默认值")
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func moveGroup(_ group: RemoteRoutingGroup, offset: Int) async {
        let userGroups = groups.filter { !$0.auto }
        guard let idx = userGroups.firstIndex(where: { $0.id == group.id }) else { return }
        let target = idx + offset
        guard target >= 0 && target < userGroups.count else { return }
        var order = userGroups.map(\.id)
        order.swapAt(idx, target)
        do {
            let resp = try await client.arrangeGroups(order: order)
            applyGroupsResponse(resp)
            showToast("已调整路由组排序")
        } catch {
            recordActionError(error)
        }
    }

    // MARK: - Agents & Profiles Actions

    func refreshStateOnly() async {
        do {
            let state = try await client.fetchState()
            applyStateResponse(state)
        } catch {
            recordActionError(error)
        }
    }

    func rescanAgents() async {
        do {
            let state = try await client.rescanAgents()
            applyStateResponse(state)
            showToast("已重新扫描服务器上的 Agents")
        } catch {
            recordActionError(error)
        }
    }

    func setAgentField(agentID: String, fieldKey: String, value: String) async -> Bool {
        do {
            let state = try await client.setAgentField(agent: agentID, field: fieldKey, value: value)
            applyStateResponse(state)
            showToast("已更新 Agent 配置")
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func performAgentAction(agent: RemoteAgent, action: String) async {
        do {
            let state = try await client.agentAction(id: agent.id, action: action)
            applyStateResponse(state)
            let label: String
            switch action {
            case "connect": label = "已接入「\(agent.name)」"
            case "disconnect": label = "已断开「\(agent.name)」"
            case "reapply": label = "已重新应用「\(agent.name)」配置"
            case "keep": label = "已保留「\(agent.name)」当前配置"
            default: label = "操作已完成"
            }
            if state.notice?.isEmpty != false {
                showToast(label)
            }
        } catch {
            recordActionError(error)
        }
    }

    func restartAgentApp(_ agent: RemoteAgent) async {
        do {
            let state = try await client.restartAgentApp(id: agent.id)
            applyStateResponse(state)
            showToast("已重启「\(agent.name)」桌面端")
        } catch {
            recordActionError(error)
        }
    }

    func setAgentTelemetry(_ agent: RemoteAgent, off: Bool) async {
        do {
            let state = try await client.setAgentTelemetry(id: agent.id, off: off)
            applyStateResponse(state)
            showToast(off ? "已关闭「\(agent.name)」遥测" : "已恢复「\(agent.name)」遥测")
        } catch {
            recordActionError(error)
        }
    }

    func fetchAgentModels(agentID: String) async -> Result<RemoteAgentModelsResponse, MagpieWebError> {
        do {
            let res = try await client.fetchAgentModels(id: agentID)
            return .success(res)
        } catch let err as MagpieWebError {
            return .failure(err)
        } catch {
            return .failure(.networkError(error.localizedDescription))
        }
    }

    func updateAgentModels(
        agentID: String,
        hidden: [String]? = nil,
        shown: [String]? = nil,
        only: Bool? = nil,
        ownHidden: Bool? = nil
    ) async -> Result<RemoteAgentModelsResponse, MagpieWebError> {
        do {
            let res = try await client.updateAgentModels(
                id: agentID,
                hidden: hidden,
                shown: shown,
                only: only,
                ownHidden: ownHidden
            )
            await refreshStateOnly()
            return .success(res)
        } catch let err as MagpieWebError {
            recordActionError(err)
            return .failure(err)
        } catch {
            recordActionError(error)
            return .failure(.networkError(error.localizedDescription))
        }
    }

    func toggleAgentFast(agentID: String, ref: String, fast: Bool, ultra: Bool) async -> Bool {
        do {
            _ = try await client.setAgentFast(agentID: agentID, ref: ref, fast: fast, ultra: ultra)
            await refreshStateOnly()
            showToast(fast ? (ultra ? "已设为 Ultrafast" : "已开启 Fast") : "已关闭 Fast")
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func saveProfile(name: String) async -> Bool {
        do {
            let state = try await client.profileAction("save", name: name)
            applyStateResponse(state)
            showToast("已保存方案「\(name)」")
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func useProfile(name: String) async {
        do {
            let state = try await client.profileAction("use", name: name)
            applyStateResponse(state)
            showToast("已切换至方案「\(name)」")
        } catch {
            recordActionError(error)
        }
    }

    func renameProfile(from: String, to: String) async -> Bool {
        do {
            let state = try await client.profileAction("rename", name: from, to: to)
            applyStateResponse(state)
            showToast("已重命名为「\(to)」")
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func deleteProfile(name: String) async {
        do {
            let state = try await client.profileAction("delete", name: name)
            applyStateResponse(state)
            showToast("已删除方案「\(name)」")
        } catch {
            recordActionError(error)
        }
    }


    // MARK: - Gateway Control Actions

    func takeOverGateway() async -> String? {
        do {
            let res = try await client.takeOverGateway()
            await refreshProviders()
            await refreshSettings()
            if res.ok {
                showToast("已接管并启动网关")
                return nil
            }
            let msg = res.error ?? res.reason ?? "网关接管未完成"
            showToast(msg)
            return msg
        } catch {
            recordActionError(error)
            return error.localizedDescription
        }
    }

    func restartGateway() async -> String? {
        do {
            let res = try await client.restartGateway()
            await refreshProviders()
            await refreshSettings()
            if res.ok {
                showToast("已重启网关服务")
                return nil
            }
            let msg = res.error ?? res.reason ?? "网关重启未完成"
            showToast(msg)
            return msg
        } catch {
            recordActionError(error)
            return error.localizedDescription
        }
    }

    func toggleGatewayPaused(_ pause: Bool) async {
        do {
            let res = try await client.setGatewayPaused(on: pause)
            await refreshSettings()
            await refreshProviders()
            if let err = res.error, !err.isEmpty {
                showToast(err)
            } else {
                showToast(res.paused ? "已暂停网关监听" : "已恢复网关监听")
            }
        } catch {
            recordActionError(error)
        }
    }

    func liftGatewayKeyRest(key: String) async -> Bool {
        do {
            let lifted = try await client.unrestGatewayKey(key: key)
            await refreshProviders()
            showToast(lifted ? "已解除「\(key)」冷却状态" : "该账号/Key 当前未处于冷却中")
            return lifted
        } catch {
            recordActionError(error)
            return false
        }
    }

    // MARK: - Proxies & Network Settings Actions

    func saveNamedProxy(id: String?, name: String, url: String, user: String, pass: String?) async -> Bool {
        do {
            remoteSettings = try await client.saveProxy(id: id, name: name, url: url, user: user, pass: pass)
            showToast("已保存代理「\(name)」")
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func deleteNamedProxy(id: String, name: String) async -> Bool {
        do {
            remoteSettings = try await client.deleteProxy(id: id)
            showToast("已删除代理「\(name)」")
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func saveGatewayPort(_ port: Int) async -> Bool {
        do {
            remoteSettings = try await client.updatePort(port)
            await refreshProviders()
            showToast("已更新网关端口为 \(port)")
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func saveCORSOrigins(_ rawText: String) async {
        let origins = rawText
            .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == " " })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        do {
            remoteSettings = try await client.updateCORS(origins)
            showToast("已保存 CORS 允许域名")
        } catch {
            recordActionError(error)
        }
    }

    func saveGitHubToken(_ token: String) async -> Bool {
        do {
            remoteSettings = try await client.updateGitHubToken(token.trimmingCharacters(in: .whitespacesAndNewlines))
            showToast(token.isEmpty ? "已清除 GitHub Token" : "已保存 GitHub Token")
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }
}
