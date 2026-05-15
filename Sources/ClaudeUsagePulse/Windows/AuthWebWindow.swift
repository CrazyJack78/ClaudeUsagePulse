import AppKit
import WebKit

class AuthWebWindow: NSObject, WKNavigationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var cookieCheckTimer: Timer?
    var onAuthSuccess: (() -> Void)?
    private(set) var isShowing = false

    // Einmal erstellt, NIEMALS deallociert.
    // WKWebView kommuniziert mit einem eigenen Web-Content-Prozess (IPC).
    // Wird das WKWebView deallociert während der Prozess noch läuft, landen
    // interne ObjC-Objekte im autorelease-Pool des Main-Run-Loops und werden
    // am Ende des Zyklus doppelt released → SIGSEGV. Lösung: WKWebView bleibt
    // für die gesamte App-Laufzeit am Leben; nur das NSWindow wird neu erstellt.
    private let webView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 960, height: 720),
                           configuration: config)
        wv.autoresizingMask = [.width, .height]
        return wv
    }()

    override init() {
        super.init()
        webView.navigationDelegate = self
    }

    func show() {
        guard !isShowing else {
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        isShowing = true

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 720),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "ClaudeUsagePulse — Bei Claude AI anmelden"
        win.animationBehavior = .none
        win.contentView = webView
        webView.frame = win.contentView!.bounds
        win.delegate = self
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win

        webView.stopLoading()
        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
    }

    func windowWillClose(_ notification: Notification) {
        cookieCheckTimer?.invalidate()
        cookieCheckTimer = nil
        isShowing = false
        webView.stopLoading()
        // WebView aus Fenster-Hierarchie lösen bevor das NSWindow deallociert wird.
        // Das verhindert, dass das NSWindow beim Dealloc eine starke Referenz auf
        // das WKWebView hält während Apples interne Autorelease-Objekte drainieren.
        window?.contentView = NSView()
        window = nil
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url?.absoluteString, !url.hasPrefix("about:") else { return }
        guard cookieCheckTimer == nil else { return }
        cookieCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.checkForAuthCookies()
        }
    }

    // MARK: - Cookie-Check

    private func checkForAuthCookies() {
        guard let currentURL = webView.url?.absoluteString else { return }

        let isAuthFlow = currentURL.contains("/login")
            || currentURL.contains("/auth")
            || currentURL.contains("accounts.google")
            || currentURL.contains("appleid.apple.com")

        guard currentURL.contains("claude.ai"), !isAuthFlow else { return }

        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self else { return }

            let sessionCookies = cookies.filter { cookie in
                (cookie.domain.contains("claude.ai") || cookie.domain.contains("anthropic.com"))
                && (cookie.name.lowercased().contains("session")
                    || cookie.name.lowercased().contains("token"))
            }

            guard !sessionCookies.isEmpty else { return }

            let allClaude = cookies.filter {
                $0.domain.contains("claude.ai") || $0.domain.contains("anthropic.com")
            }
            KeychainService.saveCookies(allClaude)

            DispatchQueue.main.async {
                guard self.isShowing else { return }
                self.cookieCheckTimer?.invalidate()
                self.cookieCheckTimer = nil
                self.isShowing = false
                let callback = self.onAuthSuccess
                self.onAuthSuccess = nil
                self.window?.contentView = NSView()
                self.window?.close()
                self.window = nil
                callback?()
            }
        }
    }
}
