# Issue #634 implementation

Implemented in the supplied worktree. Changes remain uncommitted for the wrapper.
No git commands were issued directly; the wrapper owns commit, push, and PR creation.
No external posts, live proxy calls, or provider sessions were started.

A rate-limited proxy credential now reports `resting` with its retry instant.
Settings and the deck show “Rate limited · back at <local short time>” in neutral
styling, with “Rate limited · resting” when the time cannot be parsed. Resting
does not promote a sign-in repair. Automatic recovery does not claim a sign-in happened.

## Changes by file

| File | Change |
| --- | --- |
| `src/proxy-relogin.mjs` | Allowlist `next_retry_after` and `expired`; classify a future retry on an unavailable/error entry as resting, while bad-token messages and past expiry remain error. Preserve disabled precedence and healthy-wins merging. Emit the retry instant as a canonical ISO detail. |
| `src/service.mjs` | Pass the service clock to classification. Clear repair observations when resting so a natural reset cannot become “signed in again.” The account payload still forwards the health record and detail unchanged. |
| `macos/ModelDeckMac/Sources/ModelDeckMacCore/ProxyReloginModel.swift` | Format resting copy with the existing ISO parser and local short time. Suppress repair promotion even with a routed-failure alert, and use the quiet presentation. |
| `macos/ModelDeckMac/Sources/ModelDeckMac/DeckPopoverView.swift` | Show resting copy with the neutral clock/color on the deck too. Tooltip and VoiceOver use that same sentence, without the sign-in remedy. Preserve controls for a sign-in already running. |
| `macos/ModelDeckMac/Sources/ModelDeckMacCore/DaemonModels.swift` | Update wire-field comments for resting and its ISO detail. |
| `test/proxy-relogin.test.mjs` | Add classification, payload, healthy-wins, expiry, and automatic-reset regression checks. Extend the non-secret allowlist assertion. |
| `macos/ModelDeckMac/Tests/ModelDeckMacCoreTests/ProxyReloginTests.swift` | Add local-time, invalid-time fallback, quiet repair presentation, and deck/VoiceOver regression checks. |
| `macos/ModelDeckMac/Tests/ModelDeckMacCoreTests/Issue515RoutedFailurePromotionTests.swift` | Update the existing deck icon source assertion for the shared quiet state. |
| `macos/ModelDeckMac/Tests/ModelDeckMacCoreTests/Issue539SoftRepairedBannerTests.swift` | Update existing rendering assertions while retaining repaired-state coverage. |

Auth flows, the shell-environment writer, and renewal logic are unchanged.
All new fixtures use placeholder identities.

## Named regression checks

In `test/proxy-relogin.test.mjs`:

- `proxy-rate-limit-resting`: unavailable/error with empty message and future retry is resting; retry detail is ISO. Also covers a non-auth rate-limit message.
- `proxy-rate-limit-past-retry`: elapsed, equal-to-now, missing, malformed, and non-string retries remain error.
- `proxy-rate-limit-bad-token`: unauthorized and other bad-token messages override a future retry; past credential expiry remains error.
- `proxy-rate-limit-account-payload`: both Claude and Codex account payloads carry resting and the ISO detail unchanged.
- `proxy-rate-limit-reset-is-not-sign-in`: resting-to-active and error-to-resting-to-active never manufacture a repair timestamp.
- `resting preserves healthy-wins for both providers and never replaces a disabled or active verdict`: covers both entry orders and disabled precedence.

In `ProxyReloginTests.swift`:

- `aRestingMemberShowsLocalResetTimeWithoutPromotingSignIn`: ISO timestamps with and without fractional seconds; no promoted repair or broken styling, including routed-failure alerts.
- `aRestingMemberWithNoUsableResetTimeStaysQuiet`: missing, empty, and invalid timestamp fallback.
- `aRestingDeckBannerUsesQuietCopyForDisplayAndVoiceOver`: source assertions connect the tested core copy to neutral deck rendering and spoken output.

