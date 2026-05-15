import AppKit
import WebKit

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var statusItem: NSStatusItem!
    private var refreshTimer: Timer?

    private let store = UsageStore()
    private lazy var floatingWindowController = FloatingWindowController(store: store)
    private let authWebWindow    = AuthWebWindow()
    private let settingsController = SettingsWindowController()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupCallbacks()

        if KeychainService.hasCookies() {
            scheduleTimer()
            Task { await refresh() }
        } else {
            authWebWindow.show()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false  // Menubar-App läuft ohne sichtbare Fenster weiter
    }

    func applicationWillTerminate(_ notification: Notification) {
        floatingWindowController.savePosition()
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
        if mode == "floating" || mode == "both" {
            floatingWindowController.toggle()
        } else {
            showContextMenu()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let s = Int(store.data.sessionPercentage)
        let w = Int(store.data.weeklyPercentage)
        let info = NSMenuItem(title: "Session: \(s)%  |  Wöchentlich: \(w)%", action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)

        menu.addItem(.separator())

        let floatLabel = floatingWindowController.isVisible ? "Fenster ausblenden" : "Fenster anzeigen"
        menu.addItem(makeItem(floatLabel, action: #selector(toggleFloat), key: "f"))
        menu.addItem(makeItem("Jetzt aktualisieren", action: #selector(manualRefresh), key: "r"))

        menu.addItem(.separator())
        menu.addItem(makeItem("Einstellungen…", action: #selector(openSettings), key: ","))
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
        let style = UserDefaults.standard.string(forKey: "menubarStyle") ?? "both"
        let s = store.data.sessionPercentage
        let w = store.data.weeklyPercentage

        DispatchQueue.main.async {
            if self.store.data.error != nil {
                btn.image = nil
                btn.title = "⚠️"
                return
            }

            let image: NSImage
            switch style {
            case "session":
                image = self.renderMenubarImage(rows: [("Se", s)])
            case "max":
                let maxVal = max(s, w)
                image = self.renderMenubarImage(rows: [(s >= w ? "Se" : "We", maxVal)])
            default:
                image = self.renderMenubarImage(rows: [("Se", s), ("We", w)])
            }

            btn.title = ""
            btn.image = image
            btn.imagePosition = .imageOnly
        }
    }

    // Zeichnet eine oder zwei Zeilen als NSImage für den StatusItem-Button
    private func renderMenubarImage(rows: [(String, Double)]) -> NSImage {
        let barH  = NSStatusBar.system.thickness          // ~22pt
        let fontS = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .regular)
        let fontL = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)

        // Strings und Attribute vorbereiten
        let labelColor = NSColor.white
        let stacked = rows.count > 1

        let attrRows: [NSAttributedString] = rows.map { (label, pct) in
            let str = NSMutableAttributedString()
            str.append(NSAttributedString(string: "\(label) ", attributes: [
                .font: stacked ? fontS : fontS,
                .foregroundColor: labelColor
            ]))
            str.append(NSAttributedString(string: "\(Int(pct))%", attributes: [
                .font: stacked ? fontS : fontL,
                .foregroundColor: self.menubarColor(for: pct)
            ]))
            return str
        }

        // Breite = breiteste Zeile
        let maxW = attrRows.map { $0.size().width }.max() ?? 40
        let imgW  = ceil(maxW) + 4

        let image = NSImage(size: NSSize(width: imgW, height: barH), flipped: false) { rect in
            if stacked {
                // Zwei Zeilen übereinander
                let rowH = rect.height / 2
                for (i, attr) in attrRows.enumerated() {
                    let aSize = attr.size()
                    let y: CGFloat = i == 0
                        ? rect.height - rowH + (rowH - aSize.height) / 2   // oben
                        : (rowH - aSize.height) / 2                          // unten
                    attr.draw(at: NSPoint(x: rect.maxX - aSize.width - 2, y: y))
                }
            } else {
                // Eine Zeile mittig
                let aSize = attrRows[0].size()
                let y = (rect.height - aSize.height) / 2
                attrRows[0].draw(at: NSPoint(x: rect.maxX - aSize.width - 2, y: y))
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private func menubarColor(for pct: Double) -> NSColor {
        if pct >= 90 { return .systemRed }
        if pct >= 75 { return .systemOrange }
        return .systemGreen
    }

    // MARK: - Actions

    @objc private func toggleFloat() { floatingWindowController.toggle() }
    @objc private func manualRefresh() { Task { await refresh() } }
    @objc private func openSettings() { settingsController.show() }

    // MARK: - Callbacks

    private func setupCallbacks() {
        authWebWindow.onAuthSuccess = { [weak self] in
            self?.scheduleTimer()
            Task { await self?.refresh() }
        }

        settingsController.onSettingsChanged = { [weak self] in
            self?.updateMenubar()
            self?.floatingWindowController.applyAlwaysOnTop()
            self?.scheduleTimer()
        }

        settingsController.onLogout = { [weak self] in
            // WebView-Session + Cookies vollständig löschen
            WKWebsiteDataStore.default().removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                modifiedSince: Date(timeIntervalSince1970: 0)
            ) {
                // Verzögerung damit laufende Fenster-Animationen abschließen können
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    KeychainService.clearAll()
                    APIService.shared.resetOrgId()
                    self?.store.data = UsageData()
                    self?.store.isLoading = false
                    self?.updateMenubar()
                    self?.authWebWindow.show()
                }
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
        guard !isRefreshing else { return }
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
            updateMenubar()
            if !authWebWindow.isShowing {
                authWebWindow.show()
            }
        } catch {
            store.isLoading  = false
            store.data.error = error.localizedDescription
            updateMenubar()
        }
    }
}
