import SwiftUI
import ServiceManagement

struct SettingsView: View {
    let onLogout:          () -> Void
    let onSettingsChanged: () -> Void
    let onRefreshMetrics:  () -> Void

    @ObservedObject private var metricStore = MetricConfigStore.shared

    @AppStorage("displayMode")       private var displayMode:       String = "menubar"
    @AppStorage("menubarTop")        private var menubarTop:        String = "five_hour"
    @AppStorage("menubarBottom")     private var menubarBottom:     String = "seven_day"
    @AppStorage("menubarBackground") private var menubarBackground: Bool   = true
    @AppStorage("windowStyle")       private var windowStyle:       String = "bars"
    @AppStorage("alwaysOnTop")       private var alwaysOnTop:       Bool   = false
    @AppStorage("refreshInterval")   private var refreshInterval:   Double = 10
    @AppStorage("ringEnabled")       private var ringEnabled:       Bool   = false
    @AppStorage("ringSlot")          private var ringSlot:          String = "five_hour"
    @AppStorage("ringShowElapsed")   private var ringShowElapsed:   Bool   = false

    @State private var menubarBgColor: Color = SettingsView.loadBgColor()
    @State private var ringColor:      Color = SettingsView.loadRingColor()
    @State private var editingConfigs: [MetricConfig] = []
    @State private var isRefreshing = false
    @State private var rawAPIKeys: [String] = []
    @State private var showRawKeys = false

    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = true
    @AppStorage("speedWarnEnabled")     private var speedWarnEnabled:     Bool = true
    @AppStorage("speedWarnPercent")     private var speedWarnPercent:     Int  = 10
    @AppStorage("speedWarnMinutes")     private var speedWarnMinutes:     Int  = 5

    @State private var launchAtLogin: Bool = (SMAppService.mainApp.status == .enabled)