The initial focused run failed four checks before implementation. The automatic-reset
check separately failed before its fix with a manufactured repair timestamp.

## Verification

| Check | Result |
| --- | --- |
| `node --test test/proxy-relogin.test.mjs test/member-blackout-repaired.test.mjs test/member-blackout-alert.test.mjs` | **38 passed, 0 failed**, exit 0. |
| `npm test`, worktree root, final revision | **1,169 tests: 1,126 passed, 41 failed, 2 skipped**, exit 1. Every failure was `listen EPERM: operation not permitted 127.0.0.1`; exact tests listed below. |
| `swift test --filter ProxyRelogin`, from `macos/ModelDeckMac` | **Could not run**, exit 1 before tests. The default compiler cache was unwritable. Retrying with caches under the task’s temporary directory reached `sandbox-exec: sandbox_apply: Operation not permitted`. |
| `swiftc -frontend -parse` on all six changed Swift files | Passed, exit 0. This checks syntax, not type checking or test execution. |
| Changed Swift source assertions | All 10 checked source assertions match the view. This is not a Swift test-suite pass. |

The two Node skips were the daemon CJS bundle check because its local esbuild
dependency was absent, and the live CLIProxyAPI pin check because the worktree
had no staged proxy binary. Neither dependency was installed or built for this task.

Logs and the before/after file comparison are under
`/private/tmp/modeldeck-634-9xy18tnf/`:
`node-red.log`, `node-reset-red.log`, `node-affected-final.log`,
`npm-test-final.log`, `swift-red.log`, `swift-cache.log`,
`swift-parse-final.log`, and `final-change.diff`.

## Independent review

Three isolated Codex reviewers used correctness, security/compatibility, and
spec/UI/accessibility perspectives. An independent skeptic checked every
substantive finding. Review model: `gpt-5.6-sol`, high effort.

- Automatic reset falsely recorded as sign-in: confirmed with a real-code proof,
  fixed, and checked again with real code and the new regression test.
- Resting deck alert remained red and spoke the sign-in remedy: confirmed by
  tracing the view, fixed, and checked again by tracing the rendering and
  accessibility paths. No live visual verification was possible.
- Raw ISO offset normalization: dismissed. The instant is preserved, and the
  service forwards the resulting health-record detail unchanged.
- Wire-field comment nit: fixed to document resting and the ISO retry detail.

No remaining concrete issue was found in the targeted fixes. Allowlist exclusion
of token-bearing fields, bad-token precedence, healthy-wins merging, and payload
propagation were checked with running tests. Swift compatibility and visible/spoken
rendering were checked in source; Swift execution remains unverified.

## Verification still owed

- `gh issue view 634 --repo timharris707/modeldeck-private` could not connect to
  GitHub. Implementation used the full work order supplied in this task; the live
  issue and any later comments could not be checked.
- Run the Node localhost tests and the Swift tests outside this sandbox.
- Build and visually check the Mac app. No running app or live proxy account was changed.

## Tests blocked by localhost permissions

All 41 failures below have the same `listen EPERM` cause: 38 in
`api.test.mjs`, plus one each in `claude-statusline.test.mjs`,
`shared-scope.test.mjs`, and `usage-queue-consumer.test.mjs`.

