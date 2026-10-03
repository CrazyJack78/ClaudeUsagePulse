import Foundation

/// Guthaben-Angaben in Währungseinheiten, nicht in Cent.
public struct CreditInfo: Equatable {
    public var used: Double
    public var limit: Double?
    public var currency: String

    public init(used: Double, limit: Double?, currency: String) {
        self.used = used
        self.limit = limit
        self.currency = currency
    }
}

public struct MetricData {
    public var percentage: Double = 0
    public var resetAt: Date? = nil
    public var creditInfo: CreditInfo? = nil

    /// Anzeigename aus der API, etwa "Fable" aus `limits[].scope.model.display_name`.
    /// Wird nur für neu entdeckte Metriken als Vorschlag genutzt.
    public var suggestedName: String? = nil

    public var isActive: Bool = false
    public var severity: String = "normal"

    /// Für die Anzeigereihenfolge: Session, Woche, modellspezifisch, Rest, Guthaben.
    public var sortRank: Int = 3

    public init() {}

    /// Verbleibende Zeit bis zum Zurücksetzen.
    ///
    /// Wird bei jedem Zugriff neu berechnet, damit der Text nicht veraltet,
    /// wenn die Daten ein paar Minuten alt sind.
    public var resetStr: String {
        guard let resetAt else { return "" }
        let diff = resetAt.timeIntervalSinceNow.rounded()
        if diff <= 0 { return "Wird zurückgesetzt…" }
        let hours = Int(diff / 3600)
        let minutes = Int(diff.truncatingRemainder(dividingBy: 3600) / 60)
        return hours > 0 ? "Reset in \(hours)h \(minutes)min" : "Reset in \(minutes) min"
    }
}

public struct UsageData {
    public var metrics: [String: MetricData] = [:]

    /// Schlüssel in Anzeigereihenfolge — ein Dictionary hat keine.
    public var orderedKeys: [String] = []

    public var fetchedAt: Date = Date()
    public var error: String? = nil

    public init(metrics: [String: MetricData] = [:],
                orderedKeys: [String] = [],
                fetchedAt: Date = Date(),
                error: String? = nil) {
        self.metrics = metrics
        self.orderedKeys = orderedKeys
        self.fetchedAt = fetchedAt
        self.error = error
    }

    public subscript(key: String) -> MetricData {
        metrics[key] ?? MetricData()
    }
}
