import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var petWindow: PetWindow!
    private var petView: PetView!
    private var chatPanel: ChatPanel!
    private var statusItem: NSStatusItem!

    private let brain = Brain()
    private let speaker = Speaker()
    private let voice = VoiceInput()
    private let board = CommandBoard()
    private var poseResetTimer: Timer?
    private var currentPose: PetPose?

    private var speechTimer: Timer?
    private var showTimer: Timer?
    private var hasMicPermission = false

    /// Menyentuh file ini membuat pet muncul kembali (dipakai show.sh).
    static let showRequestPath = NSHomeDirectory() + "/.pet/show.request"

    // MARK: - Siklus hidup

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildStatusItem()
        buildPet()
        buildChat()
        wireBrain()
        wireVoice()
        wireBoard()
        startShowRequestWatcher()
    }

    /// Menyambungkan papan perintah `~/.pet/poses.command`.
    private func wireBoard() {
        board.onRequest = { [weak self] request in
            guard let self else { return ["ok": false, "error": "Pet tidak tersedia."] }
            return self.handlePetRequest(request)
        }
        board.onPose = { [weak self] pose in
            self?.playPose(pose, announce: true)
        }
        board.onClip = { [weak self] name in
            guard let self else { return }
            if self.petView.playIfAvailable(name) {
                self.chatPanel.append(role: "sistem", text: "Gestur: \(name.replacingOccurrences(of: "_", with: " "))")
            } else {
                self.chatPanel.append(role: "sistem", text: "Gestur \"\(name)\" tidak ada di karakter ini.")
            }
        }
        board.onUnknown = { [weak self] name in
            let valid = PetPose.commandNames.joined(separator: ", ")
            self?.chatPanel.append(
                role: "sistem",
                text: "Gestur \"\(name)\" tidak dikenal. Yang tersedia: \(valid)"
            )
        }
        board.start()
    }

    private func petSnapshot() -> [String: Any] {
        ["ok": true, "character": petView.packID, "standby_mode": petView.standbyModeID,
         "current_pose": petView.activeClipName, "queued_poses": petView.pendingClipNames,
         "available_poses": petView.availableClipNames, "state": petView.state.label]
    }

    private func handlePetRequest(_ request: [String: Any]) -> [String: Any] {
        let action = request["action"] as? String ?? ""
        guard ["status", "character", "play"].contains(action) else {
            return ["ok": false, "error": "Perintah tidak dikenal."]
        }
        if action == "status" { return petSnapshot() }
        let id = request["character"] as? String ?? petView.packID
        guard CharacterSprite.availablePacks().contains(where: { $0.id == id }) else {
            return ["ok": false, "error": "Karakter tidak tersedia: \(id)"]
        }
        let previous = petView.packID
        if id != previous { petView.usePack(id) }
        if action == "play" {
            guard let names = request["poses"] as? [String], !names.isEmpty,
                  names.allSatisfy({ petView.availableClipNames.contains($0) }) else {
                if id != previous { petView.usePack(previous) }
                return ["ok": false, "error": "Pose tidak tersedia di karakter \(id)."]
            }
            _ = petView.playSequence(names)
            chatPanel.append(role: "sistem", text: "Gestur: \(names.joined(separator: ", "))")
        }
        chatPanel.setCharacters(CharacterSprite.availablePacks(), current: petView.packID)
        chatPanel.setStandby(petView.standbyChoices, current: petView.standbyModeID)
        chatPanel.setPoses(CharacterSprite.availablePoseChoices())
        keepOnScreen()
        return petSnapshot()
    }

    /// Memutar gestur dan menandainya di panel chat.
    private func playPose(_ pose: PetPose, announce: Bool) {
        petView.play(pose)
        currentPose = pose

        if announce {
            chatPanel.append(role: "sistem", text: "Gestur: \(pose.buttonLabel.lowercased())")
        }

        // lepaskan tanda aktif setelah gestur selesai
        poseResetTimer?.invalidate()
        let timer = Timer(timeInterval: pose.holdDuration, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.currentPose = nil
        }
        RunLoop.main.add(timer, forMode: .common)
        poseResetTimer = timer
    }

    /// Memantau ~/.pet/show.request. Karena app ini tidak punya ikon Dock,
    /// ini jalan keluar kalau pet tersembunyi: jalankan `./show.sh`.
    private func startShowRequestWatcher() {
        let timer = Timer(timeInterval: 0.7, repeats: true) { [weak self] _ in
            self?.checkShowRequest()
        }
        RunLoop.main.add(timer, forMode: .common)
        showTimer = timer
    }

    private func checkShowRequest() {
        let path = AppDelegate.showRequestPath
        guard FileManager.default.fileExists(atPath: path) else { return }
        try? FileManager.default.removeItem(atPath: path)

        if !petWindow.isVisible {
            petWindow.orderFrontRegardless()
        }
        keepOnScreen()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Dipanggil saat `open bin/Pet.app` dijalankan sementara app sudah hidup.
    /// Ini jalan keluar kalau pet disembunyikan: jalankan run.sh lagi.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !petWindow.isVisible {
            petWindow.orderFrontRegardless()
            petView.savePosition()
        } else {
            chatPanel.focusInput()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        speaker.stop()
        brain.cancel()
    }

    // MARK: - Membangun UI

    private func buildPet() {
        let size = NSSize(width: 200, height: 262)
        petWindow = PetWindow(contentRect: NSRect(origin: .zero, size: size))
        petView = PetView(frame: NSRect(origin: .zero, size: size))
        petWindow.contentView = petView

        petView.onToggleChat = { [weak self] in self?.toggleChat() }
        petView.onContextMenu = { [weak self] event in
            guard let self else { return }
            self.showMenu(with: event)
        }
        petView.onScaleChange = { [weak self] value in
            self?.chatPanel?.setScaleValue(value)
        }

        // terapkan ukuran tersimpan; window ikut menyesuaikan
        petView.scale = PetView.savedScale()
        petView.refreshLayout()

        placePet()
        petWindow.orderFrontRegardless()
        petView.startAnimating()
    }

    /// Menempatkan pet memakai titik tengah-bawah tersimpan, lalu menjepitnya
    /// agar selalu terlihat di layar.
    private func placePet() {
        guard let window = petWindow else { return }
        let visible = targetScreen().visibleFrame
        let size = window.frame.size

        let anchor = PetView.savedAnchor() ?? defaultAnchor(for: size, on: visible)
        var origin = NSPoint(x: anchor.x - size.width / 2, y: anchor.y)

        origin.x = min(max(origin.x, visible.minX), max(visible.minX, visible.maxX - size.width))
        origin.y = min(max(origin.y, visible.minY), max(visible.minY, visible.maxY - size.height))
        window.setFrameOrigin(origin)
    }

    private func defaultAnchor(for size: NSSize, on visible: NSRect) -> NSPoint {
        NSPoint(x: visible.maxX - size.width / 2 - 40, y: visible.minY + 60)
    }

    // MARK: - Ukuran pet

    private func applyScale(_ value: CGFloat) {
        petView.setScale(value)
        petView.saveScale()
        chatPanel?.setScaleValue(petView.scale)
        keepOnScreen()
    }

    private func nudgeScale(by delta: CGFloat) {
        applyScale(petView.scale + delta)
    }

    /// Setelah ukuran berubah, pastikan pet tidak keluar dari layar.
    private func keepOnScreen() {
        guard let window = petWindow else { return }
        let visible = targetScreen().visibleFrame
        var frame = window.frame
        frame.origin.x = min(max(frame.origin.x, visible.minX), max(visible.minX, visible.maxX - frame.width))
        frame.origin.y = min(max(frame.origin.y, visible.minY), max(visible.minY, visible.maxY - frame.height))
        window.setFrame(frame, display: true)
        petView.savePosition()
    }

    /// Layar tempat kursor berada. `NSScreen.main` tidak dipakai karena pada
    /// aplikasi tanpa window aktif ia bisa menunjuk monitor lain.
    private func targetScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) {
            return screen
        }
        return NSScreen.screens.first ?? NSScreen.main!
    }

    private func buildChat() {
        chatPanel = ChatPanel()
        chatPanel.onSend = { [weak self] text in self?.send(text) }
        chatPanel.onMicDown = { [weak self] in self?.beginListening() }
        chatPanel.onMicUp = { [weak self] in self?.voice.stop() }
        chatPanel.onScale = { [weak self] value in self?.applyScale(value) }
        chatPanel.onModelChange = { [weak self] model in
            guard let self else { return }
            self.brain.setModel(model)
            self.chatPanel.append(role: "sistem", text: "Model diganti ke: \(self.brain.modelName)")
        }
        chatPanel.onAgentChange = { [weak self] agent in
            guard let self else { return }
            self.brain.setAgent(agent)
            self.chatPanel.setSessionRowVisible(agent == .hermes)
            self.chatPanel.append(role: "sistem", text: "Agent diganti ke: \(self.brain.agentName)")
        }
        chatPanel.onSessionChange = { [weak self] sessionID in
            guard let self else { return }
            self.brain.setHermesSession(sessionID)
            if sessionID.isEmpty {
                self.chatPanel.append(role: "sistem", text: "Sesi Hermes: thread petasisten")
            } else {
                self.chatPanel.append(role: "sistem", text: "Sesi Hermes: \(sessionID)")
            }
        }
        chatPanel.onNamedPose = { [weak self] id, name in
            guard let self else { return }
            if self.petView.packID != id { self.petView.usePack(id) }
            guard self.petView.playSequence([name]) else { return }
            self.chatPanel.setCharacters(CharacterSprite.availablePacks(), current: id)
            self.chatPanel.setStandby(self.petView.standbyChoices, current: self.petView.standbyModeID)
            self.keepOnScreen()
            self.chatPanel.append(role: "sistem", text: "Pose: \(id) · \(name)")
        }
        chatPanel.onCharacter = { [weak self] id in
            guard let self else { return }
            self.petView.usePack(id)
            let label = CharacterSprite.availablePacks().first { $0.id == id }?.label ?? id
            self.chatPanel.setStandby(self.petView.standbyChoices, current: self.petView.standbyModeID)
            self.chatPanel.setPoses(CharacterSprite.availablePoseChoices())
            self.chatPanel.append(role: "sistem", text: "Karakter: \(label)")
        }
        chatPanel.onStandby = { [weak self] id in
            guard let self, let label = self.petView.setStandbyMode(id) else { return }
            self.chatPanel.append(role: "sistem", text: "Standby: \(label)")
        }
        chatPanel.setCharacters(CharacterSprite.availablePacks(), current: petView.packID)
        chatPanel.setStandby(petView.standbyChoices, current: petView.standbyModeID)
        chatPanel.setPoses(CharacterSprite.availablePoseChoices())
        chatPanel.onToggleMute = { [weak self] in
            guard let self else { return true }
            self.speaker.enabled.toggle()
            if !self.speaker.enabled { self.speaker.stop() }
            return self.speaker.enabled
        }
        chatPanel.setScaleValue(petView.scale)
        chatPanel.setModels(
            brain.availableModels,
            current: brain.model ?? brain.availableModels.first ?? ""
        )
        chatPanel.setAgents(current: brain.agent)
        chatPanel.setSessionText(brain.hermesSessionID)
        chatPanel.setSessionRowVisible(brain.agent == .hermes)
        chatPanel.append(role: "sistem", text: "Model aktif: \(brain.modelName)")
        chatPanel.append(role: "sistem", text: "Agent aktif: \(brain.agentName)")
        if brain.agent == .hermes {
            chatPanel.append(role: "sistem", text: "Sesi Hermes: \(brain.hermesSessionLabel)")
        }

        if let petFrame = petWindow?.frame {
            positionChatPanel(near: petFrame)
        }

        chatPanel.orderOut(nil)
    }

    /// Menaruh panel chat di samping pet, dan tetap di dalam layar.
    private func positionChatPanel(near petFrame: NSRect) {
        let panel = chatPanel.frame.size
        let visible = targetScreen().visibleFrame

        var x = petFrame.maxX + 12
        if x + panel.width > visible.maxX - 12 {
            x = petFrame.minX - panel.width - 12
        }
        x = min(max(x, visible.minX + 12), max(visible.minX + 12, visible.maxX - panel.width - 12))

        var y = petFrame.maxY - panel.height
        y = min(max(y, visible.minY + 12), max(visible.minY + 12, visible.maxY - panel.height - 12))

        chatPanel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "🐱"
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    // MARK: - Otak

    private func wireBrain() {
        brain.onText = { [weak self] partial in
            guard let self else { return }
            self.petView.state = .thinking
            self.petView.message = partial
            self.chatPanel.setStatus("mengetik…")
        }

        brain.onDone = { [weak self] text in
            guard let self else { return }
            self.chatPanel.append(role: "pet", text: text)
            self.petView.message = text
            self.petView.state = .speaking
            self.speaker.speak(text)
            self.watchSpeech()
        }

        brain.onError = { [weak self] message in
            guard let self else { return }
            self.chatPanel.append(role: "sistem", text: message)
            self.petView.state = .error
            self.petView.message = message
            self.chatPanel.setStatus("error")
        }

        brain.onBusyChange = { [weak self] busy in
            guard let self else { return }
            self.chatPanel.setStatus(busy ? "mikir…" : "siap")
        }
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if brain.isBusy {
            chatPanel.append(role: "kamu", text: trimmed)
            chatPanel.append(role: "sistem", text: "Masih mengerjakan permintaan sebelumnya. Ini akan dijalankan setelah selesai.")
        } else {
            chatPanel.append(role: "kamu", text: trimmed)
        }

        petView.state = .thinking
        petView.message = "…"
        applyActivityHint(Brain.activityHint(in: trimmed))
        brain.ask(trimmed)
    }

    /// Kalau kalimat pengguna jelas menyebut tempat atau kegiatan, standby ikut.
    private func applyActivityHint(_ hint: Brain.ActivityHint?) {
        guard let hint else { return }
        if let mode = hint.modeID, let label = petView.setStandbyMode(mode) {
            chatPanel.setStandby(petView.standbyChoices, current: petView.standbyModeID)
        chatPanel.setPoses(CharacterSprite.availablePoseChoices())
            chatPanel.append(role: "sistem", text: "Standby: \(label)")
        }
        if let clip = hint.clipName {
            _ = petView.playIfAvailable(clip)
        }
    }

    /// Menunggu `say` selesai, lalu kembali ke keadaan santai.
    private func watchSpeech() {
        speechTimer?.invalidate()

        if !speaker.enabled {
            finishAfterDelay(5)
            return
        }

        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] timer in
            guard let self else { return }
            guard !self.speaker.isSpeaking else { return }
            timer.invalidate()
            self.speechTimer = nil
            self.petView.state = .happy
            self.finishAfterDelay(1.6)
        }
        RunLoop.main.add(timer, forMode: .common)
        speechTimer = timer
    }

    private func finishAfterDelay(_ seconds: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, !self.brain.isBusy, !self.speaker.isSpeaking else { return }
            self.petView.state = .idle
            self.petView.message = nil
            self.chatPanel.setStatus("siap")
        }
    }

    // MARK: - Suara

    private func wireVoice() {
        voice.onPartial = { [weak self] text in
            self?.chatPanel.setInputText(text)
        }
        voice.onFinal = { [weak self] text in
            guard let self else { return }
            self.chatPanel.setInputText("")
            self.send(text)
        }
        voice.onError = { [weak self] message in
            self?.chatPanel.append(role: "sistem", text: message)
        }
    }

    private func beginListening() {
        if hasMicPermission {
            voice.start()
            return
        }
        voice.requestPermission { [weak self] granted in
            guard let self else { return }
            self.hasMicPermission = granted
            if granted {
                self.voice.start()
            } else {
                self.chatPanel.append(role: "sistem", text: "Izin mikrofon ditolak. Buka System Settings → Privacy & Security → Microphone, aktifkan untuk Pet.")
            }
        }
    }

    // MARK: - Chat & menu

    private func toggleChat() {
        if chatPanel.isVisible {
            chatPanel.orderOut(nil)
        } else {
            if let petFrame = petWindow?.frame {
                positionChatPanel(near: petFrame)
            }
            petView.playGreeting()
            chatPanel.focusInput()
        }
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu(with: nil)
        } else {
            toggleChat()
        }
    }

    private func showMenu(with event: NSEvent?) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Buka Chat", action: #selector(menuOpenChat), keyEquivalent: "")
        menu.addItem(withTitle: petWindow.isVisible ? "Sembunyikan Pet" : "Tampilkan Pet",
                     action: #selector(menuTogglePet), keyEquivalent: "")
        menu.addItem(withTitle: speaker.enabled ? "Bisukan Suara" : "Nyalakan Suara",
                     action: #selector(menuToggleMute), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Perbesar Pet", action: #selector(menuZoomIn), keyEquivalent: "+")
        menu.addItem(withTitle: "Perkecil Pet", action: #selector(menuZoomOut), keyEquivalent: "-")
        menu.addItem(withTitle: "Ukuran Normal", action: #selector(menuZoomReset), keyEquivalent: "0")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Buka Config Model…", action: #selector(menuOpenConfig), keyEquivalent: "")
        menu.addItem(withTitle: "Buka Papan Gestur…", action: #selector(menuOpenPoses), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Keluar", action: #selector(menuQuit), keyEquivalent: "q")
        for item in menu.items { item.target = self }

        if let event, let view = petView {
            NSMenu.popUpContextMenu(menu, with: event, for: view)
        } else if let button = statusItem.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        }
    }

    @objc private func menuOpenChat() { chatPanel.focusInput() }

    @objc private func menuTogglePet() {
        if petWindow.isVisible {
            petWindow.orderOut(nil)
        } else {
            petWindow.orderFrontRegardless()
        }
    }

    @objc private func menuToggleMute() {
        speaker.enabled.toggle()
        if !speaker.enabled { speaker.stop() }
    }

    @objc private func menuZoomIn() { nudgeScale(by: 0.1) }

    @objc private func menuZoomOut() { nudgeScale(by: -0.1) }

    @objc private func menuZoomReset() { applyScale(PetView.defaultScale) }

    @objc private func menuOpenConfig() {
        Brain.ensureConfigFile()
        NSWorkspace.shared.open(URL(fileURLWithPath: Brain.configPath))
    }

    @objc private func menuOpenPoses() {
        AppPaths.ensureDirectory()
        if !FileManager.default.fileExists(atPath: CommandBoard.path) {
            try? "".write(toFile: CommandBoard.path, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: CommandBoard.path))
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }
}
