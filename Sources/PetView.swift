import AppKit

/// View utama: menggambar karakter + gelembung pesan, menangani klik dan geser.
final class PetView: NSView {
    static let minScale: CGFloat = 0.5
    static let maxScale: CGFloat = 2.0
    static let defaultScale: CGFloat = 1.0

    private let labelArea: CGFloat = 12
    private let minContentWidth: CGFloat = 170

    /// Karakter dari folder frame. Klip yang tidak ada memakai animasi lain
    /// dari paket yang sama.
    private let character = CharacterSprite()

    var state: PetState = .idle {
        didSet {
            if state != oldValue {
                stateTime = 0
                currentClip = CharacterSprite.stateClip[state] ?? .idle
            }
            needsDisplay = true
        }
    }

    /// Teks yang tampil di gelembung. `nil` menyembunyikan gelembung.
    var message: String? {
        didSet {
            refreshLayout()
            needsDisplay = true
        }
    }

    /// Ukuran pet. 1.0 = ukuran normal.
    var scale: CGFloat = PetView.defaultScale {
        didSet {
            scale = min(max(scale, PetView.minScale), PetView.maxScale)
            refreshLayout()
            needsDisplay = true
        }
    }

    /// Tinggi karakter dalam poin pada skala 1.0.
    static let baseHeight: CGFloat = 210

    var onToggleChat: (() -> Void)?
    var onContextMenu: ((NSEvent) -> Void)?
    var onScaleChange: ((CGFloat) -> Void)?

    private var phase: Double = 0
    private var stateTime: Double = 0
    private var currentClip: CharacterSprite.Clip = .idle
    private var overrideName: String?
    private var overrideStart: Double = 0
    private var overrideHold: Double = 0
    private var currentPose: PetPose?
    private var nextVariationAt: Double = 0
    private var standbyCursor = 0
    private var timer: Timer?

    private var dragStart: NSPoint?
    private var dragOrigin: NSPoint?
    private var dragged = false

