import Foundation

/// Jembatan ke OpenCode CLI. Setiap pesan dijalankan sebagai
/// `opencode run --format json --session <id> "<pesan>"`, jadi si pet
/// memakai sesi yang sama terus-menerus dan punya ingatan jangka panjang.
final class Brain {
    /// ID sesi tetap. Ganti kalau mau memori baru.
    static let sessionID = "ses_petasisten"

    /// Nama sesi Hermes (thread bernama, dibuat otomatis kalau belum ada).
    /// Dipakai kalau `hermesSessionID` kosong.
    static let hermesSessionName = "petasisten"

    /// Batas tunggu jawaban Hermes. Sesi besar butuh reload konteks tiap
    /// pesan sehingga bisa lambat; watchdog ini menjaga UI tidak hang.
    static let hermesTimeout: TimeInterval = 180

    /// Backend agent yang bisa dipakai pet.
    enum Agent: String, CaseIterable {
        case opencode
        case hermes

        var displayName: String {
            switch self {
            case .opencode: return "OpenCode"
            case .hermes: return "Hermes"
            }
        }

        static func from(_ raw: String) -> Agent {
            let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if lower == "hermes" { return .hermes }
            return .opencode
        }
    }

    /// Agent default. Dipertahankan OpenCode supaya perilaku lama tidak berubah.
    static let defaultAgent = Agent.opencode

    /// Model default. Bisa diubah lewat ~/.pet/config.json atau env PET_MODEL.
    static let defaultModel = "9router/model-loop-gpt-oss"

    /// Daftar model yang muncul di pemilih panel chat.
    static let defaultModels = [
        "9router/model-loop-gpt-oss",
        "9router/model-loop-gemma4",
        "opencode/gpt-6.1-sol",
    ]

    static let configPath = NSHomeDirectory() + "/.pet/config.json"

    struct Config {
        var model: String?
        var models: [String]
        var agent: Agent
        var hermesSessionID: String
    }

    var onText: ((String) -> Void)?
    var onDone: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onBusyChange: ((Bool) -> Void)?

    private(set) var isBusy = false

    private var process: Process?
    private var lineBuffer = Data()
    private var reply = ""
    private var queue: [String] = []
    private let opencode: String
    private let isEnvLauncher: Bool
    private let hermesPath: String?
    private let work = DispatchQueue(label: "pet.brain")

