import Foundation
import Testing
@testable import ModelDeckMacCore

// Issue #572 — the state Tim hit on 2026-08-24: a day-old HTTP 529 blip
// (Anthropic's servers-overloaded response) sat at the top of the deck as a
// RED banner telling him to sign in again, on an account whose credential was
// fine the whole time.
//
// Ruled: soft style, no timer. The daemon classifies overload-class streaks
// (`transient: true`) and the app renders them in the #539 quiet shape —
// gray, waiting icon, no promoted repair on either surface. The #539/#395
// evidence discipline is untouched: only a measured routed success clears the
// alert; nothing hides on a clock.
//
// Placeholder identities only — this repo mirrors publicly.

private func member(
    proxyCredential: String? = "ok",
    proxyRelogin: ProxyReloginCapability? = ProxyReloginCapability(available: true)
) -> DeckAccount {
    DeckAccount(
        id: "placeholder-account", provider: "claude", label: "Placeholder Sub",
        enabled: true, isDefault: false,
        authState: "ok",
        proxyPool: "member",
        proxyCredential: proxyCredential,
        proxyRelogin: proxyRelogin
    )
}

private func alert(
    statusCode: Int? = 529,
    remedy: String = "No action needed — the provider’s servers were briefly overloaded; the next request through this subscription clears it.",
    transient: Bool? = true
) -> MemberBlackoutAlert {
    MemberBlackoutAlert(
        accountId: "placeholder-account",
        provider: "claude",
        label: "Placeholder Sub",
        consecutiveFailures: 4,
        firstFailureAt: "2026-08-24T05:17:01.000Z",
        lastFailureAt: "2026-08-24T05:17:07.000Z",
        statusCode: statusCode,
        remedy: remedy,
        transient: transient
    )
}

@Suite("Transient overload blackout (issue #572)")
@MainActor
struct Issue572TransientBlackoutTests {
    /// THE TRIPWIRE. An overload-class streak must never promote the sign-in
    /// repair — the credential is fine, and the 2026-08-24 incident was
    /// exactly this button under exactly this wrong advice.
    @Test func anOverloadStreakOffersNoFixOnEitherSurface() {
        let transient = alert()
        #expect(transient.isTransient)
        let presentation = makeModel().presentation(for: member(), routedFailures: transient)
        #expect(presentation?.credentialIsBroken == false)
        #expect(presentation?.display == .action(prominent: false))
    }

    /// The evidence line still tells the truth — the streak and its HTTP code
    /// stay visible; only the alarm and the wrong remedy go.
    @Test func theEvidenceLineSurvivesTheSoftStyle() {
        let transient = alert()
        #expect(transient.statusLine == "Placeholder Sub: last 4 requests failed")
        #expect(!transient.remedy.lowercased().contains("sign in"))
        #expect(transient.remedy.contains("No action needed"))
    }

    /// The red path is exactly what it was: an auth-class streak (401) keeps
    /// the alarm and promotes the fix.
    @Test func anAuthStreakStaysRedAndPromotesTheFix() {
        let red = alert(
            statusCode: 401,
            remedy: "Sign in again to restore proxy routing.",
            transient: nil
        )
        #expect(red.isTransient == false)
        let presentation = makeModel().presentation(for: member(), routedFailures: red)
        #expect(presentation?.credentialIsBroken == true)
        #expect(presentation?.display == .action(prominent: true))
    }

    /// Daemon skew: an older daemon omits `transient` and the payload keeps
    /// the red behaviour it always had.
    @Test func anOlderDaemonPayloadKeepsTheRedBehaviour() throws {
        let payload = #"""
        {
          "accounts": [],
          "usage": [],
          "memberBlackout": {
            "threshold": 3,
            "alerts": [{
              "accountId": "placeholder-account",
              "provider": "claude",
              "label": "Placeholder Sub",
              "consecutiveFailures": 4,
              "lastFailureAt": "2026-08-24T05:17:07.000Z",
              "statusCode": 529,
              "remedy": "Sign in again to restore proxy routing."
            }]
          }
        }
        """#
        let state = try JSONDecoder().decode(DeckState.self, from: Data(payload.utf8))
        let decoded = try #require(state.memberBlackout?.alerts.first)
        #expect(decoded.transient == nil)
        #expect(decoded.isTransient == false)
        #expect(makeModel().presentation(for: member(), routedFailures: decoded)?.display
            == .action(prominent: true))
    }

    /// A newer daemon's transient payload decodes the additive field.
    @Test func theTransientPayloadDecodes() throws {
        let payload = #"""
        {
          "accounts": [],
          "usage": [],
          "memberBlackout": {
            "threshold": 3,
            "alerts": [{
              "accountId": "placeholder-account",
              "provider": "claude",
              "label": "Placeholder Sub",
              "consecutiveFailures": 4,
              "lastFailureAt": "2026-08-24T05:17:07.000Z",
              "statusCode": 529,
              "transient": true,
              "remedy": "No action needed — the provider’s servers were briefly overloaded; the next request through this subscription clears it."
            }]
          }
        }
        """#
        let state = try JSONDecoder().decode(DeckState.self, from: Data(payload.utf8))
        let decoded = try #require(state.memberBlackout?.alerts.first)
        #expect(decoded.isTransient)
        #expect(decoded.remedy.contains("No action needed"))
    }
}

// MARK: - Helpers

@MainActor
private func makeModel() -> ProxyReloginModel {
    ProxyReloginModel(
        manager: SilentStub(),
        stateProvider: SilentStub(),
        browser: SilentStub(),
        pollInterval: .zero,
        sleep: { _ in },
        now: { Date() }
    )
}

/// No network, no browser, no daemon — these tests exercise derivations only.
private struct SilentStub: ProxyReloginManaging, DeckStateProviding, BrowserOpening {
    func startProxyRelogin(accountID: String) async throws -> ProxyReloginState {
        ProxyReloginState(phase: "idle")
    }

    func proxyReloginState(accountID: String) async throws -> ProxyReloginState {
        ProxyReloginState(phase: "idle")
    }

    func cancelProxyRelogin(accountID: String) async throws -> ProxyReloginState {
        ProxyReloginState(phase: "cancelled")
    }

    func deckState() async throws -> DeckState {
        DeckState(accounts: [], usage: [])
    }

    func open(_ url: URL) {}
}