    override var isFlipped: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncContentsScale()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        syncContentsScale()
    }

    /// Gambar ulang setajam layar, supaya memperbesar pet tidak membuat piksel pecah.
    private func syncContentsScale() {
        layer?.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) belum dipakai") }

    deinit { timer?.invalidate() }

    func startAnimating() {
        guard timer == nil else { return }
        if character.standbyClipNames.isEmpty {
            nextVariationAt = phase + Double.random(in: 20...45)
        } else {
            playNextStandby()
        }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.phase += 1.0 / 30.0
            self.stateTime += 1.0 / 30.0

            if self.overrideName != nil {
                if self.phase - self.overrideStart >= self.overrideHold {
                    self.finishOverride()
                }
            } else if self.state == .idle, self.phase >= self.nextVariationAt {
                self.startIdleVariation()
            }
            self.needsDisplay = true
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - Ukuran

    /// Lebar isi window mengikuti skala, dengan lebar minimum agar teks terbaca.
    private var contentWidth: CGFloat {
        max(spriteSize.width + 40, minContentWidth)
    }

    private var spriteSize: NSSize {
        let height = PetView.baseHeight * scale
        return NSSize(width: height * character.aspect, height: height)
    }

    /// Luas karakter di dalam view (origin kiri-bawah).
    var catRect: NSRect {
        let size = spriteSize
        return NSRect(
            x: (contentWidth - size.width) / 2,
            y: labelArea,
            width: size.width,
            height: size.height
        )
    }

    /// Memutar animasi sapaan (kiss) sekali.
    func playGreeting() {
        play(.cium)
    }

    /// Memuat paket gambar lain dan langsung menyesuaikan ukuran.
    func usePack(_ id: String) {
        character.load(pack: id)
        standbyCursor = 0
        stopPose()
        currentClip = CharacterSprite.stateClip[state] ?? .idle
        if character.standbyClipNames.isEmpty {
            nextVariationAt = phase + Double.random(in: 8...16)
        } else if state == .idle {
            playNextStandby()
        }
        refreshLayout()
    }

    var packID: String { character.packID }
    var standbyChoices: [CharacterSprite.StandbyChoice] { character.standbyChoices }
    var standbyModeID: String { character.standbyModeID }

    /// Mengganti kegiatan standby (fitness, gym, rumah, atau mode baru di pack.json).
    @discardableResult
    func setStandbyMode(_ id: String) -> String? {
        guard character.setStandbyMode(id) else { return nil }
        standbyCursor = 0
        stopPose()
        if character.standbyClipNames.isEmpty {
            nextVariationAt = phase + Double.random(in: 8...16)
        } else if state == .idle {
            playNextStandby()
        }
        return character.standbyChoices.first { $0.id == id }?.label
    }

    /// Langsung memutar kegiatan standby berikutnya, tanpa kembali ke pose diam.
    private func playNextStandby() {
        let standby = character.standbyClipNames
        guard !standby.isEmpty else { return }
        let clip = standby[standbyCursor % standby.count]
        standbyCursor += 1
        play(named: clip, hold: character.duration(named: clip))
    }

    private func finishOverride() {
        overrideName = nil
        currentPose = nil
        if state == .idle, !character.standbyClipNames.isEmpty {
            playNextStandby()
        } else {
            nextVariationAt = phase + Double.random(in: 25...60)
        }
    }

    private func startIdleVariation() {
        if !character.standbyClipNames.isEmpty {
            playNextStandby()
            return
        }
        let variations = PetPose.allCases.filter {
            CharacterSprite.idleVariations.contains($0.clip)
                && $0 != .pegangMemek
                && $0 != .mainkanAnal
        }
        if let variation = variations.randomElement() {
            play(variation)
        }
    }

    /// Memutar folder frame kalau paket karakter ini memilikinya.
    @discardableResult
    func playIfAvailable(_ name: String, hold: Double? = nil) -> Bool {
        guard character.has(named: name) else { return false }
        play(named: name, hold: hold ?? character.duration(named: name))
        return true
    }

    /// Memutar satu klip tanpa tombol gestur, misalnya fitness saat standby.
    func play(clip: CharacterSprite.Clip, hold: Double) {
        play(named: clip.rawValue, hold: hold)
    }

    func play(named name: String, hold: Double) {
        currentPose = nil
        overrideName = name
        overrideHold = hold
        overrideStart = phase
        needsDisplay = true
    }

    /// Memutar satu gestur sekali. `hold` = berapa detik gestur ditahan
    /// (0 = pakai durasi animasi). Untuk gestur pose (duduk, regang, dst)
    /// dipakai nilai yang lebih panjang supaya terasa "standby".
    func play(_ pose: PetPose, hold: Double? = nil) {
        currentPose = pose
        overrideName = pose.clip.rawValue
        overrideHold = hold ?? pose.holdDuration
        overrideStart = phase
        needsDisplay = true
    }

    /// Menghentikan gestur dan kembali ke animasi status.
    func stopPose() {
        currentPose = nil
        overrideName = nil
        overrideHold = 0
        needsDisplay = true
    }

    var activePose: PetPose? { currentPose }

    private var baseHeight: CGFloat { catRect.maxY + 12 }

    /// Mengubah skala dan memberi tahu pemanggil (untuk menyimpan / sinkron slider).
    func setScale(_ value: CGFloat, notify: Bool = false) {
        let clamped = min(max(value, PetView.minScale), PetView.maxScale)
        guard abs(clamped - scale) > 0.001 else { return }
        scale = clamped
        if notify { onScaleChange?(scale) }
    }

    func saveScale() {
        UserDefaults.standard.set(Double(scale), forKey: "pet.scale")
    }

    static func savedScale() -> CGFloat {
        let stored = UserDefaults.standard.double(forKey: "pet.scale")
        guard stored > 0 else { return defaultScale }
        return min(max(CGFloat(stored), minScale), maxScale)
    }

    // MARK: - Hit testing (area transparan bisa ditembus klik)

    private var currentBubbleRect: NSRect {
        let height = bubbleHeight()
        guard height > 0 else { return .zero }
        return NSRect(x: 8, y: baseHeight, width: contentWidth - 16, height: height)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: nil)
        if catRect.contains(local) || currentBubbleRect.contains(local) {
            return self
        }
        return nil
    }

    // MARK: - Klik & geser

    override func mouseDown(with event: NSEvent) {
        dragStart = NSEvent.mouseLocation
        dragOrigin = window?.frame.origin
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart, let dragOrigin, let window else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - dragStart.x
        let dy = current.y - dragStart.y
        if abs(dx) > 3 || abs(dy) > 3 { dragged = true }
        window.setFrameOrigin(NSPoint(x: dragOrigin.x + dx, y: dragOrigin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil; dragOrigin = nil }
        if dragged {
            savePosition()
        } else {
            onToggleChat?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onContextMenu?(event)
    }

    /// Posisi disimpan sebagai titik tengah-bawah supaya tidak melompat saat
    /// ukuran berubah.
    func savePosition() {
        guard let frame = window?.frame else { return }
        UserDefaults.standard.set("\(frame.midX),\(frame.minY)", forKey: "pet.anchor")
    }

    static func savedAnchor() -> NSPoint? {
        guard let raw = UserDefaults.standard.string(forKey: "pet.anchor") else { return nil }
        let parts = raw.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return NSPoint(x: parts[0], y: parts[1])
    }

    // MARK: - Layout

    private var bubbleFont: NSFont {
        let size = min(max(11, 12.5 * scale), 19)
        return NSFont.systemFont(ofSize: size, weight: .medium)
    }

    private func bubbleAttributes() -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        return [
            .font: bubbleFont,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ]
    }

    private func bubbleHeight() -> CGFloat {
        guard let message, !message.isEmpty else { return 0 }
        let text = PetView.bubbleText(message)
        let bounding = (text as NSString).boundingRect(
            with: NSSize(width: contentWidth - 16 - 24, height: 400),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: bubbleAttributes()
        )
        return min(bounding.height, 140 * max(scale, 1)) + 20
    }

    private static func bubbleText(_ message: String) -> String {
        let clean = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = 240
        if clean.count > limit {
            return String(clean.prefix(limit)) + "…"
        }
        return clean
    }

    /// Menyesuaikan ukuran window. Titik tengah-bawah tetap, jadi pet tumbuh
    /// ke atas dan ke samping tanpa melompat.
    func refreshLayout() {
        guard let window else { return }

        let bubble = bubbleHeight()
        let newSize = NSSize(
            width: contentWidth,
            height: baseHeight + (bubble > 0 ? bubble + 8 : 0)
        )

        var frame = window.frame
        guard abs(frame.width - newSize.width) > 0.5 || abs(frame.height - newSize.height) > 0.5 else {
            return
        }
        let centerX = frame.midX
        let bottom = frame.minY
        frame.size = newSize
        frame.origin = NSPoint(x: centerX - newSize.width / 2, y: bottom)
        window.setFrame(frame, display: true, animate: false)
    }

    // MARK: - Menggambar

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)
        context.interpolationQuality = .high

        var clipName = currentClip.rawValue
        var clipTime = stateTime

        // gestur menimpa animasi status. Pergantian standby diurus timer,
        // supaya pose diam tidak sempat tergambar di antara kegiatan.
        if let override = overrideName {
            clipName = override
            clipTime = phase - overrideStart
        }

        _ = character.drawAvailable(named: clipName, time: clipTime, in: catRect)

        drawBubble()
    }

    private func drawBubble() {
        guard let message, !message.isEmpty else { return }
        let rect = currentBubbleRect
        guard rect.height > 0 else { return }

        let radius = 14 * min(max(scale, 0.7), 1.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

        // ekor gelembung menunjuk ke kucing
        let tail = NSBezierPath()
        let tailX = min(max(catRect.midX, rect.minX + 24), rect.maxX - 24)
        tail.move(to: NSPoint(x: tailX - 8, y: rect.minY + 1))
        tail.line(to: NSPoint(x: tailX, y: rect.minY - 10))
        tail.line(to: NSPoint(x: tailX + 8, y: rect.minY + 1))
        tail.close()

        state.bubbleColor.setFill()
        path.fill()
        tail.fill()

        NSColor.white.withAlphaComponent(0.10).setStroke()
        path.lineWidth = 1
        path.stroke()

        let text = PetView.bubbleText(message)
        let inset = NSRect(
            x: rect.minX + 12,
            y: rect.minY + 10,
            width: rect.width - 24,
            height: rect.height - 20
        )
        (text as NSString).draw(
            with: inset,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: bubbleAttributes()
        )
    }
}