    /// Tag dari ~/.pet/AGENTS.md: [POSE:], [MESH:], dan [EXPR:].
    private static let cueRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "\\[(POSE|MESH|EXPR):\\s*([^\\]]*)\\]",
        options: .caseInsensitive
    )

    /// Model yang dipakai. `nil` berarti ikut default OpenCode.
    private(set) var model: String?

    /// Model yang bisa dipilih di panel chat.
    private(set) var availableModels: [String]

    /// Agent yang sedang dipakai. Bisa diganti saat pet jalan.
    private(set) var agent: Agent

    /// ID sesi Hermes yang dipakai (`--resume`). Kosong berarti memakai
    /// thread bernama `hermesSessionName`.
    private(set) var hermesSessionID: String

    /// Penanda watchdog timeout Hermes (sesi besar bisa lambat).
    private var hermesTimedOut = false

    /// Jumlah tag pose yang sudah diputar dari balasan yang sedang mengalir.
    private var emittedPoseCount = 0

    private let ioLock = NSLock()

    var modelName: String { model ?? "(default OpenCode)" }

    var agentName: String { agent.displayName }

    init() {
        let found = Brain.findOpencode()
        opencode = found
        isEnvLauncher = (found == "/usr/bin/env")
        hermesPath = Brain.findHermes()
        let config = Brain.loadConfig()
        model = config.model
        availableModels = config.models
        agent = config.agent
        hermesSessionID = config.hermesSessionID
        Brain.ensureAgentFile()
    }

    /// Folder kerja pet. Isi ~/.pet/AGENTS.md milik pengguna dan tidak ditulis ulang.
    static func ensureAgentFile() {
        AppPaths.ensureDirectory()
    }

    /// Membuat file config contoh kalau belum ada, supaya mudah ditemukan.
    static func ensureConfigFile() {
        guard !FileManager.default.fileExists(atPath: configPath) else { return }
        saveConfig(Config(model: defaultModel, models: defaultModels, agent: defaultAgent, hermesSessionID: ""))
    }

    static func loadConfig() -> Config {
        ensureConfigFile()

        guard
            let data = FileManager.default.contents(atPath: configPath),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return Config(model: defaultModel, models: defaultModels, agent: defaultAgent, hermesSessionID: "")
        }

        var models = (object["models"] as? [String])?
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? defaultModels
        if models.isEmpty { models = defaultModels }

        let rawModel = object["model"] as? String ?? defaultModel
        var model: String? = rawModel.isEmpty ? nil : rawModel

        // env PET_MODEL menang atas isi file
        if let fromEnv = ProcessInfo.processInfo.environment["PET_MODEL"], !fromEnv.isEmpty {
            model = fromEnv
        }

        if let model, !models.contains(model) {
            models.insert(model, at: 0)
        }

        let agent = Agent.from(object["agent"] as? String ?? defaultAgent.rawValue)
        let hermesSessionID = (object["hermesSessionID"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return Config(model: model, models: models, agent: agent, hermesSessionID: hermesSessionID)
    }

    static func saveConfig(_ config: Config) {
        let directory = (configPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true
        )
        let payload: [String: Any] = [
            "model": config.model ?? "",
            "models": config.models,
            "agent": config.agent.rawValue,
            "hermesSessionID": config.hermesSessionID,
        ]
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]
            ),
            let text = String(data: data, encoding: .utf8)
        else { return }
        // JSONSerialization meng-escape "/" menjadi "\/"; rapikan agar enak dibaca.
        let pretty = text.replacingOccurrences(of: "\\/", with: "/")
        try? pretty.write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    /// Mengganti model dan menyimpannya supaya bertahan setelah restart.
    func setModel(_ newModel: String) {
        let value = newModel.trimmingCharacters(in: .whitespacesAndNewlines)
        model = value.isEmpty ? nil : value

        var models = availableModels
        if !value.isEmpty, !models.contains(value) {
            models.insert(value, at: 0)
        }
        availableModels = models
        Brain.saveConfig(Config(model: model, models: models, agent: agent, hermesSessionID: hermesSessionID))
    }

    /// Mengganti agent dan menyimpannya. Aman dipanggil saat pet jalan —
    /// request berikutnya memakai agent baru. Antrean lama ikut dibatalkan
    /// karena format sesi tiap agent berbeda.
    func setAgent(_ newAgent: Agent) {
        cancel()
        agent = newAgent
        Brain.saveConfig(Config(model: model, models: availableModels, agent: newAgent, hermesSessionID: hermesSessionID))
    }

    /// Mengganti sesi Hermes yang dipakai pet. ID kosong berarti kembali ke
    /// thread bernama `hermesSessionName`. Aman dipanggil saat pet jalan.
    func setHermesSession(_ sessionID: String) {
        cancel()
        hermesSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        Brain.saveConfig(Config(model: model, models: availableModels, agent: agent, hermesSessionID: hermesSessionID))
    }

    /// Label sesi Hermes yang sedang dipakai (ID atau nama thread).
    var hermesSessionLabel: String {
        hermesSessionID.isEmpty ? Brain.hermesSessionName : hermesSessionID
    }


    private static func findOpencode() -> String {
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/.opencode/bin/opencode",
            "/opt/homebrew/bin/opencode",
            "/usr/local/bin/opencode",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return "/usr/bin/env"
    }

    private static func findHermes() -> String? {
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/.local/bin/hermes",
            "/opt/homebrew/bin/hermes",
            "/usr/local/bin/hermes",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    /// Nama model tanpa prefix provider (mis. `9router/model-loop-gemma4`
    /// menjadi `model-loop-gemma4`), karena Hermes memakai skema provider
    /// sendiri dan menolak prefix asing dengan HTTP 404.
    private var bareModelName: String? {
        guard let model, !model.isEmpty else { return nil }
        if let slash = model.lastIndex(of: "/") {
            let bare = String(model[model.index(after: slash)...])
            return bare.isEmpty ? nil : bare
        }
        return model
    }

    func ask(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if isBusy {
            queue.append(trimmed)
            return
        }
        run(trimmed)
    }

    func cancel() {
        queue.removeAll()
        hermesTimedOut = false
        process?.terminate()
        process = nil
        setBusy(false)
    }

    private func setBusy(_ value: Bool) {
        isBusy = value
        onBusyChange?(value)
    }

    private func run(_ message: String) {
        if agent == .hermes {
            runHermes(message)
        } else {
            runOpencode(message)
        }
    }

    private func commonEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        let extraPaths = "\(home)/.local/bin:\(home)/.opencode/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = extraPaths + ":" + (environment["PATH"] ?? "")
        environment["HOME"] = home
        return environment
    }

    /// Menjalankan Hermes one-shot. Kalau `hermesSessionID` diisi, pesan
    /// masuk ke sesi itu (`--resume <id>`); kalau kosong, memakai thread
    /// bernama yang persisten (`-c petasisten`).
    /// Jawaban murni ada di stdout; info sesi (↻, session_id) ada di stderr.
    private func runHermes(_ message: String) {
        reply = ""
        lineBuffer.removeAll()
        emittedPoseCount = 0
        hermesTimedOut = false
        setBusy(true)

        Brain.ensureAgentFile()

        guard let hermes = hermesPath else {
            setBusy(false)
            onError?("Hermes tidak ditemukan. Pasang dulu: ~/.local/bin/hermes")
            return
        }

        let queryPath = (AppPaths.directory as NSString).appendingPathComponent("query.txt")
        guard (try? message.write(toFile: queryPath, atomically: true, encoding: .utf8)) != nil else {
            setBusy(false)
            onError?("Gagal menyiapkan pesan untuk Hermes.")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: hermes)
        var arguments = ["chat", "--query-file", queryPath, "--oneshot"]
        if hermesSessionID.isEmpty {
            arguments.append(contentsOf: ["-c", Brain.hermesSessionName])
        } else {
            arguments.append(contentsOf: ["--resume", hermesSessionID, "--no-restore-cwd"])
        }
        arguments.append(contentsOf: ["--in", AppPaths.directory, "-Q"])
        if let bare = bareModelName {
            arguments.append(contentsOf: ["-m", bare])
        }
        process.arguments = arguments
        process.environment = commonEnvironment()
        process.currentDirectoryURL = URL(fileURLWithPath: AppPaths.directory)

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        // Hermes one-shot mencetak jawaban sekaligus di akhir, bukan streaming.
        // Sesi besar butuh reload konteks tiap pesan sehingga bisa lambat —
        // watchdog ini menjaga UI tidak hang selamanya.
        let watchdog = DispatchWorkItem { [weak self] in
            guard let self, self.process === process, !self.hermesTimedOut else { return }
            self.hermesTimedOut = true
            process.terminate()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + Brain.hermesTimeout, execute: watchdog)

        process.terminationHandler = { [weak self] proc in
            guard let self else { return }
            watchdog.cancel()
            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let outText = String(data: outData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let errText = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            self.process = nil
            let timedOut = self.hermesTimedOut
            self.hermesTimedOut = false
            DispatchQueue.main.async {
                self.setBusy(false)
                if !outText.isEmpty, !timedOut {
                    let noPoses = self.extractPoses(from: outText)
                    self.onDone?(noPoses)
                } else if timedOut {
                    self.onError?("Hermes kehabisan waktu (\(Int(Brain.hermesTimeout)) dtk). Sesi besar memang lambat karena reload konteks tiap pesan — coba lagi atau pakai sesi yang lebih kecil.")
                } else if proc.terminationStatus != 0 {
                    let detail = errText.isEmpty
                        ? "Hermes keluar dengan kode \(proc.terminationStatus)."
                        : errText
                    self.onError?(detail)
                } else {
                    self.onError?(errText.isEmpty ? "(tidak ada balasan)" : errText)
                }
                if !self.queue.isEmpty {
                    let next = self.queue.removeFirst()
                    self.run(next)
                }
            }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            setBusy(false)
            onError?("Gagal menjalankan Hermes: \(error.localizedDescription)")
        }
    }

    /// Mengekstrak tag protokol, memutar gestur yang punya frame, dan
    /// mengembalikan teks tanpa tag. Dipakai jalur Hermes (bukan streaming).
    private func extractPoses(from text: String) -> String {
        let split = splitCues(from: text)
        writePoses(split.poses)
        return split.clean
    }

    /// Memisahkan tag [POSE], [MESH], dan [EXPR] yang sudah utuh.
    /// Tag terpotong di ujung balasan streaming dibiarkan sampai potongan berikutnya.
    private func splitCues(from text: String) -> (clean: String, poses: [String]) {
        guard let regex = Brain.cueRegex else { return (text, []) }
        var cleaned = text
        var poses: [String] = []
        let matches = regex.matches(
            in: cleaned,
            range: NSRange(cleaned.startIndex..., in: cleaned)
        )
        for match in matches.reversed() {
            if
                let kindRange = Range(match.range(at: 1), in: cleaned),
                let nameRange = Range(match.range(at: 2), in: cleaned)
            {
                let kind = String(cleaned[kindRange])
                let name = String(cleaned[nameRange])
                if let pose = Brain.poseCommand(kind: kind, name: name) {
                    poses.append(pose)
                }
            }
            if let fullRange = Range(match.range, in: cleaned) {
                cleaned.removeSubrange(fullRange)
            }
        }
        poses.reverse()
        let collapsed = cleaned
            .replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (collapsed, poses)
    }

    /// Petunjuk kegiatan dari kalimat pengguna. Mode hanya berganti kalau
    /// tempatnya disebut jelas. Kegiatan spesifik memutar satu gerakan.
    struct ActivityHint {
        var modeID: String?
        var clipName: String?
    }

    static func activityHint(in text: String) -> ActivityHint? {
        let line = text.lowercased()
        var hint = ActivityHint()

        let clips: [(String, [String])] = [
            ("gym_barbell_squat", ["barbell", "barbel", "squat beban", "back squat"]),
            ("gym_leg_press", ["leg press"]),
            ("gym_biceps_curl", ["biceps", "bisep", "dumbbell curl", "angkat dumbbell"]),
            ("gym_shoulder_press", ["shoulder press", "angkat bahu"]),
            ("gym_lat_pulldown", ["lat pulldown", "pulldown"]),
            ("gym_seated_row", ["seated row", "cable row"]),
            ("gym_treadmill_walk", ["treadmill", "lari di tempat"]),
            ("gym_stationary_cycle", ["sepeda statis", "stationary bike", "static bike"]),
            ("home_sweeping", ["menyapu", "nyapu", "sapu lantai"]),
            ("home_cooking_stir", ["memasak", "mengaduk", "masak", "memasak"]),
            ("home_washing_dishes", ["cuci piring", "mencuci piring"]),
            ("home_wiping_counter", ["mengelap", "lap meja", "elap meja"]),
            ("home_folding_laundry", ["lipat baju", "melipat", "lipat cucian", "laundry"]),
            ("home_washing_hair", ["keramas", "cuci rambut", "bilas rambut"]),
        ]
        for (clip, phrases) in clips where phrases.contains(where: { line.contains($0) }) {
            hint.clipName = clip
            break
        }

        let modes: [(String, [String])] = [
            ("gym", ["lagi gym", "ke gym", "di gym", "mode gym", "ngegym", "sedang gym"]),
            ("rumah", ["di rumah", "lagi rumah", "mode rumah", "sedang di rumah", "beres-beres"]),
            ("fitness", ["mode fitness", "pemanasan", "lagi stretching", "sedang fitness"]),
        ]
        for (mode, phrases) in modes where phrases.contains(where: { line.contains($0) }) {
            hint.modeID = mode
            break
        }

        if hint.modeID == nil, hint.clipName == nil { return nil }
        return hint
    }

    /// Maps tags in ~/.pet/AGENTS.md onto pose commands that have a clip folder.
    private static func poseCommand(kind: String, name: String) -> String? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch kind.uppercased() {
        case "POSE":
            if let pose = PetPose.named(key) { return pose.rawValue }
            let clip = key.replacingOccurrences(of: " ", with: "_")
            return clip.isEmpty ? nil : clip
        case "EXPR":
            switch key {
            case "horny", "orgasme": return PetPose.moodIntense.rawValue
            default: return nil
            }
        case "MESH":
            switch key {
            case "hide_clothes": return PetPose.skinBase.rawValue
            default: return nil
            }
        default:
            return nil
        }
    }

    /// Memutar tag baru dari balasan yang sedang menumpuk.
    private func emitNewPoses(in text: String) -> String {
        let split = splitCues(from: text)
        if split.poses.count > emittedPoseCount {
            writePoses(Array(split.poses[emittedPoseCount...]))
            emittedPoseCount = split.poses.count
        }
        return split.clean
    }

    /// Menulis nama gestur ke papan perintah yang dipantau CommandBoard.
    private func writePoses(_ poses: [String]) {
        for poseName in poses {
            let line = poseName + "\n"
            let commandPath = NSHomeDirectory() + "/.pet/poses.command"
            if let fileHandle = FileHandle(forWritingAtPath: commandPath) {
                fileHandle.seekToEndOfFile()
                if let data = line.data(using: .utf8) {
                    fileHandle.write(data)
                }
                fileHandle.closeFile()
            } else {
                try? line.write(toFile: commandPath, atomically: true, encoding: .utf8)
            }
        }
    }

    /// Menjalankan OpenCode di folder ~/.pet supaya dia membaca AGENTS.md.
    /// Jawaban mengalir per baris JSON.
    private func runOpencode(_ message: String) {
        reply = ""
        lineBuffer.removeAll()
        emittedPoseCount = 0
        hermesTimedOut = false
        setBusy(true)

        Brain.ensureAgentFile()

        let process = Process()
        var arguments: [String] = []
        if isEnvLauncher {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            arguments = ["opencode"]
        } else {
            process.executableURL = URL(fileURLWithPath: opencode)
        }
        arguments.append(contentsOf: ["run", "--format", "json", "--session", Brain.sessionID])
        if let model, !model.isEmpty {
            arguments.append(contentsOf: ["--model", model])
        }
        arguments.append(message)
        process.arguments = arguments
        process.environment = commonEnvironment()
        process.currentDirectoryURL = URL(fileURLWithPath: AppPaths.directory)

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let output = stdout.fileHandleForReading

        let watchdog = DispatchWorkItem { [weak self] in
            guard let self, self.process === process, !self.hermesTimedOut else { return }
            self.hermesTimedOut = true
            process.terminate()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + Brain.hermesTimeout, execute: watchdog)

        output.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            self.ioLock.lock()
            let data = handle.availableData
            self.ioLock.unlock()
            guard !data.isEmpty else { return }
            self.work.async { self.consume(data) }
        }

        process.terminationHandler = { [weak self] proc in
            guard let self else { return }
            watchdog.cancel()
            output.readabilityHandler = nil
            self.ioLock.lock()
            let rest = output.readDataToEndOfFile()
            self.ioLock.unlock()
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let timedOut = self.hermesTimedOut
            self.hermesTimedOut = false
            self.work.async {
                if !rest.isEmpty { self.consume(rest) }
                self.flushLineBuffer()
                self.process = nil
                let cleaned = self.emitNewPoses(in: self.reply)
                DispatchQueue.main.async {
                    self.setBusy(false)
                    if !cleaned.isEmpty, !timedOut {
                        self.onDone?(cleaned)
                    } else if timedOut {
                        self.onError?("OpenCode kehabisan waktu (\(Int(Brain.hermesTimeout)) dtk).")
                    } else if proc.terminationStatus != 0 {
                        let detail = errText.isEmpty
                            ? "OpenCode keluar dengan kode \(proc.terminationStatus)."
                            : errText
                        self.onError?(detail)
                    } else {
                        self.onError?(errText.isEmpty ? "(tidak ada balasan)" : errText)
                    }
                    if !self.queue.isEmpty {
                        let next = self.queue.removeFirst()
                        self.run(next)
                    }
                }
            }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            output.readabilityHandler = nil
            setBusy(false)
            onError?("Gagal menjalankan OpenCode: \(error.localizedDescription)")
        }
    }

    /// Membaca potongan stdout, memecah per baris, lalu mengambil teks balasan.
    private func consume(_ data: Data) {
        lineBuffer.append(data)
        while let newline = lineBuffer.firstIndex(of: 0x0A) {
            let lineData = lineBuffer.subdata(in: lineBuffer.startIndex..<newline)
            lineBuffer.removeSubrange(lineBuffer.startIndex...newline)
            handle(line: lineData)
        }
    }

    private func flushLineBuffer() {
        guard !lineBuffer.isEmpty else { return }
        let leftover = lineBuffer
        lineBuffer.removeAll()
        handle(line: leftover)
    }

    private func handle(line: Data) {
        guard !line.isEmpty else { return }
        guard
            let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            let type = object["type"] as? String
        else { return }

        switch type {
        case "text":
            if let part = object["part"] as? [String: Any],
               let text = part["text"] as? String {
                reply += text
                let snapshot = emitNewPoses(in: reply)
                DispatchQueue.main.async { self.onText?(snapshot) }
            }
        case "error":
            if let message = object["message"] as? String {
                DispatchQueue.main.async { self.onError?(message) }
            }
        default:
            break
        }
    }
}
