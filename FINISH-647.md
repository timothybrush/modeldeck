# Issue #647 — Codex profiles under ModelDeck data

Implemented in the supplied worktree. No git command, commit, push, merge,
release, or live migration was performed. GitHub was unreachable; the full
work order in the implementation brief was used. No live credential files,
Keychain entries, or running provider sessions were accessed or modified.

## Changes by file

| File | Change |
| --- | --- |
| `src/paths.mjs` | Default Codex root is `DATA_DIR/codex-profiles`; environment override retained; explicit legacy-root constant for production startup. |
| `src/codex-profiles-migration.mjs` | Migration, process refusal, private verified backup, rename and EXDEV fallback, tree verification, rollback, active link, marker, and sanitized warning result. |
| `src/db.mjs` | `repointCodexProfiles()` changes only Codex profile references in one transaction; any stale reference or SQL failure rolls back the batch. |
| `src/service.mjs` | Default derives from paths; migration runs once per service; intact deferred installs continue using the legacy root, including new account creation, so retry remains possible. |
| `src/server.mjs` | Migration completes before startup maintenance and request handling. Health exposes a warning string. An incomplete rollback prevents other API operations and background work; shutdown waits for startup. |
| `test/codex-profiles-migration.test.mjs` | 23 retained migration/path/security regression tests, all with dummy bytes and temporary directories. |
| `README.md` | Credential-backup and removal descriptions match the migration; data deletion includes managed Codex homes and backups, and may leave an activation link dangling. |
| `docs/ACCOUNT_ONBOARDING.md` | Updated paths; process check, backup format, retry, verification, and recovery procedure documented. |
| `docs/CLAUDE_IDENTITY.md` | Codex path references updated. Claude behavior unchanged. |
| `docs/config-linter.md` | Codex path and existing MD-L04 coverage documented. |
| `docs/RELEASE.md` | Known gaps explains optional data deletion and separate custom roots/empty legacy directory. |
| `scripts/uninstall-launch-agent.sh` | Output/comments explain retained Codex profiles and backups; script still removes only the LaunchAgent. |

No Claude path defaults, renewal implementation, shell-env writer, drafts,
or release notes changed. Existing MD-L04 already covers Codex, so no duplicate
linter rule was added.

## Migration decisions

- Process guard: `/usr/sbin/lsof -n -P -F p +D <legacy>`, covering open files
  and working directories, including explicitly pinned `CODEX_HOME` sessions.
  Only an unambiguous no-match exit allows movement. Errors/timeouts defer it.
  The check runs before backup work and again before profile moves/deletions.
- Backup: owner-only `DATA_DIR/.codex-profiles-backup-<id>/profiles/` plus
  `restore.json` containing paths, the original active-link target, and account
  reference mappings. Backups are inert recovery data, never active homes.
- Verification compares complete tree entries, sizes, modes, symlink text,
  and SHA-256 file hashes. Regular files use no-follow read handles. External
  symlinks are preserved without copying targets; links whose meaning would
  change, hard links, unsafe ownership/modes, and unsupported node types refuse.
- Same-volume moves use rename and retain file identity. EXDEV copies are
  verified before source removal. Partial removal and corrupted destinations
  recover from the verified destination or backup. Replaced destination roots
  are not followed during rollback; backup recovery still restores the original.
- The active link and marker are prepared before the final database transaction.
  This ordering means either operation can fail without publishing new account
  references. An incomplete rollback is detected again after a daemon restart.
- The empty legacy directory remains. Custom profile-root overrides are honored;
  migration never combines a populated destination with the legacy tree.

## Tripwires

All names below are in `test/codex-profiles-migration.test.mjs`.

Required:

1. `codex-profiles-migration-startup-moves-verifies-and-repoints`
2. `codex-profiles-migration-running-process-refuses-with-health-warning`
3. `codex-profiles-migration-second-rename-rolls-back-first-profile`
4. `codex-profiles-path-default-and-env-override`
5. `codex-profiles-migration-MD-L04-flags-legacy-active-link-after-migration`

Additional failure/recovery coverage:

- `codex-profiles-migration-EXDEV-verifies-bytes-and-preserves-modes`
- `codex-profiles-migration-EXDEV-corrupt-copy-never-removes-source`
- `codex-profiles-migration-database-failure-restores-link-files-and-all-references`
- `codex-profiles-migration-marker-failure-restores-active-link`
- `codex-profiles-migration-active-link-failure-keeps-store-untouched`
- `codex-profiles-migration-preserves-symlinks-without-following-external-targets`
- `codex-profiles-migration-populated-destination-never-merges-or-overwrites`
- `codex-profiles-migration-lsof-errors-and-ambiguous-results-fail-closed`
- `codex-profiles-migration-corrupt-renamed-tree-recovers-from-verified-backup`
- `codex-profiles-migration-incomplete-rollback-stays-blocked-on-restart`
- `codex-profiles-migration-deferred-accounts-remain-usable-and-retryable`
- `codex-profiles-migration-destination-symlink-swap-never-writes-outside-root`
- `codex-profiles-migration-custom-root-and-all-registered-accounts`
- `codex-profiles-migration-late-destination-swap-restores-from-backup-without-following-link`
- `codex-profiles-migration-EXDEV-partial-source-removal-rolls-back`
- `codex-profiles-migration-empty-destination-and-completed-start-are-idempotent`
- `codex-profiles-migration-refuses-symlinks-that-would-change-meaning`
- `codex-profiles-migration-marker-collision-preserves-unowned-file`

## Verification results

| Check | Result |
| --- | --- |
| `node --test test/codex-profiles-migration.test.mjs` | **23 passed**, 0 failed. |
| Migration plus config-linter engine/snapshot, service-phase2, and db-service tests | **179 passed**, 0 failed. |
| `npm test` from worktree root, with Git subprocesses denied | **1,195 tests: 1,134 passed, 59 failed, 2 skipped; exit 1.** All failures classified: 41 `listen EPERM`, 18 blocked Git fixture calls. No other failure remained. |
| `bash -n scripts/uninstall-launch-agent.sh` | Passed. |
| `npm run test:cliproxyapi-pin` | Fixture contracts: 5 passed, 1 live test skipped. Overall exit 1 because the pinned binary is absent from this worktree. |
| `swift test --scratch-path /private/tmp/modeldeck-647-swift-build` | Blocked before compilation: sandbox cannot write the Swift/Clang module cache. |
| Default lsof helper against a temporary dummy open file | Process inspection unavailable in this sandbox; helper refused as designed. No live profile was probed. |

The Git guard lives only under `/private/tmp/modeldeck-647-no-git`; it blocks
direct Git subprocess creation and supplies a refusing shell executable. It
does not change repository configuration or test sources. An initial guard
interfered with Node's promisified execFile return shape and caused one linter
fixture failure; correcting the temporary guard removed that failure. The
numbers above are from the final run.

Final local logs: `/private/tmp/modeldeck-647-npm-test-final.log`,
`/private/tmp/modeldeck-647-focused-final.log`,
`/private/tmp/modeldeck-647-pin.log`, and `/private/tmp/modeldeck-647-swift.log`.

## Independent review

Three isolated finders reviewed correctness, security/compatibility, and the
work order. An independent skeptic reproduced four blockers: backup recovery
after destination corruption, restart losing the incomplete-recovery block,
busy deferral breaking existing accounts/obstructing retry, and destination
replacement redirecting movement. All four were fixed and independently
rechecked with executable dummy-fixture proofs (evidence level: **Run**).

The follow-up found one related late destination-replacement case. It was
reproduced, fixed, given a retained regression test, and independently verified:
original bytes/link restored, references unchanged, external directory untouched,
and blocking retained. No confirmed review blocker remains.

The skeptic dismissed the claimed requirement to migrate into arbitrary custom
roots as unproven by the exact ruling; custom-root migration is nevertheless
supported consistently with the retained environment override. No finding was
waived. Reviewers used the inherited session model at high effort in Codex;
no provider CLI or paid API probe was used.

## Limits / work still required outside this sandbox

- The full suite is **not green here**. The coordinator must rerun it where
  socket listening and its Git-based test fixtures are allowed.
- Pinned-binary compatibility and Swift tests need the normal host setup.
- Startup and health were exercised through the real startup callback and HTTP
  request handler without opening a socket. A real daemon migration was not run.
- EXDEV and process activity were injected; actual cross-volume behavior and
  successful macOS process enumeration remain host checks using dummy profiles.
- Recovery backups contain the original sign-in state; using a profile after
  successful migration can make a later backup restore require sign-in again.
- All owned test processes finished. No temporary server, provider process,
  worker, or monitor remains running. All requested changes are left in this
  worktree for the coordinator's review and integration.

Continuity: task `01a09289-7cf1-7560-ba61-bed5f9cfc938` attempted its authorized
checkpoint under `~/.codex-shared/checkpoints`; the filesystem sandbox denied
that write. This file retains the final state. All four review workers are
completed. No pending user question or approval; the next action in this task
is only the final report. Git and live-migration prohibitions still apply.
