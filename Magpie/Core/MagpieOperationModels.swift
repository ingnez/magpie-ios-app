import Foundation

struct RemoteCallerKeyChangeResponse: Decodable {
    let keys: [RemoteCallerKey]
    let secret: String?
}
struct RemoteCallerLimit: Decodable, Equatable {
    let period: String
    let tokens: Int64?
    let cost: Double?
}
struct RemoteCallerUsage: Decodable, Equatable {
    let period: String
    let tokens: Int64
    let cost: Double
    let reset: String
}
struct RemoteMaskingSent: Decodable { let body: String }
struct RemoteMaskingValues: Decodable { let values: [String: String] }
struct RemoteWarmResponse: Decodable { let results: [RemoteWarmResult] }
struct RemoteWarmResult: Decodable {
    let user: String?
    let skip: String?
    let error: String?
}
struct RemoteCheckinResult: Decodable {
    let user: String?
    let outcome: String
    let msg: String?
}
