import Foundation

/// Test-only UserDefaults. Every suite lives under one per-process temp
/// directory (an absolute path is a valid suite name), never in
/// ~/Library/Preferences. Until 2026-09-02 each fixture built
/// `UserDefaults(suiteName: "<prefix>-<UUID>")` there, and because
/// `removePersistentDomain` empties a suite's plist without deleting it,
/// every `swift test` run left one file per fixture behind: 59,899 on Tim's
/// machine. The directory is removed at process exit; whatever a crashed
/// run leaves sits in $TMPDIR, which macOS purges, and never shows up in
/// `defaults domains`.
enum ScratchDefaults {
    /// Per-process directory holding every scratch suite's plist.
    static let directory: URL = {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("modeldeck-tests-\(getpid())", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        atexit { try? FileManager.default.removeItem(at: ScratchDefaults.directory) }
        return url
    }()

    /// A fresh, empty suite; `name` only makes the plist recognizable.
    static func make(_ name: String) -> UserDefaults {
        UserDefaults(suiteName: directory.appendingPathComponent("\(name)-\(UUID().uuidString)").path)!
    }
}
