import Foundation
import UserNotifications

class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private var isFirstLoad = true
    private var lastNotifiedLevel: [String: Int] = [:]
    private var lastSnapshot:      [String: (pct: Double, time: Date)] = [:]
    private var lastSpeedFired:    [String: Date] = [:]

    override init() {
        super.init()
        UserDefaults.standard.register(defaults: [
            "notificationsEnabled": true,
            "speedWarnEnabled":     true,
            "speedWarnPercent":     10,
            "speedWarnMinutes":     5,
        ])
    }

    func requestPermission() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    @MainActor
    func checkAndNotify(data: UsageData) {
        let configs = MetricConfigStore.shared.configs
        let now     = Date()

        if isFirstLoad {
            for c in configs { lastSnapshot[c.key] = (data[c.key].percentage, now) }
            isFirstLoad = false
            return
        }

        let notifOn = UserDefaults.standard.bool(forKey: "notificationsEnabled")

        for c in configs {
            let metric = data[c.key]
            let pct    = metric.percentage

            if notifOn {
                checkAbsolute(key: c.key, name: c.name, pct: pct, resetStr: metric.resetStr)
                checkSpeed(key: c.key, name: c.name, pct: pct)
            }

            lastSnapshot[c.key] = (pct, now)
        }
    }

    // MARK: - Absolut-Schwellen (75 % / 90 %)

    @MainActor
    private func checkAbsolute(key: String, name: String, pct: Double, resetStr: String) {
        let level: Int = pct >= 90 ? 2 : pct >= 75 ? 1 : 0
        if pct < 70 { lastNotifiedLevel[key] = 0 }
        let last = lastNotifiedLevel[key] ?? 0
        guard level > last else { return }
        lastNotifiedLevel[key] = level

        let suffix = resetStr.isEmpty ? "" : " \(resetStr)"
        if level == 2 {
            send(title: "🔴 \(name) bei \(Int(pct))%",
                 body:  "Kritischer Verbrauch!\(suffix)",
                 id:    "\(key)_90")
            AlertPopupWindow.show(metric: name, percentage: pct)
        } else {
            send(title: "⚠️ \(name) bei \(Int(pct))%",
                 body:  "Hoher Verbrauch.\(suffix)",
                 id:    "\(key)_75")
        }
    }

    // MARK: - Geschwindigkeits-Warnung

    private func checkSpeed(key: String, name: String, pct: Double) {
        let ud = UserDefaults.standard
        guard ud.bool(forKey: "speedWarnEnabled") else { return }

        let threshPct = Double(ud.integer(forKey: "speedWarnPercent"))
        let threshMin = Double(ud.integer(forKey: "speedWarnMinutes"))
        guard threshPct > 0, threshMin > 0 else { return }

        guard let snap = lastSnapshot[key] else { return }
        let elapsed = Date().timeIntervalSince(snap.time) / 60.0
        guard elapsed >= 0.5 else { return }

        let delta = pct - snap.pct
        guard delta > 0 else { return }

        // Hochgerechnet: würde diese Rate den Schwellwert überschreiten?
        let projected = delta / elapsed * threshMin
        guard projected >= threshPct else { return }

        // Cooldown: nicht häufiger als einmal pro Schwellwert-Zeitfenster
        if let last = lastSpeedFired[key],
           Date().timeIntervalSince(last) / 60.0 < threshMin { return }

        lastSpeedFired[key] = Date()
        send(title: "⚡ \(name) steigt schnell",
             body:  "+\(Int(delta.rounded()))% in \(Int(elapsed.rounded())) min",
             id:    "\(key)_speed")
    }

    // MARK: - Senden

    private func send(title: String, body: String, id: String) {
        let content       = UNMutableNotificationContent()
        content.title     = title
        content.body      = body
        content.sound     = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: nil)
        )
    }

    // MARK: - Delegate — Notifications auch im Vordergrund anzeigen

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                 willPresent notification: UNNotification,
                                 withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void) {
        handler([.banner, .sound])
    }
}
