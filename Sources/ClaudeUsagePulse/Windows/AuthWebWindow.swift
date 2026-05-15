import AppKit
import WebKit

class AuthWebWindow: NSObject, WKNavigationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var cookieCheckTimer: Timer?
    var onAuthSuccess: (() -> Void)?

    private(set) var isShowing = false

    func show() {
        guard !isShowing else {
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        isShowing = true

        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()

        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 960, height: 720), configuration: config)
        wv.navigationDelegate = self
        self.webView = wv

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 720),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "ClaudeUsagePulse — Einmalig bei Claude AI anmelden"
        win.animationBehavior = .none
        win.contentView = wv
        win.delegate = self
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win

        wv.load(URLRequest(url: URL(string: "https://claude.ai/login")!))

        cookieCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkForAuthCookies()
        }
    }

    func windowWillClose(_ notification: Notification) {
        cookieCheckTimer?.invalidate()
        cookieCheckTimer = nil
        isShowing = false
        teardownWebView()
        window = nil
    }

    // MARK: - Cookie-Check

    private func checkForAuthCookies() {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self = self else { return }

            let sessionCookies = cookies.filter { cookie in
                (cookie.domain.contains("claude.ai") || cookie.domain.contains("anthropic.com"))
                && (cookie.name.lowercased().contains("session")
                    || cookie.name.lowercased().contains("token")
                    || cookie.name.lowercased().contains("auth")
                    || cookie.name == "CH-prefers-color-scheme"
                    || cookie.name.hasPrefix("__Secure")
                    || cookie.name.hasPrefix("__Host"))
            }

            guard !sessionCookies.isEmpty else { return }

            let allClaude = cookies.filter {
                $0.domain.contains("claude.ai") || $0.domain.contains("anthropic.com")
            }

            KeychainService.saveCookies(allClaude)

            DispatchQueue.main.async {
                self.cookieCheckTimer?.invalidate()
                self.cookieCheckTimer = nil
                self.isShowing = false
                self.teardownWebView()
                self.window?.close()
                self.window = nil
                self.onAuthSuccess?()
            }
        }
    }

    // WKWebView sauber entladen bevor nil gesetzt wird
    private func teardownWebView() {
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.load(URLRequest(url: URL(string: "about:blank")!))
        webView = nil
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {}
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {}
}