- `test/api.test.mjs:195:1`: retired dashboard paths return JSON 404 responses
- `test/api.test.mjs:209:1`: health, scan, account, mapping, launch, and refresh APIs work together
- `test/api.test.mjs:465:1`: rejects missing mutation token, cross-origin mutations, and hostile Host headers
- `test/api.test.mjs:485:1`: rejects non-loopback peers on GET routes despite a spoofed local Host header
- `test/api.test.mjs:510:1`: Claude renewal endpoint returns decided outcomes, 404 unknown, and 409 concurrent
- `test/api.test.mjs:542:1`: Claude identity reset clears provenance and can re-seed; other providers and unauthenticated calls are rejected
- `test/api.test.mjs:578:1`: account responses never expose the internal Claude post-expiry guard
- `test/api.test.mjs:673:1`: activates Claude and Codex accounts without changing defaults when provider switching fails
- `test/api.test.mjs:736:1`: adopt-legacy-home resolves the first-run active-link-blocked dead end
- `test/api.test.mjs:767:1`: adopt-legacy-home mode fresh moves the legacy directory aside without importing it
- `test/api.test.mjs:792:1`: adopt-legacy-home aborts when the account is deleted mid-adoption
- `test/api.test.mjs:819:1`: adopt-legacy-home undoes the flip when the account is deleted after activation
- `test/api.test.mjs:850:1`: adopt-legacy-home aborts when the profile home is repointed mid-adoption
- `test/api.test.mjs:879:1`: adopt-legacy-home names the backup path when the rollback cannot run
- `test/api.test.mjs:908:1`: adopt-legacy-home tolerates shared-scope artifacts but refuses a recorded identity
- `test/api.test.mjs:943:1`: adopt-legacy-home restores the real home when the account vanishes after the flip
- `test/api.test.mjs:969:1`: adopt-legacy-home with no legacy directory activates instead of claiming managed
- `test/api.test.mjs:983:1`: adopt-legacy-home ENOENT branch unlinks the flip when the account vanishes
- `test/api.test.mjs:1001:1`: adoption resets the shared-scope memory-merge record for the account
- `test/api.test.mjs:1021:1`: a failed post-adoption reconcile restores the empty home and keeps retry alive
- `test/api.test.mjs:1051:1`: a failed post-adoption reconcile removes the items it copied into shared memory
- `test/api.test.mjs:1097:1`: the rollback keeps a shared-memory item another session replaced in the failure window
- `test/api.test.mjs:1147:1`: the rollback preserves a replacement landing between identity check and delete
- `test/api.test.mjs:1200:1`: adoption refuses a user-authored .claude.json that merely lacks oauthAccount
- `test/api.test.mjs:1222:1`: adoption refuses a destination .claude.json containing a bare empty object
- `test/api.test.mjs:1242:1`: the post-flip rollback restores the previous shell pin state
- `test/api.test.mjs:1269:1`: the no-legacy rollback clears the shell pin the scope call wrote
- `test/api.test.mjs:1289:1`: repeated blocked add attempts accumulate no damage and clean up account by account
- `test/api.test.mjs:1318:1`: Claude activation response warns about running unpinned sessions (issue #66)
- `test/api.test.mjs:1329:1`: tool probes compare versions, cache results, force refresh, and contain registry failures
- `test/api.test.mjs:1381:1`: state exposes per-account auth and update endpoint returns 409 for an unsupported install method
- `test/api.test.mjs:1411:1`: migrate-cswap succeeds when explainer installation fails
- `test/api.test.mjs:1431:1`: state surfaces per-account refresh errors and flips authState on expired stored OAuth
- `test/api.test.mjs:1455:1`: credential expiry used by refresh never reaches API payloads (issue #265)
- `test/api.test.mjs:1475:1`: settings API validates partial updates and drives worst-capacity thresholds
- `test/api.test.mjs:1582:1`: add-account flow: create, login spec, verify, and reference-only delete
- `test/api.test.mjs:1702:1`: historical-boundary CLI: activation-driven login spec and identity-mismatch refusal
- `test/api.test.mjs:1769:1`: codex profile homes outside the managed directory are rejected end to end
- `test/claude-statusline.test.mjs:505:1`: statusline install/uninstall endpoints are token-gated and round-trip
- `test/shared-scope.test.mjs:927:1`: shared-scope endpoints are mutation guarded and expose the exact state contract
- `test/usage-queue-consumer.test.mjs:212:1`: enabled daemon retries stub failures every five minutes and persists only allowlisted fields
