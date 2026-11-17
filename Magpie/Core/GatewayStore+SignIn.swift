import Foundation

extension GatewayStore {

    // MARK: - Sign-In & OAuth Completion

    func refreshProvidersWaitAndState(forAgent agent: String? = nil) async {
        do {
            let resp = try await client.fetchProvidersWait()
            applyProvidersResponse(resp)
            if let agent = agent, !agent.isEmpty {
                loginUsageByAgent.removeValue(forKey: agent)
            }
            await refreshGroups()
            await refreshStateOnly()
        } catch {
            recordActionError(error)
        }
    }

    func fetchLoginUsage(agent: String) async {
        do {
            let usage = try await client.fetchLoginUsage(agent: agent)
            loginUsageByAgent[agent] = usage
        } catch {
            // Best-effort; keep existing cache if vendor query fails temporarily
        }
    }

    // MARK: - Login Actions (`/api/login/*`)

    func performLoginAction(_ action: String, agent: String, user: String, toast: String) async -> Bool {
        do {
            let resp = try await client.loginAction(action, agent: agent, user: user)
            applyProvidersResponse(resp)
            loginUsageByAgent.removeValue(forKey: agent)
            await refreshStateOnly()
            showToast(toast)
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func makeAccountFirst(provider: RemoteProvider, user: String, logins: [RemoteProviderLogin]) async -> Bool {
        var order = logins.map(\.user).filter { $0.caseInsensitiveCompare(user) != .orderedSame }
        order.insert(user, at: 0)
        do {
            let resp = try await client.arrangeProviderAccounts(id: provider.id, accountOrder: order)
            applyProvidersResponse(resp)
            await refreshStateOnly()
            showToast("已将「\(user)」设为首选账号")
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func moveAccountOrder(provider: RemoteProvider, user: String, offset: Int, logins: [RemoteProviderLogin]) async -> Bool {
        var order = logins.map(\.user)
        guard let idx = order.firstIndex(where: { $0.caseInsensitiveCompare(user) == .orderedSame }) else { return false }
        let target = idx + offset
        guard target >= 0 && target < order.count else { return false }
        order.swapAt(idx, target)
        do {
            let resp = try await client.arrangeProviderAccounts(id: provider.id, accountOrder: order)
            applyProvidersResponse(resp)
            await refreshStateOnly()
            showToast("已调整账号轮换顺序")
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func renameAccount(providerID: String, account: String, alias: String) async -> Bool {
        do {
            let resp = try await client.setAccountName(id: providerID, account: account, alias: alias)
            applyProvidersResponse(resp)
            showToast(alias.isEmpty ? "已清除账号别名" : "已重命名账号为「\(alias)」")
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func setAccountCap(providerID: String, account: String, cap: Int) async -> Bool {
        do {
            let resp = try await client.setAccountCap(id: providerID, account: account, cap: cap)
            applyProvidersResponse(resp)
            showToast(cap <= 0 || cap >= 100 ? "已取消账号额度上限" : "已设置额度上限 \(cap)%")
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func setAccountWeight(providerID: String, account: String, weight: Int) async -> Bool {
        do {
            let resp = try await client.setAccountWeight(id: providerID, account: account, weight: weight)
            applyProvidersResponse(resp)
            showToast("已更新账号权重为 \(weight)")
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func setAccountConcurrency(providerID: String, account: String, limit: Int?) async -> Bool {
        do {
            let resp = try await client.setAccountConcurrency(id: providerID, account: account, limit: limit)
            applyProvidersResponse(resp)
            showToast(limit == nil ? "已恢复跟随供应商并发" : "已设置账号并发上限 \(limit!)")
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func setAccountProxy(provider: RemoteProvider, account: String, proxy: String) async -> Bool {
        var next = provider.accountProxies
        let key = account.lowercased()
        let trimmed = proxy.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            next.removeValue(forKey: key)
        } else {
            next[key] = trimmed
        }
        return await saveProviderPayload(["id": provider.id, "accountProxies": next], toast: trimmed.isEmpty ? "已恢复跟随供应商代理" : "已更新账号专属代理")
    }

    func setProviderKeepLogin(id: String, keepLogin: Bool, keepLoginAs: String? = nil) async -> Bool {
        do {
            let resp = try await client.setProviderKeepLogin(id: id, keepLogin: keepLogin, keepLoginAs: keepLoginAs)
            applyProvidersResponse(resp)
            await refreshStateOnly()
            showToast(keepLogin ? "已固定客户端登录账号" : "已开启自动切换客户端账号")
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func setProviderSwitchOnly(id: String, switchOnly: Bool) async -> Bool {
        do {
            let resp = try await client.setProviderSwitchOnly(id: id, switchOnly: switchOnly)
            applyProvidersResponse(resp)
            await refreshStateOnly()
            showToast(switchOnly ? "已切为仅切换本地登录" : "已恢复网关代发与自动切号")
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func setProviderRestartApp(id: String, restartApp: Bool) async -> Bool {
        do {
            let resp = try await client.setProviderRestartApp(id: id, restartApp: restartApp)
            applyProvidersResponse(resp)
            showToast(restartApp ? "已开启切换后自动重启 Codex App" : "已关闭自动重启 Codex App")
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func setProviderCapStop(id: String, capStop: Bool) async -> Bool {
        do {
            let resp = try await client.setProviderCapStop(id: id, capStop: capStop)
            applyProvidersResponse(resp)
            showToast(capStop ? "已开启触及配额上限即停" : "已开启超限转入后备渠道")
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func setProviderCapCareful(id: String, capCareful: Bool) async -> Bool {
        do {
            let resp = try await client.setProviderCapCareful(id: id, capCareful: capCareful)
            applyProvidersResponse(resp)
            showToast(capCareful ? "已开启高占用自动复核" : "已关闭高占用自动复核")
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func restoreExcludedProvider(id: String, name: String) async -> Bool {
        do {
            let resp = try await client.restoreExcludedProvider(id: id)
            applyProvidersResponse(resp)
            await refreshStateOnly()
            showToast("已恢复「\(name)」")
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func forgetExcludedProvider(id: String, name: String) async -> Bool {
        do {
            let resp = try await client.forgetExcludedProvider(id: id)
            applyProvidersResponse(resp)
            await refreshStateOnly()
            showToast("已登出并清除「\(name)」")
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func moveAntigravityToAgy() async -> Bool {
        do {
            let resp = try await client.moveAntigravityToAgy()
            applyProvidersResponse(resp)
            await refreshStateOnly()
            showToast("已迁移至 Antigravity (local agy CLI)")
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func refreshPluginListings() async {
        do {
            let items = try await client.fetchPluginListings()
            pluginListings = items
        } catch {
            // Best-effort; fall back to built-in catalog when server is older
        }
    }

    func installSubscriptionPlugin(spec: String) async -> Bool {
        do {
            try await client.installPlugin(spec: spec)
            await refreshProvidersWaitAndState()
            await refreshPluginListings()
            showToast("已安装插件 \(spec)")
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func codexDaemonAction(_ action: String, toast: String) async -> Bool {
        do {
            let resp = try await client.codexDaemonAction(action)
            applyProvidersResponse(resp)
            if !toast.isEmpty { showToast(toast) }
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }
}
