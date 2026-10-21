import AppKit
import ImageIO
import UniformTypeIdentifiers

let source = CommandLine.arguments[1]
let root = URL(fileURLWithPath: CommandLine.arguments[2])
let image = NSImage(contentsOfFile: source)!
var bounds = CGRect(origin: .zero, size: image.size)
let sheet = image.cgImage(forProposedRect: &bounds, context: nil, hints: nil)!
let sword = CommandLine.arguments.count > 3 && CommandLine.arguments[3] == "sword"
let names = sword ? ["sword_swing"] : ["idle", "standby_blink", "standby_look", "standby_weight", "standby_nod"]
let width = 320, height = 352
func save(_ image: CGImage, _ url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    precondition(CGImageDestinationFinalize(dest))
}
for row in 0..<names.count {
    let dir = root.appendingPathComponent(names[row])
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var poses: [CGImage] = []
    for col in 0..<(sword ? 9 : 4) {
        let columns = sword ? 3 : 4, rows = sword ? 3 : 5
        let cellX = sword ? col % 3 : col, cellY = sword ? col / 3 : row
        let x0 = cellX * sheet.width / columns, x1 = (cellX + 1) * sheet.width / columns
        let y0 = cellY * sheet.height / rows, y1 = (cellY + 1) * sheet.height / rows
        let tile = sheet.cropping(to: CGRect(x: x0, y: y0, width: x1-x0, height: y1-y0))!
        let w = tile.width, h = tile.height
        var pixels = [UInt8](repeating: 0, count: w*h*4)
        let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(tile, in: CGRect(x: 0, y: 0, width: w, height: h))
        var visited = [Bool](repeating: false, count: w*h)
        var largest: [Int] = []
        for start in 0..<(w*h) where !visited[start] && pixels[start*4+3] > 20 {
            var component = [start], cursor = 0
            visited[start] = true
            while cursor < component.count {
                let p = component[cursor]; cursor += 1
                let px = p % w, py = p / w
                for dy in -1...1 { for dx in -1...1 {
                    let nx = px+dx, ny = py+dy
                    if nx < 0 || nx >= w || ny < 0 || ny >= h { continue }
                    let n = ny*w+nx
                    if !visited[n] && pixels[n*4+3] > 20 {
                        visited[n] = true; component.append(n)
                    }
                }}
            }
            if component.count > largest.count { largest = component }
        }
        var keep = [Bool](repeating: false, count: w*h)
        for p in largest { keep[p] = true }
        for p in 0..<(w*h) where !keep[p] {
            for channel in 0..<4 { pixels[p*4+channel] = 0 }
        }
        var minX = w, minY = h, maxX = 0, maxY = 0
        for y in 0..<h { for x in 0..<w where pixels[(y*w+x)*4+3] > 40 {
            minX = min(minX,x); maxX = max(maxX,x); minY = min(minY,y); maxY = max(maxY,y)
        }}
        precondition(minX < maxX && minY < maxY)
        // CGContext pixels are bottom-up; CGImage crop coordinates are top-down.
        let clean = ctx.makeImage()!
        let tight = clean.cropping(to: CGRect(x: minX, y: minY, width: maxX-minX+1, height: maxY-minY+1))!
        let out = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let scale = min(280.0 / Double(tight.width), 312.0 / Double(tight.height))
        let dw = Double(tight.width)*scale, dh = Double(tight.height)*scale
        out.interpolationQuality = .high
        out.draw(tight, in: CGRect(x: (Double(width)-dw)/2, y: 20, width: dw, height: dh))
        poses.append(out.makeImage()!)
    }
    var sequence: [Int] = []
    if sword {
        sequence = Array(repeating: 0, count: 6)
        sequence += [1,2,3,4,5,6,7]
        sequence += Array(repeating: 8, count: 6)
    } else if row == 1 {
        sequence = Array(repeating: 0, count: 20) + [1,2,1]
        sequence += Array(repeating: 3, count: 9)
    } else {
        sequence = Array(repeating: 0, count: 8)
        sequence += Array(repeating: 1, count: 6)
        sequence += Array(repeating: 2, count: 6)
        sequence += Array(repeating: 3, count: 12)
    }
    for (index, pose) in sequence.enumerated() {
        save(poses[pose], dir.appendingPathComponent(String(format: "%02d.png", index)))
    }
    let meta: [String: Any] = ["frame_duration": 0.125, "loops": true]
    try JSONSerialization.data(withJSONObject: meta, options: .prettyPrinted).write(to: dir.appendingPathComponent("animation.json"))
}
var pack: [String: Any] = ["label": "Ksatria Kecil", "description": "Lima gerakan standby chibi.", "modes": [["id": "standby", "label": "Standby Santai", "clips": names]]]
if sword {
    pack = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("pack.json"))) as! [String: Any]
    var modes = pack["modes"] as! [[String: Any]]
    modes.removeAll { $0["id"] as? String == "sword" }
    if let index = modes.firstIndex(where: { $0["id"] as? String == "standby" }) {
        var clips = modes[index]["clips"] as? [String] ?? []
        for name in names where !clips.contains(name) { clips.append(name) }
        modes[index]["clips"] = clips
        modes[index]["label"] = "Standby"
    } else {
        modes.append(["id": "standby", "label": "Standby", "clips": names])
    }
    pack["modes"] = modes
}
try JSONSerialization.data(withJSONObject: pack, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("pack.json"))
print("Exported \(names.count) clips, 320x352 RGBA; source \(sheet.width)x\(sheet.height)")
