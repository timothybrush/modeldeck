# FINISH-645

Implemented the existing-profile choice for Claude and Codex account creation. An unregistered base-name folder now returns HTTP 409 `profile-exists` before account creation or file-content reads. The app offers **Adopt existing**, **Start fresh** (the default), and Cancel. Fresh creates the next numbered folder and shows where the original remains. Adopt retains the folder and history, requires a real directory owned by the current user, rejects top-level symbolic links, and sets permissions to 0700.

Changes remain in this worktree. No git commands, commits, pushes, PRs, merges, deployments, provider calls, or live Keychain operations were performed. The wrapper owns commit/push/PR. GitHub was unreachable; the complete supplied work order was used.

## Per-file changes

- `src/adapters/provider-profile.mjs`: export the existing name-normalization function for the pre-create check; preserve provider-specific validation errors and exclusive suffix allocation.
- `src/service.mjs`: inspect only the exact derived base name; return metadata-only collision summaries; handle explicit adopt/fresh; compare filesystem identities for registered folders, including capitalization aliases; prevent overlapping creation/adoption for each provider through failure cleanup; preserve adopted homes on failure; return the fresh-profile notice.
- `src/server.mjs`: expose the coded 409 with its profile summary and include `profileNote` beside the created account.
- `macos/ModelDeckMac/Sources/ModelDeckMacCore/DaemonModels.swift`: add `ExistingProfileSummary`, optional request `existingProfile`, and a creation-only `profileNote` that is excluded from account serialization.
- `macos/ModelDeckMac/Sources/ModelDeckMacCore/DaemonClient.swift`: retain optional profile summaries in coded errors, encode the choice, and decode the creation notice. Existing errors without summaries keep their previous behavior.
- `macos/ModelDeckMac/Sources/ModelDeckMacCore/AddAccountModel.swift`: add `.adoptExistingProfile`, retain and retry the original request, and continue the existing sign-in/activation flow. If sign-in setup fails after creation, retry the same account rather than creating another; Cancel then uses the existing keep/remove flow.
- `macos/ModelDeckMac/Sources/ModelDeckMac/AddAccountSheet.swift`: render the prompt, transcript count and local date; make Start fresh the default; show the fresh notice and sign-in retry when needed.
- `macos/ModelDeckMac/Sources/ModelDeckMacCore/DeckPopoverModel.swift`: ignore the new optional error payload in two existing pattern matches. No activation behavior changes.
- `macos/ModelDeckMac/Sources/ModelDeckMacCore/SharedScopeModel.swift`: ignore the new optional error payload in its existing conflict match. No shared-settings behavior changes.
- `test/api.test.mjs`: add ten API regression tests, using the real request handler without opening a listener.
- `test/service-phase2.test.mjs`: update the old suffix-only expectation to require an explicit fresh choice and notice.
- `macos/ModelDeckMac/Tests/ModelDeckMacCoreTests/AddAccountModelTests.swift`: add prompt, choice, wire-format, and retry tests; update the existing post-create failure expectation to the recoverable sign-in step.

## Required regression checks

`test/api.test.mjs` runs the following for both Claude and Codex:

- `profile-exists: <provider> asks before reattaching an unregistered base folder`: 409 summary; no opened files or partial account; explicit fresh selects `-2` and includes the original path; adoption retains the old transcript and user instructions; registered base takes the normal suffix path; explicit adoption of a registered folder is refused.
- `profile-exists: <provider> refuses unsafe adoption and preserves an orphan on failure`: root and top-level symlink refusal, no traversal into a linked projects folder, invalid choice refusal, and preservation after save failure.
- `profile-exists: <provider> checks only the exact base name and serializes competing adoptions`: ignores numbered orphans when the base is free; only one simultaneous adopter succeeds.
- `profile-exists: <provider> recognizes registered folders with different capitalization`: rejects adoption of the same directory through a case alias; ordinary second-account creation still uses a suffix. Runs on this case-insensitive Mac; skips on case-sensitive filesystems.

Two additional API tests cover `profile-exists: a base folder still being created cannot be adopted before failure cleanup` and `profile-exists: a numbered folder still being created cannot be adopted before failure cleanup`.

The service check is `starting fresh explicitly leaves a leftover profile directory and uses a suffixed home`.

Swift checks in `AddAccountModelTests`:

