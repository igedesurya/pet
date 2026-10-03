import AppKit
import ImageIO

// Split a transparent six-cell animation strip into the existing 960×1040 canvas.
// Keep one scale and baseline for the whole strip, preserving motion between frames.
let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 2,
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[0]) as CFURL, nil),
      let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil) else { exit(1) }
let output = URL(fileURLWithPath: args[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let count = 6
let poseScale = output.lastPathComponent == "home_sleeping" ? 0.75 : 1.0
let scale = min(960.0 / (Double(sheet.width) / Double(count)), 1040.0 / Double(sheet.height)) * poseScale
for index in 0..<count {
    let left = index * sheet.width / count
    let right = (index + 1) * sheet.width / count
    guard let frame = sheet.cropping(to: CGRect(x: left, y: 0, width: right-left, height: sheet.height)),
          let canvas = CGContext(data: nil, width: 960, height: 1040,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
    canvas.interpolationQuality = .high
    let width = Double(frame.width) * scale
    let height = Double(frame.height) * scale
    canvas.draw(frame, in: CGRect(x: (960-width)/2, y: 0, width: width, height: height))
    // Discard isolated alpha islands introduced around the generated cutout.
    // Retain the main connected character and props without altering their colors.
    let pixels = canvas.data!.assumingMemoryBound(to: UInt8.self)
    let stride = canvas.bytesPerRow
    var seen = [Bool](repeating: false, count: 960*1040)
    var components = [[Int]]()
    for start in 0..<seen.count where !seen[start] {
        seen[start] = true
        guard pixels[(start/960)*stride+(start%960)*4+3] > 200 else { continue }
        var component = [start]
        var cursor = 0
        while cursor < component.count {
            let p = component[cursor]; cursor += 1
            let x = p%960, y = p/960
            for dy in -1...1 {
                for dx in -1...1 {
                    let nx = x+dx, ny = y+dy
                    guard nx >= 0, nx < 960, ny >= 0, ny < 1040 else { continue }
                    let next = ny*960+nx
                    guard !seen[next] else { continue }
                    seen[next] = true
                    if pixels[ny*stride+nx*4+3] > 200 { component.append(next) }
                }
            }
        }
        components.append(component)
    }
    var keep = [Bool](repeating: false, count: 960*1040)
    for p in components.max(by: { $0.count < $1.count }) ?? [] {
        for dy in -2...2 {
            for dx in -2...2 {
                let x = p%960+dx, y = p/960+dy
                if x >= 0, x < 960, y >= 0, y < 1040 { keep[y*960+x] = true }
            }
        }
    }
    for p in 0..<keep.count where !keep[p] {
        let offset = (p/960)*stride+(p%960)*4
        for c in 0..<4 { pixels[offset+c] = 0 }
    }
    guard let image = canvas.makeImage(),
          let destination = CGImageDestinationCreateWithURL(
            output.appendingPathComponent(String(format: "%02d.png", index)) as CFURL,
            "public.png" as CFString, 1, nil) else { exit(1) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { exit(1) }
}
print("Saved six transparent 960×1040 frames to \(output.path)")
