import AppKit

/// Status yang bisa ditampilkan si pet.
enum PetState {
    case idle
    case thinking
    case speaking
    case happy
    case error

    /// Warna gelembung pesan.
    var bubbleColor: NSColor {
        switch self {
        case .error: return NSColor(srgbRed: 0.38, green: 0.16, blue: 0.18, alpha: 0.96)
        case .thinking: return NSColor(srgbRed: 0.18, green: 0.20, blue: 0.30, alpha: 0.96)
        default: return NSColor(srgbRed: 0.16, green: 0.15, blue: 0.22, alpha: 0.96)
        }
    }

    var label: String {
        switch self {
        case .idle: return "siap"
        case .thinking: return "mikir..."
        case .speaking: return "bicara"
        case .happy: return "senang"
        case .error: return "error"
        }
    }
}

/// Gestur yang bisa diminta lewat tombol atau perintah.
///
/// Nama perintah adalah bentuk pendek yang dipakai di
/// `~/.pet/poses.command`, misalnya `duduk`, `ketawa`, `lompat`.
enum PetPose: String, CaseIterable {
    case duduk
    case ketawa
    case peluk
    case lompat
    case lambai
    case cium
    case senyum
    case sedih
    case menunggu
    case bicara
    case telutut
    case regang
    /// Names from ~/.pet/AGENTS.md. They play the dedicated visual variants.
    case pegangMemek = "pegang_memek"
    case mainkanAnal = "mainkan_anal"
    case skinBase = "skin_base"
    case interaksiBawah1 = "interaksi_bawah_1"
    case interaksiBawah2 = "interaksi_bawah_2"
    case moodIntense = "mood_intense"

    /// Nama file animasi di `Resources/character`.
    var clip: CharacterSprite.Clip {
        switch self {
        case .duduk: return .sitting
        case .ketawa: return .laughing
        case .peluk: return .hug
        case .lompat: return .jumping
        case .lambai: return .waving
        case .cium: return .kiss
        case .senyum: return .okaySmile
        case .sedih: return .failed
        case .menunggu: return .waiting
        case .bicara: return .talking
        case .telutut: return .handOnKnee
        case .regang: return .seatedSplit
        case .skinBase: return .skinBase
        case .interaksiBawah1, .pegangMemek: return .interaksiBawah1
        case .interaksiBawah2, .mainkanAnal: return .interaksiBawah2
        case .moodIntense: return .moodIntense
        }
    }

    /// Label tombol di panel chat.
    var buttonLabel: String {
        switch self {
        case .duduk: return "Duduk"
        case .ketawa: return "Ketawa"
        case .peluk: return "Peluk"
        case .lompat: return "Lompat"
        case .lambai: return "Lambai"
        case .cium: return "Cium"
        case .senyum: return "Senyum"
        case .sedih: return "Sedih"
        case .menunggu: return "Menunggu"
        case .bicara: return "Bicara"
        case .telutut: return "Telutut"
        case .regang: return "Regang"
        case .pegangMemek: return "Pegang"
        case .mainkanAnal: return "Mainkan"
        case .skinBase: return "Skin"
        case .interaksiBawah1: return "Bawah A"
        case .interaksiBawah2: return "Bawah B"
        case .moodIntense: return "Intens"
        }
    }

    var isHeld: Bool {
        switch self {
        case .duduk, .telutut, .regang, .sedih, .pegangMemek, .mainkanAnal,
             .skinBase, .interaksiBawah1, .interaksiBawah2, .moodIntense:
            return true
        default: return false
        }
    }

    var holdDuration: Double { isHeld ? 6 : 3 }

    /// Mencari gestur dari nama perintah; toleran terhadap huruf besar dan spasi.
    static func named(_ text: String) -> PetPose? {
        let key = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        guard !key.isEmpty else { return nil }
        switch key {
        case "hide_clothes": return .skinBase
        case "horny", "orgasme": return .moodIntense
        default:
            return allCases.first { $0.rawValue == key }
        }
    }

    /// Semua nama yang bisa dipakai di papan perintah.
    static var commandNames: [String] { allCases.map(\.rawValue) }
}
