# Issue 648 — implementation saved, Claude identity decision pending

The default one-login behavior is implemented for Claude and Codex. The required home-preservation, consent, migration, reversal, and Mac flow checks pass. **This work is not ready to integrate:** a separate regression check demonstrates that Claude's reported config identity can disagree with the Keychain login used for quota after a home move.

The user’s amended work order is authoritative; the requested GitHub issue/comments read was unavailable. No Git command, commit, merge, PR, deployment, or external message was performed. Changes remain in this worktree. Development and review used placeholder identities and temporary homes, without accessing live credentials, the live Keychain, provider quota, or running user sessions.

## Pending decision

Claude stores its sign-in outside the home directory on macOS. Moving the last managed account back to `~/.claude` can select an older unscoped Keychain login belonging to a different account. The existing `auth status` check can report the identity from the moved config while the credential belongs to someone else; the repository documents that split in `docs/CLAUDE_IDENTITY.md`.

A partial safeguard currently marks moved Claude homes as requiring verification and withholds quota/renewal until verification. The independent skeptic proved that ordinary verification can clear that safeguard incorrectly. The failing test **`Claude home move cannot unlock quota from config identity alone`** preserves the problem in `test/provider-management.test.mjs`.

Tim has been asked whether the unsafe Claude transition may refuse until a provider-owned sign-in flow can prove the correct login. That would narrow the amended requirement that one remaining account can always turn switching off. **No answer has arrived, and that refusal has not been implemented.** The default one-account installation does not require this transition and is covered by passing checks.

## Behavior implemented

- `claudeManaged` / `codexManaged` default to `null`. An existing ModelDeck-owned home symlink promotes only an undecided setting to `true` at startup. Explicit `false` stays false.
- An unmanaged first account references its real home and creates no profile directory. Usage, transcript ingestion, verification, login, and renewal use that home.
- Unmanaged activation, home adoption/restoration, shell writers/installers, and related managed configuration writers refuse with `not-managed` (409) before writes.
- A second registration requires `manageProvider: true`; otherwise it returns `manage-required` (409). Consent takes over the existing home with the shared legacy mover, writes the managed environment, then creates the additional account. Failure restores the home, account, setting, environment contents, and file modes.
- Turning switching off with one account reverses the move and clears the provider's hook/environment. More than one account or overlapping management work refuses. Codex activation holds its reservation through its final environment write.
- `/api/state` reports each provider's managed state and reasons a change is unavailable. The Mac app implements consent/repost, per-provider toggles, and hidden activation controls for unmanaged providers. Sign-in setup retries reuse the account already registered.

## Per-file changes

