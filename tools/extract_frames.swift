import AppKit
import CoreGraphics
import Foundation
import ImageIO

// pakai: extract_all <outdir> <sheet> <nama> [<sheet> <nama> ...]
// Memotong sprite sheet menjadi frame individual, menghapus latar magenta,
// menormalkan tinggi karakter, dan menyelaraskan tiap frame pada satu garis
// tumpu (kaki di bawah, badan di tengah).

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 3, args.count % 2 == 1 else {
    print("pakai: extract_all <outdir> <sheet> <nama> [<sheet> <nama> ...]")
    exit(1)
}
let outDir = args[0]
var inputs: [(path: String, name: String)] = []
var index = 1
while index + 1 < args.count {
    inputs.append((args[index], args[index + 1]))
    index += 2
}

let referenceHeight: Double = 640   // tinggi karakter setelah normalisasi (piksel)
let padding: Double = 16

// MARK: - Muat + kroma-key

struct Sheet {
    var name: String
    var width: Int
    var height: Int
    var image: CGImage
    var alpha: [UInt8]        // 1 = ada isi
    var storage: UnsafeMutablePointer<UInt8>   // dijaga tetap hidup selama program
}

func loadSheet(path: String, name: String) -> Sheet? {
    guard
        let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
        let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }

    let width = cgImage.width
    let height = cgImage.height
    let byteCount = width * height * 4

    // Dialokasikan manual: CGContext menyimpan pointer ini, jadi tidak boleh
    // menunjuk ke variabel lokal yang bisa dilepas.
    let storage = UnsafeMutablePointer<UInt8>.allocate(capacity: byteCount)
    storage.initialize(repeating: 0, count: byteCount)

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: storage, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    func pixel(_ x: Int, _ y: Int) -> (Int, Int, Int) {
        let i = (y * width + x) * 4
        return (Int(storage[i]), Int(storage[i + 1]), Int(storage[i + 2]))
    }
    let corners = [pixel(2, 2), pixel(width - 3, 2), pixel(2, height - 3), pixel(width - 3, height - 3)]
    let bg = (
        Double(corners.map { $0.0 }.reduce(0, +)) / 4,
        Double(corners.map { $0.1 }.reduce(0, +)) / 4,
        Double(corners.map { $0.2 }.reduce(0, +)) / 4
    )

    let t1 = 55.0, t2 = 130.0
    var alpha = [UInt8](repeating: 0, count: width * height)

    for y in 0..<height {
        for x in 0..<width {
            let i = (y * width + x) * 4
            let r = Double(storage[i]), g = Double(storage[i + 1]), b = Double(storage[i + 2])
            let dr = r - bg.0, dg = g - bg.1, db = b - bg.2
            let distance = (dr * dr + dg * dg + db * db).squareRoot()

            var a = (distance - t1) / (t2 - t1)
            a = min(max(a, 0), 1)
            if a <= 0 {
                storage[i] = 0; storage[i + 1] = 0; storage[i + 2] = 0; storage[i + 3] = 0
                continue
            }
            // F = (pixel - (1-a)*bg) / a  -> membuang sisa warna magenta di tepi
            let inv = 1 - a
            storage[i] = UInt8(min(max((r - inv * bg.0) / a, 0), 255))
            storage[i + 1] = UInt8(min(max((g - inv * bg.1) / a, 0), 255))
            storage[i + 2] = UInt8(min(max((b - inv * bg.2) / a, 0), 255))
            storage[i + 3] = UInt8(a * 255)
            alpha[y * width + x] = a > 0.1 ? 1 : 0
        }
    }

    guard let keyed = context.makeImage() else { return nil }
    return Sheet(
        name: name, width: width, height: height,
        image: keyed, alpha: alpha, storage: storage
    )
}

// MARK: - Deteksi frame & titik tumpu

struct Frame {
    var rect: CGRect
    var bodyCenterX: Double
    var contentBottom: Double
}

