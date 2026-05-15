import SwiftUI
import ServiceManagement

struct SettingsView: View {
    let onLogout: () -> Void
    let onSettingsChanged: () -> Void

    @AppStorage("displayMode")       private var displayMode:       String = "menubar"
    @AppStorage("menubarTop")        private var menubarTop:        String = "session"
    @AppStorage("menubarBottom")     private var menubarBottom:     String = "weekly"
    @AppStorage("menubarBackground") private var menubarBackground: Bool   = true
    @AppStorage("windowStyle")       private var windowStyle:       String = "bars"
    @AppStorage("alwaysOnTop")       private var alwaysOnTop:       Bool   = false
    @AppStorage("refreshInterval")   private var refreshInterval:   Double = 10

    @State private var menubarBgColor: Color = SettingsView.loadBgColor()

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

                Section("Menubar-Slots") {
                    Picker("Obere Zeile", selection: $menubarTop) {
                        Text("Session (5h)").tag("session")
                        Text("Wöchentlich (7d)").tag("weekly")
                        Text("Nur Sonnet").tag("sonnet")
                        Text("Claude Design").tag("design")
                        Text("API Credits").tag("credits")
                    }
                    .onChange(of: menubarTop) { onSettingsChanged() }

                    Picker("Untere Zeile", selection: $menubarBottom) {
                        Text("Keine").tag("none")
                        Text("Session (5h)").tag("session")
                        Text("Wöchentlich (7d)").tag("weekly")
                        Text("Nur Sonnet").tag("sonnet")
                        Text("Claude Design").tag("design")
                        Text("API Credits").tag("credits")
                    }
                    .onChange(of: menubarBottom) { onSettingsChanged() }
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
                        if launchAtLogin {
                            try? SMAppService.mainApp.register()
                        } else {
                            try? SMAppService.mainApp.unregister()
                        }
                    }
            }

            Section("Aktualisierung") {
                Picker("Intervall", selection: $refreshInterval) {
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
                Text("Beim Abmelden werden alle gespeicherten Anmeldedaten gelöscht. Beim nächsten Start öffnet sich das Login-Fenster.")
                    .font(.system(size: 11))
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .padding(.vertical, 8)
    }

    // MARK: - Hintergrundfarbe Persistenz

    static func defaultBgColor() -> Color {
        Color(NSColor.black.withAlphaComponent(0.45))
    }

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
}
