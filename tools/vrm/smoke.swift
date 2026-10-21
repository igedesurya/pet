import AppKit
import WebKit
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 350, height: 500), styleMask: [.borderless], backing: .buffered, defer: false)
let view = VRMView()
window.contentView = view
window.orderBack(nil)
var completed = false
let expectFailure = CommandLine.arguments.contains("--expect-failure")
view.onError = { message in
    print(expectFailure ? "PASS: invalid model rejected: \(message)" : "FAIL: \(message)")
    fflush(stdout); exit(expectFailure ? 0 : 1)
}
view.onLoaded = {
    if expectFailure { print("FAIL: invalid model was accepted"); exit(1) }
    print("PASS: VRM loaded in WKWebView using local scheme")
    view.evaluateJavaScript("window.pet3D.play('waving', 3)") { value, error in
        guard error == nil, value as? Bool == true else { print("FAIL: wave \(String(describing: error))"); exit(1) }
        print("PASS: wave accepted")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            view.takeSnapshot(with: nil) { image, error in
                guard let image, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { print("FAIL: snapshot"); exit(1) }
                try! png.write(to: URL(fileURLWithPath: "/tmp/pet-vrm-wave.png"))
                guard bitmap.colorAt(x: 0, y: 0)?.alphaComponent == 0 else { print("FAIL: background not transparent"); exit(1) }
                guard view.hitTest(NSPoint(x: 10, y: 10)) == nil else { print("FAIL: mouse events intercepted"); exit(1) }
                print("PASS: transparent background and mouse passthrough")
                completed = true
                print("PASS: rendered snapshot"); fflush(stdout); exit(0)
            }
        }
    }
}
view.open(URL(fileURLWithPath: CommandLine.arguments[1]))
DispatchQueue.main.asyncAfter(deadline: .now() + 25) { if !completed { print("FAIL: load timeout"); fflush(stdout); exit(1) } }
app.run()
