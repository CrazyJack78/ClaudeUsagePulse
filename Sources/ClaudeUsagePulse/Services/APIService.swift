import Foundation

enum APIError: Error, LocalizedError {
    case notAuthenticated
    case noOrganizationId
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:  return "Nicht angemeldet"
        case .noOrganizationId: return "Organisation-ID nicht gefunden"
        case .invalidResponse:  return "Ungültige Antwort vom Server"
        case .httpError(let c): return "HTTP Fehler \(c)"
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

    func resetOrgId() { cachedOrgId = nil }

    /// Alle Top-Level-Keys der letzten Usage-Antwort (für Debug)
    private(set) var lastRawKeys: [String] = []

    // MARK: - Private

    private func resolveOrganizationId(cookies: [HTTPCookie]) async throws -> String {
        if let json = try? await getJSON(path: "/api/bootstrap", cookies: cookies) {
            if let id = json["organization_id"] as? String { return id }
            if let id = json["organizationId"]  as? String { return id }
            if let acc = json["account"] as? [String: Any],
               let id  = acc["organization_id"] as? String { return id }
            if let orgs = json["organizations"] as? [[String: Any]],
               let id   = orgs.first?["id"] as? String { return id }
        }
        if let json = try? await getJSON(path: "/api/account", cookies: cookies) {
            if let id = json["organization_id"] as? String { return id }
            if let memberships = json["memberships"] as? [[String: Any]],
               let org = memberships.first?["organization"] as? [String: Any],
               let id  = org["uuid"] as? String { return id }
        }
        throw APIError.noOrganizationId
    }

    private func fetchUsage(orgId: String, cookies: [HTTPCookie]) async throws -> UsageData {
        guard orgId.range(of: #"^[a-zA-Z0-9_-]{1,64}$"#, options: .regularExpression) != nil else {
            throw APIError.invalidResponse
        }
        let json = try await getJSON(path: "/api/organizations/\(orgId)/usage", cookies: cookies)

        var metrics: [String: MetricData] = [:]

        // Alle Keys speichern (inkl. solche ohne utilization — für Debug)
        lastRawKeys = json.keys.sorted()

        for (key, value) in json {
            guard let dict = value as? [String: Any],
                  dict["utilization"] != nil else { continue }

            var m = MetricData()
            m.percentage = min(doubleVal(dict["utilization"]), 100)
            m.resetStr   = resetStr(from: dict["resets_at"] as? String)
            m.resetAt    = (dict["resets_at"] as? String).flatMap { parseDate($0) }

            if dict["used_credits"] != nil || dict["monthly_limit"] != nil {
                m.creditInfo = (
                    used:  doubleVal(dict["used_credits"])  / 100.0,
                    limit: doubleVal(dict["monthly_limit"]) / 100.0
                )
            }

            metrics[key] = m
        }

        // Neu entdeckte Keys mit User-Configs mergen
        let discoveredKeys = Array(metrics.keys)
        await MainActor.run {
            MetricConfigStore.shared.merge(discoveredKeys: discoveredKeys)
        }

        return UsageData(metrics: metrics, fetchedAt: Date())
    }

    // MARK: - Helpers

    private func parseDate(_ str: String) -> Date? {
        let iso1 = ISO8601DateFormatter()
        iso1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso1.date(from: str) { return d }
        let iso2 = ISO8601DateFormatter()
        iso2.formatOptions = [.withInternetDateTime]
        if let d = iso2.date(from: str) { return d }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ"
        if let d = df.date(from: str) { return d }
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        return df.date(from: str)
    }

    private func resetStr(from str: String?) -> String {
        guard let str = str, let date = parseDate(str) else { return "" }
        let diff = date.timeIntervalSinceNow
        if diff <= 0 { return "Wird zurückgesetzt…" }
        let h = Int(diff / 3600)
        let m = Int(diff.truncatingRemainder(dividingBy: 3600) / 60)
        return h > 0 ? "Reset in \(h)h \(m)min" : "Reset in \(m) min"
    }

    private func doubleVal(_ v: Any?) -> Double {
        if let d = v as? Double   { return d }
        if let i = v as? Int      { return Double(i) }
        if let n = v as? NSNumber { return n.doubleValue }
        return 0
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
