import AVFoundation
import Speech

/// Input suara: merekam mikrofon lalu mengubahnya jadi teks (Bahasa Indonesia).
final class VoiceInput {
    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "id-ID"))
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var transcript = ""

    private(set) var isRecording = false

    /// Meminta izin mikrofon + pengenalan suara. Hasil dipanggil di main thread.
    func requestPermission(_ completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        }
    }

    func start() {
        guard !isRecording else { return }
        guard let recognizer, recognizer.isAvailable else {
            onError?("Pengenal suara Bahasa Indonesia tidak tersedia.")
            return
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            onError?("Tidak ada mikrofon yang terdeteksi.")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        transcript = ""

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            onError?("Gagal membuka mikrofon: \(error.localizedDescription)")
            return
        }

        self.engine = engine
        self.request = request
        isRecording = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                self.transcript = text
                DispatchQueue.main.async { self.onPartial?(text) }
                if result.isFinal {
                    self.finish(with: text, error: nil)
                }
            }
            if let error {
                self.finish(with: self.transcript, error: error)
            }
        }
    }

    func stop() {
        guard isRecording else { return }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        request?.endAudio()
        finish(with: transcript, error: nil)
    }

    private func finish(with text: String, error: Error?) {
        guard isRecording else { return }
        isRecording = false
        task?.cancel()
        task = nil
        request = nil
        engine = nil

        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        DispatchQueue.main.async {
            if !cleaned.isEmpty {
                self.onFinal?(cleaned)
            } else if let error {
                self.onError?("Suara tidak terbaca: \(error.localizedDescription)")
            }
        }
    }
}
