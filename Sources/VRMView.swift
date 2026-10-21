import AppKit
import WebKit

/// A local-only WebGL renderer. Mouse events remain owned by PetView.
private final class VRMBridge: NSObject, WKScriptMessageHandler, WKURLSchemeHandler {
    weak var owner: VRMView?
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.receive(message)
    }
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) { owner?.serve(task) }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

final class VRMView: WKWebView {
    static let preferenceKey = "pet.vrm.path"
    static var clips: Set<String> { VRMMotion.names }
    var onLoaded: (() -> Void)?
    var onError: ((String) -> Void)?
    private var modelURL: URL?
    private var ready = false
    private var currentState = "idle"

    init() {
        let config = WKWebViewConfiguration()
        let bridge = VRMBridge()
        config.userContentController.add(bridge, name: "vrm")
        config.setURLSchemeHandler(bridge, forURLScheme: "pet-vrm")
        super.init(frame: .zero, configuration: config)
        bridge.owner = self
        setValue(false, forKey: "drawsBackground")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func open(_ url: URL) {
        modelURL = url
        if ready { loadModel() }
        else { load(URLRequest(url: URL(string: "pet-vrm://local/index.html")!)) }
    }
    func setState(_ state: String) {
        currentState = state
        if ready { evaluateJavaScript("window.pet3D.setState(\(json(state)))", completionHandler: nil) }
    }
    func play(_ name: String, duration: Double) {
        guard ready else { return }
        evaluateJavaScript("window.pet3D.play(\(json(name)), \(max(0.1, duration)))", completionHandler: nil)
    }
    private func json(_ text: String) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: text, options: [.fragmentsAllowed]), encoding: .utf8)!
    }
    private func loadModel() {
        evaluateJavaScript("window.pet3D.load('pet-vrm://local/avatar.vrm')", completionHandler: nil)
    }
    func receive(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: String] else { return }
        switch body["type"] {
        case "ready": ready = true; setState(currentState); loadModel()
        case "loaded": onLoaded?()
        case "error": onError?(body["message"] ?? "Gagal memuat VRM.")
        default: break
        }
    }
    func serve(_ urlSchemeTask: WKURLSchemeTask) {
        let path = urlSchemeTask.request.url?.path ?? ""
        let file: URL?
        let mime: String
        switch path {
        case "/avatar.vrm": file = modelURL; mime = "model/gltf-binary"
        case "/index.html": file = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "vrm"); mime = "text/html"
        case "/viewer.js": file = Bundle.main.url(forResource: "viewer", withExtension: "js", subdirectory: "vrm"); mime = "application/javascript"
        default: file = nil; mime = "application/octet-stream"
        }
        do {
            guard let file else { throw NSError(domain: "PetVRM", code: 404) }
            let data = try Data(contentsOf: file)
            urlSchemeTask.didReceive(URLResponse(url: urlSchemeTask.request.url!, mimeType: mime, expectedContentLength: data.count, textEncodingName: mime == "model/gltf-binary" ? nil : "utf-8"))
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch { urlSchemeTask.didFailWithError(error) }
    }
    func close() {
        stopLoading()
        configuration.userContentController.removeScriptMessageHandler(forName: "vrm")
        removeFromSuperview()
    }
}
