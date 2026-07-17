import AppKit
import SwiftUI

class AlertPopupWindow: NSObject {
    private static var panel:      NSPanel?
    private static var closeTimer: Timer?

    @MainActor
    static func show(metric: String, percentage: Double) {
        dismiss()

        let view    = AlertView(metric: metric, percentage: percentage) { dismiss() }
        let hosting = NSHostingView(rootView: view)

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 180),
            styleMask:   [.borderless],
            backing:     .buffered,
            defer:       false
        )
        p.backgroundColor = .clear
        p.isOpaque        = false
        p.hasShadow       = true
        p.level           = .floating
        p.contentView     = hosting
        p.center()
        p.orderFrontRegardless()
        panel = p

        closeTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { _ in
            DispatchQueue.main.async { dismiss() }
        }
    }

    static func dismiss() {
        closeTimer?.invalidate()
        closeTimer = nil
        panel?.close()
        panel = nil
    }
}

private struct AlertView: View {
    let metric:     String
    let percentage: Double
    let onDismiss:  () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("🔴 Kritischer Verbrauch")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)

            Text(metric)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))

            Text("\(Int(percentage))%")
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .foregroundColor(.white)

            Button("Schließen") { onDismiss() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.75))
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .padding(20)
        .frame(width: 280, height: 170)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.red.opacity(0.93))
                .shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 8)
        )
    }
}
