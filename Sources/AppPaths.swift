import Foundation

/// Lokasi folder kerja pet (`~/.pet`).
enum AppPaths {
    static var directory: String { NSHomeDirectory() + "/.pet" }

    static func ensureDirectory() {
        try? FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true
        )
    }
}
