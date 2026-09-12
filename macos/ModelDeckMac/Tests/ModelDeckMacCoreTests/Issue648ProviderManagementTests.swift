import Foundation
import Testing
@testable import ModelDeckMacCore

@Suite("Issue 648 provider home management")
@MainActor
struct Issue648ProviderManagementTests {
    @Test func managementConsentSurvivesExistingProfileChoiceAndSignInRetry() async {
        for provider in [DeckProvider.claude, .codex] {
            for choice in ["adopt", "fresh"] {
                let backend = StubOnboardingBackend()
                let profile = ExistingProfileSummary(path: "/profiles/work", name: "work", transcripts: 3, lastModified: "2026-09-11T12:00:00.000Z")
                backend.createError = DaemonClientError.daemonCodedError(message: "Manage switching first.", code: "manage-required", status: 409)
                let model = AddAccountModel(onboarding: backend, launcher: backend, stateProvider: backend, activator: backend)
                #expect(await model.begin(provider: provider, label: "Work", purpose: "Testing", colorHex: nil))
                #expect(model.step == .manageProvider)
                backend.createError = DaemonClientError.daemonCodedError(message: "Choose a profile.", code: "profile-exists", status: 409, profile: profile)
                #expect(await model.manageSwitching())
                #expect(model.step == .adoptExistingProfile(profile))
                #expect(backend.launchedCommands.isEmpty)
                backend.createError = nil
                backend.loginCommandError = DaemonClientError.httpStatus(503)
                #expect(!(await model.resolveExistingProfile(startFresh: choice == "fresh")))
                #expect(backend.created.last?.manageProvider == true)
                #expect(backend.created.last?.existingProfile == choice)
                #expect(model.step == .signIn)
                backend.loginCommandError = nil
                #expect(await model.retrySignIn())
                #expect(backend.created.count == 3)
                #expect(backend.loginCommandRequests == ["acct-1", "acct-1"])
            }
        }
    }

    @Test func managementClientDecodesCodedRefusals() async {
        for code in ["manage-required", "claude-unmanage-unavailable"] {
            let transport = StubTransport(stubs: [
                .init(status: 200, body: #"{"token":"fixture-token"}"#),
                .init(status: 409, body: "{\"error\":\"Switching refused.\",\"code\":\"\(code)\"}"),
            ])
            let client = DaemonClient(transport: transport)
            await #expect(throws: DaemonClientError.daemonCodedError(message: "Switching refused.", code: code, status: 409)) {
                _ = try await client.createAccount(AccountCreate(provider: "claude", label: "Work", purpose: ""))
            }
        }
    }

    @Test func claudeUnmanageIsDisabledWithTheRefusalReason() throws {
        let message = "Turning off account switching for Claude is not available yet. Your accounts and history are unchanged."
        let accounts = [DeckAccount(id: "one", provider: "claude", label: "Personal"), DeckAccount(id: "two", provider: "codex", label: "Work")]
        let managed = DeckState(accounts: accounts, managed: ["claude": true, "codex": true])
        #expect(managed.managementDisabledReason(for: .claude) == message)
        #expect(managed.managementDisabledReason(for: .codex) == nil)
        let unmanaged = DeckState(accounts: accounts, managed: ["claude": false, "codex": false])
        #expect(unmanaged.managementDisabledReason(for: .claude) == nil)
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let view = try String(contentsOf: package.appendingPathComponent("Sources/ModelDeckMac/SettingsWindowView.swift"), encoding: .utf8)
        #expect(view.contains("let reason = state?.managementDisabledReason(for: provider)"))
        #expect(view.contains(".disabled(!settingsSync.isLoaded || settingsSync.isSaving || state?.managed == nil || reason != nil)"))
        #expect(view.contains("Text(reason ??"))
    }

    @Test func manageRequiredStepAndRepost() async {
        for provider in [DeckProvider.claude, .codex] {
            let backend = StubOnboardingBackend()
            backend.createError = DaemonClientError.daemonCodedError(
                message: "Manage switching first.", code: "manage-required", status: 409
            )
            let model = AddAccountModel(onboarding: backend, launcher: backend, stateProvider: backend, activator: backend)
            #expect(await model.begin(provider: provider, label: "Work", purpose: "Testing", colorHex: nil))
            #expect(model.step == .manageProvider)
            #expect(model.account == nil)
            #expect(backend.launchedCommands.isEmpty)
            #expect(backend.created.first?.manageProvider == nil)
            backend.createError = nil
            #expect(await model.manageSwitching())
            #expect(backend.created.count == 2)
            #expect(backend.created.last?.manageProvider == true)
            #expect(backend.created.last?.provider == provider.rawValue)
            #expect(model.step == .signIn)
        }
    }

