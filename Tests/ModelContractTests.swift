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
        print("PASS: routing conditions, shared agent options, group disabled/off compatibility, numeric balance")
    }
}
