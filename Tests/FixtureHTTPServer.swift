import Foundation
import Network

/// Runs inside the simulator's test process, so both the app and WebKit reach
/// the same local fixture even when the CI host's loopback is isolated.
final class FixtureHTTPServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "magpie.fixture")
    private let lock = NSLock()
    private var rows: [[String: Any]] = []
    private var traceRows: [[String: Any]] = []
    private var responses: [String: Any]
    var port: UInt16 { listener.port!.rawValue }

    init() throws {
        let file = Bundle(for: FixtureHTTPServer.self).url(forResource: "mock-responses", withExtension: "json")!
        responses = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        listener = try NWListener(using: .tcp, on: .any)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            switch state { case .ready, .failed: ready.signal(); default: break }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self = self else { connection.cancel(); return }
            connection.start(queue: self.queue)
            self.read(connection, buffer: Data())
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 10) == .success, listener.port != nil else {
            throw NSError(domain: "Fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Simulator fixture listener could not start"])
        }
    }
    func stop() { listener.cancel() }
    func requests() -> [[String: Any]] { lock.lock(); defer { lock.unlock() }; return rows }
    func trace() -> [[String: Any]] { lock.lock(); defer { lock.unlock() }; return traceRows }

    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024 * 1024) { [weak self] data, _, done, error in
            guard let self = self, error == nil else { connection.cancel(); return }
            var bytes = buffer
            if let data = data { bytes.append(data) }
            guard let boundary = bytes.range(of: Data("\r\n\r\n".utf8)) else {
                if done { connection.cancel() } else { self.read(connection, buffer: bytes) }; return
            }
            let headers = String(decoding: bytes[..<boundary.lowerBound], as: UTF8.self)
            let lengthLine = headers.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("content-length:") }
            let length = lengthLine.flatMap { Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)) } ?? 0
            guard bytes.count - boundary.upperBound >= length else { self.read(connection, buffer: bytes); return }
            let first = headers.components(separatedBy: "\r\n")[0].split(separator: " ")
            guard first.count >= 2, let url = URLComponents(string: "http://fixture" + first[1]) else { connection.cancel(); return }
            let body = Data(bytes[boundary.upperBound...].prefix(length))
            self.answer(connection, method: String(first[0]), url: url, headers: headers, body: body)
        }
    }
    private func send(_ connection: NWConnection, _ data: Data, status: Int = 200, type: String = "application/json; charset=utf-8", extra: String = "") {
        let headers = "HTTP/1.1 \(status) OK\r\nContent-Type: \(type)\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\(extra)\r\n"
        var packet = Data(headers.utf8); packet.append(data)
        connection.send(content: packet, completion: .contentProcessed { _ in connection.cancel() })
    }
    private func json(_ connection: NWConnection, _ value: Any, status: Int = 200) {
        send(connection, (try? JSONSerialization.data(withJSONObject: value)) ?? Data("{}".utf8), status: status)
    }
    private func snapshot(_ key: String) -> Any? {
        lock.lock(); defer { lock.unlock() }
        return responses[key]
    }

    private func mutateProviders(_ transform: ([[String: Any]]) -> [[String: Any]]) {
        lock.lock()
        defer { lock.unlock() }
        guard var wrap = responses["/api/providers"] as? [String: Any],
              let list = wrap["providers"] as? [[String: Any]] else { return }
        wrap["providers"] = transform(list)
        responses["/api/providers"] = wrap
    }

    private func answer(_ connection: NWConnection, method: String, url: URLComponents, headers: String, body: Data) {
        let path = url.path
        lock.lock(); traceRows.append(["method": method, "path": path, "hasSession": headers.contains("magpie_web_fixture=test-session")]); lock.unlock()
        if method == "GET", path == "/api/state", let key = url.queryItems?.first(where: { $0.name == "k" })?.value {
            guard key == "fixture-only-not-a-real-key" else { json(connection, ["error": "wrong fixture key"], status: 401); return }
            send(connection, Data(), status: 303, extra: "Set-Cookie: magpie_web_fixture=test-session; Path=/; HttpOnly; SameSite=Strict\r\nLocation: /api/state\r\n")
            return
        }
        guard headers.contains("magpie_web_fixture=test-session") else { json(connection, ["error": "Cookie required"], status: 401); return }
        if method == "GET" {
            if path == "/" {
                let html = "<!doctype html><meta name='viewport' content='width=device-width'><h1>控制台联调演示</h1><p>Cookie 会话验证通过</p><p id=tab></p><script>if(localStorage.getItem('magpie.usageTab')==='context')document.getElementById('tab').textContent='上下文页签选择通过'</script>"
                send(connection, Data(html.utf8), type: "text/html; charset=utf-8"); return
            }
            let value: Any? = { lock.lock(); defer { lock.unlock() }; return responses[path] }()
            guard let value = value else { json(connection, ["error": "unknown GET: \(path)"], status: 404); return }
            if path == "/api/gateway/trace" {
                queue.asyncAfter(deadline: .now() + 0.4) { self.json(connection, value) }
            } else { json(connection, value) }
            return
        }
        let payload = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        lock.lock(); rows.append(["path": path, "body": payload]); lock.unlock()
        if path.hasPrefix("/api/groups/") { json(connection, snapshot("/api/groups")!) }
        else if path == "/api/provider/route" {
            mutateProviders { providers in
                let pid = payload["id"] as? String ?? ""
                let routing = payload["routing"] as? String ?? ""
                return providers.map { p in
                    var m = p
                    if (m["id"] as? String) == pid { m["routing"] = routing }
                    return m
                }
            }
            json(connection, snapshot("/api/providers")!)
        }
        else if path == "/api/provider/arrange" {
            mutateProviders { providers in
                let pid = payload["id"] as? String ?? ""
                let order = payload["accountOrder"] as? [String] ?? []
                return providers.map { p in
                    var m = p
                    if (m["id"] as? String) == pid, var acc = m["account"] as? [String: Any], let logins = acc["logins"] as? [[String: Any]] {
                        var reordered: [[String]] = []
                        _ = reordered
                        var nextLogins: [[String: Any]] = []
                        for u in order {
                            if let match = logins.first(where: { ($0["user"] as? String)?.caseInsensitiveCompare(u) == .orderedSame }) {
                                nextLogins.append(match)
                            }
                        }
                        for l in logins where !nextLogins.contains(where: { ($0["user"] as? String) == (l["user"] as? String) }) {
                            nextLogins.append(l)
                        }
                        acc["logins"] = nextLogins
                        if let firstUser = nextLogins.first?["user"] as? String { acc["user"] = firstUser }
                        m["account"] = acc
                    }
                    return m
                }
            }
            json(connection, snapshot("/api/providers")!)
        }
        else if path == "/api/provider/save" || path.hasPrefix("/api/provider/") || path.hasPrefix("/api/providers/") || path.hasPrefix("/api/keys/") {
            json(connection, snapshot("/api/providers")!)
        }
        else if path == "/api/masking/values" { json(connection, ["values": ["{{EMAIL_demo}}": "demo@example.invalid"]]) }
        else if path == "/api/masking/preview" { json(connection, ["text": "预览 {{EMAIL_demo}}", "hits": []]) }
        else if path == "/api/settings/port" {
            json(connection, ["settings": snapshot("/api/settings")!, "port": ["ok": true]])
        }
        else if path == "/api/settings/archive" {
            json(connection, ["on": (payload["on"] as? Bool) ?? false, "folder": "~/.config/magpie/archive"])
        }
        else if path == "/api/settings" || path.hasPrefix("/api/settings/") { json(connection, snapshot("/api/settings")!) }
        else if path == "/api/proxies/test" { json(connection, ["ok": true, "ms": 35, "ip": "203.0.113.10", "loc": "HK"]) }
        else if path.hasPrefix("/api/proxies/") { json(connection, snapshot("/api/settings")!) }
        else if path == "/api/backup/export" {
            json(connection, ["path": "~/Downloads/magpie-2026-11-17.magpie", "providers": 1, "profiles": 1, "agents": 1, "library": true, "signIns": 0])
        }
        else if path == "/api/backup/import" {
            json(connection, ["providers": 1, "profiles": 1, "agents": 1, "settings": true, "library": true, "memory": 0, "signIns": 0, "signInsLocked": false])
        }
        else if path.hasPrefix("/api/autobackup/") { json(connection, snapshot("/api/autobackup")!) }
        else if path.hasPrefix("/api/davsync/") { json(connection, snapshot("/api/davsync")!) }
        else if path.hasPrefix("/api/tune/") {
            json(connection, ["value": (payload["value"] as? String) ?? "160000", "source": "long", "ours": true, "take": false])
        }
        else if path == "/api/model-price" { json(connection, snapshot("/api/model-price")!) }
        else if path == "/api/privacy-model" { json(connection, snapshot("/api/privacy-model")!) }
        else if path == "/api/gateway/take-over" || path == "/api/gateway/restart" { json(connection, ["ok": true]) }
        else if path == "/api/gateway/pause" { json(connection, ["paused": (payload["on"] as? Bool) ?? false, "agents": ["claude"]]) }
        else if path == "/api/gateway/unrest" {
            let targetKey = payload["key"] as? String ?? ""
            mutateProviders { providers in
                providers.map { p in
                    var m = p
                    if var rests = m["accountRests"] as? [String: [[String: Any]]] {
                        for (user, items) in rests {
                            let filtered = items.filter { ($0["key"] as? String) != targetKey }
                            if filtered.isEmpty { rests.removeValue(forKey: user) } else { rests[user] = filtered }
                        }
                        m["accountRests"] = rests
                    }
                    return m
                }
            }
            json(connection, ["lifted": true])
        }
        else if path == "/api/usage/clear" || path == "/api/usage/codex-reset" { json(connection, ["ok": true]) }
        else if path == "/api/signin" || path == "/api/plugin-signin" {
            lock.lock()
            var st = (responses["/api/signin/s1"] as? [String: Any]) ?? [:]
            if let ag = payload["agent"] as? String { st["agent"] = ag }
            st["state"] = "waiting"
            st.removeValue(forKey: "user")
            responses["/api/signin/s1"] = st
            lock.unlock()
            json(connection, st)
        }
        else if path == "/api/signin/s1/cancel" { json(connection, [:]) }
        else if path == "/api/signin/s1/callback" {
            if let cbURL = payload["url"] as? String, cbURL.contains("trigger-400") {
                json(connection, ["error": "that address isn't from this sign-in: paste the one its browser tab ended on"], status: 400)
                return
            }
            lock.lock()
            var st = (responses["/api/signin/s1"] as? [String: Any]) ?? [:]
            st["state"] = "done"
            st["user"] = "demo3@gmail.com"
            st["plan"] = "Google AI Pro"
            responses["/api/signin/s1"] = st
            lock.unlock()
            mutateProviders { providers in
                providers.map { p in
                    var m = p
                    if (m["id"] as? String) == "antigravity", var acc = m["account"] as? [String: Any], var logins = acc["logins"] as? [[String: Any]] {
                        if !logins.contains(where: { ($0["user"] as? String) == "demo3@gmail.com" }) {
                            logins.append(["agent": "antigravity", "user": "demo3@gmail.com", "plan": "Google AI Pro", "active": false, "on": true])
                        }
                        acc["logins"] = logins
                        m["account"] = acc
                    }
                    return m
                }
            }
            json(connection, [:])
        }
        else if path == "/api/signin/claude-token" { json(connection, ["user": "claude-token-demo"]) }
        else if path == "/api/signin/import" {
            json(connection, ["results": [["user": "imported@gmail.com", "status": "added"]], "providers": snapshot("/api/providers")!])
        }
        else if path == "/api/signin/export" {
            json(connection, ["path": "~/Downloads/magpie-export.json", "accounts": ["demo1@gmail.com"], "skipped": []])
        }
        else if path == "/api/plugin-signin/prompt" {
            json(connection, ["inputs": payload["inputs"] ?? [:]])
        }
        else if path == "/api/login/off" || path == "/api/login/on" {
            let enable = (path == "/api/login/on")
            let targetUser = payload["user"] as? String ?? ""
            let targetAgent = payload["agent"] as? String ?? ""
            mutateProviders { providers in
                providers.map { p in
                    var m = p
                    if var acc = m["account"] as? [String: Any], (acc["agent"] as? String) == targetAgent, var logins = acc["logins"] as? [[String: Any]] {
                        logins = logins.map { l in
                            var lm = l
                            if (lm["user"] as? String)?.caseInsensitiveCompare(targetUser) == .orderedSame {
                                lm["on"] = enable
                                lm["paused"] = !enable && ((lm["active"] as? Bool) == true)
                            }
                            return lm
                        }
                        acc["logins"] = logins
                        m["account"] = acc
                    }
                    return m
                }
            }
            json(connection, snapshot("/api/providers")!)
        }
        else if path.hasPrefix("/api/login/") || path.hasPrefix("/api/codex/daemon/") {
            json(connection, snapshot("/api/providers")!)
        }
        else if path.hasPrefix("/api/caller-keys/") { json(connection, snapshot("/api/caller-keys")!) }
        else { json(connection, snapshot("/api/state")!) }
    }
}
