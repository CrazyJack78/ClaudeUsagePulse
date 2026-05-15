import AppKit
import SwiftUI

class FloatingWindowController: NSObject {
    private var panel: NSPanel?
    private(set) var store: UsageStore

    init(store: UsageStore) {
        self.store = store
    }

    var isVisible: Bool { panel?.isVisible == true }

    func show() {
        if panel == nil { buildPanel() }
        panel?.makeKeyAndOrderFront(nil)
        applyAlwaysOnTop()
    }

    func hide() { panel?.orderOut(nil) }

    func toggle() { isVisible ? hide() : show() }

    func applyAlwaysOnTop() {
        let on = UserDefaults.standard.bool(forKey: "alwaysOnTop")
        panel?.level = on ? .floating : .normal
    }

    func savePosition() {
        if let desc = panel?.frameDescriptor {
            UserDefaults.standard.set(desc, forKey: "floatingWindowFrame")
        }
    }

    // MARK: - Private

    private func buildPanel() {
        let rootView = FloatingView(store: store)
        let hosting  = NSHostingView(rootView: rootView)
        hosting.autoresizingMask = [.width, .height]

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 160),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "ClaudeUsagePulse"
        panel.contentView = hosting
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.isFloatingPanel = true

        if let saved = UserDefaults.standard.string(forKey: "floatingWindowFrame") {
            panel.setFrame(from: saved)
        } else {
            panel.center()
        }

        self.panel = panel
    }
}
