#!/usr/bin/env swift
import AppKit
import CoreImage
import Foundation
import ImageIO
import Vision

// Extract the full-canvas foreground from every PNG in a source directory.
// Usage: swift tools/extract_ironman_foreground.swift [source-dir] [cutout-dir]
// The Vision mask is applied without cropping or changing the source canvas.

let sourceDir = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    : URL(fileURLWithPath: "artwork/iron-man-action/local-frames", isDirectory: true)
let outputDir = CommandLine.arguments.count > 2
    ? URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    : URL(fileURLWithPath: "artwork/iron-man-action/cutouts", isDirectory: true)
let fileManager = FileManager.default
let ciContext = CIContext(options: [.useSoftwareRenderer: false])

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw NSError(domain: "IronManForeground", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Could not create PNG destination: \(url.path)"])
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "IronManForeground", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Could not write PNG: \(url.path)"])
    }
}

func foregroundMask(_ observation: VNInstanceMaskObservation,
                    handler: VNImageRequestHandler,
                    imageRect: CGRect) throws -> CIImage {
    let buffer = try observation.generateMaskedImage(ofInstances: observation.allInstances,
                                                     from: handler,
                                                     croppedToInstancesExtent: false)
    let cutout = CIImage(cvPixelBuffer: buffer).cropped(to: imageRect)
    // CIBlendWithMask reads the mask's grayscale color values. Convert Vision's
    // colored cutout to white, then composite over black so its alpha becomes
    // grayscale coverage rather than accidentally using the source colors.
    let white = cutout.applyingFilter("CIColorMatrix", parameters: [
        "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0)
    ])
    return white.composited(over: CIImage(color: .black).cropped(to: imageRect))
        .cropped(to: imageRect)
}

guard fileManager.fileExists(atPath: sourceDir.path) else {
    fputs("Source directory not found: \(sourceDir.path)\n", stderr)
    exit(1)
}
let inputs = try fileManager.contentsOfDirectory(at: sourceDir,
                                                 includingPropertiesForKeys: [.isRegularFileKey],
                                                 options: [.skipsHiddenFiles])
    .filter { $0.pathExtension.lowercased() == "png" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
guard !inputs.isEmpty else {
    fputs("No PNG frames found in \(sourceDir.path)\n", stderr)
    exit(1)
}
try fileManager.createDirectory(at: outputDir, withIntermediateDirectories: true)

for input in inputs {
    guard let imageSource = CGImageSourceCreateWithURL(input as CFURL, nil),
          let sourceImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
        throw NSError(domain: "IronManForeground", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "Could not read input PNG: \(input.path)"])
    }
    let imageRect = CGRect(x: 0, y: 0, width: sourceImage.width, height: sourceImage.height)
    let handler = VNImageRequestHandler(cgImage: sourceImage, options: [:])
    let request = VNGenerateForegroundInstanceMaskRequest()
    try handler.perform([request])
    guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
        throw NSError(domain: "IronManForeground", code: 4,
                      userInfo: [NSLocalizedDescriptionKey: "Vision found no foreground instances in \(input.lastPathComponent)"])
    }
    let mask = try foregroundMask(observation, handler: handler, imageRect: imageRect)
    // Use the original pixels with Vision's soft mask, preserving every source
    // coordinate so shared baselines and jump heights remain aligned.
    let cutout = CIImage(cgImage: sourceImage).applyingFilter("CIBlendWithMask", parameters: [
        kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: imageRect),
        kCIInputMaskImageKey: mask
    ]).cropped(to: imageRect)
    guard let result = ciContext.createCGImage(cutout, from: imageRect),
          result.width == sourceImage.width, result.height == sourceImage.height else {
        throw NSError(domain: "IronManForeground", code: 5,
                      userInfo: [NSLocalizedDescriptionKey: "Could not render full-canvas cutout for \(input.lastPathComponent)"])
    }
    try writePNG(result, to: outputDir.appendingPathComponent(input.lastPathComponent))
    print("\(input.lastPathComponent): \(sourceImage.width)x\(sourceImage.height), \(observation.allInstances.count) foreground instance(s), full canvas preserved")
}
