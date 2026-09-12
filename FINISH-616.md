# PR #616 fix round

Updated `ScratchDefaultsTripwireTests.swift` to detect direct suite construction
with `\bUserDefaults\s*\(\s*suiteName\s*:`. The small static helper
`containsDirectSuiteConstruction(_:)` is shared by the fixture scan and its
regression test, so spaces and newlines between the tokens cannot bypass the check.

Test names:

- `directSuiteMatcherFlagsNormalSpacedAndMultilineCalls`: new regression test;
  expects normal, spaced, and multiline sample strings to be flagged.
- `everyFixtureGoesThroughScratchDefaults`: now uses the shared matcher.
- `aScratchSuiteLivesInTheTempDirectoryOnly`: existing filesystem check, unchanged.

Validation: attempted `swift test --filter ScratchDefaults` from
`macos/ModelDeckMac`. It exited 1 before tests ran because the sandbox denied
writing the compiler module cache. Retried with compiler caches under
`/private/tmp`; it exited 1 before tests ran with
`sandbox-exec: sandbox_apply: Operation not permitted`. The Swift tests still
need to run outside this sandbox; no passing test result is claimed.

No git commands were run. Changes are left in the worktree for the wrapper.
