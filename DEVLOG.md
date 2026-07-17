# ClaudeUsagePulse — Devlog

---

## v0.1.6 — 2026-07-13

### DMG-Installer mit Drag-to-Applications Layout
- Neues `create_dmg.sh` Skript erstellt ein professionelles macOS-DMG mit Hintergrundbild, Applications-Symlink und vorpositionierten Icons
- Hintergrundbild (540×380 px, dunkelgrau) wird via Python 3 (stdlib, kein externes Tool) automatisch generiert — Pfeil zeigt von App-Icon zu Applications-Ordner
- Finder-Layout wird per AppleScript gesetzt (Icon-Größe 100 px, App links bei 130/195, Ordner rechts bei 410/195)
- Nutzer sieht beim Öffnen sofort: App links → Pfeil → Applications rechts → einfach rüberziehen

### Verbrauchswarnungen
- **75%-Schwelle**: macOS Systemnotification + Sound ("⚠️ [Metrik] bei 75%")
- **90%-Schwelle**: Notification + rotes Popup-Fenster das über allen anderen Fenstern erscheint (schließt sich nach 10 Sek. automatisch)
- **Geschwindigkeits-Warner**: konfigurierbar — warnt wenn der Verbrauch eine bestimmte Rate überschreitet (Standard: >10% in 5 min); Cooldown verhindert Spam
- Beim ersten App-Start werden Notifications automatisch beantragt (macOS-Berechtigungsdialog)
- Warnungen werden beim Erststart unterdrückt (nur Änderungen auslösen Alerts, nicht der initiale Ladezustand)

### Einstellungen
- Neue Section "Warnungen": Master-Toggle, Geschwindigkeits-Warnung Toggle + konfigurierbarer Schwellenwert (Stepper für % und Minuten)
- Neue Refresh-Intervalle: 1 Minute und 2 Minuten

### Technisch
- `NotificationService.swift`: Singleton, UNUserNotificationCenterDelegate, Absolut- und Geschwindigkeits-Checks mit Duplikat-Schutz
- `AlertPopupWindow.swift`: NSPanel (borderless, floating level) mit SwiftUI-View (rotes RoundedRectangle, 10s Auto-Close)
- `Info.plist`: Version `0.1.6`, Build `7`

---

## v0.1.5 — 2026-07-12

### Dynamisches Metrik-System
- **MetricConfig / MetricConfigStore**: Neue Datenmodell-Schicht; entdeckte API-Keys werden dynamisch gespeichert, mit vorgeschlagenen Namen/Kürzeln vorbelegt und per UserDefaults persistiert
- **Automatische Discovery**: `APIService.fetchUsage` iteriert alle JSON-Keys, sucht nach `utilization`-Feld; neue Keys werden beim nächsten Fetch automatisch hinzugefügt, weggefallene entfernt
- **UserDefaults-Migration**: `migrateUserDefaults()` übersetzt alte Schlüssel (`session`, `weekly`, `sonnet`, `design`, `credits`) auf neue API-Key-Namen (`five_hour`, `seven_day`, etc.)
- **Bekannte API-Keys** mit vorgeschlagenen Anzeigenamen: `five_hour`, `seven_day`, `seven_day_sonnet`, `seven_day_omelette`, `seven_day_fable`, `seven_day_fable_5`, `seven_day_opus`, `seven_day_haiku`, `extra_usage`

### Einstellungen — Balken konfigurieren
- Liste aller entdeckten Metriken mit Checkbox (sichtbar im schwebenden Fenster), editierbarem Name und Kürzel
- **Aktualisieren-Button**: Löst neuen API-Fetch aus, lädt Configs neu — inkl. Debug-Keys nach 3s
- **Scrollbar**: Settings-Panel wird auf `screen.visibleFrame.height - 80` gedeckelt → SwiftUI Form scrollt intern
- **Debug-Section "API-Keys"**: Nach Aktualisieren werden alle Top-Level-JSON-Keys der API-Antwort angezeigt (inkl. Markierung ob sie ein `utilization`-Feld haben → als Metrik erkannt)

### Schwebendes Fenster
- Balken-Filter basiert nur noch auf `visibleInFloat`-Checkbox — keine Sonderbedingung für Credits mehr
- Credits werden wie jede andere Metrik durch die Checkbox ein-/ausgeblendet

### Technisch
- `UsageData` und `MetricData` vollständig neu geschrieben (dictionary-basiert statt hardcodierter Felder)
- `APIService.lastRawKeys`: speichert alle Top-Level-Keys für Debug
- `FloatingView` und `SettingsView` nutzen `@ObservedObject MetricConfigStore.shared`
- `Info.plist`: Version `0.1.5`, Build `6`
- Neues DMG und GitHub-Release **v0.1.5** veröffentlicht

---

## v0.1.4 — 2026-06-14

### Zeitring im Menubar
- Neuer optionaler Fortschrittsring um die Menubar-Pill
- Startet bei 12 Uhr, läuft im Uhrzeigersinn; grauer Track + farbiger Fortschrittsbogen
- Einstellungen: Ring an/aus, Metrik (Session/Weekly/Sonnet/Design), Farbe, Restzeit vs. verstrichene Zeit
- Pill und Text rücken bei aktivem Ring vertikal ein → sichtbarer Abstand zwischen Ring und Schrift
- Horizontale Bildbreite bei aktivem Ring leicht erhöht (4pt pro Seite)

