# ClaudeUsagePulse — Devlog

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
