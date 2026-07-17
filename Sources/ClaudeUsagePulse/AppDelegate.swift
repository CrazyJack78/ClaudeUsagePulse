import AppKit
import WebKit

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var statusItem: NSStatusItem!
    private var refreshTimer: Timer?
    private var isAuthenticated = false

    private let store = UsageStore()
    private lazy var floatingWindowController = FloatingWindowController(store: store)
    private let authWebWindow      = AuthWebWindow()
    private let settingsController = SettingsWindowController()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        migrateUserDefaults()
        setupStatusItem()
        setupCallbacks()
        NotificationService.shared.requestPermission()
        checkAuthAndStart()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        floatingWindowController.savePosition()
    }

    // MARK: - Migration alter UserDefaults-Keys

    private func migrateUserDefaults() {
        let map = [
            "session": "five_hour",
            "weekly":  "seven_day",
            "sonnet":  "seven_day_sonnet",
            "design":  "seven_day_omelette",
            "credits": "extra_usage",
        ]
        for key in ["menubarTop", "menubarBottom", "ringSlot"] {
            if let val = UserDefaults.standard.string(forKey: key), let mapped = map[val] {
                UserDefaults.standard.set(mapped, forKey: key)
            }
        }
    }

    // MARK: - Auth

    private func checkAuthAndStart() {
        guard KeychainService.hasCookies() else { setUnauthenticated(); return }
        Task { @MainActor in
            do {
                store.data       = try await APIService.shared.fetchUsageData()
                store.data.error = nil
                isAuthenticated  = true
                scheduleTimer()
                updateMenubar()
            } catch {
                cleanupCredentials { [weak self] in self?.setUnauthenticated() }
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
        ) { DispatchQueue.main.async { completion?() } }
    }

    // MARK: - Login

    @objc private func showLogin() {
        cleanupCredentials { [weak self] in self?.authWebWindow.show() }
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
        if NSApp.currentEvent?.type == .rightMouseUp { showContextMenu() }
        else { handleLeftClick() }
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
            // Erste Zeile: alle bekannten Metriken kompakt
            let summary = MetricConfigStore.shared.configs.map { c in
                "\(c.shortLabel) \(Int(store.data[c.key].percentage))%"
            }.joined(separator: "  ")
            let info = NSMenuItem(title: summary, action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
            menu.addItem(.separator())

            let floatLabel = floatingWindowController.isVisible ? "Fenster ausblenden" : "Fenster anzeigen"
            menu.addItem(makeItem(floatLabel,          action: #selector(toggleFloat),   key: "f"))
            menu.addItem(makeItem("Jetzt aktualisieren", action: #selector(manualRefresh), key: "r"))
            menu.addItem(.separator())
            menu.addItem(makeItem("Einstellungen…",    action: #selector(openSettings),  key: ","))
        } else {
            menu.addItem(makeItem("Bei Claude anmelden…", action: #selector(showLogin), key: "l"))
        }

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "ClaudeUsagePulse beenden",
                                  action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
            DispatchQueue.main.async { btn.image = nil; btn.title = "Anmelden" }
            return
        }
        let top    = UserDefaults.standard.string(forKey: "menubarTop")    ?? "five_hour"
        let bottom = UserDefaults.standard.string(forKey: "menubarBottom") ?? "seven_day"

        DispatchQueue.main.async {
            if self.store.data.error != nil { btn.image = nil; btn.title = "⚠️"; return }
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

    private func menubarRow(for key: String) -> (String, Double) {
        let label = MetricConfigStore.shared.shortLabel(for: key)
        let pct   = store.data[key].percentage
        return (label, pct)
    }

    // MARK: - Menubar-Bild

    private func renderMenubarImage(rows: [(String, Double)]) -> NSImage {
        let barH   = NSStatusBar.system.thickness
        let fontS  = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let fontL  = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        let stacked = rows.count > 1

        let attrRows: [NSAttributedString] = rows.map { (label, pct) in
            let str = NSMutableAttributedString()
            str.append(NSAttributedString(string: "\(label) ", attributes: [
                .font: fontS, .foregroundColor: NSColor.white
            ]))
            str.append(NSAttributedString(string: "\(Int(pct))%", attributes: [
                .font: stacked ? fontS : fontL,
                .foregroundColor: menubarColor(for: pct)
            ]))
            return str
        }

        let ringEnabled = UserDefaults.standard.bool(forKey: "ringEnabled")
        let maxW      = attrRows.map { $0.size().width }.max() ?? 40
        let hPadding: CGFloat = ringEnabled ? 22 : 14
        let size      = NSSize(width: ceil(maxW) + hPadding, height: barH)
        let image     = NSImage(size: size)
        image.lockFocus()

        let vPad: CGFloat = ringEnabled ? 2.5 : 0

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
                roundedRect: NSRect(x: 0, y: vPad, width: size.width, height: size.height - 2 * vPad),
                xRadius: 6, yRadius: 6
            ).fill()
        }

        let innerH = size.height - 2 * vPad
        if stacked {
            let rowH = innerH / 2
            for (i, attr) in attrRows.enumerated() {
                let aSize = attr.size()
                let y: CGFloat = i == 0
                    ? vPad + innerH - rowH + (rowH - aSize.height) / 2
                    : vPad + (rowH - aSize.height) / 2
                attr.draw(at: NSPoint(x: (size.width - aSize.width) / 2, y: y))
            }
        } else {
            let aSize = attrRows[0].size()
            attrRows[0].draw(at: NSPoint(x: (size.width - aSize.width) / 2,
                                         y: vPad + (innerH - aSize.height) / 2))
        }

        if ringEnabled { drawRing(in: size) }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    // MARK: - Zeitring

    private func drawRing(in size: NSSize) {
        let slot        = UserDefaults.standard.string(forKey: "ringSlot") ?? "five_hour"
        let showElapsed = UserDefaults.standard.bool(forKey: "ringShowElapsed")
        let fraction    = ringFraction(slot: slot, showElapsed: showElapsed)

        let ringColor: NSColor
        if let data = UserDefaults.standard.data(forKey: "ringColorData"),
           let c = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
            ringColor = c
        } else {
            ringColor = .systemTeal
        }

        let lw: CGFloat = 1.5
        let ringRect = NSRect(x: lw/2, y: lw/2, width: size.width - lw, height: size.height - lw)
        let cr       = min(ringRect.height / 2, 5.5)

        let trackPath = clockwiseRingPath(rect: ringRect, cornerRadius: cr)
        trackPath.lineWidth = lw
        NSColor.white.withAlphaComponent(0.2).setStroke()
        trackPath.stroke()

        guard fraction > 0.005 else { return }
        let perim: CGFloat = 2*(ringRect.width - 2*cr) + 2*(ringRect.height - 2*cr) + 2 * .pi * cr
        let progressPath = clockwiseRingPath(rect: ringRect, cornerRadius: cr)
        var dashes: [CGFloat] = [CGFloat(fraction) * perim, perim]
        progressPath.setLineDash(&dashes, count: dashes.count, phase: 0)
        progressPath.lineWidth    = lw
        progressPath.lineCapStyle = .round
        ringColor.setStroke()
        progressPath.stroke()
    }

    private func clockwiseRingPath(rect: NSRect, cornerRadius r: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let x = rect.minX, y = rect.minY, W = rect.width, H = rect.height
        path.move(to: NSPoint(x: x + W/2, y: y + H))
        path.line(to: NSPoint(x: x + W - r, y: y + H))
        path.appendArc(withCenter: NSPoint(x: x+W-r, y: y+H-r), radius: r, startAngle: 90,  endAngle: 0,   clockwise: true)
        path.line(to: NSPoint(x: x + W, y: y + r))
        path.appendArc(withCenter: NSPoint(x: x+W-r, y: y+r),   radius: r, startAngle: 0,   endAngle: 270, clockwise: true)
        path.line(to: NSPoint(x: x + r, y: y))
        path.appendArc(withCenter: NSPoint(x: x+r,   y: y+r),   radius: r, startAngle: 270, endAngle: 180, clockwise: true)
        path.line(to: NSPoint(x: x, y: y + H - r))
        path.appendArc(withCenter: NSPoint(x: x+r,   y: y+H-r), radius: r, startAngle: 180, endAngle: 90,  clockwise: true)
        path.line(to: NSPoint(x: x + W/2, y: y + H))
        return path
    }

    private func ringFraction(slot: String, showElapsed: Bool) -> Double {
        let metric = store.data[slot]
        guard let resetAt = metric.resetAt, resetAt > Date() else {
            return showElapsed ? 1.0 : 0.0
        }
        let period = inferPeriod(for: slot)
        let remaining = min(resetAt.timeIntervalSinceNow / period, 1.0)
        return showElapsed ? 1.0 - remaining : remaining
    }

    private func inferPeriod(for key: String) -> TimeInterval {
        if key.contains("five_hour") { return 5 * 3600 }
        if key.contains("seven_day") { return 7 * 24 * 3600 }
        return 5 * 3600
    }

    private func menubarColor(for pct: Double) -> NSColor {
        if pct >= 90 { return .systemRed }
        if pct >= 75 { return .systemOrange }
        return .systemGreen
    }

    // MARK: - Actions

    @objc private func toggleFloat()   { floatingWindowController.toggle() }
    @objc private func manualRefresh() { Task { await refresh() } }
    @objc private func openSettings()  { settingsController.show() }

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

        settingsController.onRefreshMetrics = { [weak self] in
            Task { await self?.refresh() }
        }

        settingsController.onLogout = { [weak self] in
            self?.settingsController.close()
            self?.refreshTimer?.invalidate()
            self?.refreshTimer = nil
            self?.cleanupCredentials { self?.setUnauthenticated() }
        }
    }

    // MARK: - Timer

    private func scheduleTimer() {
        refreshTimer?.invalidate()
        let minutes  = UserDefaults.standard.double(forKey: "refreshInterval")
        let interval = (minutes > 0 ? minutes : 10) * 60
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    // MARK: - Daten laden

    private var isRefreshing = false

    @MainActor
    func refresh() async {
        guard isAuthenticated, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        store.isLoading = true
        updateMenubar()

        do {
            store.data       = try await APIService.shared.fetchUsageData()
            store.isLoading  = false
            store.data.error = nil
            NotificationService.shared.checkAndNotify(data: store.data)
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
