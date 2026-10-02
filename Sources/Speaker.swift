import AppKit

/// Mengubah balasan teks menjadi suara memakai `say` bawaan macOS.
final class Speaker {
    var enabled = true
    /// Damayanti is the Indonesian female voice built into macOS.
    var voice = "Damayanti"

    private var process: Process?

    var isSpeaking: Bool {
        process?.isRunning ?? false
    }

    func speak(_ text: String) {
        guard enabled else { return }
        let clean = Speaker.sanitize(text)
        guard !clean.isEmpty else { return }
        stop()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-v", voice, "-r", "240", clean]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return
        }
        self.process = process
    }

    func stop() {
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
    }

    /// Buang markdown dan blok kode supaya yang dibaca terdengar natural.
    static func sanitize(_ text: String) -> String {
        var s = text

        while let start = s.range(of: "```") {
            if let end = s.range(of: "```", range: start.upperBound..<s.endIndex) {
                s.removeSubrange(start.lowerBound..<end.upperBound)
            } else {
                s.removeSubrange(start.lowerBound..<s.endIndex)
            }
        }

        if let regex = try? NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\([^)]+\\)") {
            let range = NSRange(s.startIndex..<s.endIndex, in: s)
            s = regex.stringByReplacingMatches(in: s, range: range, withTemplate: "$1")
        }

        for junk in ["`", "*", "#", ">", "|", "~"] {
            s = s.replacingOccurrences(of: junk, with: "")
        }
        s = s.replacingOccurrences(of: "_", with: " ")
        s = s.replacingOccurrences(of: "\n", with: ". ")

        while s.contains("  ") {
            s = s.replacingOccurrences(of: "  ", with: " ")
        }

        let limit = 700
        if s.count > limit {
            s = String(s.prefix(limit)) + "..."
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
