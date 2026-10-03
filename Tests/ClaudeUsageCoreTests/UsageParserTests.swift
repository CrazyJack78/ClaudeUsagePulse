import XCTest
@testable import ClaudeUsageCore

/// Die Antwort hat seit Juli 2026 drei Ebenen: die alten Top-Level-Schlüssel,
/// das neue `limits`-Array und `spend` für Guthaben.
final class UsageParserTests: XCTestCase {

    private func parse(_ json: [String: Any]) -> UsageData {
        UsageParser.parse(json)
    }

    // MARK: - limits[] als Hauptquelle

    func test_sessionAusLimitsWirdAufFiveHourAbgebildet() throws {
        let metric = try XCTUnwrap(parse(Fixtures.usageCurrent).metrics["five_hour"])
        XCTAssertEqual(metric.percentage, 6)
        XCTAssertNotNil(metric.resetAt)
    }

    func test_weeklyAllWirdAufSevenDayAbgebildet() {
        let data = parse(Fixtures.usageCurrent)
        XCTAssertEqual(data.metrics["seven_day"]?.percentage, 13)
        XCTAssertEqual(data.metrics["seven_day"]?.isActive, true)
    }

    /// Der Kern: Fable steht ausschließlich in limits[].scope.model —
    /// deshalb konnte v0.1.6 den Balken nie finden.
    func test_modellspezifischeGrenzeErscheintMitModellnamen() {
        let data = parse(Fixtures.usageCurrent)
        let fable = data.metrics["scoped_fable"]

        XCTAssertNotNil(fable, "Fable muss aus limits[].scope.model stammen")
        XCTAssertEqual(fable?.percentage, 0)
        XCTAssertEqual(fable?.suggestedName, "Fable",
                       "Der Anzeigename kommt aus display_name, nicht aus dem Schlüssel")
    }

    func test_anderesModellBekommtEigenenSchluessel() {
        let data = parse(Fixtures.usageWithCredits)
        XCTAssertEqual(data.metrics["scoped_opus"]?.percentage, 45)
        XCTAssertEqual(data.metrics["scoped_opus"]?.suggestedName, "Opus")
    }

    func test_schweregradWirdUebernommen() {
        XCTAssertEqual(parse(Fixtures.usageWithCredits).metrics["five_hour"]?.severity,
                       "critical")
    }

    // MARK: - Top-Level-Schlüssel

    func test_schluesselAufNullErzeugenKeineMetrik() {
        let data = parse(Fixtures.usageCurrent)
        for key in ["seven_day_sonnet", "seven_day_opus", "seven_day_omelette",
                    "seven_day_cowork", "seven_day_oauth_apps", "tangelo",
                    "iguana_necktie", "omelette_promotional", "cinder_cove",
                    "amber_ladder", "juniper_tide"] {
            XCTAssertNil(data.metrics[key], "\(key) steht auf null")
        }
    }

    /// Genau hier entstand der 0-%-Geisterbalken: In Swift besteht NSNull
    /// die Prüfung `!= nil`, die Metrik wurde also angelegt.
    func test_extraUsageMitUtilizationNullErzeugtKeineMetrik() {
        XCTAssertNil(parse(Fixtures.usageCurrent).metrics["extra_usage"])
    }

    func test_unbekannterSchluesselMitUtilizationWirdUebernommen() {
        XCTAssertEqual(parse(Fixtures.usageCurrent).metrics["nimbus_quill"]?.percentage, 0)
    }

    func test_keineDublettenZwischenLimitsUndTopLevel() {
        let data = parse(Fixtures.usageCurrent)
        XCTAssertEqual(data.metrics.keys.filter { $0 == "five_hour" }.count, 1)
        XCTAssertEqual(data.metrics.keys.filter { $0 == "seven_day" }.count, 1)
    }

    // MARK: - Guthaben

