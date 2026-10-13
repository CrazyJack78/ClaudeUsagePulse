import XCTest
@testable import ClaudeUsageCore

/// Diese Tests halten die Ursache des Anmelde-Problems fest:
/// Die alte Prüfung akzeptierte jedes Cookie, dessen Name "session" enthält —
/// und fiel damit auf `activitySessionId` herein, das schon vor der Anmeldung existiert.
final class SessionCookiesTests: XCTestCase {

    // MARK: - Anmeldung erkennen

    func test_angemeldetNurMitSessionKey() {
        XCTAssertTrue(SessionCookies.isLoggedIn(Fixtures.loggedInCookies))
    }

    func test_anonymeCookiesGeltenNichtAlsAnmeldung() {
        XCTAssertFalse(
            SessionCookies.isLoggedIn(Fixtures.anonymousCookies),
            "activitySessionId enthält 'session', belegt aber keine Anmeldung"
        )
    }

    func test_leereCookielisteIstNichtAngemeldet() {
        XCTAssertFalse(SessionCookies.isLoggedIn([]))
    }

    func test_sessionKeyLCGiltNichtAlsSessionKey() {
        let cookies = [Fixtures.cookie("sessionKeyLC", "nur-ein-cache")]
        XCTAssertFalse(SessionCookies.isLoggedIn(cookies),
                       "Namen müssen exakt übereinstimmen, nicht nur im Präfix")
    }

    func test_leererWertGiltNichtAlsAnmeldung() {
        let cookies = [Fixtures.cookie("sessionKey", "")]
        XCTAssertFalse(SessionCookies.isLoggedIn(cookies))
    }

    func test_fremdeDomainsZaehlenNicht() {
        let cookies = [Fixtures.cookie("sessionKey", "abc", domain: ".example.com")]
        XCTAssertFalse(SessionCookies.isLoggedIn(cookies))
    }

    // MARK: - Relevante Cookies filtern

    func test_nurClaudeUndAnthropicCookiesWerdenUebernommen() {
        let mixed = Fixtures.loggedInCookies
            + [Fixtures.cookie("SID", "google", domain: ".accounts.google.com")]
        let relevant = SessionCookies.relevant(mixed)

        XCTAssertFalse(relevant.contains { $0.name == "SID" })
        XCTAssertTrue(relevant.contains { $0.name == "sessionKey" })
    }

    // MARK: - Organisation ermitteln

    func test_organisationKommtAusLastActiveOrg() {
        XCTAssertEqual(
            SessionCookies.orgIdCandidates(Fixtures.loggedInCookies),
            ["f25c7b20-1234-5678-9abc-def012345678"]
        )
    }

    func test_ohneLastActiveOrgGibtEsKeineKandidaten() {
        XCTAssertTrue(SessionCookies.orgIdCandidates(Fixtures.anonymousCookies).isEmpty)
    }

    func test_organisationsIdWirdAufSicheresFormatGeprueft() {
        XCTAssertTrue(SessionCookies.isValidOrgId("f25c7b20-1234-5678-9abc-def012345678"))
        XCTAssertTrue(SessionCookies.isValidOrgId("abc_DEF-123"))
        XCTAssertFalse(SessionCookies.isValidOrgId("../../etc/passwd"))
        XCTAssertFalse(SessionCookies.isValidOrgId("mit leerzeichen"))
        XCTAssertFalse(SessionCookies.isValidOrgId(""))
    }

    func test_unsichereOrganisationsIdWirdAussortiert() {
        let cookies = Fixtures.anonymousCookies
            + [Fixtures.cookie("lastActiveOrg", "../../etc")]
        XCTAssertTrue(SessionCookies.orgIdCandidates(cookies).isEmpty)
    }

    // MARK: - Kandidaten aus dem Bootstrap

    func test_bootstrapLiefertAlleOrganisationenInReihenfolge() {
        XCTAssertEqual(
            SessionCookies.orgIdsFromBootstrap(Fixtures.bootstrapTwoOrgs),
            ["aaaaaaaa-1111-2222-3333-444444444444",
             "f25c7b20-1234-5678-9abc-def012345678"],
            "Beide Organisationen, damit die zweite probiert werden kann, "
            + "wenn die erste 403 liefert"
        )
    }

    func test_bootstrapOhneOrganisationLiefertNichts() {
        XCTAssertTrue(SessionCookies.orgIdsFromBootstrap(["account": NSNull()]).isEmpty)
    }

    func test_bootstrapMitDirekterOrganisationsId() {
        let json = ["organization_id": "f25c7b20-1234"] as [String: Any]
        XCTAssertEqual(SessionCookies.orgIdsFromBootstrap(json), ["f25c7b20-1234"])
    }
}
