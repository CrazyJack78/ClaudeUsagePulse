import Foundation

enum APIError: Error, LocalizedError {
    case notAuthenticated
    case noOrganizationId
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:   return "Nicht angemeldet"
        case .noOrganizationId:  return "Organisation-ID nicht gefunden"
        case .invalidResponse:   return "Ungültige Antwort vom Server"
        case .httpError(let c):  return "HTTP Fehler \(c)"
        }
    }
}

class APIService {
    static let shared = APIService()
    private var cachedOrgId: String?

    func fetchUsageData() async throws -> UsageData {
        let cookies = KeychainService.loadCookies()
        guard !cookies.isEmpty else { throw APIError.notAuthenticated }

        if cachedOrgId == nil { cachedOrgId = KeychainService.loadOrgId() }

        if cachedOrgId == nil {
            let orgId = try await resolveOrganizationId(cookies: cookies)
            KeychainService.saveOrgId(orgId)
            cachedOrgId = orgId
        }

        return try await fetchUsage(orgId: cachedOrgId!, cookies: cookies)
    }

    func resetOrgId() {
        cachedOrgId = nil
    }

    // MARK: - Private

    private func resolveOrganizationId(cookies: [HTTPCookie]) async throws -> String {
        // Versuch 1: Bootstrap-Endpoint
        if let json = try? await getJSON(path: "/api/bootstrap", cookies: cookies) {
            if let id = json["organization_id"] as? String { return id }
            if let id = json["organizationId"] as? String { return id }
            if let acc = json["account"] as? [String: Any],
               let id  = acc["organization_id"] as? String { return id }
            if let orgs = json["organizations"] as? [[String: Any]],
               let id   = orgs.first?["id"] as? String { return id }
        }
        // Versuch 2: Account-Endpoint
        if let json = try? await getJSON(path: "/api/account", cookies: cookies) {
            if let id = json["organization_id"] as? String { return id }
            if let memberships = json["memberships"] as? [[String: Any]],
               let org = memberships.first?["organization"] as? [String: Any],
               let id  = org["uuid"] as? String { return id }
        }
        throw APIError.noOrganizationId
    }

    private func fetchUsage(orgId: String, cookies: [HTTPCookie]) async throws -> UsageData {
        let json = try await getJSON(path: "/api/organizations/\(orgId)/usage", cookies: cookies)

        let fiveHour = json["five_hour"] as? [String: Any] ?? [:]
        let sevenDay  = json["seven_day"]  as? [String: Any] ?? [:]

        // utilization ist bereits ein Prozentwert 0–100 (z.B. 43 = 43%)
        let sessionPct = min(fiveHour["utilization"] as? Double ?? 0, 100)
        let weeklyPct  = min(sevenDay["utilization"]  as? Double ?? 0, 100)

        let iso = ISO8601DateFormatter()
        let sessionReset = (fiveHour["resets_at"] as? String).flatMap { iso.date(from: $0) }
        let weeklyReset  = (sevenDay["resets_at"]  as? String).flatMap { iso.date(from: $0) }

        return UsageData(
            sessionPercentage: sessionPct,
            weeklyPercentage:  weeklyPct,
            sessionResetAt:    sessionReset,
            weeklyResetAt:     weeklyReset,
            fetchedAt:         Date()
        )
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

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        if http.statusCode == 401 || http.statusCode == 403 { throw APIError.notAuthenticated }
        guard http.statusCode == 200 else { throw APIError.httpError(http.statusCode) }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }
        return json
    }
}