    var body: some View {
        Form {
            Section("Anzeige-Modus") {
                Picker("Wo anzeigen", selection: $displayMode) {
                    Text("Nur Menubar-Text").tag("menubar")
                    Text("Nur schwebendes Fenster").tag("floating")
                    Text("Beides").tag("both")
                }
                .onChange(of: displayMode) { onSettingsChanged() }
            }

            if displayMode == "menubar" || displayMode == "both" {
                Section("Menubar-Hintergrund") {
                    Toggle("Hintergrund anzeigen", isOn: $menubarBackground)
                        .onChange(of: menubarBackground) { onSettingsChanged() }

                    if menubarBackground {
                        ColorPicker("Farbe", selection: $menubarBgColor, supportsOpacity: true)
                            .onChange(of: menubarBgColor) {
                                SettingsView.saveBgColor(menubarBgColor)
                                onSettingsChanged()
                            }
                        Button("Farbe zurücksetzen") {
                            menubarBgColor = SettingsView.defaultBgColor()
                            SettingsView.saveBgColor(menubarBgColor)
                            onSettingsChanged()
                        }
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    }
                }

                Section("Zeitring") {
                    Toggle("Ring anzeigen", isOn: $ringEnabled)
                        .onChange(of: ringEnabled) { onSettingsChanged() }

                    if ringEnabled {
                        Picker("Metrik", selection: $ringSlot) {
                            ForEach(metricStore.configs) { c in
                                Text(c.name).tag(c.key)
                            }
                        }
                        .onChange(of: ringSlot) { onSettingsChanged() }

                        ColorPicker("Ringfarbe", selection: $ringColor)
                            .onChange(of: ringColor) {
                                SettingsView.saveRingColor(ringColor)
                                onSettingsChanged()
                            }

                        Toggle("Verstrichene Zeit anzeigen", isOn: $ringShowElapsed)
                            .onChange(of: ringShowElapsed) { onSettingsChanged() }
                    }
                }

                Section("Menubar-Slots") {
                    Picker("Obere Zeile", selection: $menubarTop) {
                        ForEach(metricStore.configs) { c in
                            Text(c.name).tag(c.key)
                        }
                    }
                    .onChange(of: menubarTop) { onSettingsChanged() }

                    Picker("Untere Zeile", selection: $menubarBottom) {
                        Text("Keine").tag("none")
                        ForEach(metricStore.configs) { c in
                            Text(c.name).tag(c.key)
                        }
                    }
                    .onChange(of: menubarBottom) { onSettingsChanged() }
                }

                // Balken-Konfiguration
                Section {
                    // Spalten-Header
                    HStack(spacing: 10) {
                        Text("☑")
                            .frame(width: 16)
                        Text("API-Key / Name")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Kürzel")
                            .frame(width: 56, alignment: .center)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                    Divider()

                    ForEach($editingConfigs) { $config in
                        HStack(spacing: 10) {
                            // Checkbox: im schwebenden Fenster anzeigen
                            Toggle("", isOn: $config.visibleInFloat)
                                .toggleStyle(.checkbox)
                                .labelsHidden()
                                .onChange(of: config.visibleInFloat) { saveEdits() }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(config.key)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                                HStack(spacing: 8) {
                                    TextField("", text: $config.name)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 13))
                                        .onChange(of: config.name) { saveEdits() }
                                    TextField("", text: $config.shortLabel)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 52)
                                        .font(.system(size: 13, design: .monospaced))
                                        .multilineTextAlignment(.center)
                                        .onChange(of: config.shortLabel) { saveEdits() }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    HStack {
                        Text("Balken konfigurieren")
                        Spacer()
                        Button {
                            isRefreshing = true
                            onRefreshMetrics()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                editingConfigs = metricStore.configs
                                rawAPIKeys = APIService.shared.lastRawKeys
                                isRefreshing = false
                            }
                        } label: {
                            if isRefreshing {
                                ProgressView().scaleEffect(0.7)
                            } else {
                                Label("Aktualisieren", systemImage: "arrow.clockwise")
                                    .font(.system(size: 11))
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(isRefreshing)
                    }
                }
            }

            if displayMode == "floating" || displayMode == "both" {
                Section("Schwebendes Fenster") {
                    Picker("Darstellung", selection: $windowStyle) {
                        Text("Balken").tag("bars")
                        Text("Kreise").tag("circles")
                    }
                    .onChange(of: windowStyle) { onSettingsChanged() }

                    Toggle("Immer im Vordergrund", isOn: $alwaysOnTop)
                        .onChange(of: alwaysOnTop) { onSettingsChanged() }
                }
            }

            Section("Allgemein") {
                Toggle("Bei Anmeldung starten", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) {
                        if launchAtLogin { try? SMAppService.mainApp.register() }
                        else             { try? SMAppService.mainApp.unregister() }
                    }
            }

            Section {
                Toggle("Warnungen aktivieren", isOn: $notificationsEnabled)

                if notificationsEnabled {
                    Toggle("Geschwindigkeits-Warnung", isOn: $speedWarnEnabled)

                    if speedWarnEnabled {
                        Stepper("Wenn mehr als \(speedWarnPercent)% ...",
                                value: $speedWarnPercent, in: 1...50)
                        Stepper("... in \(speedWarnMinutes) Minuten",
                                value: $speedWarnMinutes, in: 1...30)
                    }
                }
            } header: {
                Text("Warnungen")
            } footer: {
                Text("75% → Systembenachrichtigung · 90% → Benachrichtigung + rotes Popup")
                    .font(.system(size: 11))
            }

            Section("Aktualisierung") {
                Picker("Intervall", selection: $refreshInterval) {
                    Text("1 Minute").tag(1.0)
                    Text("2 Minuten").tag(2.0)
                    Text("5 Minuten").tag(5.0)
                    Text("10 Minuten").tag(10.0)
                    Text("15 Minuten").tag(15.0)
                    Text("30 Minuten").tag(30.0)
                }
                .onChange(of: refreshInterval) { onSettingsChanged() }
            }

            Section {
                Button(role: .destructive, action: onLogout) {
                    Label("Abmelden (erneut einloggen)", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } header: {
                Text("Account")
            } footer: {
                Text("Beim Abmelden werden alle gespeicherten Anmeldedaten gelöscht.")
                    .font(.system(size: 11))
            }

            if !rawAPIKeys.isEmpty {
                Section {
                    DisclosureGroup(
                        isExpanded: $showRawKeys,
                        content: {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(rawAPIKeys, id: \.self) { key in
                                    let isMetric = metricStore.configs.contains { $0.key == key }
                                    HStack {
                                        Text(key)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Text(isMetric ? "✓ Metrik" : "– kein utilization")
                                            .font(.system(size: 10))
                                            .foregroundStyle(isMetric ? Color.green : Color.orange)
                                    }
                                    .padding(.vertical, 1)
                                }
                            }
                            .padding(.vertical, 4)
                        },
                        label: {
                            Label("API-Keys (\(rawAPIKeys.count) gesamt)", systemImage: "list.bullet")
                                .font(.system(size: 12))
                        }
                    )
                } header: {
                    Text("Debug — letzte API-Antwort")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.visible)
        .frame(width: 400)
        .padding(.vertical, 8)
        .onAppear { editingConfigs = metricStore.configs }
        .onChange(of: metricStore.configs) { editingConfigs = metricStore.configs }
        .safeAreaInset(edge: .bottom) {
            Text("ClaudeUsagePulse v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
        }
    }

    private func saveEdits() {
        for config in editingConfigs {
            metricStore.update(config)
        }
        onSettingsChanged()
    }

    // MARK: - Farbpersistenz

    static func defaultBgColor() -> Color { Color(NSColor.black.withAlphaComponent(0.45)) }

    static func loadBgColor() -> Color {
        guard let data = UserDefaults.standard.data(forKey: "menubarBgColor"),
              let ns = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
        else { return defaultBgColor() }
        return Color(ns)
    }

    static func saveBgColor(_ color: Color) {
        let ns = NSColor(color)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: ns, requiringSecureCoding: false) {
            UserDefaults.standard.set(data, forKey: "menubarBgColor")
        }
    }

    static func loadRingColor() -> Color {
        guard let data = UserDefaults.standard.data(forKey: "ringColorData"),
              let ns = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
        else { return Color(NSColor.systemTeal) }
        return Color(ns)
    }

    static func saveRingColor(_ color: Color) {
        let ns = NSColor(color)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: ns, requiringSecureCoding: false) {
            UserDefaults.standard.set(data, forKey: "ringColorData")
        }
    }
}
