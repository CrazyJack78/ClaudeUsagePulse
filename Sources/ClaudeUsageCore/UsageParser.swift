import Foundation

/// Wertet die Antwort von `GET /api/organizations/{orgId}/usage` aus.
///
/// Die Antwort hat seit Juli 2026 drei Ebenen, die nebeneinander existieren:
///
/// 1. `limits[]`     — die aktuelle Quelle. Enthält auch modellspezifische Grenzen
///                     wie Fable, die in **keinem** Top-Level-Schlüssel auftauchen.
/// 2. Top-Level      — die ältere Form; viele Schlüssel stehen inzwischen auf `null`.
/// 3. `spend`        — Guthaben, löst das alte `extra_usage` ab.
///
/// Bei Dubletten gewinnt `limits[]`, damit dieselbe Grenze nicht zweimal erscheint.
public enum UsageParser {

    /// Schlüssel, die keine Metrik sind.
    private static let nonMetricKeys: Set<String> = [
        "limits", "spend", "member_dashboard_available"
    ]

    /// `limits[].kind` auf den bisherigen Schlüssel abbilden, damit Top-Level
    /// und `limits` dieselbe Grenze bezeichnen.
    private static let kindToKey: [String: String] = [
        "session": "five_hour",
        "weekly_all": "seven_day"
    ]

    public static func parse(_ json: [String: Any]) -> UsageData {
        var metrics: [String: MetricData] = [:]

        parseLimits(json["limits"], into: &metrics)
        parseTopLevel(json, into: &metrics)
        parseSpend(json["spend"], into: &metrics)

        let ordered = metrics.keys.sorted { lhs, rhs in
            let l = metrics[lhs]!.sortRank, r = metrics[rhs]!.sortRank
            return l == r ? lhs < rhs : l < r
        }

        return UsageData(metrics: metrics, orderedKeys: ordered)
    }

    // MARK: - 1) limits[]

    private static func parseLimits(_ raw: Any?, into metrics: inout [String: MetricData]) {
        guard let limits = raw as? [[String: Any]] else { return }

        for entry in limits {
            guard let kind = entry["kind"] as? String, !kind.isEmpty else { continue }

            let modelName = (entry["scope"] as? [String: Any])
                .flatMap { $0["model"] as? [String: Any] }
                .flatMap { $0["display_name"] as? String }
                .flatMap { $0.isEmpty ? nil : $0 }

            let key: String
            if let modelName {
                key = "scoped_" + slug(modelName)
            } else {
                key = kindToKey[kind] ?? kind
            }

            var metric = MetricData()
            metric.percentage = clamp(double(entry["percent"]) ?? 0)
            metric.resetAt = date(entry["resets_at"])
            metric.isActive = entry["is_active"] as? Bool ?? false
            metric.severity = entry["severity"] as? String ?? "normal"
            metric.suggestedName = modelName
            metric.sortRank = rank(for: key)

            metrics[key] = metric
        }
    }

    // MARK: - 2) Top-Level-Schlüssel

    private static func parseTopLevel(_ json: [String: Any],
                                      into metrics: inout [String: MetricData]) {
        for (key, value) in json {
            if nonMetricKeys.contains(key) { continue }
            if metrics[key] != nil { continue }               // limits[] hat Vorrang
            guard let dict = value as? [String: Any] else { continue }

            // `utilization: null` bedeutet "nicht vorhanden". In Swift besteht NSNull
            // die Prüfung `!= nil` — genau dort entstand der 0-%-Geisterbalken.
            guard let utilization = double(dict["utilization"]) else { continue }

            var metric = MetricData()
            metric.percentage = clamp(utilization)
            metric.resetAt = date(dict["resets_at"])
            metric.severity = dict["severity"] as? String ?? "normal"
            metric.creditInfo = legacyCredit(dict)
            metric.sortRank = rank(for: key)

            metrics[key] = metric
        }
    }

    /// Alte Guthaben-Felder: Beträge in Cent.
    private static func legacyCredit(_ dict: [String: Any]) -> CreditInfo? {
        guard let used = double(dict["used_credits"]) else { return nil }
        return CreditInfo(
            used: used / 100.0,
            limit: double(dict["monthly_limit"]).map { $0 / 100.0 },
            currency: dict["currency"] as? String ?? "EUR"
        )
    }

    // MARK: - 3) spend

    private static func parseSpend(_ raw: Any?, into metrics: inout [String: MetricData]) {
        guard let spend = raw as? [String: Any],
              spend["enabled"] as? Bool == true else { return }

        let used = spend["used"] as? [String: Any]
        let limit = spend["limit"] as? [String: Any]

        var metric = MetricData()
        metric.percentage = clamp(double(spend["percent"]) ?? 0)
        metric.severity = spend["severity"] as? String ?? "normal"
        metric.suggestedName = "Guthaben"
        metric.sortRank = 4
        metric.creditInfo = CreditInfo(
            used: money(used),
            limit: limit.map { money($0) },
            currency: used?["currency"] as? String ?? "USD"
        )

        metrics["spend"] = metric
    }

    /// `{ amount_minor: 1250, exponent: 2 }` entspricht 12,50
    private static func money(_ dict: [String: Any]?) -> Double {
        guard let dict else { return 0 }
        let minor = double(dict["amount_minor"]) ?? 0
        let exponent = (dict["exponent"] as? Int) ?? 2
        return minor / pow(10.0, Double(exponent))
    }

    // MARK: - Helfer

    private static func rank(for key: String) -> Int {
        switch key {
        case "five_hour": return 0
        case "seven_day": return 1
        case "spend": return 4
        default: return key.hasPrefix("scoped_") ? 2 : 3
        }
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 100)
    }

    private static func slug(_ name: String) -> String {
        let lowered = name.lowercased()
        let mapped = lowered.map { ch -> Character in
            ch.isLetter || ch.isNumber ? ch : "_"
        }
        return String(mapped)
            .split(separator: "_", omittingEmptySubsequences: true)
            .joined(separator: "_")
    }

    /// `null` sauber als "nicht vorhanden" behandeln — NSNull ist nicht nil.
    private static func double(_ value: Any?) -> Double? {
        switch value {
        case let d as Double: return d
        case let i as Int: return Double(i)
        case let n as NSNumber:
            // Bool kommt als NSNumber an und ist hier kein sinnvoller Messwert
            return n === kCFBooleanTrue || n === kCFBooleanFalse ? nil : n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }

    /// Akzeptiert ISO-8601 mit und ohne Sekundenbruchteile.
    private static func date(_ value: Any?) -> Date? {
        guard let text = value as? String, !text.isEmpty else { return nil }

        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) { return date }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ"
        if let date = formatter.date(from: text) { return date }
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        return formatter.date(from: text)
    }
}
