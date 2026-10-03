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
final class AuthWebWindow: NSObject, WKNavigationDelegate, NSWindowDelegate {

    var onAuthSuccess: (() -> Void)?
    private(set) var isShowing = false

    private var cookieCheckTimer: Timer?

    /// Einmal erstellt, NIEMALS deallociert.
    /// WKWebView spricht über IPC mit einem eigenen Web-Content-Prozess. Wird es
    /// freigegeben, während dieser Prozess noch läuft, landen interne Objekte im
    /// Autorelease-Pool und werden doppelt freigegeben.
    private let webView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
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
        win.contentView = webView
        webView.frame = win.contentView!.bounds
        win.delegate = self
        win.center()
        return win
    }()

    override init() {
        super.init()
        webView.navigationDelegate = self
    }

    // MARK: - Anzeigen

    func show() {
        guard !isShowing else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        isShowing = true

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        webView.stopLoading()
        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))

        startCookieCheck()
    }

    /// Blendet das Fenster aus, ohne es freizugeben.
    private func hide() {
        stopCookieCheck()
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
        isShowing = false
        webView.stopLoading()
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