    func test_spendOhneFreischaltungErzeugtKeineMetrik() {
        XCTAssertNil(parse(Fixtures.usageCurrent).metrics["spend"])
    }

    func test_spendLiefertBetraegeInWaehrungseinheiten() throws {
        let metric = try XCTUnwrap(parse(Fixtures.usageWithCredits).metrics["spend"])
        let credit = try XCTUnwrap(metric.creditInfo)
        // amount_minor 1250 bei exponent 2 entspricht 12,50
        XCTAssertEqual(credit.used, 12.50, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(credit.limit), 50.00, accuracy: 0.001)
        XCTAssertEqual(credit.currency, "EUR")
    }

    func test_spendProzentWirdUebernommen() {
        XCTAssertEqual(parse(Fixtures.usageWithCredits).metrics["spend"]?.percentage, 25)
    }

    // MARK: - Rückwärtskompatibilität

    func test_alteStrukturOhneLimitsFunktioniertWeiter() {
        let data = parse(Fixtures.usageLegacy)
        XCTAssertEqual(data.metrics["five_hour"]?.percentage, 42)
        XCTAssertEqual(data.metrics["seven_day"]?.percentage, 55)
        XCTAssertEqual(data.metrics["seven_day_sonnet"]?.percentage, 30)
    }

    func test_alteGuthabenFelderWerdenWeiterGelesen() throws {
        let metric = try XCTUnwrap(parse(Fixtures.usageLegacy).metrics["extra_usage"])
        let credit = try XCTUnwrap(metric.creditInfo)
        XCTAssertEqual(credit.used, 5.0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(credit.limit), 25.0, accuracy: 0.001)
    }

    // MARK: - Robustheit

    func test_prozentwerteWerdenBegrenzt() {
        let json = Fixtures.json("""
          {"five_hour": {"utilization": 150}, "seven_day": {"utilization": -5}}
        """)
        let data = parse(json)
        XCTAssertEqual(data.metrics["five_hour"]?.percentage, 100)
        XCTAssertEqual(data.metrics["seven_day"]?.percentage, 0)
    }

    func test_leereAntwortLiefertKeineMetriken() {
        XCTAssertTrue(parse([:]).metrics.isEmpty)
    }

    // MARK: - Reihenfolge

    func test_reihenfolgeSessionDannWocheDannRest() {
        let keys = parse(Fixtures.usageCurrent).orderedKeys
        XCTAssertEqual(keys.first, "five_hour")
        XCTAssertEqual(keys.dropFirst().first, "seven_day")
        XCTAssertTrue(keys.contains("scoped_fable"))
    }

    // MARK: - Zeitangaben

    func test_resetMitMikrosekundenUndOffsetWirdGelesen() {
        let metric = parse(Fixtures.usageCurrent).metrics["five_hour"]
        let expected = ISO8601DateFormatter().date(from: "2026-09-02T15:00:00Z")!
        XCTAssertEqual(metric?.resetAt?.timeIntervalSince1970 ?? 0,
                       expected.timeIntervalSince1970, accuracy: 1.0)
    }

    func test_fehlendesResetBleibtLeer() {
        XCTAssertNil(parse(Fixtures.usageCurrent).metrics["nimbus_quill"]?.resetAt)
    }

    func test_resetTextWirdAusDerVerbleibendenZeitGebildet() {
        var metric = MetricData()
        metric.resetAt = Date().addingTimeInterval(2 * 3600 + 30 * 60)
        XCTAssertEqual(metric.resetStr, "Reset in 2h 30min")

        metric.resetAt = Date().addingTimeInterval(45 * 60)
        XCTAssertEqual(metric.resetStr, "Reset in 45 min")

        metric.resetAt = Date().addingTimeInterval(-60)
        XCTAssertEqual(metric.resetStr, "Wird zurückgesetzt…")

        metric.resetAt = nil
        XCTAssertEqual(metric.resetStr, "")
    }
}
