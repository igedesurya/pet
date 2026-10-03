#!/usr/bin/env swift
import AppKit
import CoreImage
import Foundation
import ImageIO
import Vision

// Isolate Friday activity subjects with the system Vision saliency model.
// Usage: swift tools/extract_friday_foreground.swift [source-dir] [output-dir]
// Requires macOS 14 or later (VNGenerateForegroundInstanceMaskRequest).

let sourceDir = CommandLine.arguments.count > 1 ? URL(fileURLWithPath: CommandLine.arguments[1]) : URL(fileURLWithPath: "artwork/friday-activities-natural")
let outputDir = CommandLine.arguments.count > 2 ? URL(fileURLWithPath: CommandLine.arguments[2]) : URL(fileURLWithPath: "artwork/friday-animation-masks")
let cutoutDir = outputDir.appendingPathComponent("cutouts", isDirectory: true)
let maskDir = outputDir.appendingPathComponent("masks", isDirectory: true)
let diagnosticDir = outputDir.appendingPathComponent("instances", isDirectory: true)
try FileManager.default.createDirectory(at: cutoutDir, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: maskDir, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: diagnosticDir, withIntermediateDirectories: true)
for url in try FileManager.default.contentsOfDirectory(at: diagnosticDir, includingPropertiesForKeys: nil) {
    try FileManager.default.removeItem(at: url)
}
let ciContext = CIContext(options: [.useSoftwareRenderer: false])
let approved = ["home_waking_up.png", "home_cooking_stir.png", "home_sweeping.png", "home_watering_plants.png", "home_hanging_laundry.png"]

// Small action-prop regions guide an extra Vision pass where the main subject
// suppresses an overlapping prop. Rectangles use top-left source-image pixels.
let supportCrops: [String: [(String, CGRect)]] = [
    "home_cooking_stir": [("pot", CGRect(x: 615, y: 1030, width: 409, height: 506)), ("stove", CGRect(x: 700, y: 1360, width: 250, height: 110))],
    "home_watering_plants": [("front_planter", CGRect(x: 700, y: 1040, width: 324, height: 496))]
]

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { throw NSError(domain: "FridayMatte", code: 1) }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "FridayMatte", code: 2) }
}

func foregroundImage(_ observation: VNInstanceMaskObservation, handler: VNImageRequestHandler) throws -> CIImage {
    let imageBuffer = try observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: false)
    return CIImage(cvPixelBuffer: imageBuffer)
}

func whiteSilhouette(_ rgba: CIImage) -> CIImage {
    // Preserve only the Vision alpha and make foreground pixels white.
    rgba.applyingFilter("CIColorMatrix", parameters: [
        "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0)
    ])
}

func alphaFromGray(_ gray: CIImage) -> CIImage {
    gray.applyingFilter("CIColorMatrix", parameters: [
        "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        "inputAVector": CIVector(x: 1, y: 0, z: 0, w: 0),
        "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0)
    ])
}

func cropImage(_ image: CGImage, topLeftRect: CGRect) -> (CGImage, CGRect)? {
    let ciRect = CGRect(x: topLeftRect.minX, y: CGFloat(image.height) - topLeftRect.maxY, width: topLeftRect.width, height: topLeftRect.height)
    guard let patch = ciContext.createCGImage(CIImage(cgImage: image).cropped(to: ciRect), from: ciRect) else { return nil }
    return (patch, ciRect)
}