| File | Change |
| --- | --- |
| `src/db.mjs` | Tri-state management defaults and settings validation before transitions. |
| `src/service.mjs` | Management state, consent, takeover/release and rollback, operation guards, real-home reads, Codex shell writes, state output, stale-read protection, partial Claude identity safeguard described above. |
| `src/server.mjs` | Management error codes and settings updates through the transition service. |
| `src/adapters/provider-profile.mjs` | Shared reversible legacy-home mover and read-only unmanaged-home validation. |
| `src/adapters/claude.mjs` | Real-home validation for unmanaged usage/auth paths; existing adoption uses the shared mover. |
| `src/adapters/codex.mjs` | Real-home validation for unmanaged usage/auth paths. |
| `src/provider-shell-env.mjs` | New atomic provider hook updater; refuses symlink targets and malformed marked blocks. |
| `src/transcript-ingest.mjs` | Real-home roots work without requiring a managed profiles directory. |
| `src/codex-rollout-ingest.mjs` | Registered real-home roots and reconciliation outside the managed profiles directory. |
| `scripts/install-shell-env.sh` | Per-provider management checks before installation or removal; read-only settings lookup; symlink refusal. |
| `macos/ModelDeckMac/Sources/ModelDeckMacCore/DaemonModels.swift` | Managed state, blocked reasons, consent request flag, older-daemon compatibility. |
| `macos/ModelDeckMac/Sources/ModelDeckMacCore/DaemonSettings.swift` | Optional persisted management flags and partial updates. |
| `macos/ModelDeckMac/Sources/ModelDeckMacCore/SettingsSyncModel.swift` | Per-provider toggle updates. |
| `macos/ModelDeckMac/Sources/ModelDeckMacCore/AddAccountModel.swift` | Consent/repost step and sign-in retries without duplicate registration. |
| `macos/ModelDeckMac/Sources/ModelDeckMac/AddAccountSheet.swift` | Required consent copy/buttons and recoverable sign-in setup errors. |
| `macos/ModelDeckMac/Sources/ModelDeckMac/SettingsWindowView.swift` | Per-provider toggles, reasons, and management-gated activation controls. |
| `macos/ModelDeckMac/Tests/ModelDeckMacCoreTests/Issue648ProviderManagementTests.swift` | New consent, settings, retry, and activation presentation-wiring checks. |
| `macos/ModelDeckMac/Tests/ModelDeckMacCoreTests/AddAccountModelTests.swift` | Failed activation now expects the recoverable sign-in step. |
| `macos/ModelDeckMac/Tests/ModelDeckMacCoreTests/Issue459SubscriptionCopyTripwireTests.swift` | Exact exceptions for Tim's required account-switching label and consent wording; other copy rules remain enforced. |
| `test/provider-management.test.mjs` | Required both-provider tripwires, HTTP boundaries, injected rollback failures, concurrency, and the red Claude identity proof. |
| `test/shell-env.test.mjs` | Managed fixtures and unmanaged/symlinked removal refusal. |
| `test/api.test.mjs` | Existing managed API fixtures explicitly opt in. |
| `test/auto-refresh.test.mjs` | Existing managed refresh fixture explicitly opts in. |
| `test/claude-activation-watchdog.test.mjs` | Existing activation fixtures explicitly opt in. |
| `test/claude-profile-explainer.test.mjs` | Existing managed profile fixtures explicitly opt in. |
| `test/claude-renewal-proxy-identity.test.mjs` | Existing managed renewal fixture explicitly opts in. |
| `test/claude-statusline.test.mjs` | Existing managed statusline fixtures explicitly opt in. |
| `test/client-key-helper-wiring.test.mjs` | Existing managed shell/helper fixture explicitly opts in. |
| `test/codex-duplicate-token.test.mjs` | Existing managed duplicate-token fixture explicitly opts in. |
| `test/db-service.test.mjs` | Existing managed service fixtures explicitly opt in. |
| `test/proxy-pool.test.mjs` | Existing managed routing fixture explicitly opts in. |
| `test/service-phase2.test.mjs` | Existing managed activation/auth fixtures explicitly opt in. |
| `test/shared-scope.test.mjs` | Existing managed shared-scope fixtures explicitly opt in. |
| `test/tool-path-fallback.test.mjs` | Existing managed CLI-path fixture explicitly opts in. |
| `test/warehouse-ingest-scheduler.test.mjs` | Existing managed ingestion fixture explicitly opts in. |
| `README.md` | Replaces the unconditional switching promise with the second-login offer and untouched single-login home behavior. |
| `FINISH-648.md` | This implementation, review, and verification record. |

## Required tripwires

The original regression was unconditional profile-home creation and activation on the first registration, which redirected clients such as T3 Code away from the original home.

| Check | Result |
| --- | --- |
| `one-login-never-touches-home` — Claude and Codex | Pass. Real home and transcript bytes/inodes/modes remain intact; no profile or shell environment created; verification and quota are stubbed; ingestion finds the original transcript; activation and hook installation refuse with `not-managed`. |
| `second-account-asks-before-managing` — both providers, including rollback variants | Pass. Coded refusal without consent; symlink, original transcript, two accounts, and environment after consent; injected failures restore one account, real home, and prior setting. |
| `existing-managed-install-stays-managed` — both providers | Pass. Owned symlink promotes null to true without replacing the link. |
| `unmanage-with-one-account-restores-real-home` — both providers | Pass for the filesystem/registration contract; more than one account refuses. Native Claude identity continuity remains the separate open finding. |
| Swift `manageRequiredStepAndRepost` | Pass for Claude and Codex. |
| Swift `settingsToggleRoundTrip` | Pass. |
| Swift `deckHidesActivationWhenUnmanaged` | Pass for decoded state and all four view/action wiring guards; no visual app claim. |
| `Claude home move cannot unlock quota from config identity alone` | **Fail — pending identity decision.** |

Additional passing checks cover unreadable launchd capture, file-mode rollback, Codex activation versus unmanage, stale plan/metadata/verification reads, takeover versus account mutations, foreign symlinks, explicit false, API authorization, and sign-in retries after failed setup.

## Verification

