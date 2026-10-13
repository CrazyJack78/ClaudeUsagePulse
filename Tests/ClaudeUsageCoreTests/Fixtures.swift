import Foundation

/// Echte Daten, aufgezeichnet am 2026-09-02 gegen claude.ai.
/// Siehe ../docs/API-ERKENNTNISSE.md
enum Fixtures {

    // MARK: - Cookies

    static func cookie(_ name: String, _ value: String,
                       domain: String = ".claude.ai") -> HTTPCookie {
        HTTPCookie(properties: [
            .name: name, .value: value, .domain: domain, .path: "/"
        ])!
    }

    /// Die 13 Cookies, die claude.ai schon **ohne** Anmeldung setzt.
    /// `activitySessionId` enthält "session" — darauf ist die alte Prüfung hereingefallen.
    static var anonymousCookies: [HTTPCookie] {
        [
            cookie("anthropic-device-id", "3a169fa1-c242"),
            cookie("activitySessionId", "bf84ebe4-41f8"),
            cookie("ion-vk", "abc"),
            cookie("CH-prefers-color-scheme", "dark"),
            cookie("__ssid", "1d1b309c"),
            cookie("anthropic-consent-preferences", "%7B%7D"),
            cookie("_fbp", "fb.1.178"),
            cookie("ajs_anonymous_id", "claudeai.v1.0c44"),
            cookie("_gcl_au", "1.1.401"),
            cookie("_cfuvid", "xyz"),
            cookie("__cf_bm", "cfbm"),
            cookie("_dd_s_v2", "dd"),
            cookie("g_state", "%7B%7D")
        ]
    }

    /// Nach erfolgreicher Anmeldung kommen fünf weitere dazu.
    static var loggedInCookies: [HTTPCookie] {
        anonymousCookies + [
            cookie("sessionKey", "sk-ant-sid01-EXAMPLE"),
            cookie("sessionKeyLC", "lc"),
            cookie("routingHint", "eu"),
            cookie("lastActiveOrg", "f25c7b20-1234-5678-9abc-def012345678"),
            cookie("user-sidebar-visible-on-load", "true")
        ]
    }

    // MARK: - API-Antworten

    /// Aktuelle Antwort von GET /api/organizations/{orgId}/usage
    static var usageCurrent: [String: Any] {
        json("""
        {
          "five_hour": { "utilization": 6,
            "resets_at": "2026-09-02T15:00:00.235567+00:00",
            "limit_dollars": null, "used_dollars": null,
            "remaining_dollars": null, "locked_reason": null },
          "seven_day": { "utilization": 13,
            "resets_at": "2026-09-08T07:00:00.235587+00:00",
            "limit_dollars": null, "used_dollars": null,
            "remaining_dollars": null, "locked_reason": null },
          "seven_day_oauth_apps": null,
          "seven_day_opus": null,
          "seven_day_sonnet": null,
          "seven_day_cowork": null,
          "seven_day_omelette": null,
          "tangelo": null,
          "iguana_necktie": null,
          "omelette_promotional": null,
          "nimbus_quill": { "utilization": 0, "resets_at": null,
            "limit_dollars": null, "used_dollars": null,
            "remaining_dollars": null, "locked_reason": null },
          "cinder_cove": null,
          "amber_ladder": null,
          "juniper_tide": null,
          "extra_usage": { "is_enabled": false, "monthly_limit": null,
            "used_credits": null, "utilization": null, "currency": null,
            "decimal_places": null, "disabled_reason": null,
            "user_disabled": true, "spend_limit_reached": false,
            "credits_ever_enabled": true, "daily": null, "weekly": null },
          "limits": [
            { "kind": "session", "group": "session", "percent": 6,
              "severity": "normal", "resets_at": "2026-09-02T15:00:00.235567+00:00",
              "scope": null, "is_active": false },
            { "kind": "weekly_all", "group": "weekly", "percent": 13,
              "severity": "normal", "resets_at": "2026-09-08T07:00:00.235587+00:00",
              "scope": null, "is_active": true },
            { "kind": "weekly_scoped", "group": "weekly", "percent": 0,
              "severity": "normal", "resets_at": null,
              "scope": { "model": { "id": null, "display_name": "Fable" },
                         "surface": null },
              "is_active": false }
          ],
          "spend": {
            "used": { "amount_minor": 0, "currency": "USD", "exponent": 2 },
            "limit": null, "percent": 0, "severity": "normal",
            "enabled": false, "can_purchase_credits": true, "can_toggle": true },
          "member_dashboard_available": false
        }
        """)
    }

    /// Variante mit aktivem Guthaben und hohen Werten.
    static var usageWithCredits: [String: Any] {
        json("""
        {
          "five_hour": { "utilization": 92,
            "resets_at": "2026-09-02T15:00:00.000000+00:00" },
          "seven_day": { "utilization": 78,
            "resets_at": "2026-09-08T07:00:00.000000+00:00" },
          "limits": [
            { "kind": "session", "group": "session", "percent": 92,
              "severity": "critical", "resets_at": "2026-09-02T15:00:00.000000+00:00",
              "scope": null, "is_active": true },
            { "kind": "weekly_scoped", "group": "weekly", "percent": 45,
              "severity": "normal", "resets_at": "2026-09-08T07:00:00.000000+00:00",
              "scope": { "model": { "id": "opus", "display_name": "Opus" } },
              "is_active": true }
          ],
          "spend": {
            "used": { "amount_minor": 1250, "currency": "EUR", "exponent": 2 },
            "limit": { "amount_minor": 5000, "currency": "EUR", "exponent": 2 },
            "percent": 25, "severity": "normal", "enabled": true }
        }
        """)
    }

    /// Alte Struktur, wie v0.1.6 sie kennt — muss weiter funktionieren.
    static var usageLegacy: [String: Any] {
        json("""
        {
          "five_hour":        { "utilization": 42, "resets_at": "2026-09-02T15:00:00+00:00" },
          "seven_day":        { "utilization": 55, "resets_at": "2026-09-08T07:00:00+00:00" },
          "seven_day_sonnet": { "utilization": 30, "resets_at": "2026-09-08T07:00:00+00:00" },
          "extra_usage":      { "utilization": 20, "used_credits": 500,
                                "monthly_limit": 2500 }
        }
        """)
    }

    /// Antwort des Bootstrap mit zwei Organisationen.
    static var bootstrapTwoOrgs: [String: Any] {
        json("""
        {
          "account": { "memberships": [
            { "organization": { "uuid": "aaaaaaaa-1111-2222-3333-444444444444" } },
            { "organization": { "uuid": "f25c7b20-1234-5678-9abc-def012345678" } }
          ]}
        }
        """)
    }

    static func json(_ text: String) -> [String: Any] {
        try! JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
    }
}