- `profileExistsOffersAdoptionBeforeLogin`
- `existingProfileChoiceRepostsAndContinuesNormalLogin(startFresh:)`, both fresh/adopt choices, including activation and restoration
- `addAccountClientDecodesProfileExistsSummary`
- `addAccountClientEncodesExistingProfileChoiceAndReadsNote(choice:)`, both serialized values
- `existingProfilePostCreateFailureCanRetryWithoutAnotherAccount(activationFails:)`, both login-command and activation failures

## Verification

- Focused Node checks: **11 passed, 0 failed**. Command: `node --test --test-name-pattern='profile-exists:|starting fresh explicitly' test/api.test.mjs test/service-phase2.test.mjs`.
- `npm test`: **1,182 tests; 1,139 passed, 41 failed, 2 skipped**. Every failure is `listen EPERM: operation not permitted 127.0.0.1`; names listed below. The new API checks all pass without listeners.
- `swift test --filter AddAccount --disable-automatic-resolution` from `macos/ModelDeckMac`: blocked by the sandbox's unwritable default compiler cache. Moving caches to `/private/tmp` reached another sandbox restriction: `sandbox-exec: sandbox_apply: Operation not permitted`.
- Alternative execution used the actual current core sources, an existing generated resource accessor, the current test files, and Swift Testing's entry point. `swiftc` compiled the core library/module and a standalone test executable. **36 AddAccountModelTests passed, 0 failed**, including both choices and both failure/retry cases. No provider sign-in or live daemon was involved.
- `swiftc -parse`: passed for all seven changed Swift source/test files. The actual `AddAccountSheet` also passed `swiftc -typecheck` against the freshly built core module and the repository's color helpers.
- `npm run test:cliproxyapi-pin`: five contract tests passed, one live test skipped; the subsequent verification cannot run because this worktree has no `dist/cliproxyapi/cliproxyapi` binary. No production proxy was queried.
- Native sheet rendering was attempted with a temporary fixture-only executable. Both captures were blank, so visual appearance, installed-app clicks, and human acceptance remain unverified. The temporary executable exited; no owned server or app process remains.

Test-first evidence: both original collision tests first failed with 201 instead of 409. The capitalization and overlapping-add tests also failed before their fixes. SwiftPM could not provide an initial red run; final Swift behavior was executed using the standalone test binary.

## Independent review

Three isolated finders reviewed correctness, security/compatibility, and the spec/UI. An independent skeptic confirmed three defects, all fixed with retained regression tests:

1. Registered directory capitalization aliases could bypass the guard. The fix compares device and inode identity.
2. A new folder could be adopted while its creator was still running, and then deleted by that creator's failure cleanup. The fix reserves creation/adoption for each provider until completion, including numbered allocations. The skeptic reproduced the original deletion with a real shared-settings filesystem failure.
3. A sign-in request failure after creation could leave both choice buttons inert. The fix moves to recoverable sign-in and reuses the created account.

The skeptic independently reran the final **11 Node and 36 Swift checks** and reported no confirmed issue remaining. No findings were waived. Source inspection confirmed that activation, renewal, shell-environment writing, and Keychain behavior remain outside this change.

## Remaining limits and evidence

GitHub/PR checks, ordinary SwiftPM execution, live proxy compatibility, and native visual verification remain for the host-side verification step. Useful local evidence:

- `/private/tmp/modeldeck-645-focused.log`
- `/private/tmp/modeldeck-645-npm-final.log`
- `/private/tmp/modeldeck-645-swift-tests.log`
- `/private/tmp/modeldeck-645-pin.log`
- `/private/tmp/modeldeck-645-swift-build/` contains the compiled core, test executable, compile/typecheck logs, and test build script.
- `/private/tmp/modeldeck-645-final.patch` and `/private/tmp/modeldeck-645-before/` contain the reviewed comparison generated without git.

The requested shared checkpoint could not be written: its parent `/Users/timharris/.codex-shared/checkpoints/8772c85c84530f6f3662` is outside the writable sandbox and directory creation returned `Operation not permitted`. This report preserves the authorized scope, completed work, outstanding verification, and ownership. All four reviewers completed; there are no pending user questions or running owned workers/processes. The existing Claude handoff was left unchanged.

## Sandbox listener failures

All 41 failures below are `listen EPERM` before the listener-dependent behavior can run.