- Final focused Node command: `node --test test/provider-management.test.mjs test/shell-env.test.mjs` — **50 passed, 1 failed**, no skips. The only failure is the preserved Claude identity proof. Log: `/tmp/modeldeck-648-final-tripwires.log`.
- `npm test` from this worktree — **1,213 tests: 1,169 passed, 42 failed, 2 skipped, 0 cancelled**. Of the failures, 41 are `listen EPERM` at local socket setup and one is the preserved Claude identity regression. No other failure remains. Log: `/tmp/modeldeck-648-npm-final.log`.
- Swift dependency-free Core package using this worktree's sources: **54 tests passed** across add-account flow, settings, issue 648, and the copy-policy tripwire. Log: `/tmp/modeldeck-648-swift-final-filtered.log`. All six changed Swift source files also pass `swiftc -parse`.
- The ordinary Swift package cannot resolve Sparkle with network access disabled. A broader Core attempt ran 1,751 tests but was not green because of temporary fixture paths and sandbox restrictions on socket/process, preferences, and scratch-Keychain checks. A second attempt with corrected paths ran out of disk space while compiling. Its task-owned build output was removed; no user data was cleaned. These attempts do not count as a passing full Swift suite.
- `npm run test:cliproxyapi-pin` — **5 fixture tests passed; live test skipped; command exit 1** because this worktree has no built `dist/cliproxyapi/cliproxyapi`. Building requires unavailable fetching; no production listener was used. Log: `/tmp/modeldeck-648-pin.log`.
- No native app, T3 Code resume, installed-CLI login, or real Keychain continuity test was run. Tests never spent provider quota. The scratch-Keychain test attempted only its own explicitly named temporary keychain and failed at creation; it never reached the login Keychain.

## Independent review

Three independent finders covered correctness/concurrency, security/compatibility, and the amended spec/UI. An independent skeptic reproduced and checked their findings. The following were fixed with regression checks: Codex activation/write race; stale profile-reference persistence; unguarded shell removal; incomplete launchd rollback capture; rollback file modes; duplicate account creation on sign-in retry; missing activation presentation wiring in the test.

The Claude credential-identity issue remains **MAJOR, unresolved**. Its control flow is reproduced with placeholders, supported by the repository's documented identity/credential split; current native-provider behavior was deliberately not probed. Review record: `/tmp/review648-skeptic.md`. Do not describe this work as ready or fully green while that finding and its red test remain.

The review also checked a possible missing `profile-exists` / `adoptExistingProfile` flow. Those symbols are absent from the captured starting baseline and appeared in the main checkout later; this task did not remove them. Integration must combine this unmanaged branch with the later #645/#649 managed-profile choice. No Git operation or unrelated port of later main changes was attempted.


## Integration round

This section supersedes the pending Claude-unmanage decision and red-test status above. Tim's specified refusal is implemented. All six supplied conflict files are resolved, with both the unmanaged first-login flow and main's adopt-or-fresh flow retained. **The full requested integration remains incomplete because #644 is absent from the supplied merge.**

### Conflict resolutions

| File | Resolution |
| --- | --- |
| `src/service.mjs` | Kept `moveLegacyHome`, `safeProfileName`, all management state/guards, main's `CODEX_PROFILES_DIR` default/migration fields, and `accountProfileCreations`. First unmanaged registration uses the real home and skips profile inspection. A second requires consent, performs takeover, then calls the managed create method. Both managed methods use main's `accountProfileForCreation`, adoption/cleanup checks, serialization and `profileNote`. Preserved main's concurrent-create error message. Management inference runs after Codex migration chooses its effective root. |
| `src/server.mjs` | Combined the management error codes and `profile-exists`; added `claude-unmanage-unavailable` to the exposed coded-error allowlist. Kept main's profile summary/note response handling and startup migration wait. |
| `macos/ModelDeckMac/Sources/ModelDeckMacCore/DaemonModels.swift` | Kept both optional request fields, `manageProvider` and `existingProfile`, plus `ExistingProfileSummary` and `profileNote`. Managed Claude reports the exact refusal reason through `managementDisabledReason`, which the existing Settings toggle already uses for disabling and caption text. |
| `macos/ModelDeckMac/Sources/ModelDeckMacCore/AddAccountModel.swift` | Kept `.manageProvider` and `.adoptExistingProfile`, both coded-error cases, and request flags through successive choices. Removed duplicate pending-request storage/reset and duplicate retry method. One retry path reuses the saved subscription after sign-in setup failure. |
| `macos/ModelDeckMac/Sources/ModelDeckMac/AddAccountSheet.swift` | Kept both prompts, their buttons/titles, and step-one numbering. Kept one retry presentation with main's exact wording: “Your subscription was added, but sign-in could not start.” `profileNote` remains visible. |
| `macos/ModelDeckMac/Tests/ModelDeckMacCoreTests/AddAccountModelTests.swift` | Retained the recoverable `.signIn` assertion and all test cases from both sides. Review verified all 47 baseline test functions remain. |

