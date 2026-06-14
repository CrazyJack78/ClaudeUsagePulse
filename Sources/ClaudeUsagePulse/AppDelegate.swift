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

        let ringEnabled = UserDefaults.standard.bool(forKey: "ringEnabled")
        let maxW     = attrRows.map { $0.size().width }.max() ?? 40
        let hPadding: CGFloat = ringEnabled ? 22 : 14   // ring braucht mehr Luft seitlich
        let size     = NSSize(width: ceil(maxW) + hPadding, height: barH)
        let image = NSImage(size: size)
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
            attrRows[0].draw(at: NSPoint(x: (size.width - aSize.width) / 2, y: vPad + (innerH - aSize.height) / 2))
        }

        if ringEnabled {
            drawRing(in: size)
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func drawRing(in size: NSSize) {
        let slot        = UserDefaults.standard.string(forKey: "ringSlot") ?? "session"
        let showElapsed = UserDefaults.standard.bool(forKey: "ringShowElapsed")
        let fraction    = ringFraction(slot: slot, showElapsed: showElapsed)

        let ringColor: NSColor
        if let data = UserDefaults.standard.data(forKey: "ringColorData"),
           let c = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
            ringColor = c
        } else {
            ringColor = .systemTeal
        }

        let lw: CGFloat  = 1.5
        let ringRect = NSRect(x: lw / 2, y: lw / 2, width: size.width - lw, height: size.height - lw)
        let cr       = min(ringRect.height / 2, 5.5)

        // Track (full ring, dim)
        let trackPath = clockwiseRingPath(rect: ringRect, cornerRadius: cr)
        trackPath.lineWidth = lw
        NSColor.white.withAlphaComponent(0.2).setStroke()
        trackPath.stroke()

        // Progress arc
        guard fraction > 0.005 else { return }
        let W    = ringRect.width
        let H    = ringRect.height
        let perim: CGFloat = 2 * (W - 2*cr) + 2 * (H - 2*cr) + 2 * .pi * cr
        let progressPath = clockwiseRingPath(rect: ringRect, cornerRadius: cr)
        var dashes: [CGFloat] = [CGFloat(fraction) * perim, perim]
        progressPath.setLineDash(&dashes, count: dashes.count, phase: 0)
        progressPath.lineWidth   = lw
        progressPath.lineCapStyle = .round
        ringColor.setStroke()
        progressPath.stroke()
    }

    private func clockwiseRingPath(rect: NSRect, cornerRadius r: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let x = rect.minX, y = rect.minY, W = rect.width, H = rect.height
        // Clockwise starting from top-center (12 o'clock)
        path.move(to: NSPoint(x: x + W/2, y: y + H))
        path.line(to: NSPoint(x: x + W - r, y: y + H))
        path.appendArc(withCenter: NSPoint(x: x + W - r, y: y + H - r), radius: r,
                       startAngle: 90, endAngle: 0, clockwise: true)
        path.line(to: NSPoint(x: x + W, y: y + r))
        path.appendArc(withCenter: NSPoint(x: x + W - r, y: y + r), radius: r,
                       startAngle: 0, endAngle: 270, clockwise: true)
        path.line(to: NSPoint(x: x + r, y: y))
        path.appendArc(withCenter: NSPoint(x: x + r, y: y + r), radius: r,
                       startAngle: 270, endAngle: 180, clockwise: true)
        path.line(to: NSPoint(x: x, y: y + H - r))
        path.appendArc(withCenter: NSPoint(x: x + r, y: y + H - r), radius: r,
                       startAngle: 180, endAngle: 90, clockwise: true)
        path.line(to: NSPoint(x: x + W/2, y: y + H))
        return path
    }

    private func ringFraction(slot: String, showElapsed: Bool) -> Double {
        let now = Date()
        let resetAt: Date?
        let period: TimeInterval
        switch slot {
        case "weekly":  resetAt = store.data.weeklyResetAt;  period = 7 * 24 * 3600
        case "sonnet":  resetAt = store.data.sonnetResetAt;  period = 7 * 24 * 3600
        case "design":  resetAt = store.data.designResetAt;  period = 7 * 24 * 3600
        default:        resetAt = store.data.sessionResetAt; period = 5 * 3600
        }
        guard let reset = resetAt, reset > now else {
            return showElapsed ? 1.0 : 0.0
        }
        let remaining = min(reset.timeIntervalSince(now) / period, 1.0)
        return showElapsed ? 1.0 - remaining : remaining
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
