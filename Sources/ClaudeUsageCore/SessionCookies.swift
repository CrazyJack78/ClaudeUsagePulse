import Foundation

/// Auswertung der Cookies von claude.ai.
///
/// Wichtig: claude.ai setzt rund dreizehn Cookies **ohne** jede Anmeldung, darunter
/// `activitySessionId`. Eine Prüfung auf "Name enthält session" schlägt dort
/// fälschlich an — genau daran scheiterte die Anmeldung ab Oktober 2026.
/// Eine Sitzung belegt allein `sessionKey`.
public enum SessionCookies {

    /// Cookie-Namen, die eine angemeldete Sitzung belegen. Exakter Vergleich.
    private static let sessionNames = ["sessionKey", "__Secure-next-auth.session-token"]

    private static let relevantDomains = ["claude.ai", "anthropic.com"]

    /// Die Organisations-ID landet in einem URL-Pfad — nur unverdächtige Zeichen zulassen.
    private static let orgIdPattern = "^[A-Za-z0-9_-]{1,64}$"

    // MARK: - Anmeldung

    public static func isLoggedIn(_ cookies: [HTTPCookie]) -> Bool {
        relevant(cookies).contains { cookie in
            sessionNames.contains(cookie.name) && !cookie.value.isEmpty
        }
    }

    /// Nur Cookies der eigenen Domains — fremde (etwa von Google) gehören nicht dazu.
    public static func relevant(_ cookies: [HTTPCookie]) -> [HTTPCookie] {
        cookies.filter { cookie in
            relevantDomains.contains { cookie.domain.contains($0) }
        }
    }

    public static func value(_ cookies: [HTTPCookie], name: String) -> String? {
        relevant(cookies).first { $0.name == name }
            .map(\.value)
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    // MARK: - Organisation

    public static func isValidOrgId(_ id: String) -> Bool {
        id.range(of: orgIdPattern, options: .regularExpression) != nil
    }

    /// Die aktive Organisation steht im Cookie `lastActiveOrg`.
    /// Der Bootstrap kann dagegen eine Organisation nennen, für die `/usage`
    /// mit 403 antwortet.
    public static func orgIdCandidates(_ cookies: [HTTPCookie]) -> [String] {
        guard let id = value(cookies, name: "lastActiveOrg"), isValidOrgId(id) else {
            return []
        }
        return [id]
    }

    /// Alle Organisationen aus dem Bootstrap, in stabiler Reihenfolge.
    /// Mehrere, damit die nächste probiert werden kann, wenn eine 403 liefert.
    public static func orgIdsFromBootstrap(_ json: [String: Any]) -> [String] {
        var found: [String] = []

        func add(_ value: Any?) {
            guard let id = value as? String, !id.isEmpty, isValidOrgId(id),
                  !found.contains(id) else { return }
            found.append(id)
        }

        add(json["organization_id"])
        add(json["organizationId"])

        if let account = json["account"] as? [String: Any] {
            add(account["organization_id"])
            for membership in account["memberships"] as? [[String: Any]] ?? [] {
                if let org = membership["organization"] as? [String: Any] {
                    add(org["uuid"]); add(org["id"])
                }
            }
        }

        for org in json["organizations"] as? [[String: Any]] ?? [] {
            add(org["uuid"]); add(org["id"])
        }

        for membership in json["memberships"] as? [[String: Any]] ?? [] {
            if let org = membership["organization"] as? [String: Any] {
                add(org["uuid"]); add(org["id"])
            }
        }

        return found
    }
}
