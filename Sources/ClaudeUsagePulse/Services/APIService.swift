import Foundation
import ClaudeUsageCore

enum APIError: Error, LocalizedError {
    case notAuthenticated
    case noOrganizationId
    case invalidResponse
    case blocked
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Nicht angemeldet"
        case .noOrganizationId: return "Organisation-ID nicht gefunden"
        case .invalidResponse:  return "Ungültige Antwort vom Server"
        case .blocked:          return "Vom Server abgewiesen, bitte später erneut"
        case .httpError(let c): return "HTTP Fehler \(c)"
        }
    }
}

class APIService {
    static let shared = APIService()
    private var cachedOrgId: String?

    /// Alle Top-Level-Keys der letzten Usage-Antwort (für die Debug-Ansicht)
    private(set) var lastRawKeys: [String] = []

    func fetchUsageData() async throws -> UsageData {
        let cookies = KeychainService.loadCookies()

        // Auf das echte Sitzungs-Cookie prüfen. Die anonymen Cookies von claude.ai
        // belegen keine Anmeldung.
        guard SessionCookies.isLoggedIn(cookies) else { throw APIError.notAuthenticated }

        for orgId in try await organizationCandidates(cookies: cookies) {
            do {
                let data = try await fetchUsage(orgId: orgId, cookies: cookies)
                // Erst bei Erfolg merken — eine Organisation ohne Berechtigung
                // soll nicht im Keychain landen.
                KeychainService.saveOrgId(orgId)
                cachedOrgId = orgId
                return data
            } catch APIError.notAuthenticated {
                // 403 kann auch "falsche Organisation" bedeuten — nächste probieren
                cachedOrgId = nil
                continue
            }
        }
        throw APIError.noOrganizationId
    }

    func resetOrgId() {
        cachedOrgId = nil
    }

    // MARK: - Organisation ermitteln

    /// Reihenfolge: zuletzt erfolgreiche, dann das Cookie `lastActiveOrg`,
    /// zuletzt der Bootstrap.
    ///
    /// Der Bootstrap ist mehrere hundert Kilobyte gross und kann eine Organisation
    /// nennen, für die `/usage` mit 403 antwortet. Deshalb wird er nur befragt,
    /// wenn die günstigeren Quellen nichts hergeben.
    private func organizationCandidates(cookies: [HTTPCookie]) async throws -> [String] {
        var candidates: [String] = []

        func add(_ id: String?) {
            guard let id, SessionCookies.isValidOrgId(id), !candidates.contains(id) else { return }
            candidates.append(id)
        }

        add(cachedOrgId ?? KeychainService.loadOrgId())
        SessionCookies.orgIdCandidates(cookies).forEach { add($0) }

        if candidates.isEmpty,
           let json = try? await getJSON(path: "/api/bootstrap", cookies: cookies) {
            SessionCookies.orgIdsFromBootstrap(json).forEach { add($0) }
        }

        guard !candidates.isEmpty else { throw APIError.noOrganizationId }
        return candidates
    }

    // MARK: - Abruf

    private func fetchUsage(orgId: String, cookies: [HTTPCookie]) async throws -> UsageData {
        guard SessionCookies.isValidOrgId(orgId) else { throw APIError.invalidResponse }

        let json = try await getJSON(path: "/api/organizations/\(orgId)/usage",
                                     cookies: cookies)
        lastRawKeys = json.keys.sorted()

        let data = UsageParser.parse(json)

        // Neu entdeckte Metriken mit den Einstellungen des Nutzers zusammenführen
        let discovered = data.orderedKeys.map { key in
            (key: key, suggestedName: data.metrics[key]?.suggestedName)
        }
        await MainActor.run {
            MetricConfigStore.shared.merge(discovered: discovered)
        }

        return data
    }

    private func getJSON(path: String, cookies: [HTTPCookie]) async throws -> [String: Any] {
        guard let url = URL(string: "https://claude.ai\(path)") else {
            throw APIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; "),
            forHTTPHeaderField: "Cookie"
        )
        // Bewusst kein eigener User-Agent: Mit einem Browser-Kennzeichen antwortet
        // Cloudflare mit einer Bot-Challenge, weil der TLS-Fingerabdruck nicht dazu passt.

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        if http.statusCode == 403,
           let body = String(data: data, encoding: .utf8),
           body.contains("Just a moment") {
            throw APIError.blocked
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw APIError.notAuthenticated
        }
        guard http.statusCode == 200 else { throw APIError.httpError(http.statusCode) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }
        return json
    }
}
