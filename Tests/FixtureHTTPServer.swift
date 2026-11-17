import Foundation
import Network

/// Runs inside the simulator's test process, so both the app and WebKit reach
/// the same local fixture even when the CI host's loopback is isolated.
final class FixtureHTTPServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "magpie.fixture")
    private let lock = NSLock()
    private var rows: [[String: Any]] = []
    private let responses: [String: Any]
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
    private func answer(_ connection: NWConnection, method: String, url: URLComponents, headers: String, body: Data) {
        let path = url.path
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
            guard let value = responses[path] else { json(connection, ["error": "unknown GET: \(path)"], status: 404); return }
            if path == "/api/gateway/trace" {
                queue.asyncAfter(deadline: .now() + 0.4) { self.json(connection, value) }
            } else { json(connection, value) }
            return
        }
        let payload = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        lock.lock(); rows.append(["path": path, "body": payload]); lock.unlock()
        if path.hasPrefix("/api/groups/") { json(connection, responses["/api/groups"]!) }
        else if path == "/api/provider/save" { json(connection, responses["/api/providers"]!) }
        else if path == "/api/masking/values" { json(connection, ["values": ["{{EMAIL_demo}}": "demo@example.invalid"]]) }
        else if path == "/api/settings" || path.hasPrefix("/api/settings/") { json(connection, responses["/api/settings"]!) }
        else if path.hasPrefix("/api/caller-keys/") { json(connection, responses["/api/caller-keys"]!) }
        else { json(connection, responses["/api/state"]!) }
    }
}