    @Test func settingsToggleRoundTrip() async throws {
        let initial = try JSONDecoder().decode(DaemonSettings.self, from: Data("{\"claudeManaged\":null,\"codexManaged\":false}".utf8))
        #expect(initial.claudeManaged == nil)
        #expect(initial.codexManaged == false)
        var enabled = initial
        enabled.claudeManaged = true
        let message = "Turning off account switching for Claude is not available yet. Your accounts and history are unchanged."
        let backend = StubSettingsSync(results: [.success(initial), .success(enabled), .failure(
            DaemonClientError.daemonCodedError(message: message, code: "claude-unmanage-unavailable", status: 409)
        )])
        let model = SettingsSyncModel(sync: backend)
        await model.load()
        await model.setProviderManaged(.claude, enabled: true)
        #expect(model.settings.claudeManaged == true)
        #expect(backend.pushedPatches.last?.claudeManaged == true)
        await model.setProviderManaged(.claude, enabled: false)
        #expect(model.settings.claudeManaged == true)
        #expect(model.lastError == message)
        let payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(backend.pushedPatches.last)) as? [String: Bool]
        #expect(payload == ["claudeManaged": false])

        var codexEnabled = initial
        codexEnabled.codexManaged = true
        let codexBackend = StubSettingsSync(results: [.success(initial), .success(codexEnabled), .success(initial)])
        let codexModel = SettingsSyncModel(sync: codexBackend)
        await codexModel.load()
        await codexModel.setProviderManaged(.codex, enabled: true)
        #expect(codexModel.settings.codexManaged == true)
        await codexModel.setProviderManaged(.codex, enabled: false)
        #expect(codexModel.settings.codexManaged == false)
        #expect(codexBackend.pushedPatches.last?.codexManaged == false)
    }

    @Test func signInSetupRetryKeepsTheRegisteredAccount() async {
        for provider in [DeckProvider.claude, .codex] {
            let backend = StubOnboardingBackend()
            backend.loginCommandError = DaemonClientError.httpStatus(503)
            let model = AddAccountModel(onboarding: backend, launcher: backend, stateProvider: backend, activator: backend)
            #expect(!(await model.begin(provider: provider, label: "Personal", purpose: "", colorHex: nil)))
            #expect(model.step == .signIn)
            #expect(model.account?.id == "acct-1")
            backend.loginCommandError = nil
            #expect(await model.begin(provider: provider, label: "Personal", purpose: "", colorHex: nil))
            #expect(backend.created.count == 1)
            #expect(backend.loginCommandRequests == ["acct-1", "acct-1"])
            #expect(model.step == .signIn)
        }
    }

    @Test func managementConsentRetryDoesNotRegisterAgainAfterActivationFailure() async {
        let backend = StubOnboardingBackend()
        backend.createError = DaemonClientError.daemonCodedError(message: "Manage switching first.", code: "manage-required", status: 409)
        let model = AddAccountModel(onboarding: backend, launcher: backend, stateProvider: backend, activator: backend)
        #expect(await model.begin(provider: .claude, label: "Work", purpose: "", colorHex: nil))
        backend.createError = nil
        backend.loginResult = LoginCommand(provider: "claude", command: "placeholder login", requiresActivation: true)
        backend.activateError = DaemonClientError.httpStatus(503)
        #expect(!(await model.manageSwitching()))
        #expect(model.step == .signIn)
        #expect(backend.launchedCommands.isEmpty)
        backend.activateError = nil
        #expect(await model.begin(provider: .claude, label: "Work", purpose: "", colorHex: nil))
        #expect(backend.created.count == 2) // one refused POST, one consented POST
        #expect(backend.launchedCommands == ["placeholder login"])
    }

    @Test func deckHidesActivationWhenUnmanaged() throws {
        let state = try JSONDecoder().decode(DeckState.self, from: Data("{\"managed\":{\"claude\":false,\"codex\":true}}".utf8))
        #expect(!state.isManaged(.claude))
        #expect(state.isManaged(.codex))
        #expect(DeckState().isManaged(.claude)) // older daemon compatibility
        #expect(state.managementDisabledReason(for: .claude) == nil)
        let multiple = DeckState(accounts: [
            DeckAccount(id: "one", provider: "codex", label: "Personal"),
            DeckAccount(id: "two", provider: "codex", label: "Work"),
        ], managed: ["codex": true])
        #expect(multiple.managementDisabledReason(for: .codex) != nil)
        // The app is a separate executable target. Keep its visibility and action
        // wiring under this tripwire too: removing a view guard must fail it.
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let view = try String(contentsOf: package.appendingPathComponent("Sources/ModelDeckMac/SettingsWindowView.swift"), encoding: .utf8)
        #expect(view.contains("showActivation: state?.isManaged(section.provider) == true"))
        #expect(view.contains("onActivate: deckModel.canActivate && state?.isManaged(section.provider) == true"))
        #expect(view.contains("if showActivation && account.isDefault"))
        #expect(view.contains("if showActivation { radio }"))
    }
}
