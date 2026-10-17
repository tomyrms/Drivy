import Foundation

/// Proposition éditable issue du jeton déjà reçu avec la session. Cette lecture ne valide pas
/// une identité et ne donne aucun droit : les commandes restent authentifiées par le serveur.
enum IdentityDisplayName {
    static func suggestion(fromIDToken token: String?, configuration: AppConfiguration) -> String? {
        guard let token, token.utf8.count <= 65_536 else { return nil }
        let sections = token.split(separator: ".", omittingEmptySubsequences: false)
        guard sections.count == 3, sections.allSatisfy({ !$0.isEmpty }) else { return nil }
        let encoded = String(sections[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padded = encoded + String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        // Ne pas utiliser le parseur AppAuth ici : ses erreurs peuvent journaliser le contenu du jeton.
        guard let data = Data(base64Encoded: padded),
              let claims = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              claims["iss"] as? String == configuration.issuer.absoluteString,
              let subject = claims["sub"] as? String, !subject.isEmpty else { return nil }
        let audiences = (claims["aud"] as? [String]) ?? (claims["aud"] as? String).map { [$0] } ?? []
        guard audiences.contains(configuration.clientID) else { return nil }
        if let name = usable(claims["name"]) { return name }
        guard let first = usable(claims["given_name"]), let last = usable(claims["family_name"]) else { return nil }
        // Composer deux champs structurés est permis ; aucun nom public n'est découpé.
        return usable("\(first) \(last)")
    }

    private static func usable(_ value: Any?) -> String? {
        guard let raw = value as? String,
              !raw.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty && value.utf16.count <= 200 ? value : nil
    }
}