func bedSupportMask(width: Int, height: Int) -> CIImage? {
    // Visible bedding only: narrow exposed side and lower/right quilt margins.
    // The Vision person matte remains on top wherever the woman overlaps these regions.
    let colorSpace = CGColorSpaceCreateDeviceGray()
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
    ctx.setFillColor(gray: 0, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.translateBy(x: 0, y: CGFloat(height)); ctx.scaleBy(x: 1, y: -1) // draw with top-left image coordinates
    ctx.setFillColor(gray: 1, alpha: 1)
    let polygons: [[CGPoint]] = [
        [CGPoint(x: 0,y: 735), CGPoint(x: 100,y: 720), CGPoint(x: 190,y: 775), CGPoint(x: 218,y: 1040), CGPoint(x: 220,y: 1315), CGPoint(x: 255,y: 1428), CGPoint(x: 558,y: 1452), CGPoint(x: 555,y: 1536), CGPoint(x: 0,y: 1536)],
        [CGPoint(x: 812,y: 840), CGPoint(x: 1024,y: 820), CGPoint(x: 1024,y: 1370), CGPoint(x: 950,y: 1378), CGPoint(x: 876,y: 1300), CGPoint(x: 837,y: 1120)]
    ]
    for points in polygons {
        let path = CGMutablePath(); path.addLines(between: points); path.closeSubpath(); ctx.addPath(path); ctx.fillPath()
    }
    guard let cg = ctx.makeImage() else { return nil }
    return CIImage(cgImage: cg)
}

var contactItems: [(String, CGImage)] = []
for name in approved {
    let input = sourceDir.appendingPathComponent(name)
    guard let imageSource = CGImageSourceCreateWithURL(input as CFURL, nil), let sourceImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
        fputs("Could not read \(input.path)\n", stderr); continue
    }
    let stem = input.deletingPathExtension().lastPathComponent
    let imageRect = CGRect(x: 0, y: 0, width: sourceImage.width, height: sourceImage.height)
    let handler = VNImageRequestHandler(cgImage: sourceImage, options: [:])
    let request = VNGenerateForegroundInstanceMaskRequest()
    try handler.perform([request])
    guard let observation = request.results?.first else { fputs("No instances in \(name)\n", stderr); continue }

    var matte = CIImage(color: .black).cropped(to: imageRect)
    let main = try foregroundImage(observation, handler: handler).cropped(to: imageRect)
    matte = whiteSilhouette(main).composited(over: matte)
    var supportCount = 0

    for (label, topLeftRect) in supportCrops[stem] ?? [] {
        guard let (patch, ciRect) = cropImage(sourceImage, topLeftRect: topLeftRect) else { continue }
        let patchHandler = VNImageRequestHandler(cgImage: patch, options: [:])
        let patchRequest = VNGenerateForegroundInstanceMaskRequest()
        try patchHandler.perform([patchRequest])
        guard let patchObservation = patchRequest.results?.first else { continue }
        let patchCutout = try foregroundImage(patchObservation, handler: patchHandler)
        if let diagnostic = ciContext.createCGImage(patchCutout, from: patchCutout.extent) {
            try writePNG(diagnostic, to: diagnosticDir.appendingPathComponent("\(stem)_support_\(label).png"))
        }
        let isolated = patchCutout
            .transformed(by: CGAffineTransform(translationX: ciRect.minX, y: ciRect.minY))
            .cropped(to: imageRect)
        matte = whiteSilhouette(isolated).composited(over: matte)
        supportCount += patchObservation.allInstances.count
    }

    if stem == "home_waking_up", let bedMask = bedSupportMask(width: sourceImage.width, height: sourceImage.height) {
        matte = alphaFromGray(bedMask).composited(over: matte)
        supportCount += 1
    }

    matte = matte.cropped(to: imageRect)
    let cutout = sourceImageCI(sourceImage).applyingFilter("CIBlendWithMask", parameters: [
        kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: imageRect),
        kCIInputMaskImageKey: matte
    ]).cropped(to: imageRect)
    guard let rgba = ciContext.createCGImage(cutout, from: imageRect), let mask = ciContext.createCGImage(matte, from: imageRect) else {
        fputs("Could not render final matte for \(stem)\n", stderr); continue
    }
    try writePNG(rgba, to: cutoutDir.appendingPathComponent("\(stem).png"))
    try writePNG(mask, to: maskDir.appendingPathComponent("\(stem).png"))
    contactItems.append((stem, rgba))
    print("\(stem): \(sourceImage.width)x\(sourceImage.height), \(observation.allInstances.count) Vision foreground instance(s), \(supportCount) prop-support pass(es)")
}

func sourceImageCI(_ image: CGImage) -> CIImage { CIImage(cgImage: image) }

// Compact visual review sheet on a checkerboard so transparent edges stay visible.
if !contactItems.isEmpty {
    let cellW = 256, cellH = 384, titleH = 28, gap = 12
    let sheetW = contactItems.count * cellW + (contactItems.count + 1) * gap
    let sheetH = cellH + titleH + 2 * gap
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: sheetW, pixelsHigh: sheetH, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor(calibratedWhite: 0.88, alpha: 1).setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: sheetW, height: sheetH)).fill()
    for (index, item) in contactItems.enumerated() {
        let x = gap + index * (cellW + gap)
        let box = NSRect(x: x, y: gap + titleH, width: cellW, height: cellH)
        let tile = 16
        for row in 0..<(cellH / tile) {
            for column in 0..<(cellW / tile) {
                NSColor(calibratedWhite: ((row + column) % 2 == 0) ? 0.94 : 0.78, alpha: 1).setFill()
                NSBezierPath(rect: NSRect(x: box.minX + CGFloat(column * tile), y: box.minY + CGFloat(row * tile), width: CGFloat(tile), height: CGFloat(tile))).fill()
            }
        }
        let cell = NSImage(cgImage: item.1, size: NSSize(width: cellW, height: cellH))
        cell.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1)
        let title = item.0 as NSString
        title.draw(at: NSPoint(x: x + 2, y: gap), withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.black])
    }
    NSGraphicsContext.restoreGraphicsState()
    if let data = rep.representation(using: .png, properties: [:]), let dest = CGImageSourceCreateWithData(data as CFData, nil), let sheet = CGImageSourceCreateImageAtIndex(dest, 0, nil) {
        try writePNG(sheet, to: outputDir.appendingPathComponent("contact-sheet.png"))
    }
}
