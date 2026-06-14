import AppKit
import Combine
import SwiftUI

class FloatingWindowController: NSObject {
    private var panel: NSPanel?
    private var hosting: NSHostingView<FloatingView>?
    private var cancellable: AnyCancellable?
    private(set) var store: UsageStore

    init(store: UsageStore) {
        self.store = store
        super.init()
        // NSHostingView + @ObservedObject ist in non-activating Panels unzuverlässig.
        // Deshalb: store.$data direkt subscriben und rootView manuell pushen.
        cancellable = store.$data
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.hosting?.rootView = FloatingView(store: self.store)
            }
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
        let h = NSHostingView(rootView: FloatingView(store: store))
        h.autoresizingMask = [.width, .height]
        self.hosting = h

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 380),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel,
                        .hudWindow, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Usage Pulse"
        panel.contentView = h
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.isFloatingPanel = true
        panel.minSize = NSSize(width: 240, height: 200)

        if let saved = UserDefaults.standard.string(forKey: "floatingWindowFrame") {
            panel.setFrame(from: saved)
        } else {
            panel.center()
        }

        self.panel = panel
    }
}
