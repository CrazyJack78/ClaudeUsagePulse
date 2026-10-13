# Wiederaufnahme — ClaudeUsagePulse

**Stand:** 2026-10-13 · **Version:** 0.1.7

macOS-Menüleisten-App, die den Verbrauch des eigenen Claude-Abos anzeigt.

Architektur, Bauweg und Konventionen stehen in `CLAUDE.md`, die Versionshistorie in
`DEVLOG.md`, die Schnittstellen-Details in `../docs/API-ERKENNTNISSE.md` (außerhalb
dieses Repositorys). Hier steht nur, was sich **nicht** aus dem Code ableiten lässt.

> **Hinweis:** Dieses Repository ist **öffentlich**. In keine Datei hier gehören Tokens,
> Organisations-Kennungen, Cookies, Download-Links mit Zugangsschlüssel oder Auszüge aus
> Gesprächsverläufen. Das ist am 02.09.2026 einmal schiefgegangen und wurde am 13.10.2026
> bereinigt.

## Zuerst lesen

| Datei | Warum |
|---|---|
| `Sources/ClaudeUsageCore/SessionCookies.swift` | Welches Cookie als Anmeldung gilt. Drei Regeln, alle hart erkauft |
| `Sources/ClaudeUsageCore/UsageParser.swift` | Auswertung der Antwort. Behandelt beide Schema-Ebenen |
| `Sources/ClaudeUsagePulse/Windows/AuthWebWindow.swift` | Anmeldefenster. Hier saßen zwei der drei v0.1.7-Fehler |
| `Sources/ClaudeUsageCore/BrowserUserAgent.swift` | Warum überhaupt ein eigener User-Agent nötig ist |

## Befehle

```bash
swift test              # 41 Tests
swift build -c release
./build.sh              # App-Bundle erzeugen
./create_dmg.sh         # DMG mit Drag-to-Applications-Layout
```

## Absicht, kein Fehler

Jede dieser Stellen sieht nach einer Vereinfachungsmöglichkeit aus. Alle sind das Ergebnis
einer Fehlersuche, die Tage gekostet hat.

| Stelle | Sieht aus wie | Ist aber |
|---|---|---|
| `SessionCookies`: nur `sessionKey`, **exakt** verglichen — kein „Name enthält session/token" | unnötig streng | `activitySessionId` ist eines von ~13 Cookies, die claude.ai schon **ohne** Anmeldung setzt. Ein Namensvergleich trifft es und die App hält sich mitten im Vorgang für angemeldet |
| **Kein** Filter auf die Adresse (`/login`, `/auth`, `accounts.google`) | fehlende Absicherung | Der Filter war die eigentliche Fehlerquelle. Läuft die Anmeldung über eine Zwischenseite, deren Adresse keines der Muster enthält — z. B. der Schritt mit dem sechsstelligen Code —, schließt die App das Fenster mittendrin. Bewusst ersatzlos entfernt |
| `AuthWebWindow`: Fenster **nicht** auf `nil` setzen | Speicherleck | Per Code erzeugte `NSWindow` haben `isReleasedWhenClosed == true` und geben sich beim Schließen selbst frei. Zusammen mit `window = nil` sind das zwei Freigaben → Absturz, und zwar erst beim Leeren des Autorelease-Pools, weshalb der Stapel nur `objc_release` zeigt |
| `UsageParser`: eigene Prüfung auf `NSNull`, nicht nur `!= nil` | überflüssig | `extra_usage` liefert `utilization: null`. `NSNull` besteht in Swift die Prüfung `!= nil` und erzeugt einen Balken mit 0 % |
| `UsageParser` wertet **zusätzlich** `limits[]` aus | Dopplung | Modellspezifische Grenzen (Fable) stehen **ausschließlich** in `limits[].scope.model.display_name` mit `kind: "weekly_scoped"`, in keinem Schlüssel der obersten Ebene. Monatelang als „Schnittstelle liefert den Wert nicht" fehlgedeutet |
| `BrowserUserAgent` baut einen vollwertigen Safari-User-Agent | Verschleierung | Google lehnt Anmeldungen in eingebetteten Browser-Ansichten ab (seit 2021) und erkennt sie daran, dass dem `WKWebView`-Standard der abschließende `Version/… Safari/…`-Teil fehlt |
| Logik liegt in `ClaudeUsageCore`, nicht in der App | unnötige Aufteilung | Ein `executableTarget` ist nicht testbar. Vor v0.1.7 hatte das Projekt deshalb **keine** Tests |

## Nicht nochmal versuchen

- **Cookies nicht über Namensmuster erkennen.** Zweimal gescheitert, siehe oben.
- **Den Adressfilter nicht wieder einbauen.** Er sieht nach Härtung aus und war die Ursache.
- **Nicht nur die oberste Ebene der Antwort durchsuchen.** Seit etwa Juli 2026 hat sie drei
  Ebenen: alte Schlüssel (viele inzwischen `null`), `limits[]` und `spend`.

## Plattform-Gegensatz — wichtig bei gemeinsamem Code

Die Android-Fassung (`../ClaudeUsagePulseAndroid/`) braucht an derselben Stelle das
**Gegenteil**:

| | macOS | Android |
|---|---|---|
| User-Agent | vollwertiger Safari-UA **nötig** (sonst lehnt Google die Anmeldung ab) | **kein** Browser-UA (sonst Bot-Abfrage, weil die Verbindungssignatur nicht passt) |

Wer Logik zwischen beiden teilt, muss diesen Punkt plattformabhängig halten.

## Symptom → Ursache

| Symptom | Ursache |
|---|---|
| Anmeldefenster schließt mittendrin, App hält sich für angemeldet | Cookie-Erkennung per Namensmuster (`activitySessionId`) |
| Absturz direkt nach erfolgreicher Anmeldung, Stapel nur mit `objc_release` | Doppelte Fenster-Freigabe, siehe oben |
| Balken mit dauerhaft 0 % | `utilization: null` als `NSNull` durchgelassen |
| Fable- oder anderer Modellbalken fehlt | Nur die oberste Ebene durchsucht, `limits[]` nicht ausgewertet |
| Google verweigert die Anmeldung | User-Agent ohne `Version/… Safari/…`-Teil |

## Vorlieben für dieses Projekt

Stehen in `CLAUDE.md`. Ergänzend: **Tests vor der Funktion.** Ein fehlgeschlagener Test wird
nicht passend geschrieben, sondern zuerst geprüft, ob die Funktion falsch ist oder der Test
veraltet.

## Gerade halbfertig

- **Untrackte Icon-Quellen** im Wurzelverzeichnis (`AppIcon.icns`, `AppIcon.iconset/`,
  `icon_1024.png`). Die für den Bau nötige Fassung liegt unter `Sources/…/Resources/`, der
  Bau funktioniert also auch ohne. Einchecken oder in `.gitignore` — ungeklärt.
- Die Erkenntnisse aus der Android-Arbeit sind hier noch nicht überall nachgezogen.
