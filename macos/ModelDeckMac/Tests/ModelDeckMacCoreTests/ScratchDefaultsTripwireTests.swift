import Foundation
import Testing

// TRIPWIRE scratch-defaults (2026-09-02). Tim's machine had 59,899
// `<prefix>-<UUID>.plist` files in ~/Library/Preferences, one per test
// fixture per `swift test` run since the suites began: each fixture built
// its own `UserDefaults(suiteName:)`, and `removePersistentDomain` empties
// the plist without deleting it. ScratchDefaults keeps every test suite
// under a per-process temp directory instead. These fail if a fixture
// bypasses it, or if a scratch suite ever lands in Preferences again.

@Suite("Scratch defaults never reach ~/Library/Preferences (tripwire)")
struct ScratchDefaultsTripwireTests {
    static func containsDirectSuiteConstruction(_ source: String) -> Bool {
        source.range(of: #"\bUserDefaults\s*(?:\.init\s*)?\(\s*suiteName\s*:"#, options: .regularExpression) != nil
    }

    @Test func directSuiteMatcherFlagsNormalSpacedAndMultilineCalls() {
        #expect(Self.containsDirectSuiteConstruction(#"UserDefaults(suiteName: "fixture")"#))
        #expect(Self.containsDirectSuiteConstruction(#"UserDefaults ( suiteName : "fixture")"#))
        #expect(Self.containsDirectSuiteConstruction(#"UserDefaults.init(suiteName: "fixture")"#))
        #expect(Self.containsDirectSuiteConstruction("""
            UserDefaults
            (
                suiteName
                : "fixture")
            """))
    }

    @Test func everyFixtureGoesThroughScratchDefaults() throws {
        let this = URL(fileURLWithPath: #filePath)
        let tests = this.deletingLastPathComponent()
        let offenders = try FileManager.default.contentsOfDirectory(atPath: tests.path)
            .filter { $0.hasSuffix(".swift") && $0 != "ScratchDefaults.swift" && $0 != this.lastPathComponent }
            .filter {
                Self.containsDirectSuiteConstruction(
                    try String(contentsOf: tests.appendingPathComponent($0), encoding: .utf8)
                )
            }
        #expect(
            offenders.isEmpty,
            "TRIPWIRE scratch-defaults: \(offenders.sorted()) build their own UserDefaults suite; use ScratchDefaults.make(_:) so the plist lands in the per-process temp directory, not ~/Library/Preferences"
        )
    }

    @Test func aScratchSuiteLivesInTheTempDirectoryOnly() throws {
        let defaults = ScratchDefaults.make("tripwire")
        defaults.set(true, forKey: "written")
        defaults.synchronize()

        let temp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).standardizedFileURL.path
        #expect(ScratchDefaults.directory.standardizedFileURL.path.hasPrefix(temp))
        let plists = try FileManager.default.contentsOfDirectory(atPath: ScratchDefaults.directory.path)
            .filter { $0.hasPrefix("tripwire-") && $0.hasSuffix(".plist") }
        #expect(!plists.isEmpty, "the scratch suite wrote nothing under \(ScratchDefaults.directory.path)")

        let preferences = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences")
        for plist in plists {
            #expect(!FileManager.default.fileExists(atPath: preferences.appendingPathComponent(plist).path))
        }
    }
}
