import Foundation

struct AppConfiguration: Codable, Equatable, Sendable {
    let apiBaseURL: URL
    let issuer: URL
    let clientID: String
    let redirectURL: URL

    static let callback = URL(string: "ch.drivy.qualification:/oauth/callback")!

    static func fromBundle() -> AppConfiguration? {
        from(values: Bundle.main.infoDictionary ?? [:])
    }

    static func from(values: [String: Any]) -> AppConfiguration? {
        guard let api = values["DrivyAPIBaseURL"] as? String,
              let issuer = values["DrivyOIDCIssuer"] as? String,
              let clientID = values["DrivyOIDCClientID"] as? String,
              let apiURL = URL(string: api), let issuerURL = URL(string: issuer) else { return nil }
        let configuration = AppConfiguration(apiBaseURL: apiURL, issuer: issuerURL,
                                             clientID: clientID, redirectURL: callback)
        return configuration.isValid ? configuration : nil
    }

    var isValid: Bool {
        Self.isSecureEndpoint(apiBaseURL) && Self.isSecureEndpoint(issuer)
            && !clientID.isEmpty && clientID.count <= 200
            && clientID.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil
            && !clientID.contains("$(") && redirectURL.absoluteString == Self.callback.absoluteString
    }

    static func isSecureEndpoint(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return parts.scheme == "https" && !(parts.host ?? "").isEmpty
            && parts.user == nil && parts.password == nil && parts.query == nil && parts.fragment == nil
            && !url.absoluteString.contains("$(")
    }

    func acceptsIdentityEndpoint(_ url: URL) -> Bool {
        Self.isSecureEndpoint(url) && url.host == issuer.host && (url.port ?? 443) == (issuer.port ?? 443)
    }
}
