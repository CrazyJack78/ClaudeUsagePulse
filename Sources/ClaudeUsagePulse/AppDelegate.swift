import AppKit
import WebKit

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var statusItem: NSStatusItem!
    private var refreshTimer: Timer?
    private var isAuthenticated = false

    private let store = UsageStore()
    private lazy var floatingWindowController = FloatingWindowController(store: store)
    private let authWebWindow     = AuthWebWindow()
    private let settingsController = SettingsWindowController()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupCallbacks()
        checkAuthAndStart()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        floatingWindowController.savePosition()
    }

    // MARK: - Auth-Check beim Start

    private func checkAuthAndStart() {
        guard KeychainService.hasCookies() else {
            setUnauthenticated()
            return
        }
        // Credentials vorhanden → API testen
        Task { @MainActor in
            do {
                store.data      = try await APIService.shared.fetchUsageData()
                store.data.error = nil
                isAuthenticated  = true
                scheduleTimer()
                updateMenubar()
            } catch {
                // Credentials ungültig → alles bereinigen
                cleanupCredentials { [weak self] in
                    self?.setUnauthenticated()
                }
            }
        }
    }

    private func setUnauthenticated() {
        isAuthenticated = false
        refreshTimer?.invalidate()
        refreshTimer = nil
        store.data = UsageData()
        guard let btn = statusItem?.button else { return }
        btn.image = nil
        btn.title = "Anmelden"
        updateMenubar()
    }

    private func cleanupCredentials(completion: (() -> Void)? = nil) {
        KeychainService.clearAll()
        APIService.shared.resetOrgId()
        WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: Date(timeIntervalSince1970: 0)
        ) {
            DispatchQueue.main.async { completion?() }
        }
    }

    // MARK: - Login

    @objc private func showLogin() {
        cleanupCredentials { [weak self] in
            self?.authWebWindow.show()
        }
    }

    // MARK: - StatusItem

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let btn = statusItem.button else { return }
        btn.title = "…"
        btn.action = #selector(statusButtonClicked)
        btn.target  = self
        btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusButtonClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            handleLeftClick()
        }
    }

    private func handleLeftClick() {
        let mode = UserDefaults.standard.string(forKey: "displayMode") ?? "menubar"
        if isAuthenticated && (mode == "floating" || mode == "both") {
            floatingWindowController.toggle()
        } else {
            showContextMenu()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        if isAuthenticated {
            let s  = Int(store.data.sessionPercentage)
            let w  = Int(store.data.weeklyPercentage)
            let sn = Int(store.data.sonnetPercentage)
            let d  = Int(store.data.designPercentage)
            let info = NSMenuItem(title: "Se \(s)%  We \(w)%  Son \(sn)%  Des \(d)%", action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
            menu.addItem(.separator())
            let floatLabel = floatingWindowController.isVisible ? "Fenster ausblenden" : "Fenster anzeigen"
            menu.addItem(makeItem(floatLabel, action: #selector(toggleFloat), key: "f"))
            menu.addItem(makeItem("Jetzt aktualisieren", action: #selector(manualRefresh), key: "r"))
            menu.addItem(.separator())
            menu.addItem(makeItem("Einstellungen…", action: #selector(openSettings), key: ","))
        } else {
            menu.addItem(makeItem("Bei Claude anmelden…", action: #selector(showLogin), key: "l"))
        }

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "ClaudeUsagePulse beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func makeItem(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - Menubar-Anzeige

    private func updateMenubar() {
        guard let btn = statusItem?.button else { return }

        if !isAuthenticated {
            DispatchQueue.main.async {
                btn.image = nil
                btn.title = "Anmelden"
            }
            return
        }

        let top    = UserDefaults.standard.string(forKey: "menubarTop")    ?? "session"
        let bottom = UserDefaults.standard.string(forKey: "menubarBottom") ?? "weekly"

        DispatchQueue.main.async {
            if self.store.data.error != nil {
                btn.image = nil
                btn.title = "⚠️"
                return
            }
            let rows: [(String, Double)]
            if bottom == "none" {
                rows = [self.menubarRow(for: top)]
            } else {
                rows = [self.menubarRow(for: top), self.menubarRow(for: bottom)]
            }
            btn.title = ""
            btn.image = self.renderMenubarImage(rows: rows)
            btn.imagePosition = .imageOnly
        }
    }

    private func renderMenubarImage(rows: [(String, Double)]) -> NSImage {
        let barH  = NSStatusBar.system.thickness
        let fontS = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let fontL = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        let labelColor = NSColor.white
        let stacked = rows.count > 1

        let attrRows: [NSAttributedString] = rows.map { (label, pct) in
            let str = NSMutableAttributedString()
            str.append(NSAttributedString(string: "\(label) ", attributes: [
                .font: fontS, .foregroundColor: labelColor
            ]))
            str.append(NSAttributedString(string: "\(Int(pct))%", attributes: [
                .font: stacked ? fontS : fontL,
                .foregroundColor: self.menubarColor(for: pct)
            ]))
            return str
        }

        let maxW = attrRows.map { $0.size().width }.max() ?? 40
        let size  = NSSize(width: ceil(maxW) + 14, height: barH)
        let image = NSImage(size: size)
        image.lockFocus()

        if UserDefaults.standard.bool(forKey: "menubarBackground") {
            let bgColor: NSColor
            if let data = UserDefaults.standard.data(forKey: "menubarBgColor"),
               let stored = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
                bgColor = stored
            } else {
                bgColor = NSColor.black.withAlphaComponent(0.45)
            }
            bgColor.setFill()
            NSBezierPath(
                roundedRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
                xRadius: 6, yRadius: 6
            ).fill()
        }

        if stacked {
            let rowH = size.height / 2
            for (i, attr) in attrRows.enumerated() {
                let aSize = attr.size()
                let y: CGFloat = i == 0
                    ? size.height - rowH + (rowH - aSize.height) / 2
                    : (rowH - aSize.height) / 2
                attr.draw(at: NSPoint(x: (size.width - aSize.width) / 2, y: y))
            }
        } else {
            let aSize = attrRows[0].size()
            attrRows[0].draw(at: NSPoint(x: (size.width - aSize.width) / 2, y: (size.height - aSize.height) / 2))
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func menubarColor(for pct: Double) -> NSColor {
        if pct >= 90 { return .systemRed }
        if pct >= 75 { return .systemOrange }
        return .systemGreen
    }

    private func menubarRow(for slot: String) -> (String, Double) {
        switch slot {
        case "session": return ("Se", store.data.sessionPercentage)
        case "weekly":  return ("We", store.data.weeklyPercentage)
        case "sonnet":  return ("So", store.data.sonnetPercentage)
        case "design":  return ("De", store.data.designPercentage)
        case "credits": return ("Cr", store.data.creditsPercentage)
        default:        return ("Se", store.data.sessionPercentage)
        }
    }

    // MARK: - Actions

    @objc private func toggleFloat()   { floatingWindowController.toggle() }
    @objc private func manualRefresh() { Task { await refresh() } }
    @objc private func openSettings()  { settingsController.show() }

    @objc private func exploreAPI() {
        Task {
            do {
                let raw = try await APIService.shared.fetchRawData()
                let data = try JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted, .sortedKeys])
                let url = URL(fileURLWithPath: NSString("~/Desktop/ClaudeAPI_dump.json").expandingTildeInPath)
                try data.write(to: url)
                NSWorkspace.shared.open(url)
            } catch {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "API-Erkundung fehlgeschlagen"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }

    // MARK: - Callbacks

    private func setupCallbacks() {
        authWebWindow.onAuthSuccess = { [weak self] in
            self?.isAuthenticated = true
            self?.scheduleTimer()
            Task { await self?.refresh() }
        }

        settingsController.onSettingsChanged = { [weak self] in
            self?.updateMenubar()
            self?.floatingWindowController.applyAlwaysOnTop()
            self?.scheduleTimer()
        }

        settingsController.onLogout = { [weak self] in
            self?.settingsController.close()
            self?.refreshTimer?.invalidate()
            self?.refreshTimer = nil
            self?.cleanupCredentials {
                self?.setUnauthenticated()
            }
        }
    }

    // MARK: - Timer

    private func scheduleTimer() {
        refreshTimer?.invalidate()
        let minutes = UserDefaults.standard.double(forKey: "refreshInterval")
        let interval = (minutes > 0 ? minutes : 10) * 60
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    // MARK: - Daten laden

    private var isRefreshing = false

    @MainActor
    private func refresh() async {
        guard isAuthenticated, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        store.isLoading = true
        updateMenubar()

        do {
            store.data       = try await APIService.shared.fetchUsageData()
            store.isLoading  = false
            store.data.error = nil
            updateMenubar()
        } catch APIError.notAuthenticated {
            store.isLoading  = false
            store.data.error = "not_authenticated"
            isAuthenticated  = false
            cleanupCredentials { [weak self] in self?.setUnauthenticated() }
        } catch {
            store.isLoading  = false
            store.data.error = error.localizedDescription
            updateMenubar()
        }
    }
}
