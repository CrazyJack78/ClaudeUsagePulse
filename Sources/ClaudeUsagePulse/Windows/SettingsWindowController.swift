import AppKit
import SwiftUI

class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    var onLogout: (() -> Void)?
    var onSettingsChanged: (() -> Void)?
    var onRefreshMetrics: (() -> Void)?

    func show() {
        if window == nil { buildWindow() }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }

    private func buildWindow() {
        let view = SettingsView(
            onLogout: { [weak self] in self?.onLogout?() },
            onSettingsChanged: { [weak self] in self?.onSettingsChanged?() },
            onRefreshMetrics: { [weak self] in self?.onRefreshMetrics?() }
        )

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 1),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "ClaudeUsagePulse — Einstellungen"
        panel.contentView = NSHostingView(rootView: view)
        panel.delegate = self
        panel.isFloatingPanel = false
        panel.animationBehavior = .none
        panel.center()
        let fitting   = panel.contentView!.fittingSize
        let maxHeight = (NSScreen.main?.visibleFrame.height ?? 800) - 80
        panel.setContentSize(CGSize(width: fitting.width, height: min(fitting.height, maxHeight)))
        self.window = panel
    }
}
