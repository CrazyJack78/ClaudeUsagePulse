import Foundation

/// Baut einen User-Agent, den Google als vollwertigen Browser akzeptiert.
///
/// Google verweigert Anmeldungen in eingebetteten Browser-Ansichten (Schutz gegen
/// Phishing, seit 2021). Erkannt werden sie am User-Agent: Dem Standard eines
/// `WKWebView` fehlt der abschliessende `Version/… Safari/…`-Teil.
///
/// ```
/// WKWebView: …AppleWebKit/605.1.15 (KHTML, like Gecko)
/// Safari:    …AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.0 Safari/605.1.15
/// ```
///
/// Das ist das Gegenstück zum `; wv`, das auf Android entfernt werden muss.
public enum BrowserUserAgent {

    private static let fallbackWebKitVersion = "605.1.15"

    private static let fallbackBase =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        + "AppleWebKit/\(fallbackWebKitVersion) (KHTML, like Gecko)"

    /// Fertiger User-Agent für die Anmeldeansicht.
    public static func current(from base: String) -> String {
        safariLike(from: base, safariVersion: detectedSafariVersion())
    }

    /// Ergänzt den fehlenden Safari-Teil. Ein bereits vollständiger User-Agent
    /// bleibt unverändert.
    public static func safariLike(from base: String, safariVersion: String) -> String {
        guard !base.contains("Safari/") else { return base }

        let source = base.isEmpty ? fallbackBase : base
        let webKitVersion = extractWebKitVersion(from: source) ?? fallbackWebKitVersion

        // Fehlt die WebKit-Kennung ganz, ist der Ausgangswert unbrauchbar —
        // dann lieber einen vollständigen Standard-Safari aufbauen.
        let prefix = source.contains("AppleWebKit/") ? source : fallbackBase

        return "\(prefix) Version/\(safariVersion) Safari/\(webKitVersion)"
    }

    /// Safari-Version des Systems. Seit macOS 26 entspricht die Hauptnummer der
    /// des Betriebssystems, was als Rückfall dient, falls Safari nicht am
    /// erwarteten Ort liegt.
    public static func detectedSafariVersion() -> String {
        if let plist = NSDictionary(contentsOfFile:
                "/Applications/Safari.app/Contents/Info.plist"),
           let version = plist["CFBundleShortVersionString"] as? String,
           let major = version.split(separator: ".").first,
           Int(major) != nil {
            let minor = version.split(separator: ".").dropFirst().first ?? "0"
            return "\(major).\(minor)"
        }

        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "\(os.majorVersion).\(os.minorVersion)"
    }

    private static func extractWebKitVersion(from userAgent: String) -> String? {
        guard let range = userAgent.range(of: "AppleWebKit/") else { return nil }
        let rest = userAgent[range.upperBound...]
        let version = rest.prefix { $0.isNumber || $0 == "." }
        return version.isEmpty ? nil : String(version)
    }
}
