import AppKit

/// Memuat dan menggambar karakter "Nori" dari `Resources/character`.
///
/// Tiap animasi adalah folder berisi `00.png`, `01.png`, ... dengan kanvas
/// seragam (192x208) dan garis kaki yang sama, sehingga perpindahan animasi
/// tidak membuat karakter melompat.
final class CharacterSprite {
    struct Animation {
        var frames: [NSImage]
        var frameDuration: Double
        var loops: Bool
    }

    /// Semua animasi yang tersedia di `Resources/character`.
    enum Clip: String, CaseIterable {
        case idle
        case waving
        case waiting
        case review
        case running
        case jumping
        case failed
        case runningLeft = "running-left"
        case runningRight = "running-right"
        case kiss
        case hug
        case talking
        case okaySmile = "okay-smile"
        case laughing
        case sitting
        case seatedSplit = "seated-split"
        case handOnKnee = "hand-on-knee"
        case skinBase = "skin_base"
        case interaksiBawah1 = "interaksi_bawah_1"
        case interaksiBawah2 = "interaksi_bawah_2"
        case moodIntense = "mood_intense"
        case standbyFitness = "standby-fitness"
        case standbyStretch = "standby-stretch"
        case seatedDoubleLegRaise = "seated-double-leg-raise"
        case seatedStraddleLegRaise = "seated-straddle-leg-raise"
    }

    struct Pack: Equatable {
        var id: String
        var label: String
    }

    /// Satu pilihan standby. Daftar ini datang dari `pack.json`, jadi mode baru
    /// cukup menambah folder frame dan satu entri, tanpa mengubah kode.
    struct StandbyChoice: Equatable {
        var id: String
        var label: String
        var clips: [String]
    }

    static let defaultPackID = "nori"
    private static let packDefaultsKey = "pet.characterPack"

    private(set) var animations: [Clip: Animation] = [:]
    /// Semua folder frame, termasuk gerak gym/rumah yang tidak ada di enum.
    private(set) var namedAnimations: [String: Animation] = [:]
    private(set) var canvasSize = NSSize(width: 192, height: 208)

    /// Animasi untuk tiap status pet.
    static let stateClip: [PetState: Clip] = [
        .idle: .idle,
        .thinking: .waiting,      // sedang menunggu jawaban
        .speaking: .talking,      // sedang berbicara
        .happy: .okaySmile,       // OK / senyum
        .error: .failed,          // gagal / sedih
    ]

    /// Sapaan saat panel chat dibuka.
    static let greetingClip: Clip = .kiss

    /// Gestur yang sesekali diputar saat pet sedang santai, supaya hidup.
    static let idleVariations: [Clip] = [
        .laughing, .handOnKnee, .seatedSplit, .jumping, .waving,
    ]

    /// Kalau folder klip tidak ada, pakai animasi lain yang pakaiannya sama.
    private static let fallbackAlias: [Clip: Clip] = [
        .talking: .waiting,
        .kiss: .waving,
        .hug: .idle,
        .okaySmile: .idle,
        .laughing: .idle,
        .sitting: .seatedDoubleLegRaise,
        .seatedSplit: .standbyStretch,
        .handOnKnee: .standbyStretch,
        .skinBase: .idle,
        .interaksiBawah1: .seatedDoubleLegRaise,
        .interaksiBawah2: .seatedStraddleLegRaise,
        .moodIntense: .idle,
    ]

    /// Klip yang diputar bergiliran saat standby. Kosong = variasi gestur lama.
    private(set) var standbyClipNames: [String] = []
    private(set) var standbyChoices: [StandbyChoice] = []
    private(set) var standbyModeID = "santai"
    private(set) var packID = CharacterSprite.defaultPackID

    var isReady: Bool { !namedAnimations.isEmpty }

    var aspect: CGFloat {
        guard canvasSize.height > 0 else { return 0.92 }
        return canvasSize.width / canvasSize.height
    }

    init() {
        load(pack: CharacterSprite.savedPackID())
    }

