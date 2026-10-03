# ClaudeUsagePulse — Projektkontext für Claude

> **Hinweis:** Die `CLAUDE.md` eine Ebene höher (`Claude Usage/CLAUDE.md`) beschreibt einen
> READ-ONLY Security-Scanner für das Nachbarprojekt `ClaudeKarma/`. Diese Regeln gelten für
> **Scan-Vorgänge an ClaudeKarma**, nicht für die Entwicklung von ClaudeUsagePulse.

## Was ist das?

Eine native macOS-Menubar-App (Swift/SwiftUI, Swift Package Manager), die den Verbrauch des
eigenen Claude-Abos anzeigt — ohne dass man ständig in der Claude-Desktop-App nachschauen muss.

**Ursprung:** Entstanden aus dem Security-Scan des GitHub-Repos `ClaudeKarma` (Mai 2026). Jack
wollte das Prinzip, aber unter eigener Kontrolle und ohne fremden Code.

- **Repo:** https://github.com/CrazyJack78/ClaudeUsagePulse
- **Aktuelle Version:** v0.1.7 (Build 8) — Anmeldung repariert, Absturz behoben, neues API-Schema
- **Letzte aktive Entwicklung:** 2026-10-03 (noch nicht committet)

## Architektur

```
Sources/ClaudeUsageCore/             Reine Logik, ohne AppKit — hier liegen die Tests an
├── SessionCookies.swift             Anmeldung erkennen, Organisation ermitteln
├── UsageParser.swift                Auswertung der API-Antwort (drei Ebenen)
└── UsageData.swift                  Datenmodell

Sources/ClaudeUsagePulse/
├── main.swift                       Einstiegspunkt
├── AppDelegate.swift                Menubar-Item, Statusanzeige, Zeitring
├── UsageData.swift                  Datenmodell (dictionary-basiert, seit v0.1.5)
├── UsageStore.swift                 State + Refresh-Zyklus
├── MetricConfig.swift               Dynamische Metrik-Konfiguration (Name/Kürzel/Sichtbarkeit)
├── NotificationService.swift        Verbrauchswarnungen (75% / 90% / Geschwindigkeit)
├── Services/
│   ├── APIService.swift             Claude-API-Abruf + automatische Metrik-Discovery
│   └── KeychainService.swift        Session-Cookie im Keychain, mit Geräteschutz
├── Views/
│   ├── FloatingView.swift           Schwebendes Desktop-Fenster mit Balken
│   └── SettingsView.swift           Einstellungen (scrollbar)
└── Windows/
    ├── AuthWebWindow.swift          WKWebView-Login (persistent gehalten wg. Crash)
    ├── FloatingWindowController.swift
    ├── SettingsWindowController.swift
    └── AlertPopupWindow.swift       Rotes Warn-Popup bei 90%
```

**Kernprinzip seit v0.1.5:** Die App hat *keine* fest verdrahteten Metriken. Alles, was die
API als Grenze meldet, wird automatisch zum Balken. Namen und Kürzel sind in den
Einstellungen editierbar, Entscheidungen des Nutzers überleben jede Neuerkennung.

**Seit v0.1.7 wertet `UsageParser` drei Ebenen aus** (die Antwort führt sie parallel):

1. `limits[]` — die aktuelle Quelle. Modellspezifische Grenzen wie **Fable** stehen
   ausschliesslich hier, in `scope.model.display_name`, und in keinem Top-Level-Schlüssel.
2. Top-Level-Schlüssel — die ältere Form; viele stehen inzwischen auf `null`.
3. `spend` — Guthaben, löst `extra_usage` ab.

Bei Dubletten gewinnt `limits[]` (`session` → `five_hour`, `weekly_all` → `seven_day`).
`null` gilt durchgehend als "nicht vorhanden" — sonst entsteht ein 0-%-Geisterbalken,
weil `NSNull` in Swift die Prüfung `!= nil` besteht.

## Drei Regeln für die Anmeldung (teuer gelernt)

1. **Nur `sessionKey` belegt eine Anmeldung.** claude.ai setzt rund dreizehn Cookies schon
   ohne Anmeldung, darunter `activitySessionId`. Eine Prüfung auf "Name enthält session"
   schlägt dort fälschlich an — genau daran scheiterte die Anmeldung ab Oktober 2026.
2. **Fenster nie beim Schliessen freigeben lassen.** Ein per Code erzeugtes `NSWindow` hat
   `isReleasedWhenClosed == true`; zusammen mit `window = nil` ergibt das eine doppelte
   Freigabe und einen Absturz im Autorelease-Pool. Fenster und `WKWebView` werden einmal
   erzeugt und nur noch aus- und eingeblendet.
3. **Die Organisation kommt aus dem Cookie `lastActiveOrg`.** Der Bootstrap kann eine
   Organisation nennen, für die `/usage` mit 403 antwortet; `/api/account` antwortet
   inzwischen selbst mit 403.

Ausserdem: **keinen eigenen User-Agent setzen** — mit Browser-Kennzeichen antwortet
Cloudflare mit einer Bot-Challenge, weil der TLS-Fingerabdruck nicht dazu passt.

Ausführlich in `../docs/API-ERKENNTNISSE.md`.

## Build & Test

```bash
swift test          # 34 Tests gegen ClaudeUsageCore
./build.sh          # Baut ClaudeUsagePulse.app (inkl. codesign --force --deep)
./create_dmg.sh     # DMG mit Drag-to-Applications-Layout + generiertem Hintergrundbild
```

## Offene Punkte (Stand 2026-10-03)

1. **v0.1.7 ist noch nicht committet** — Änderungen liegen nur im Arbeitsbaum.
2. **Untracked Dateien** im Repo: `AppIcon.icns`, `AppIcon.iconset/`, `icon_1024.png`,
   `.dmg_bg_85973/` — bewusst nicht committet oder vergessen? Bei Gelegenheit klären.

### Erledigt in v0.1.7 (nicht erneut anfangen)

- **Fable-Balken** — erscheint jetzt. Er stand nie in einem Top-Level-Schlüssel, sondern
  in `limits[].scope.model`.
- **Post-Login-Crash** — Ursache war die doppelte Freigabe des `NSWindow`, nicht das WebView.

## DMG-Verteilung — Gatekeeper

Die App ist nur ad-hoc signiert (`codesign --sign -`), nicht notarisiert. Auf fremden Macs
blockiert Gatekeeper. Details siehe Memory `feedback_dmg_distribution.md`. Kurzfassung:

- **Option A (funktioniert immer):** Systemeinstellungen → Datenschutz & Sicherheit → Sicherheit
  → "Trotzdem öffnen"
- **Option B (`xattr -cr`):** nur bei USB/SMB/WhatsApp — **nicht** bei AirDrop, E-Mail, Browser-Download
- **Empfohlen für Vertraute:** Download per `curl` (setzt kein Quarantine-Flag) über Jacks
  n8n-Server `https://n8njack.scarecrowdev.com/webhook/dl?t=TOKEN`
- **Dauerhaft:** Apple Developer Account (99 €/Jahr) + Notarisierung

## Historie

- Versionshistorie mit technischen Details: `DEVLOG.md`
- Rekonstruierter Gesprächsverlauf der Entwicklung: `docs/SESSION-CHRONIK.md`

## Arbeitsweise mit Jack

- Deutsch, Ansprache "Jack"
- Bei Fragen erst planen, dann coden
- Tests **vor** dem Code schreiben, wenn Funktionen neu dazukommen oder sich ändern
- Am Ende einer Aufgabe: Timecode (YY:MM:DD-HH:MM) und Tokenverbrauch (Input/Output) ausgeben
