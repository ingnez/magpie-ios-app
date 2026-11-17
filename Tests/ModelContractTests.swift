import Foundation

@main
struct ModelContractTests {
    static func main() throws {
        func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
            try JSONDecoder().decode(type, from: Data(json.utf8))
        }
        let rule = try decode(RemoteGroupRule.self, #"{"use":"p/m","where":[{"field":"model","op":"eq","value":"gpt"}]}"#)
        precondition(rule.toDictionary()["where"] != nil, "Editing a routing group must preserve advanced conditions")
        let state = try decode(RemoteStateResponse.self, #"{"agents":[{"id":"claude","fields":[{"key":"model","list":1}]}],"optionLists":[[0,99,-1]],"options":[{"value":"group/main","fastFor":"*"}]}"#)
        precondition(state.agents[0].fields[0].options.count == 1)
        precondition(state.agents[0].fields[0].options[0].fastFor == "claude")
        let groups = try decode(RemoteGroupsResponse.self, #"{"groups":[{"id":"a","off":["p/m"],"disabled":true},{"id":"legacy","off":true}]}"#)
        precondition(groups.groups[0].offMembers == ["p/m"] && groups.groups[0].disabled)
        precondition(groups.groups[1].disabled)
        let balance = try decode(RemoteProviderBalanceResponse.self, #"{"ok":true,"amount":1.25}"#)
        precondition(balance.amount == "1.2500")
        let base = URL(string: "https://example.com:443/magpie")!
        precondition(sameConsoleOrigin(URL(string: "https://example.com/path")!, base))
        precondition(!sameConsoleOrigin(URL(string: "http://example.com/path")!, base))
        precondition(!sameConsoleOrigin(URL(string: "https://example.com:8443/")!, base))
        precondition(!sameConsoleOrigin(URL(string: "https://evil.example/path")!, base))
        let console = ConsoleDestination.backup.url(base: base)!
        precondition(console.path == "/magpie/" && console.query!.contains("tab=sync"))
        precondition(!console.query!.contains("k="))
        let payload = preservedProviderPayload(current: ["headers": ["X-Custom": "test"], "contexts": ["m": 200000], "chosen": ["m"], "key": ["masked": "hidden"], "models": [["id": "m"]]], changes: ["name": "Renamed"])
        precondition((payload["headers"] as? [String: String])?["X-Custom"] == "test")
        precondition(payload["key"] == nil && payload["models"] as? [String] == ["m"])
        precondition(payload["name"] as? String == "Renamed")
        let key = try decode(RemoteCallerKey.self, #"{"id":"k","limit":{"period":"week","tokens":500000},"used":{"period":"week","tokens":100,"cost":0.01,"reset":"2026-11-23"}}"#)
        precondition(key.limit?.tokens == 500000 && key.used?.tokens == 100)
        print("PASS: origins, console routes, preserved provider fields, caller budgets")
        print("PASS: routing conditions, shared agent options, group disabled/off compatibility, numeric balance")
    }
}
