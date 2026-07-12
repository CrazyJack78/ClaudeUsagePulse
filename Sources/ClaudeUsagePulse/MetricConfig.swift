import Foundation
import Combine

struct MetricConfig: Codable, Identifiable, Equatable {
    var key:            String  // API-Key, z.B. "five_hour"
    var name:           String  // Vollständiger Name, z.B. "Session (5h)"
    var shortLabel:     String  // Kürzel für Menubar, z.B. "Se"
    var visibleInFloat: Bool    = true  // Im schwebenden Fenster anzeigen

    var id: String { key }

    // Bekannte API-Keys mit vorgeschlagenen Namen/Kürzeln
    static let knownSuggestions: [String: (name: String, short: String)] = [
        "five_hour":          ("Session (5h)",    "Se"),
        "seven_day":          ("Wöchentlich (7d)", "We"),
        "seven_day_sonnet":   ("Nur Sonnet",       "So"),
        "seven_day_omelette": ("Claude Design",    "De"),
        "seven_day_fable":    ("Fable",            "Fa"),
        "seven_day_fable_5":  ("Fable 5",          "F5"),
        "seven_day_opus":     ("Opus",             "Op"),
        "seven_day_haiku":    ("Haiku",            "Ha"),
        "extra_usage":        ("API Credits",      "Cr"),
    ]

    static func suggested(for key: String) -> MetricConfig {
        if let s = knownSuggestions[key] {
            return MetricConfig(key: key, name: s.name, shortLabel: s.short)
        }
        let readable = key.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ").map { $0.capitalized }.joined(separator: " ")
        let short = String(readable.filter { !$0.isWhitespace }.prefix(2))
        return MetricConfig(key: key, name: readable, shortLabel: short)
    }
}

class MetricConfigStore: ObservableObject {
    static let shared = MetricConfigStore()

    @Published private(set) var configs: [MetricConfig] = []

    private let udKey = "metricConfigs_v2"

    init() { load() }

    // MARK: - Persistenz

    func load() {
        if let data = UserDefaults.standard.data(forKey: udKey),
           let arr  = try? JSONDecoder().decode([MetricConfig].self, from: data) {
            configs = arr
        } else {
            configs = Self.defaultConfigs
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(configs) {
            UserDefaults.standard.set(data, forKey: udKey)
        }
    }

    func update(_ config: MetricConfig) {
        if let i = configs.firstIndex(where: { $0.key == config.key }) {
            configs[i] = config
            save()
        }
    }

    // MARK: - Discovery

    /// Merged neu entdeckte API-Keys mit bestehenden Configs (erhält User-Edits)
    func merge(discoveredKeys: [String]) {
        let existingKeys = Set(configs.map { $0.key })
        var updated = configs
        for key in discoveredKeys where !existingKeys.contains(key) {
            updated.append(MetricConfig.suggested(for: key))
        }
        // Entfernte Keys herausnehmen
        updated = updated.filter { discoveredKeys.contains($0.key) }
        configs = updated
        save()
    }

    // MARK: - Lookup

    func config(for key: String) -> MetricConfig? {
        configs.first { $0.key == key }
    }

    func shortLabel(for key: String) -> String {
        config(for: key)?.shortLabel ?? String(key.prefix(2))
    }

    func name(for key: String) -> String {
        config(for: key)?.name ?? key
    }

    // MARK: - Defaults

    static var defaultConfigs: [MetricConfig] {
        ["five_hour", "seven_day", "seven_day_sonnet", "seven_day_omelette", "extra_usage"]
            .map { MetricConfig.suggested(for: $0) }
    }
}