- `test/api.test.mjs:382:1` retired dashboard paths return JSON 404 responses
- `test/api.test.mjs:396:1` health, scan, account, mapping, launch, and refresh APIs work together
- `test/api.test.mjs:652:1` rejects missing mutation token, cross-origin mutations, and hostile Host headers
- `test/api.test.mjs:672:1` rejects non-loopback peers on GET routes despite a spoofed local Host header
- `test/api.test.mjs:697:1` Claude renewal endpoint returns decided outcomes, 404 unknown, and 409 concurrent
- `test/api.test.mjs:729:1` Claude identity reset clears provenance and can re-seed; other providers and unauthenticated calls are rejected
- `test/api.test.mjs:765:1` account responses never expose the internal Claude post-expiry guard
- `test/api.test.mjs:860:1` activates Claude and Codex accounts without changing defaults when provider switching fails
- `test/api.test.mjs:923:1` adopt-legacy-home resolves the first-run active-link-blocked dead end
- `test/api.test.mjs:954:1` adopt-legacy-home mode fresh moves the legacy directory aside without importing it
- `test/api.test.mjs:979:1` adopt-legacy-home aborts when the account is deleted mid-adoption
- `test/api.test.mjs:1006:1` adopt-legacy-home undoes the flip when the account is deleted after activation
- `test/api.test.mjs:1037:1` adopt-legacy-home aborts when the profile home is repointed mid-adoption
- `test/api.test.mjs:1066:1` adopt-legacy-home names the backup path when the rollback cannot run
- `test/api.test.mjs:1095:1` adopt-legacy-home tolerates shared-scope artifacts but refuses a recorded identity
- `test/api.test.mjs:1130:1` adopt-legacy-home restores the real home when the account vanishes after the flip
- `test/api.test.mjs:1156:1` adopt-legacy-home with no legacy directory activates instead of claiming managed
- `test/api.test.mjs:1170:1` adopt-legacy-home ENOENT branch unlinks the flip when the account vanishes
- `test/api.test.mjs:1188:1` adoption resets the shared-scope memory-merge record for the account
- `test/api.test.mjs:1208:1` a failed post-adoption reconcile restores the empty home and keeps retry alive
- `test/api.test.mjs:1238:1` a failed post-adoption reconcile removes the items it copied into shared memory
- `test/api.test.mjs:1284:1` the rollback keeps a shared-memory item another session replaced in the failure window
- `test/api.test.mjs:1334:1` the rollback preserves a replacement landing between identity check and delete
- `test/api.test.mjs:1387:1` adoption refuses a user-authored .claude.json that merely lacks oauthAccount
- `test/api.test.mjs:1409:1` adoption refuses a destination .claude.json containing a bare empty object
- `test/api.test.mjs:1429:1` the post-flip rollback restores the previous shell pin state
- `test/api.test.mjs:1456:1` the no-legacy rollback clears the shell pin the scope call wrote
- `test/api.test.mjs:1476:1` repeated blocked add attempts accumulate no damage and clean up account by account
- `test/api.test.mjs:1505:1` Claude activation response warns about running unpinned sessions (issue #66)
- `test/api.test.mjs:1516:1` tool probes compare versions, cache results, force refresh, and contain registry failures
- `test/api.test.mjs:1568:1` state exposes per-account auth and update endpoint returns 409 for an unsupported install method
- `test/api.test.mjs:1598:1` migrate-cswap succeeds when explainer installation fails
- `test/api.test.mjs:1618:1` state surfaces per-account refresh errors and flips authState on expired stored OAuth
- `test/api.test.mjs:1642:1` credential expiry used by refresh never reaches API payloads (issue #265)
- `test/api.test.mjs:1662:1` settings API validates partial updates and drives worst-capacity thresholds
- `test/api.test.mjs:1769:1` add-account flow: create, login spec, verify, and reference-only delete
- `test/api.test.mjs:1889:1` historical-boundary CLI: activation-driven login spec and identity-mismatch refusal
- `test/api.test.mjs:1956:1` codex profile homes outside the managed directory are rejected end to end
- `test/claude-statusline.test.mjs:505:1` statusline install/uninstall endpoints are token-gated and round-trip
- `test/shared-scope.test.mjs:927:1` shared-scope endpoints are mutation guarded and expose the exact state contract
- `test/usage-queue-consumer.test.mjs:212:1` enabled daemon retries stub failures every five minutes and persists only allowlisted fields
