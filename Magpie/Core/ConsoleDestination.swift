import Foundation

enum ConsoleDestination: String, CaseIterable, Identifiable {
    case network, backup, sessions, library, plugins, pricing
    var id: String { rawValue }
    var title: String {
        switch self {
        case .network: return "代理池与网络"
        case .backup: return "备份与同步"
        case .sessions: return "Sessions"
        case .library: return "Library"
        case .plugins: return "Plugins"
        case .pricing: return "定价与模型调优"
        }
    }
    var queryItems: [URLQueryItem] {
        let view: String
        let tab: String?
        switch self {
        case .network: view = "settings"; tab = "network"
        case .backup: view = "settings"; tab = "sync"
        case .sessions: view = "sessions"; tab = nil
        case .library: view = "library"; tab = nil
        case .plugins: view = "plugins"; tab = nil
        case .pricing: view = "settings"; tab = "models"
        }
        var query = [URLQueryItem(name: "mode", value: "window"), URLQueryItem(name: "view", value: view)]
        if let tab = tab { query.append(URLQueryItem(name: "tab", value: tab)) }
        return query
    }
    func url(base: URL) -> URL? {
        guard var parts = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        if !parts.path.hasSuffix("/") { parts.path += "/" }
        parts.queryItems = queryItems
        parts.fragment = nil
        return parts.url
    }
}

func sameConsoleOrigin(_ url: URL, _ base: URL) -> Bool {
    func port(_ url: URL) -> Int? { url.port ?? (url.scheme?.lowercased() == "https" ? 443 : (url.scheme?.lowercased() == "http" ? 80 : nil)) }
    return ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        && url.scheme?.lowercased() == base.scheme?.lowercased()
        && url.host?.lowercased() == base.host?.lowercased()
        && port(url) == port(base)
}
