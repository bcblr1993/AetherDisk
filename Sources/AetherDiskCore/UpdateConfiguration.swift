import Foundation
public struct UpdateConfiguration: Sendable {
    public let feed: String
    public let publicKey: String
    public init(feed: String, publicKey: String) { self.feed = feed; self.publicKey = publicKey }
    public var valid: Bool {
        guard let u = URLComponents(string: feed), u.scheme == "https", let host = u.host, !host.isEmpty, u.user == nil, u.password == nil, u.fragment == nil else { return false }
        return Data(base64Encoded: publicKey)?.count == 32
    }
}