### Sonstiges
- `Info.plist`: Version `0.1.4`, Build `5`
- Neues DMG und GitHub-Release **v0.1.4** veröffentlicht

---

## v0.1.3 — 2026-06-14

### Reset-Zeiten im Floating Window
- Reset-Countdowns werden jetzt korrekt unter jedem Balken angezeigt: z. B. „Reset in 2h 49min"
- Berechnung erfolgt beim API-Abruf (nicht per Live-Timer) — aktualisiert sich mit jedem Datenfetch
- `parseDate` unterstützt jetzt ISO8601 mit Mikrosekunden (z. B. `2026-06-14T14:29:59.548449+00:00`)
- `doubleVal()` löst `JSONSerialization`-Ambiguität bei Int/Double/NSNumber
- `UsageData` speichert Reset-Texte direkt als `String` (statt `Date?`) — vermeidet SwiftUI-Timing-Probleme
- `FloatingWindowController` nutzt Combine-Subscription auf `store.$data`, um `NSHostingView.rootView` manuell zu pushen (Workaround für `@ObservedObject`-Bug in `.nonactivatingPanel`)

### Sonstiges
- `Info.plist`: Version `0.1.3`, Build `4`
- Neues DMG und GitHub-Release **v0.1.3** veröffentlicht

---

## v0.1.2 — 2026-05-25

### Floating Window überarbeitet
- Panel-Stil auf `.hudWindow + .utilityWindow` umgestellt (dunkles, transluzentes macOS HUD-Fenster)
- Standardgröße von 280×160 auf **300×380** erhöht — reicht für alle 5 Balken ohne Scrollen
- Fenstertitel von "ClaudeUsagePulse" auf "Usage Pulse" verkürzt
- `minSize = NSSize(width: 240, height: 200)` ergänzt, damit Inhalte nicht abgeschnitten werden

### Versionsanzeige
- In der Einstellungsansicht wird nun am unteren Rand die aktuelle Version angezeigt: `ClaudeUsagePulse vX.X.X`
- Wert wird zur Laufzeit aus `Bundle.main.infoDictionary["CFBundleShortVersionString"]` gelesen

### Sonstiges
- `Info.plist`: Version `0.1.2`, Build `3`
- Neues DMG und GitHub-Release **v0.1.2** veröffentlicht

---

## v0.1.1 — 2026-05-16

### Datenmodell erweitert
- Neue Felder in `UsageData`: `sonnetPercentage`, `designPercentage`, `creditsPercentage`, `creditsUsedEUR`, `creditsLimitEUR`, `sonnetResetAt`, `designResetAt`
- `APIService` parst jetzt `seven_day_sonnet`, `seven_day_omelette` (Design) und `extra_usage` (API Credits)

### Menubar
- **Konfigurierbare Slots**: Obere und untere Zeile frei wählbar (Session / Weekly / Sonnet / Design / Credits / Keine)
- **Hintergrund mit Farbauswahl**: optionaler, dunkel-transluzenter Capsule-Hintergrund, Farbe & Opacity per `ColorPicker` einstellbar; Persistenz via `NSKeyedArchiver`/`NSColor`
- Capsule-Breite dynamisch — wächst automatisch bei dreistelligen Prozent-Werten
- Font: monospacedDigit, 11pt (klein) / 13pt (groß), mittig zentriert
- Capsule-Padding rundum 15% größer (von `+8` auf `+14`)
- "API-Daten erkunden…" aus dem Kontextmenü entfernt

### Floating Window
- Alle 5 Metriken als Balkenansicht (Session, Weekly, Sonnet, Design, API Credits)
- Kreise-Ansicht zeigt die zwei gewählten Menubar-Slots
- Reset-Countdowns pro Metrik

### Einstellungen
- Neue Sections: Menubar-Hintergrund, Menubar-Slots (ersetzt alten Menubar-Stil-Picker)

### App Icon
- Horizontale Pill-Balken in CoreGraphics (`generate_icon.swift`)
- ICNS via `iconutil`, in `build.sh` ins App Bundle kopiert

### GitHub
- README (Englisch) mit Icon, Feature-Liste, Settings-Tabelle, Privacy-Section
- MIT LICENSE
- Releases mit DMG-Anhang (v0.1.0, v0.1.1)
- Repo-Topics gesetzt

---

## v0.1.0 — 2026-05 (Initiales Release)

### Grundfunktionen
- Menubar-App (NSStatusItem) zeigt Session (5h) und Weekly (7d) Usage
- Login via `WKWebView` (claude.ai), Session-Cookie im macOS Keychain gespeichert
- Schwebendes Fenster (NSPanel) mit Balken- und Kreise-Ansicht
- Auto-Refresh (5 / 10 / 15 / 30 Minuten)
- Einstellungen: Anzeige-Modus, Fenster-Stil, AlwaysOnTop, Refresh-Intervall, Launch at Login
- "Always on Top"-Unterstützung über `.floating`-Level
- Fenstergröße und -position werden in `UserDefaults` gespeichert