func detectFrames(_ sheet: Sheet) -> [Frame] {
    let w = sheet.width, h = sheet.height
    var columnContent = [Int](repeating: 0, count: w)
    for x in 0..<w {
        var count = 0
        for y in 0..<h where sheet.alpha[y * w + x] == 1 { count += 1 }
        columnContent[x] = count
    }

    var runs: [(Int, Int)] = []
    var start: Int?
    for x in 0..<w {
        let filled = columnContent[x] > 1
        if filled, start == nil { start = x }
        if !filled, let s = start { runs.append((s, x - 1)); start = nil }
    }
    if let s = start { runs.append((s, w - 1)) }
    runs = runs.filter { $0.1 - $0.0 >= 20 }

    var frames: [Frame] = []
    for (x0, x1) in runs {
        var minY = h, maxY = 0
        for y in 0..<h {
            var found = false
            for x in x0...x1 where sheet.alpha[y * w + x] == 1 { found = true; break }
            if found {
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxY > minY else { continue }

        // badan bawah (35%) -> pusat horizontal yang stabil walau tangan diangkat
        let bandStart = maxY - Int(Double(maxY - minY) * 0.35)
        var sum = 0, count = 0
        for y in bandStart...maxY {
            for x in x0...x1 where sheet.alpha[y * w + x] == 1 { sum += x; count += 1 }
        }
        let centerX = count > 0 ? Double(sum) / Double(count) : Double(x0 + x1) / 2

        frames.append(Frame(
            rect: CGRect(x: x0, y: minY, width: x1 - x0 + 1, height: maxY - minY + 1),
            bodyCenterX: centerX,
            contentBottom: Double(maxY)
        ))
    }
    return frames
}

// MARK: - Proses

struct Animation {
    var name: String
    var sheet: Sheet
    var frames: [Frame]
    var groundY: Double
    var anchorX: Double
    var scale: Double
}

var animations: [Animation] = []
for input in inputs {
    guard let sheet = loadSheet(path: input.path, name: input.name) else {
        print("gagal memuat \(input.path)"); continue
    }
    let frames = detectFrames(sheet)
    guard !frames.isEmpty else { print("\(input.name): tidak ada frame"); continue }

    // garis tumpu = kaki terendah pada animasi ini (menjaga lompatan tetap terlihat)
    let groundY = frames.map { $0.contentBottom }.max()!
    let sortedCenters = frames.map { $0.bodyCenterX }.sorted()
    let anchorX = sortedCenters[sortedCenters.count / 2]
    // acuan skala: frame pertama (pose netral)
    let h0 = Double(frames[0].rect.height)
    let scale = referenceHeight / h0

    animations.append(Animation(
        name: input.name, sheet: sheet, frames: frames,
        groundY: groundY, anchorX: anchorX, scale: scale
    ))
    print(String(format: "%-8s %2d frame  tinggi-netral=%4.0f  skala=%.3f",
                 (input.name as NSString).utf8String!, frames.count, h0, scale))
}

guard !animations.isEmpty else { exit(1) }

// kanvas bersama supaya ukuran pet konsisten antar animasi
var maxAbove = 0.0
var maxWidth = 0.0
for animation in animations {
    for frame in animation.frames {
        maxAbove = max(maxAbove, (animation.groundY - Double(frame.rect.minY)) * animation.scale)
        maxWidth = max(maxWidth, Double(frame.rect.width) * animation.scale)
    }
}
let canvasW = Int(maxWidth + padding * 2)
let canvasH = Int(maxAbove + padding * 2)
print("kanvas: \(canvasW)x\(canvasH)")

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let colorSpace = CGColorSpaceCreateDeviceRGB()
var manifest: [[String: Any]] = []

for animation in animations {
    let directory = "\(outDir)/\(animation.name)"
    try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

    for (i, frame) in animation.frames.enumerated() {
        guard let crop = animation.sheet.image.cropping(to: frame.rect) else { continue }
        guard let canvas = CGContext(
            data: nil, width: canvasW, height: canvasH,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { continue }
        canvas.interpolationQuality = .high

        let scaledW = Double(frame.rect.width) * animation.scale
        let scaledH = Double(frame.rect.height) * animation.scale
        // titik tumpu horizontal dihitung per frame (tiap frame punya posisi
        // sendiri di dalam sheet); garis kaki memakai acuan animasi agar
        // lompatan tetap terlihat.
        let offsetX = (frame.bodyCenterX - Double(frame.rect.minX)) * animation.scale
        let offsetY = (animation.groundY - Double(frame.rect.minY)) * animation.scale

        // origin kiri-atas pada kanvas
        let left = Double(canvasW) / 2 - offsetX
        let top = Double(canvasH) - padding - offsetY
        let bottom = Double(canvasH) - top - scaledH

        canvas.draw(crop, in: CGRect(x: left, y: bottom, width: scaledW, height: scaledH))

        guard let out = canvas.makeImage(),
              let dest = CGImageDestinationCreateWithURL(
                URL(fileURLWithPath: String(format: "%@/%02d.png", directory, i)) as CFURL,
                "public.png" as CFString, 1, nil
              ) else { continue }
        CGImageDestinationAddImage(dest, out, nil)
        CGImageDestinationFinalize(dest)
    }
    manifest.append(["name": animation.name, "frames": animation.frames.count])
}

let manifestData = try? JSONSerialization.data(
    withJSONObject: ["canvas": ["width": canvasW, "height": canvasH], "animations": manifest],
    options: [.prettyPrinted, .sortedKeys]
)
try? manifestData?.write(to: URL(fileURLWithPath: "\(outDir)/manifest.json"))
print("selesai -> \(outDir)")
