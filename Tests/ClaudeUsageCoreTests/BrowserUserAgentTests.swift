import XCTest
@testable import ClaudeUsageCore

/// Google verweigert Anmeldungen in eingebetteten Browser-Ansichten. Erkannt werden
/// sie am User-Agent: Dem Standard eines WKWebView fehlt der abschliessende
/// `Version/… Safari/…`-Teil, den ein echter Safari mitschickt.
final class BrowserUserAgentTests: XCTestCase {

    /// Der tatsächliche Standard-User-Agent eines WKWebView unter macOS 27.
    private let webViewDefault =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko)"

    func test_derSafariTeilWirdErgaenzt() {
        let result = BrowserUserAgent.safariLike(from: webViewDefault, safariVersion: "27.0")
        XCTAssertEqual(
            result,
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.0 Safari/605.1.15"
        )
    }

    func test_dieWebKitVersionWirdAusDemOriginalUebernommen() {
        let eigen = "Mozilla/5.0 (Macintosh) AppleWebKit/612.3.4 (KHTML, like Gecko)"
        let result = BrowserUserAgent.safariLike(from: eigen, safariVersion: "28.1")
        XCTAssertTrue(result.hasSuffix("Version/28.1 Safari/612.3.4"), result)
    }

    func test_einVollstaendigerSafariBleibtUnveraendert() {
        let safari = webViewDefault + " Version/27.0 Safari/605.1.15"
        XCTAssertEqual(BrowserUserAgent.safariLike(from: safari, safariVersion: "27.0"), safari)
    }

    func test_ohneWebKitAngabeGibtEsEinenVerlaesslichenRueckfall() {
        let result = BrowserUserAgent.safariLike(from: "irgendwas", safariVersion: "27.0")
        XCTAssertTrue(result.contains("Safari/"), result)
        XCTAssertTrue(result.contains("Version/27.0"), result)
    }

    func test_leererUserAgentErgibtEinenVollstaendigenSafari() {
        let result = BrowserUserAgent.safariLike(from: "", safariVersion: "27.0")
        XCTAssertTrue(result.hasPrefix("Mozilla/5.0 (Macintosh"), result)
        XCTAssertTrue(result.contains("Version/27.0 Safari/"), result)
    }

    func test_dieErmittelteVersionIstPlausibel() {
        // Darf nie leer sein und muss mit einer Ziffer beginnen,
        // sonst entsteht ein kaputter User-Agent.
        let version = BrowserUserAgent.detectedSafariVersion()
        XCTAssertFalse(version.isEmpty)
        XCTAssertTrue(version.first?.isNumber == true, version)
    }

    func test_derFertigeUserAgentWirdVonGoogleNichtAlsEingebettetErkannt() {
        let result = BrowserUserAgent.current(from: webViewDefault)
        // Beide Merkmale muessen vorhanden sein
        XCTAssertTrue(result.contains("Version/"), result)
        XCTAssertTrue(result.contains("Safari/"), result)
    }
}
