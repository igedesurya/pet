import Foundation

/// Gerakan yang tersedia pada model VRM dan label yang ditampilkan di UI.
enum VRMMotion {
    struct Entry {
        let name: String
        let label: String
        let duration: Double

        var choice: CharacterSprite.PoseChoice {
            CharacterSprite.PoseChoice(characterID: "3D", name: name, title: label)
        }
    }

    static let entries: [Entry] = [
        Entry(name: "idle", label: "Berdiri santai", duration: 6),
        Entry(name: "waving", label: "Melambaikan tangan", duration: 6),
        Entry(name: "talking", label: "Berbicara", duration: 6),
        Entry(name: "waiting", label: "Menunggu", duration: 6),
        Entry(name: "okay-smile", label: "Senyum", duration: 6),
        Entry(name: "failed", label: "Gagal", duration: 6),
        Entry(name: "walking", label: "Berjalan", duration: 6),
        Entry(name: "walk-talk", label: "Jalan lalu bicara", duration: 9),
        Entry(name: "sad", label: "Sedih", duration: 6),
        Entry(name: "happy", label: "Senang", duration: 6),
        Entry(name: "jumping", label: "Loncat", duration: 5),
        Entry(name: "laughing", label: "Tertawa", duration: 6),
        Entry(name: "thinking", label: "Berpikir", duration: 6),
        Entry(name: "pondering", label: "Merenung", duration: 15),
        Entry(name: "sitting-cross-legged", label: "Duduk bersila", duration: 15),
        Entry(name: "kneeling", label: "Bersimpuh", duration: 15),
        Entry(name: "clapping", label: "Tepuk tangan", duration: 6),
        Entry(name: "nodding", label: "Mengangguk", duration: 6),
        Entry(name: "shaking-head", label: "Menggeleng", duration: 6),
        Entry(name: "bowing", label: "Membungkuk", duration: 6),
        Entry(name: "stretching", label: "Meregangkan badan", duration: 6),
    ]

    static let byName = Dictionary(uniqueKeysWithValues: entries.map { ($0.name, $0) })
    static var names: Set<String> { Set(entries.map(\.name)) }
    static var choices: [CharacterSprite.PoseChoice] { entries.map(\.choice) }

    private static let aliases: [String: String] = [
        "merenung": "pondering",
        "duduk bersila": "sitting-cross-legged",
        "bersimpuh": "kneeling",
        "tepuk tangan": "clapping",
        "sedih": "sad",
        "senang": "happy",
        "loncat": "jumping",
        "tertawa": "laughing",
        "berpikir": "thinking",
        "berdiri": "idle",
        "jalan lalu bicara": "walk-talk",
        "jalan lalu berbicara": "walk-talk",
        "jalan kemudian berbicara": "walk-talk",
    ]

    private static let chatNames: [String: String] = {
        var result = Self.aliases
        for entry in entries {
            result[entry.name] = entry.name
            result[Self.normalize(entry.label)] = entry.name
        }
        return result
    }()

    /// Commands intentionally match only short, exact phrases, optionally
    /// preceded by a polite request word. Questions continue to the assistant.
    static func chatCommand(_ text: String) -> Entry? {
        var phrase = normalize(text)
        while let last = phrase.last, ".!?。！？,，;；:：".contains(last) {
            phrase.removeLast()
        }

        for prefix in ["coba ", "tolong "] where phrase.hasPrefix(prefix) {
            phrase = String(phrase.dropFirst(prefix.count))
            break
        }

        guard let name = chatNames[phrase] else { return nil }
        return byName[name]
    }

    private static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
