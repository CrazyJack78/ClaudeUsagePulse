import AppKit
import WebKit
import ClaudeUsageCore

/// Anmeldefenster für claude.ai.
///
/// Zwei Dinge sind hier entscheidend und waren bis v0.1.6 falsch:
///
/// **1. Woran die Anmeldung erkannt wird.** claude.ai setzt rund dreizehn Cookies
/// schon *ohne* Anmeldung, darunter `activitySessionId`. Die frühere Prüfung
/// "Name enthält session" schlug dort an, hielt die Anmeldung für erledigt und
/// schloss das Fenster mitten im Vorgang. Jetzt zählt allein `sessionKey`.
///
/// **2. Wie das Fenster verschwindet.** Ein per Code erzeugtes `NSWindow` hat
/// `isReleasedWhenClosed == true`: `close()` gibt es frei, und das anschliessende
/// `window = nil` gibt es ein zweites Mal frei. Der Absturz fällt dabei nicht sofort
/// auf, sondern erst beim Leeren des Autorelease-Pools des Main-Run-Loops — daher
/// die Stapel, die nur noch `objc_release` zeigen.
/// Jetzt wird das Fenster einmal erzeugt, nie freigegeben und beim Erfolg nur
/// ausgeblendet.
final class AuthWebWindow: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {

    var onAuthSuccess: (() -> Void)?
    private(set) var isShowing = false

    private var cookieCheckTimer: Timer?

    /// Zweites Fenster des Anmeldevorgangs (Google öffnet es über window.open).
    private var popupWebView: WKWebView?

    /// Einmal erstellt, NIEMALS deallociert.
    /// WKWebView spricht über IPC mit einem eigenen Web-Content-Prozess. Wird es
    /// freigegeben, während dieser Prozess noch läuft, landen interne Objekte im
    /// Autorelease-Pool und werden doppelt freigegeben.
    private let webView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        // Der Google-Anmeldevorgang läuft in einem zweiten Fenster. Ohne diese
        // Erlaubnis verwirft WebKit den Aufruf stillschweigend.
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 960, height: 720),
                             configuration: config)
        view.autoresizingMask = [.width, .height]
        return view
    }()

    /// Ebenfalls dauerhaft. Siehe Hinweis oben zu `isReleasedWhenClosed`.
    private lazy var window: NSWindow = {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 720),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "ClaudeUsagePulse — Bei Claude AI anmelden"
        win.animationBehavior = .none
        // Ohne das gibt close() das Fenster frei, obwohl noch eine Referenz darauf zeigt.
        win.isReleasedWhenClosed = false

        // Ein Container, damit das zweite Fenster des Anmeldevorgangs als
        // weitere Ebene darüber gelegt werden kann.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 960, height: 720))
        container.autoresizingMask = [.width, .height]
        webView.frame = container.bounds
        container.addSubview(webView)
        win.contentView = container

        win.delegate = self
        win.center()
        return win
    }()

    override init() {
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        configureUserAgent()
    }

    /// Google verweigert Anmeldungen in eingebetteten Browser-Ansichten. Erkannt
    /// werden sie am User-Agent: Dem Standard eines WKWebView fehlt der
    /// abschliessende `Version/… Safari/…`-Teil, den ein echter Safari mitschickt.
    private func configureUserAgent() {
        // Erst den tatsächlichen Wert dieses Systems auslesen, dann ergänzen —
        // andernfalls läse man den bereits gesetzten eigenen Wert zurück.
        webView.evaluateJavaScript("navigator.userAgent") { [weak self] result, _ in
            guard let self else { return }
            self.webView.customUserAgent =
                BrowserUserAgent.current(from: (result as? String) ?? "")
        }
    }

    // MARK: - Anzeigen

    func show() {
        guard !isShowing else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        isShowing = true

        // Falls die Ermittlung oben noch nicht zurück ist: verlässlichen Wert setzen
        if webView.customUserAgent?.isEmpty ?? true {
            webView.customUserAgent = BrowserUserAgent.current(from: "")
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        webView.stopLoading()
        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))

        startCookieCheck()
    }

    /// Blendet das Fenster aus, ohne es freizugeben.
    private func hide() {
        stopCookieCheck()
        closePopup()
        isShowing = false
        window.orderOut(nil)
        // Die Seite nicht im Hintergrund weiterlaufen lassen
        webView.stopLoading()
        webView.load(URLRequest(url: URL(string: "about:blank")!))
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Nutzer hat das Fenster selbst geschlossen
        stopCookieCheck()
        closePopup()
        isShowing = false
        webView.stopLoading()
    }

    // MARK: - WKUIDelegate — zweites Fenster des Anmeldevorgangs

    /// Google wickelt die Anmeldung in einem eigenen Fenster ab. Liefert diese
    /// Methode nichts zurück, verwirft WebKit den Aufruf — die Anmeldung bricht
    /// dann ohne sichtbare Ursache ab.
    ///
    /// Die übergebene Konfiguration muss übernommen werden, sonst teilen sich
    /// beide Ansichten weder Sitzung noch Cookies.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {

        let popup = WKWebView(frame: webView.bounds, configuration: configuration)
        popup.autoresizingMask = [.width, .height]
        popup.navigationDelegate = self
        popup.uiDelegate = self
        popup.customUserAgent = webView.customUserAgent

        window.contentView?.addSubview(popup)
        popupWebView = popup
        return popup
    }

    /// Schliesst sich das zweite Fenster, ist der Anmeldevorgang dort beendet.
    func webViewDidClose(_ webView: WKWebView) {
        guard webView === popupWebView else { return }
        closePopup()
    }

    private func closePopup() {
        popupWebView?.removeFromSuperview()
        popupWebView = nil
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url?.absoluteString, !url.hasPrefix("about:") else { return }
        startCookieCheck()
    }

    // MARK: - Auf die Anmeldung warten

    private func startCookieCheck() {
        guard cookieCheckTimer == nil else { return }
        cookieCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) {
            [weak self] _ in
            self?.checkForAuthCookies()
        }
    }

    private func stopCookieCheck() {
        cookieCheckTimer?.invalidate()
        cookieCheckTimer = nil
    }

    /// Kein Filtern nach Adresse mehr: Entscheidend ist allein, ob eine echte
    /// Sitzung existiert. Damit ist es gleichgültig, über welche Zwischenseiten
    /// die Anmeldung läuft — Google, Apple, E-Mail mit Code.
    private func checkForAuthCookies() {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self else { return }
            guard SessionCookies.isLoggedIn(cookies) else { return }

            let relevant = SessionCookies.relevant(cookies)
            KeychainService.saveCookies(relevant)

            DispatchQueue.main.async {
                guard self.isShowing else { return }
                let callback = self.onAuthSuccess
                self.onAuthSuccess = nil
                self.hide()
                callback?()
            }
        }
    }
}
