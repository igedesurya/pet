import AppKit
import ImageIO

let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 2 else { exit(1) }
let directory = URL(fileURLWithPath: args[0])
let frames = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "png" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
guard let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL,
    "com.compuserve.gif" as CFString, frames.count, nil) else { exit(1) }
CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary:
    [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for frame in frames {
    guard let source = CGImageSourceCreateWithURL(frame as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let canvas = CGContext(data: nil, width: 360, height: 390, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
    canvas.setFillColor(CGColor(red: 0.91, green: 0.92, blue: 0.94, alpha: 1))
    canvas.fill(CGRect(x: 0, y: 0, width: 360, height: 390))
    canvas.interpolationQuality = .high
    canvas.draw(image, in: CGRect(x: 0, y: 0, width: 360, height: 390))
    CGImageDestinationAddImage(destination, canvas.makeImage()!, [kCGImagePropertyGIFDictionary:
        [kCGImagePropertyGIFDelayTime: 5.0 / Double(frames.count)]] as CFDictionary)
}
guard CGImageDestinationFinalize(destination) else { exit(1) }
print("Saved \(args[1])")
