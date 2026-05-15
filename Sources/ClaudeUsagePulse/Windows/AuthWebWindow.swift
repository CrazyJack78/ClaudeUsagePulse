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
        win.title = "ClaudeUsagePulse — Bei Claude AI anmelden"
        win.animationBehavior = .none
        win.contentView = wv
        win.delegate = self
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win

        wv.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
    }

    func windowWillClose(_ notification: Notification) {
        cookieCheckTimer?.invalidate()
        cookieCheckTimer = nil
        isShowing = false
        teardownWebView()
        window = nil
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard cookieCheckTimer == nil else { return }
        cookieCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.checkForAuthCookies()
        }
    }

    // MARK: - Cookie-Check

    private func checkForAuthCookies() {
        guard let wv = webView,
              let currentURL = wv.url?.absoluteString else { return }

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
                self.teardownWebView()
                self.window?.close()
                self.window = nil
                callback?()
            }
        }
    }

    // MARK: - Teardown

    private func teardownWebView() {
        guard let wv = webView else { return }
        wv.stopLoading()
        wv.navigationDelegate = nil
        // WKWebView in eigenem autoreleasepool deallocieren: verhindert
        // dass sein Dealloc-autorelease in den Haupt-RunLoop-Pool läuft
        // und am Ende des Zyklus doppelt released wird (SIGSEGV).
        autoreleasepool {
            window?.contentView = NSView()  // WKWebView aus Fensterhierarchie entfernen
            webView = nil                   // letzter Retain → Dealloc passiert hier, im Pool
        }
    }
}