    /// Ganti set gambar tanpa menutup aplikasi.
    func load(pack id: String) {
        animations = [:]
        namedAnimations = [:]
        standbyClipNames = []
        standbyChoices = []
        canvasSize = NSSize(width: 192, height: 208)
        packID = id
        guard let root = CharacterSprite.root(for: id) else {
            standbyChoices = [StandbyChoice(id: "santai", label: "Santai", clips: [])]
            standbyModeID = "santai"
            return
        }
        loadAnimations(from: root)
        applyAliases()
        standbyChoices = CharacterSprite.standbyChoices(in: root, available: namedAnimations)
        let saved = UserDefaults.standard.string(forKey: CharacterSprite.modeKey(for: id))
        let mode = standbyChoices.first { $0.id == saved }?.id ?? standbyChoices.first?.id ?? "santai"
        _ = setStandbyMode(mode)
        if let idle = animations[.idle]?.frames.first, idle.size.height > 0 {
            canvasSize = idle.size
        } else if let first = namedAnimations.values.first?.frames.first, first.size.height > 0 {
            canvasSize = first.size
        }
        UserDefaults.standard.set(id, forKey: CharacterSprite.packDefaultsKey)
    }

    /// Mengganti mode standby kalau id-nya ada di paket ini.
    @discardableResult
    func setStandbyMode(_ id: String) -> Bool {
        guard let choice = standbyChoices.first(where: { $0.id == id }) else { return false }
        standbyModeID = choice.id
        standbyClipNames = choice.clips.filter { namedAnimations[$0] != nil }
        UserDefaults.standard.set(choice.id, forKey: CharacterSprite.modeKey(for: packID))
        return true
    }

    func has(named name: String) -> Bool {
        animation(named: name) != nil
    }

