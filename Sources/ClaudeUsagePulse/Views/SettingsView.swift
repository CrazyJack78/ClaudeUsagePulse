import SwiftUI
import ServiceManagement

struct SettingsView: View {
    let onLogout: () -> Void
    let onSettingsChanged: () -> Void

    @AppStorage("displayMode")      private var displayMode:      String = "menubar"
    @AppStorage("menubarStyle")     private var menubarStyle:     String = "both"
    @AppStorage("windowStyle")      private var windowStyle:      String = "bars"
    @AppStorage("alwaysOnTop")      private var alwaysOnTop:      Bool   = false
    @AppStorage("refreshInterval")  private var refreshInterval:  Double = 10

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
                Section("Menubar") {
                    Picker("Menubar zeigt", selection: $menubarStyle) {
                        Text("Session%").tag("session")
                        Text("Session% · Wöchentlich%").tag("both")
                        Text("Höchsten Wert").tag("max")
                    }
                    .onChange(of: menubarStyle) { onSettingsChanged() }
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
}
