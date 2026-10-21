import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 230,height: 260), styleMask: [.borderless],backing: .buffered,defer: false)
let pet = PetView(frame: window.contentView!.bounds)
window.contentView = pet
window.orderBack(nil)
pet.startAnimating()
pet.onVRMError = { message in print("FAIL: \(message)"); exit(1) }
pet.useVRM(URL(fileURLWithPath: "/tmp/pet-vrm-test.vrm"))
var attempts = 0
let timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { timer in
    attempts += 1
    if pet.is3D {
        guard pet.playSequence(["waving"]), pet.activeClipName == "waving", !pet.playSequence(["sitting"]), !pet.playSequence(["waving", "idle"]) else { print("FAIL: gesture routing"); exit(1) }
        pet.scale = 1.4
        pet.layoutSubtreeIfNeeded()
        guard pet.subviews.last?.frame == pet.catRect else { print("FAIL: 3D layout"); exit(1) }
        pet.useSprites()
        guard !pet.is3D, pet.subviews.isEmpty else { print("FAIL: PNG restore"); exit(1) }
        print("PASS: hidden import, gesture routing, resize, PNG restore")
        fflush(stdout); exit(0)
    }
    if attempts > 120 { print("FAIL: hidden load timeout"); exit(1) }
}
app.run()