    private func animation(named name: String) -> Animation? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let animation = namedAnimations[key] { return animation }
        let underscored = key.replacingOccurrences(of: "-", with: "_").replacingOccurrences(of: " ", with: "_")
        if let animation = namedAnimations[underscored] { return animation }
        let hyphenated = key.replacingOccurrences(of: "_", with: "-").replacingOccurrences(of: " ", with: "-")
        return namedAnimations[hyphenated]
    }

    private static func modeKey(for packID: String) -> String {
        "pet.standbyMode." + packID
    }

    private func loadAnimations(from root: URL) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return }
        for name in names where name != "pack.json" {
            let directory = root.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            guard let animation = CharacterSprite.animation(in: directory, name: name) else { continue }
            namedAnimations[name] = animation
            if let clip = Clip(rawValue: name) {
                animations[clip] = animation
            }
        }
    }

    private static func animation(in directory: URL, name: String) -> Animation? {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return nil
        }
        let pngs = files.filter { $0.hasSuffix(".png") }.sorted()
        var frames: [NSImage] = []
        for file in pngs {
            guard let image = NSImage(contentsOf: directory.appendingPathComponent(file)) else { continue }
            frames.append(image)
        }
        guard !frames.isEmpty else { return nil }
        let count = frames.count
        return Animation(
            frames: frames,
            frameDuration: frameDuration(forName: name, frameCount: count),
            loops: loops(forName: name)
        )
    }

    /// Mengisi klip yang tidak punya folder sendiri dari animasi yang sudah dimuat.
    private func applyAliases() {
        for (missing, source) in CharacterSprite.fallbackAlias {
            guard namedAnimations[missing.rawValue] == nil,
                  let animation = namedAnimations[source.rawValue] else { continue }
            namedAnimations[missing.rawValue] = animation
            animations[missing] = animation
        }
    }

    private static func frameDuration(forName name: String, frameCount: Int) -> Double {
        let count = max(frameCount, 1)
        if name.hasPrefix("gym_") || name.hasPrefix("home_") {
            return 5.0 / Double(count)
        }
        guard let clip = Clip(rawValue: name) else { return 0.14 }
        switch clip {
        case .idle, .waiting, .failed, .review, .skinBase, .moodIntense: return 0.16
        case .jumping: return 0.11
        case .waving, .kiss, .okaySmile: return 0.15
        case .interaksiBawah1, .interaksiBawah2: return 0.14
        case .standbyFitness: return 1.22 / Double(count)
        case .standbyStretch: return 2.60 / Double(count)
        case .seatedDoubleLegRaise: return 1.81 / Double(count)
        case .seatedStraddleLegRaise: return 2.29 / Double(count)
        default: return 0.14
        }
    }

    private static func loops(forName name: String) -> Bool {
        if name.hasPrefix("gym_") || name.hasPrefix("home_") { return true }
        guard let clip = Clip(rawValue: name) else { return true }
        // gestur sekali jalan; sisanya berulang
        switch clip {
        case .kiss, .hug, .jumping, .okaySmile, .laughing,
             .sitting, .seatedSplit, .handOnKnee, .waving,
             .interaksiBawah1, .interaksiBawah2:
            return false
        default:
            return true
        }
    }

    static func savedPackID() -> String {
        UserDefaults.standard.string(forKey: packDefaultsKey) ?? defaultPackID
    }

    /// Pilihan yang tampil di panel: Nori yang sudah ada, lalu paket tambahan.
    static func availablePacks() -> [Pack] {
        var packs = [Pack(id: defaultPackID, label: "Nori")]
        let root = charactersRoot()
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        for name in folders.sorted() where name != defaultPackID {
            let dir = root.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            packs.append(Pack(id: name, label: packLabel(in: dir, fallback: name)))
        }
        return packs
    }

    private static func charactersRoot() -> URL {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("characters"),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/characters")
    }

    private static func root(for id: String) -> URL? {
        if id == defaultPackID {
            if let bundled = Bundle.main.resourceURL?.appendingPathComponent("character"),
               FileManager.default.fileExists(atPath: bundled.path) {
                return bundled
            }
            let besideSource = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/character")
            if FileManager.default.fileExists(atPath: besideSource.path) {
                return besideSource
            }
            return nil
        }
        let extra = charactersRoot().appendingPathComponent(id)
        return FileManager.default.fileExists(atPath: extra.path) ? extra : nil
    }

    private static func packLabel(in directory: URL, fallback: String) -> String {
        let url = directory.appendingPathComponent("pack.json")
        guard
            let data = try? Data(contentsOf: url),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let label = object["label"] as? String,
            !label.isEmpty
        else { return fallback }
        return label
    }

    private static func standbyChoices(in directory: URL, available: [String: Animation]) -> [StandbyChoice] {
        let url = directory.appendingPathComponent("pack.json")
        guard
            let data = try? Data(contentsOf: url),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [StandbyChoice(id: "santai", label: "Santai", clips: [])]
        }

        if let modes = object["modes"] as? [[String: Any]] {
            let choices = modes.compactMap { mode -> StandbyChoice? in
                guard let id = mode["id"] as? String, !id.isEmpty else { return nil }
                let label = (mode["label"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? id
                let clips = (mode["clips"] as? [String] ?? []).filter { available[$0] != nil }
                guard !clips.isEmpty else { return nil }
                return StandbyChoice(id: id, label: label, clips: clips)
            }
            if !choices.isEmpty { return choices }
        }

        if let names = object["standby"] as? [String] {
            let clips = names.filter { available[$0] != nil }
            if !clips.isEmpty {
                return [StandbyChoice(id: "standby", label: "Standby", clips: clips)]
            }
        }
        return [StandbyChoice(id: "santai", label: "Santai", clips: [])]
    }

    /// Indeks frame yang harus tampil pada detik `time`.
    func frameIndex(for clip: Clip, time: Double) -> Int {
        frameIndex(named: clip.rawValue, time: time)
    }

    func frameIndex(named name: String, time: Double) -> Int {
        guard let animation = animation(named: name), !animation.frames.isEmpty else { return 0 }
        let raw = Int(time / animation.frameDuration)
        if animation.loops {
            return raw % animation.frames.count
        }
        return min(raw, animation.frames.count - 1)
    }

    /// Menggambar karakter ke dalam `rect`. Kalau nama klip tidak ada,
    /// memakai animasi lain dari paket yang sama.
    @discardableResult
    func drawAvailable(named name: String, time: Double, in rect: NSRect) -> Bool {
        if draw(named: name, time: time, in: rect) { return true }
        if name != Clip.idle.rawValue, draw(named: Clip.idle.rawValue, time: time, in: rect) { return true }
        if name != Clip.waiting.rawValue, draw(named: Clip.waiting.rawValue, time: time, in: rect) { return true }
        guard let any = namedAnimations.keys.sorted().first else { return false }
        return draw(named: any, time: time, in: rect)
    }

    /// Menggambar karakter ke dalam `rect`. Mengembalikan false kalau aset
    /// tidak tersedia.
    @discardableResult
    func draw(clip: Clip, time: Double, in rect: NSRect) -> Bool {
        draw(named: clip.rawValue, time: time, in: rect)
    }

    @discardableResult
    func draw(named name: String, time: Double, in rect: NSRect) -> Bool {
        guard let animation = animation(named: name), !animation.frames.isEmpty else {
            return false
        }
        let index = frameIndex(named: name, time: time)
        let image = animation.frames[index]

        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: rect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        return true
    }

    /// Durasi total satu putaran animasi.
    func duration(for clip: Clip) -> Double {
        duration(named: clip.rawValue)
    }

    func duration(named name: String) -> Double {
        guard let animation = animation(named: name) else { return 1 }
        return Double(animation.frames.count) * animation.frameDuration
    }
}
