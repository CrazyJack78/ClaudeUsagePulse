import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // Kein Dock-Icon — nur Menubar
let delegate = AppDelegate()
app.delegate = delegate
app.run()
