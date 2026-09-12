# Issue #644 implementation

Implemented in this worktree. No commit, push, PR, merge, or live account switch.
GitHub was unreachable; the supplied work order was the specification.

## Per-file changes

- `src/shared-transcripts.mjs`: reconciles relative links from other managed
  Claude `projects/<slug>/*.jsonl` files and Codex rollout files. Uses `lstat`,
  refuses directory symlinks and unsafe directory permissions, creates directories
  with mode 0700, and never copies transcript bytes or replaces existing entries.
  Cleanup requires a recorded target plus matching symlink inode, device, and
  creation time. Only a missing target within the same managed root permits
  cleanup. Synchronous validation and mutation close the demonstrated daemon
  interleaving races. Enumeration is capped at 20,000 entries per pass, including
  directories and unrelated files; logs contain counts and sanitized errors.
- `src/service.mjs`: calls reconciliation after successful activation/adoption,
  on creation/registration/import, and at startup for the active profiles.
  Activation's flip, scope, rollback, renewal, and Keychain implementations remain
  unchanged. Transcript work runs after activation's existing timeout and default
  update, so a linking failure cannot undo a successful switch. Reconciliation is
  serialized per profile. Daemon-owned account metadata records link ownership;
  registration cannot supply it, and public account responses strip it.
  `/api/state` adds optional `sharedTranscripts` (Claude only) and
  `sharedTranscriptsWarning` (any reconciled provider). Counts exclude broken/nonregular targets, cache for
  30 seconds, and are invalidated by reconciliation.
- `test/shared-transcripts.test.mjs`: 25 passing tests covering the required
  behavior, security regressions, creation/startup/adopt/fresh, cache behavior,
  restart ownership, Codex, and moving the profiles directory.
- `FINISH-644.md`: this report.

`src/transcript-ingest.mjs` and all Swift files are unchanged. The first end-to-end
test failed with ENOENT before implementation, then passed after adding the
activation reconciliation.

## Required tripwires

All pass in `test/shared-transcripts.test.mjs`:

1. `resume-survives-account-switch`
2. `own-conversation-never-overwritten`
3. `dangling-links-are-pruned-only-when-modeldeck-owned`
4. `usage-ingest-counts-each-transcript-once`
5. `activation-still-succeeds-when-linking-fails`

The two directory-replacement tests were also checked by loading temporary
in-memory mutations that reintroduced the former asynchronous write/recheck
windows. Both failed against those mutations and pass against the saved code.
No repository files were mutated for that check.

## Verification

- `node --test test/shared-transcripts.test.mjs`: **25 passed, 0 failed**.
- `node --check src/shared-transcripts.mjs` and `node --check src/service.mjs`: pass.
- Root `npm test`, with temporary subprocess guards to enforce no git:
  **1,204 tests; 1,140 passed; 62 failed; 2 skipped**. All 62 failures have an
  environment explanation: **41 `listen EPERM`**, **21 blocked git-dependent
  fixtures**. Full log: `/private/tmp/modeldeck-644-final-npm-test.log`.
  The final test-only improvement to race injection timing was then verified by
  the focused 25-test run and the two failing mutation checks.
- Earlier targeted activation/watchdog/explainer/transcript-ingest suites:
  **134 passed, 0 failed**. Their executable non-listening tests also passed in
  the final root suite.
- Full independent review used three GPT-6 Astra/high finders: correctness,
  security, and specification/compatibility. An independent skeptic reproduced
  the findings and verified all six code fixes: asynchronous directory swaps,
  forged ownership on registration, activation-timeout coupling, broken-link
  counts, misleading limit retry guidance, and repeated state scans. The final
  race-test timing gap was corrected and independently exercised by the mutation
  checks. No remaining code findings from that review.

## Codex decision

**Implemented.** The installed Codex CLI package is 0.152.1. A temporary,
credential-free app-server process with an isolated HOME and CODEX_HOME resolved
`thread/read` for placeholder UUID `11111111-1111-4111-8111-111111111111` through a
relative symlink under
`sessions/2026/08/09/rollout-2026-08-09T10-00-00-<uuid>.jsonl`. The returned thread
ID and path matched the fixture. No turn was started; its provider was configured
to an unused loopback endpoint. The process (PID 34187) exited and the fixture was
removed. This proves ID lookup reaches the rollout path in the installed binary.

The same reconciler supports `sessions/YYYY/MM/DD/rollout-*.jsonl` and flat
`archived_sessions/*.jsonl`. Older Codex registrations outside the managed root
retain their existing activation behavior and are excluded from sharing.

## Limits and integration follow-up

- Full unrestricted `npm test` remains for the integrating coordinator. No Swift
  code changed, so no Swift build or parse was needed.
- T3 Code's GUI and a live Claude/Codex resume were not exercised. Tests verify
  the exact Claude well-known file path and Codex's real read-only ID lookup;
  no provider quota, live credentials, or running sessions were used.
- This base has the existing `adoptClaudeLegacyHome` adopt/fresh flow; those hooks
  are covered. The separately proposed #645 implementation was unavailable.
  While a real legacy home blocks activation, creation defers transcript links
  so the existing adoption emptiness guard remains valid. It reconciles after
  successful adopt/fresh. Existing legacy-copy behavior was not changed here.
- A corpus exceeding the 20,000-entry cap can remain partially linked. The
  warning explicitly reports that limit and makes no promise that repeating the
  same bounded scan will finish. There is no new background drain or scheduler.
- Cleanup deliberately preserves links without durable ownership evidence,
  including links left by a crash before their ownership record was persisted.
- The filesystem checks close in-process asynchronous races. They are not an
  OS-level atomic containment guarantee against a separate process running as
  the same user; managed directories must remain trusted against that actor.
- No git command was issued directly. The first guarded full test run revealed
  that existing appcast shell helpers still invoke a read-only git build-number
  lookup, bypassing the Node guard. Subsequent runs also blocked shell git calls.
  There were no git writes, commits, pushes, or merges.

Model/harness: GPT-6 Astra (Codex); independent reviewers GPT-6 Astra/high.
