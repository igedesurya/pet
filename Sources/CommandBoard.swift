import Foundation

/// Pemantau `~/.pet/poses.command`.
///
/// Setiap baris berisi nama gestur (`duduk`, `ketawa`, `peluk`, ...). File
/// dibaca lalu dikosongkan, jadi gestur yang sama bisa diminta berkali-kali.
/// Ini jalur yang dipakai perintah terminal dan MCP.
final class CommandBoard {
    static let path = AppPaths.directory + "/poses.command"
    static let requestsPath = AppPaths.directory + "/command-requests"
    static let resultsPath = AppPaths.directory + "/command-results"

    var onPose: ((PetPose) -> Void)?
    var onClip: ((String) -> Void)?
    var onUnknown: ((String) -> Void)?
    var onRequest: (([String: Any]) -> [String: Any])?

    private var timer: Timer?
    private var lastSeen = ""

    func start() {
        AppPaths.ensureDirectory()
        try? FileManager.default.createDirectory(atPath: CommandBoard.requestsPath, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(atPath: CommandBoard.resultsPath, withIntermediateDirectories: true)
        seedFile()
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Membuat file kosong berisi petunjuk kalau belum ada.
    private func seedFile() {
        guard !FileManager.default.fileExists(atPath: CommandBoard.path) else { return }
        let body = """
        # Tulis nama gestur di sini untuk memicu si pet.
        # Contoh: duduk
        #
        # Gestur yang tersedia:
        # \(PetPose.commandNames.joined(separator: ", "))
        #
        # Bisa juga dari terminal:
        #   echo duduk >> ~/.pet/poses.command

        """
        try? body.write(toFile: CommandBoard.path, atomically: true, encoding: .utf8)
    }

    private func poll() {
        pollRequests()
        guard let text = try? String(contentsOfFile: CommandBoard.path, encoding: .utf8) else {
            return
        }
        // hindari memproses ulang isi yang sama
        guard text != lastSeen else { return }
        lastSeen = text

        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        guard !lines.isEmpty else { return }

        // kosongkan file supaya gestur yang sama bisa diminta lagi nanti
        try? "".write(toFile: CommandBoard.path, atomically: true, encoding: .utf8)
        lastSeen = ""

        for line in lines {
            if let pose = PetPose.named(line) {
                onPose?(pose)
            } else if onClip != nil {
                onClip?(line)
            } else {
                onUnknown?(line)
            }
        }
    }

    /// One atomic file per MCP request prevents concurrent callers losing commands.
    private func pollRequests() {
        let root = URL(fileURLWithPath: CommandBoard.requestsPath)
        let files = ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        for file in files {
            guard UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil,
                  let data = try? Data(contentsOf: file),
                  let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                try? FileManager.default.removeItem(at: file)
                continue
            }
            let response = onRequest?(request) ?? ["ok": false, "error": "Pet belum siap menerima perintah."]
            if let encoded = try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys]) {
                let result = URL(fileURLWithPath: CommandBoard.resultsPath).appendingPathComponent(file.lastPathComponent)
                try? encoded.write(to: result, options: .atomic)
            }
            try? FileManager.default.removeItem(at: file)
        }
    }
}