### Claude refusal and integration checks

- New refusal tripwire: **`claude-unmanage-unavailable refuses before moving home or changing settings`**, replacing `Claude home move cannot unlock quota from config identity alone`. It failed before the refusal was implemented, then passed. It exercises the HTTP transition with shared settings both off and on, plus the direct release method, and asserts the exact 409 code/message, identical settings/accounts/files, and zero home moves or environment writes.
- Exact refusal: **“Turning off account switching for Claude is not available yet. Your accounts and history are unchanged.”** Added this exact literal to `Issue459SubscriptionCopyTripwireTests.swift`'s exception list. Codex switching off remains available and tested.
- `Issue648ProviderManagementTests.swift` retains all five original cases and adds consent → profile choice → sign-in retry, coded-error decoding, and `claudeUnmanageIsDisabledWithTheRefusalReason`. Settings tests now cover Claude's refused update retaining its state and Codex's successful round trip.
- Added Node cases for first-login orphan bypass, both providers' consent followed by adopt/fresh, and management inference after legacy Codex migration.
- Review found a real #647/#648 interaction: activation after a deferred migration writes a terminal pin to the legacy profile; a later successful migration previously left that pin pointing to a missing folder. Startup now repairs an existing Codex terminal file from its validated registered active profile. A failed repair reports blocked startup and retries on a later restart. It creates no new terminal file or hook. The new tripwire **`Codex migration updates an existing terminal pin and retries a failed write at restart`** failed before the repair and now passes, including sourcing the corrected file in a temporary shell.

### Verification

- `node --check` passes on all three changed `.mjs` files: service, server and provider-management tests. `swiftc -parse` passes on all six changed Swift files.
- Final root `npm test`: **1,254 tests; 1,211 passed, 41 failed, 2 skipped, 0 cancelled**. Every failure is the known local-socket **`listen EPERM`** restriction; no other failure remains. Log: `/tmp/modeldeck-648-integration-npm-final.log`.
- Focused management/migration/shell run: **81 passed, 0 failed** before the extra terminal-repair test. All **10 profile-exists tests** passed after preserving main's concurrent-create response. The terminal-repair test passed separately and in the final root run.
- Requested ordinary Swift filters were attempted: AddAccount hit the unwritable default compiler cache; Issue648 with writable cache paths could not resolve Sparkle in this sandbox. A temporary dependency-free Core package linked to the current worktree then passed **62 tests across five suites**, covering AddAccount, Issue648, SettingsSyncModel, and the subscription-copy tripwire. Temporary fixture layout/dependency issues were corrected before the passing run. Log: `/tmp/modeldeck-648-integration-swift-core.log`. No native UI rendering or installed-provider sign-in was performed.
- Independent review: three isolated GPT-6 Astra/high reviewers covered correctness, security/compatibility, and the user spec. A separate GPT-6 Astra/high skeptic confirmed the terminal-pin defect and subsequently verified its repair with the new regression, the original reproduction updated to require the correct path, and **23 passing Codex migration tests**. No other new defect remains in the implemented integration; #644 remains the completion blocker below. Reports: `/tmp/modeldeck-648-integration-{correctness,security,spec-review,skeptic}.md`.
- No direct Git command, staging, commit, push, merge, or external message was issued. Before/after SHA-256 checks confirm **HEAD, MERGE_HEAD, MERGE_MSG, MERGE_MODE and index are unchanged**. The permitted package/test runners may invoke their own Git dependency/fixture helpers; no merge metadata changed. Zero conflict markers remain. Source changes are left for the wrapper.

### Remaining #644 dependency

Neither the supplied worktree nor the main checkout inspected in this round contains `reconcileCreatedProfileTranscripts`, `reconcileAccountTranscripts`, or `src/shared-transcripts.mjs`. The source exists in `/Users/timharris/projects/modeldeck/.claude/worktrees/issue-644`, but copying the entire change would be a hand port beyond resolving these conflicts. Two user messages requested the missing source/permission to copy it; no answer has arrived. **No #644 source was copied and no optional/no-op helper was substituted.**

The required create/adoption/startup reconciliation therefore remains outstanding. The next authorized action is either approval to copy the reviewed #644 change from that worktree, or a wrapper/orchestrator merge that actually supplies #644, followed by resolving those integration points and rerunning the affected checks. Do not treat this round as satisfying #644 or as permission to merge to main.
