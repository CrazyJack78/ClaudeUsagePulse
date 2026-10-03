# ClaudeUsagePulse — Devlog

---

## v0.1.7 — 2026-10-03

**Anmeldung repariert, Absturz behoben, neues API-Schema**

Die Anmeldung schlug ab Anfang Oktober fehl: Google meldete einen Fehler, der Weg über
E-Mail und sechsstelligen Code schien zu klappen, danach stürzte die App ab. Drei Ursachen,
die zusammenwirkten.

### 1. Die App hielt sich zu früh für angemeldet

`AuthWebWindow` akzeptierte jedes Cookie, dessen Name "session" oder "token" enthält.
Darauf passt **`activitySessionId`** — eines von rund dreizehn Cookies, die claude.ai
schon *ohne* Anmeldung setzt. Geschützt hat davor nur ein Filter auf die Adresse
(`/login`, `/auth`, `accounts.google`).

Sobald die Anmeldung über eine Zwischenseite lief, deren Adresse keines dieser Muster
enthält — und genau das tut der Schritt mit der Code-Eingabe — hielt die App den Vorgang
für beendet und schloss das Fenster mittendrin. Deshalb lief es vorher lange gut: Früher
blieb man während der Anmeldung durchgehend auf `/login`.

Jetzt zählt allein `sessionKey`, exakt verglichen. Der Adressfilter ist ersatzlos entfallen —
es ist gleichgültig, über welche Zwischenseiten die Anmeldung läuft.

### 2. Der Absturz: doppelte Freigabe des Fensters

Ein per Code erzeugtes `NSWindow` hat `isReleasedWhenClosed == true`. Der alte Ablauf

```swift
self.window?.close()   // gibt das Fenster frei
self.window = nil      // ARC gibt es ein zweites Mal frei
```

gibt es also zweimal frei. Der Absturz fällt nicht an dieser Stelle auf, sondern erst beim
Leeren des Autorelease-Pools des Main-Run-Loops — daher die vier Absturzberichte, deren
Stapel nur noch `objc_release` → `AutoreleasePoolPage::releaseUntil` zeigen.

Das `WKWebView` wurde seit `683facc` bereits dauerhaft gehalten, das `NSWindow` aber nicht.
Jetzt wird auch das Fenster einmal erzeugt, nie freigegeben und beim Erfolg nur noch
ausgeblendet (`orderOut`). Zusätzlich steht `isReleasedWhenClosed = false`.

Damit ist der alte offene Punkt "Post-Login-Crash" erledigt.

### 3. Selbst nach korrekter Anmeldung kamen keine Daten

`resolveOrganizationId` nahm die erste Organisation aus `/api/bootstrap`. Genau dieser Weg
liefert eine Organisation, für die `/usage` mit
`403 "Invalid authorization for organization"` antwortet. `/api/account` antwortet
inzwischen selbst mit 403.

Neu: Die Organisation kommt zuerst aus dem zuletzt erfolgreichen Wert, dann aus dem Cookie
**`lastActiveOrg`**, und erst zuletzt aus dem Bootstrap — dort als Liste, die der Reihe nach
durchprobiert wird. Gemerkt wird eine Organisation erst, wenn der Abruf geklappt hat.

### 4. Nicht mehr bei jedem Fehler abmelden

Vorher führte beim Start *jeder* Fehler zu `cleanupCredentials()` — auch ein kurzer
Netzwerkaussetzer. Jetzt wird nur bei einer echt abgelaufenen Anmeldung abgemeldet;
vorübergehende Störungen zeigen eine Meldung, und der nächste Durchlauf versucht es erneut.
Eine Cloudflare-Abweisung ("Just a moment…") wird als eigener Fall erkannt.

Ausserdem prüft der Start mit `hasValidSession()`, ob überhaupt eine echte Sitzung
hinterlegt ist — gespeicherte anonyme Cookies gelten nicht mehr als Anmeldung.

### 5. Neues Antwortschema der API

Die Antwort von `/usage` hat seit Juli 2026 drei Ebenen nebeneinander:

- **`limits[]`** — die aktuelle Quelle, enthält auch modellspezifische Grenzen
- **Top-Level-Schlüssel** — die ältere Form, viele stehen inzwischen auf `null`
- **`spend`** — Guthaben, löst `extra_usage` ab

Daraus folgen zwei Korrekturen:

- **Der Fable-Balken erscheint endlich.** Modellspezifische Grenzen stehen ausschliesslich
  in `limits[].scope.model.display_name` und tauchen in keinem Top-Level-Schlüssel auf.
  Die alte Auswertung konnte sie prinzipiell nicht finden — unabhängig davon, wie oft
  aktualisiert wurde.
- **Der 0-%-Geisterbalken ist weg.** `extra_usage` hat `utilization: null`; in Swift besteht
  `NSNull` die Prüfung `!= nil`, die Metrik wurde also mit 0 % angelegt. `null` gilt jetzt
  durchgehend als "nicht vorhanden".

Guthaben wird in der Währung angezeigt, die die API nennt (USD oder EUR), nicht mehr fest €.

### Umbau der Projektstruktur

Die reine Logik liegt neu im Target **`ClaudeUsageCore`** (`SessionCookies`, `UsageParser`,
`UsageData`) — ein `executableTarget` lässt sich nicht testen. Dazu das erste Testtarget des
Projekts: **34 Tests**, die unter anderem festhalten, dass `activitySessionId` nicht als
Anmeldung durchgeht und dass Fable aus `limits[]` kommt.

```bash
swift test     # 34 Tests
./build.sh
```

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
