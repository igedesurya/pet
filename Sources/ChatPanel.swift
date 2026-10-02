import AppKit

/// Panel chat untuk mengobrol dengan pet (teks dan suara).
final class ChatPanel: NSPanel, NSTextFieldDelegate {
    var onSend: ((String) -> Void)?
    var onMicDown: (() -> Void)?
    var onMicUp: (() -> Void)?
    var onToggleMute: (() -> Bool)?
    var onScale: ((CGFloat) -> Void)?
    var onModelChange: ((String) -> Void)?
    var onAgentChange: ((Brain.Agent) -> Void)?
    var onSessionChange: ((String) -> Void)?
    var onPose: ((PetPose) -> Void)?
    var onCharacter: ((String) -> Void)?
    var onStandby: ((String) -> Void)?

    private let scroll = NSScrollView()
    private let transcript = NSTextView()
    private let input = NSTextField()
    private let sendButton = NSButton()
    private let micButton = NSButton()
    private let muteButton = NSButton()
    private let statusLabel = NSTextField(labelWithString: "siap")
    private let sizeLabel = NSTextField(labelWithString: "Ukuran")
    private let sizeSlider = NSSlider()
    private let sizeValue = NSTextField(labelWithString: "100%")
    private let modelLabel = NSTextField(labelWithString: "Model")
    private let modelPopup = NSPopUpButton()
    private let agentLabel = NSTextField(labelWithString: "Agent")
    private let agentPopup = NSPopUpButton()
    private let sessionLabel = NSTextField(labelWithString: "Sesi")
    private let sessionField = NSTextField()
    private let poseStack = NSStackView()
    private var poseButtons: [PetPose: NSButton] = [:]
    private let characterLabel = NSTextField(labelWithString: "Karakter")
    private let characterPopup = NSPopUpButton()
    private var characterIDs: [String] = []
    private let standbyLabel = NSTextField(labelWithString: "Standby")
    private let standbyPopup = NSPopUpButton()
    private var standbyIDs: [String] = []

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 730),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        title = "Pet Asisten"
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        appearance = NSAppearance(named: .darkAqua)
        isReleasedWhenClosed = false
        buildUI()
    }

    private func buildUI() {
        guard let content = contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.14, alpha: 1).cgColor

        // riwayat percakapan
        scroll.frame = NSRect(x: 12, y: 378, width: 406, height: 340)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor(srgbRed: 0.08, green: 0.08, blue: 0.11, alpha: 1)
        scroll.borderType = .noBorder
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 10

        transcript.isEditable = false
        transcript.isSelectable = true
        transcript.drawsBackground = false
        transcript.textContainerInset = NSSize(width: 10, height: 10)
        transcript.isVerticallyResizable = true
        transcript.isHorizontallyResizable = false
        transcript.textContainer?.widthTracksTextView = true
        transcript.autoresizingMask = [.width]
        transcript.frame = scroll.bounds
        scroll.documentView = transcript
        content.addSubview(scroll)

        // kolom input
        input.frame = NSRect(x: 12, y: 342, width: 310, height: 28)
        input.autoresizingMask = [.width]
        input.placeholderString = "Tanya apa saja… (Enter untuk kirim)"
        input.font = NSFont.systemFont(ofSize: 13)
        input.delegate = self
        input.target = self
        input.action = #selector(sendTapped)
        content.addSubview(input)

        sendButton.frame = NSRect(x: 330, y: 342, width: 88, height: 28)
        sendButton.autoresizingMask = [.minXMargin]
        sendButton.title = "Kirim"
        sendButton.bezelStyle = .rounded
        sendButton.keyEquivalent = "\r"
        sendButton.target = self
        sendButton.action = #selector(sendTapped)
        content.addSubview(sendButton)

        // pemilih model
        modelLabel.frame = NSRect(x: 12, y: 282, width: 56, height: 20)
        modelLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        modelLabel.textColor = NSColor(white: 0.75, alpha: 1)
        content.addSubview(modelLabel)

        modelPopup.frame = NSRect(x: 72, y: 278, width: 200, height: 26)
        modelPopup.autoresizingMask = [.width]
        modelPopup.target = self
        modelPopup.action = #selector(modelChanged)
        modelPopup.font = NSFont.systemFont(ofSize: 12)
        content.addSubview(modelPopup)

        // pemilih agent
        agentLabel.frame = NSRect(x: 282, y: 282, width: 42, height: 20)
        agentLabel.autoresizingMask = [.minXMargin]
        agentLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        agentLabel.textColor = NSColor(white: 0.75, alpha: 1)
        content.addSubview(agentLabel)

        agentPopup.frame = NSRect(x: 326, y: 278, width: 92, height: 26)
        agentPopup.autoresizingMask = [.minXMargin]
        agentPopup.target = self
        agentPopup.action = #selector(agentChanged)
        agentPopup.font = NSFont.systemFont(ofSize: 12)
        content.addSubview(agentPopup)

        // kolom sesi Hermes (ID sesi aktif, kosong = thread bernama petasisten)
        sessionLabel.frame = NSRect(x: 12, y: 310, width: 56, height: 20)
        sessionLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        sessionLabel.textColor = NSColor(white: 0.75, alpha: 1)
        content.addSubview(sessionLabel)

        sessionField.frame = NSRect(x: 72, y: 306, width: 346, height: 26)
        sessionField.autoresizingMask = [.width]
        sessionField.placeholderString = "ID sesi Hermes (kosong = thread petasisten) — Enter untuk pakai"
        sessionField.font = NSFont.systemFont(ofSize: 12)
        sessionField.delegate = self
        sessionField.target = self
        sessionField.action = #selector(sessionChanged)
        sessionField.isHidden = true
        content.addSubview(sessionField)

        // pengatur ukuran pet
        sizeLabel.frame = NSRect(x: 12, y: 250, width: 56, height: 20)
        sizeLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        sizeLabel.textColor = NSColor(white: 0.75, alpha: 1)
        content.addSubview(sizeLabel)

        sizeSlider.frame = NSRect(x: 72, y: 246, width: 220, height: 24)
        sizeSlider.minValue = Double(PetView.minScale)
        sizeSlider.maxValue = Double(PetView.maxScale)
        sizeSlider.doubleValue = Double(PetView.defaultScale)
        sizeSlider.isContinuous = true
        sizeSlider.target = self
        sizeSlider.action = #selector(sizeChanged)
        content.addSubview(sizeSlider)

        sizeValue.frame = NSRect(x: 298, y: 250, width: 108, height: 20)
        sizeValue.autoresizingMask = [.minXMargin]
        sizeValue.alignment = .right
        sizeValue.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        sizeValue.textColor = NSColor(white: 0.75, alpha: 1)
        sizeValue.stringValue = "100%"
        content.addSubview(sizeValue)

        characterLabel.frame = NSRect(x: 12, y: 218, width: 64, height: 20)
        characterLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        characterLabel.textColor = NSColor(white: 0.75, alpha: 1)
        content.addSubview(characterLabel)

        characterPopup.frame = NSRect(x: 80, y: 214, width: 338, height: 26)
        characterPopup.autoresizingMask = [.width]
        characterPopup.target = self
        characterPopup.action = #selector(characterChanged)
        characterPopup.font = NSFont.systemFont(ofSize: 12)
        content.addSubview(characterPopup)

        standbyLabel.frame = NSRect(x: 12, y: 186, width: 64, height: 20)
        standbyLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        standbyLabel.textColor = NSColor(white: 0.75, alpha: 1)
        content.addSubview(standbyLabel)

        standbyPopup.frame = NSRect(x: 80, y: 182, width: 338, height: 26)
        standbyPopup.autoresizingMask = [.width]
        standbyPopup.target = self
        standbyPopup.action = #selector(standbyChanged)
        standbyPopup.font = NSFont.systemFont(ofSize: 12)
        content.addSubview(standbyPopup)

        // tombol gestur
        poseStack.frame = NSRect(x: 12, y: 96, width: 406, height: 80)
        poseStack.orientation = .horizontal
        poseStack.spacing = 4
        poseStack.distribution = .fillEqually
        content.addSubview(poseStack)
        buildPoseButtons(in: poseStack)

        micButton.frame = NSRect(x: 12, y: 58, width: 168, height: 30)
        micButton.title = "🎤 Tahan untuk bicara"
        micButton.bezelStyle = .rounded
        micButton.target = self
        micButton.action = #selector(micTapped)
        micButton.sendAction(on: [.leftMouseDown, .leftMouseUp])
        content.addSubview(micButton)

        muteButton.frame = NSRect(x: 188, y: 58, width: 140, height: 30)
        muteButton.title = "🔊 Suara: Aktif"
        muteButton.bezelStyle = .rounded
        muteButton.target = self
        muteButton.action = #selector(muteTapped)
        content.addSubview(muteButton)

        statusLabel.frame = NSRect(x: 330, y: 62, width: 88, height: 20)
        statusLabel.autoresizingMask = [.minXMargin]
        statusLabel.alignment = .right
        statusLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        statusLabel.textColor = NSColor(srgbRed: 1, green: 0.72, blue: 0.35, alpha: 1)
        statusLabel.stringValue = "siap"
        content.addSubview(statusLabel)

        append(role: "sistem", text: "Halo! Aku Pet Asisten. Tanya lewat teks atau tahan tombol mikrofon untuk bicara.")
    }

    // MARK: - Aksi

    /// Mengisi baris tombol gestur.
    private func buildPoseButtons(in stack: NSStackView) {
        let firstRow = NSStackView()
        firstRow.orientation = .horizontal
        firstRow.spacing = 4
        firstRow.distribution = .fillEqually
        for pose in [PetPose.duduk, .ketawa, .peluk, .lompat, .lambai, .cium] {
            firstRow.addArrangedSubview(poseButton(for: pose))
        }

        let secondRow = NSStackView()
        secondRow.orientation = .horizontal
        secondRow.spacing = 4
        secondRow.distribution = .fillEqually
        for pose in [PetPose.senyum, .sedih, .menunggu, .bicara, .telutut, .regang] {
            secondRow.addArrangedSubview(poseButton(for: pose))
        }

        let thirdRow = NSStackView()
        thirdRow.orientation = .horizontal
        thirdRow.spacing = 4
        thirdRow.distribution = .fillEqually
        for pose in [PetPose.skinBase, .interaksiBawah1, .interaksiBawah2, .moodIntense] {
            thirdRow.addArrangedSubview(poseButton(for: pose))
        }

        stack.orientation = .vertical
        stack.spacing = 4
        stack.distribution = .fillEqually
        stack.addArrangedSubview(firstRow)
        stack.addArrangedSubview(secondRow)
        stack.addArrangedSubview(thirdRow)
    }

    private func poseButton(for pose: PetPose) -> NSButton {
        let button = NSButton(title: pose.buttonLabel, target: self, action: #selector(poseTapped(_:)))
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = NSFont.systemFont(ofSize: 11)
        button.setButtonType(.momentaryPushIn)
        button.identifier = NSUserInterfaceItemIdentifier(pose.rawValue)
        poseButtons[pose] = button
        return button
    }

    func setCharacters(_ packs: [CharacterSprite.Pack], current id: String) {
        characterIDs = packs.map(\.id)
        characterPopup.removeAllItems()
        for pack in packs {
            characterPopup.addItem(withTitle: pack.label)
        }
        if let index = characterIDs.firstIndex(of: id) {
            characterPopup.selectItem(at: index)
        }
    }

    @objc private func characterChanged() {
        let index = characterPopup.indexOfSelectedItem
        guard characterIDs.indices.contains(index) else { return }
        onCharacter?(characterIDs[index])
    }

    func setStandby(_ choices: [CharacterSprite.StandbyChoice], current id: String) {
        standbyIDs = choices.map(\.id)
        standbyPopup.removeAllItems()
        for choice in choices {
            standbyPopup.addItem(withTitle: choice.label)
        }
        if let index = standbyIDs.firstIndex(of: id) {
            standbyPopup.selectItem(at: index)
        }
    }

    @objc private func standbyChanged() {
        let index = standbyPopup.indexOfSelectedItem
        guard standbyIDs.indices.contains(index) else { return }
        onStandby?(standbyIDs[index])
    }

    @objc private func poseTapped(_ sender: NSButton) {
        guard
            let raw = sender.identifier?.rawValue,
            let pose = PetPose.named(raw)
        else { return }
        highlight(pose: pose)
        onPose?(pose)
    }

    /// Menandai gestur yang sedang aktif.
    func highlight(pose: PetPose?) {
        for (candidate, button) in poseButtons {
            let isActive = candidate == pose
            button.bezelColor = isActive
                ? NSColor(srgbRed: 1.0, green: 0.68, blue: 0.28, alpha: 1)
                : nil
            button.contentTintColor = isActive ? .black : nil
        }
    }

    @objc private func sendTapped() {
        let text = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input.stringValue = ""
        onSend?(text)
    }

    @objc private func micTapped() {
        let isDown = NSApp.currentEvent?.type == .leftMouseDown
        if isDown {
            micButton.title = "🔴 Mendengarkan…"
            onMicDown?()
        } else {
            micButton.title = "🎤 Tahan untuk bicara"
            onMicUp?()
        }
    }

    @objc private func muteTapped() {
        let enabled = onToggleMute?() ?? true
        muteButton.title = enabled ? "🔊 Suara: Aktif" : "🔇 Suara: Mati"
    }

    @objc private func sizeChanged() {
        let value = CGFloat(sizeSlider.doubleValue)
        updateSizeValue(value)
        onScale?(value)
    }

    @objc private func modelChanged() {
        guard let title = modelPopup.titleOfSelectedItem, !title.isEmpty else { return }
        onModelChange?(title)
    }

    @objc private func agentChanged() {
        guard let title = agentPopup.titleOfSelectedItem, !title.isEmpty else { return }
        for agent in Brain.Agent.allCases where agent.displayName == title {
            onAgentChange?(agent)
            return
        }
    }

    @objc private func sessionChanged() {
        let value = sessionField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        onSessionChange?(value)
    }

    private func updateSizeValue(_ value: CGFloat) {
        sizeValue.stringValue = "\(Int((value * 100).rounded()))%"
    }

    // MARK: - API

    func append(role: String, text: String) {
        let color: NSColor
        switch role {
        case "kamu": color = NSColor(srgbRed: 0.55, green: 0.78, blue: 1.0, alpha: 1)
        case "pet": color = NSColor(srgbRed: 1.0, green: 0.72, blue: 0.35, alpha: 1)
        default: color = NSColor(white: 0.62, alpha: 1)
        }
        let head = NSAttributedString(string: "\(role)\n", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: color,
        ])
        let body = NSAttributedString(string: text + "\n\n", attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor(white: 0.93, alpha: 1),
        ])
        transcript.textStorage?.append(head)
        transcript.textStorage?.append(body)
        transcript.scrollToEndOfDocument(nil)
    }

    func setStatus(_ text: String) {
        statusLabel.stringValue = text
    }

    /// Menyinkronkan slider dengan ukuran pet saat ini.
    func setScaleValue(_ value: CGFloat) {
        sizeSlider.doubleValue = Double(value)
        updateSizeValue(value)
    }

    /// Mengisi daftar model dan menandai yang sedang aktif.
    func setModels(_ models: [String], current: String) {
        modelPopup.removeAllItems()
        modelPopup.addItems(withTitles: models)
        if models.contains(current) {
            modelPopup.selectItem(withTitle: current)
        } else if !current.isEmpty {
            modelPopup.addItem(withTitle: current)
            modelPopup.selectItem(withTitle: current)
        }
    }

    /// Menyinkronkan pilihan tanpa memicu callback.
    func setSelectedModel(_ model: String) {
        if modelPopup.itemTitles.contains(model) {
            modelPopup.selectItem(withTitle: model)
        }
    }

    /// Mengisi daftar agent dan menandai yang sedang aktif.
    func setAgents(current: Brain.Agent) {
        agentPopup.removeAllItems()
        agentPopup.addItems(withTitles: Brain.Agent.allCases.map { $0.displayName })
        agentPopup.selectItem(withTitle: current.displayName)
    }

    /// Menyinkronkan pilihan agent tanpa memicu callback.
    func setSelectedAgent(_ agent: Brain.Agent) {
        if agentPopup.itemTitles.contains(agent.displayName) {
            agentPopup.selectItem(withTitle: agent.displayName)
        }
    }

    /// Menampilkan kolom sesi Hermes hanya saat agent Hermes aktif.
    func setSessionRowVisible(_ visible: Bool) {
        sessionLabel.isHidden = !visible
        sessionField.isHidden = !visible
    }

    /// Mengisi kolom sesi tanpa memicu callback.
    func setSessionText(_ text: String) {
        if sessionField.stringValue != text {
            sessionField.stringValue = text
        }
    }

    func setInputText(_ text: String) {
        input.stringValue = text
    }

    func focusInput() {
        orderFrontRegardless()
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        makeFirstResponder(input)
        input.selectText(nil)
    }

    // MARK: - NSTextFieldDelegate

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if control === sessionField {
                sessionChanged()
            } else {
                sendTapped()
            }
            return true
        }
        return false
    }
}
