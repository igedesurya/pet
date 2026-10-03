#!/usr/bin/env swift
import AppKit
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

// Render the approved Iron Man reference as articulated bitmap animation.
// Usage: swift tools/render_ironman_rig.swift [reference.png] [frames-dir] [rig-dir] [--clips=a,b,...]

let referenceURL = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "artwork/iron-man-action/rig/reference.png")
let framesRoot = URL(fileURLWithPath: CommandLine.arguments.count > 2
    ? CommandLine.arguments[2] : "artwork/iron-man-action/rig-frames", isDirectory: true)
let rigRoot = URL(fileURLWithPath: CommandLine.arguments.count > 3
    ? CommandLine.arguments[3] : "artwork/iron-man-action/rig", isDirectory: true)
let canvasWidth = 960
let canvasHeight = 1040
let sourceWidth = 512
let sourceHeight = 768
let rigCanvasWidth = 1600
let rigCanvasHeight = 1600
let rigOffset = CGPoint(x: 544, y: 416)
let frameRate = 30
let frameCount = 60
let cycleSeconds = 2.0
let renderScale: CGFloat = 1.08
let placementX = (CGFloat(canvasWidth) - CGFloat(sourceWidth) * renderScale) / 2
let placementY: CGFloat = 140
let pelvis = CGPoint(x: 235, y: 418)

func fail(_ message: String) -> Never {
    fputs("render_ironman_rig: \(message)\n", stderr)
    exit(1)
}
func log(_ message: String) {
    print(message)
    fflush(stdout)
}

func requireContext(width: Int, height: Int) -> CGContext {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                      CGBitmapInfo.byteOrder32Big.rawValue) else {
        fail("Could not allocate \(width)x\(height) bitmap context")
    }
    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    return context
}

func quartzPoint(_ point: CGPoint, height: Int = sourceHeight) -> CGPoint {
    CGPoint(x: point.x, y: CGFloat(height) - point.y)
}

func writePNG(_ image: CGImage, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL,
                                                            "public.png" as CFString, 1, nil) else {
        throw NSError(domain: "IronManRig", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Could not create \(url.path)"])
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "IronManRig", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Could not write \(url.path)"])
    }
}

struct Part {
    let name: String
    let image: CGImage
    let rect: CGRect
}

func capsule(from start: CGPoint, to end: CGPoint, radius: CGFloat) -> [CGPoint] {
    let dx = end.x - start.x, dy = end.y - start.y
    let angle = atan2(dy, dx)
    var points: [CGPoint] = []
    for step in 0...12 {
        let theta = angle - .pi/2 + .pi * CGFloat(step) / 12
        points.append(CGPoint(x: end.x + radius*cos(theta), y: end.y + radius*sin(theta)))
    }
    for step in 0...12 {
        let theta = angle + .pi/2 + .pi * CGFloat(step) / 12
        points.append(CGPoint(x: start.x + radius*cos(theta), y: start.y + radius*sin(theta)))
    }
    return points
}

let jointPolygons: [String: [[CGPoint]]] = [
    "head": [[CGPoint(x: 206,y: 26), CGPoint(x: 263,y: 24), CGPoint(x: 275,y: 43),
              CGPoint(x: 274,y: 92), CGPoint(x: 261,y: 116), CGPoint(x: 255,y: 145),
              CGPoint(x: 214,y: 145), CGPoint(x: 209,y: 119), CGPoint(x: 199,y: 93),
              CGPoint(x: 200,y: 49)]],
    "left_upper_arm": [[CGPoint(x: 144,y: 126), CGPoint(x: 173,y: 124), CGPoint(x: 194,y: 143),
                        CGPoint(x: 185,y: 164), CGPoint(x: 173,y: 187), CGPoint(x: 163,y: 213),
                        CGPoint(x: 154,y: 241), CGPoint(x: 139,y: 265), CGPoint(x: 117,y: 260),
                        CGPoint(x: 121,y: 227), CGPoint(x: 126,y: 192), CGPoint(x: 131,y: 159)],
                       capsule(from: CGPoint(x: 165,y: 173), to: CGPoint(x: 135,y: 257), radius: 27)],
    "right_upper_arm": [[CGPoint(x: 304,y: 122), CGPoint(x: 337,y: 128), CGPoint(x: 360,y: 142),
                         CGPoint(x: 371,y: 166), CGPoint(x: 365,y: 192), CGPoint(x: 365,y: 219),
                         CGPoint(x: 376,y: 247), CGPoint(x: 363,y: 267), CGPoint(x: 340,y: 254),
                         CGPoint(x: 326,y: 227), CGPoint(x: 317,y: 194), CGPoint(x: 300,y: 163)],
                        capsule(from: CGPoint(x: 338,y: 173), to: CGPoint(x: 350,y: 256), radius: 28)],
    "left_forearm": [[CGPoint(x: 116,y: 237), CGPoint(x: 140,y: 241), CGPoint(x: 157,y: 255),
                      CGPoint(x: 148,y: 286), CGPoint(x: 134,y: 323), CGPoint(x: 115,y: 348),
                      CGPoint(x: 98,y: 335), CGPoint(x: 107,y: 302), CGPoint(x: 111,y: 271)],
                     capsule(from: CGPoint(x: 135,y: 257), to: CGPoint(x: 114,y: 340), radius: 22)],
    "right_forearm": [[CGPoint(x: 341,y: 235), CGPoint(x: 363,y: 232), CGPoint(x: 377,y: 255),
                       CGPoint(x: 384,y: 289), CGPoint(x: 401,y: 323), CGPoint(x: 391,y: 350),
                       CGPoint(x: 369,y: 346), CGPoint(x: 354,y: 319), CGPoint(x: 345,y: 282)],
                      capsule(from: CGPoint(x: 350,y: 256), to: CGPoint(x: 383,y: 340), radius: 23)],
    "left_hand": [[CGPoint(x: 96,y: 319), CGPoint(x: 118,y: 319), CGPoint(x: 139,y: 337),
                   CGPoint(x: 146,y: 363), CGPoint(x: 136,y: 395), CGPoint(x: 113,y: 402),
                   CGPoint(x: 98,y: 382), CGPoint(x: 89,y: 353)]],
    "right_hand": [[CGPoint(x: 365,y: 316), CGPoint(x: 388,y: 313), CGPoint(x: 405,y: 333),
                    CGPoint(x: 410,y: 359), CGPoint(x: 397,y: 387), CGPoint(x: 375,y: 400),
                    CGPoint(x: 358,y: 384), CGPoint(x: 351,y: 358)]],
    "left_thigh": [[CGPoint(x: 173,y: 397), CGPoint(x: 217,y: 397), CGPoint(x: 239,y: 419),
                    CGPoint(x: 242,y: 454), CGPoint(x: 231,y: 495), CGPoint(x: 228,y: 540),
                    CGPoint(x: 211,y: 566), CGPoint(x: 179,y: 556), CGPoint(x: 158,y: 526),
                    CGPoint(x: 159,y: 483), CGPoint(x: 165,y: 443)],
                   capsule(from: CGPoint(x: 199,y: 420), to: CGPoint(x: 181,y: 525), radius: 31)],
    "right_thigh": [[CGPoint(x: 226,y: 396), CGPoint(x: 273,y: 396), CGPoint(x: 305,y: 416),
                     CGPoint(x: 315,y: 453), CGPoint(x: 309,y: 492), CGPoint(x: 303,y: 537),
                     CGPoint(x: 284,y: 562), CGPoint(x: 261,y: 550), CGPoint(x: 249,y: 509),
                     CGPoint(x: 237,y: 468)],
                    capsule(from: CGPoint(x: 270,y: 420), to: CGPoint(x: 296,y: 525), radius: 31)],
    "left_shin": [[CGPoint(x: 157,y: 525), CGPoint(x: 226,y: 529), CGPoint(x: 226,y: 576),
                   CGPoint(x: 221,y: 625), CGPoint(x: 225,y: 657), CGPoint(x: 198,y: 673),
                   CGPoint(x: 164,y: 666), CGPoint(x: 157,y: 638), CGPoint(x: 157,y: 588)],
                  capsule(from: CGPoint(x: 181,y: 525), to: CGPoint(x: 173,y: 661), radius: 27)],
    "right_shin": [[CGPoint(x: 260,y: 519), CGPoint(x: 306,y: 520), CGPoint(x: 321,y: 568),
                    CGPoint(x: 333,y: 613), CGPoint(x: 350,y: 654), CGPoint(x: 325,y: 675),
                    CGPoint(x: 306,y: 661), CGPoint(x: 294,y: 650), CGPoint(x: 277,y: 654),
                    CGPoint(x: 265,y: 610), CGPoint(x: 256,y: 568)],
                   capsule(from: CGPoint(x: 296,y: 525), to: CGPoint(x: 329,y: 661), radius: 29)],
    "left_boot": [[CGPoint(x: 151,y: 650), CGPoint(x: 174,y: 657), CGPoint(x: 198,y: 666),
                   CGPoint(x: 224,y: 662), CGPoint(x: 230,y: 684), CGPoint(x: 232,y: 725),
                   CGPoint(x: 216,y: 752), CGPoint(x: 174,y: 754), CGPoint(x: 156,y: 736),
                   CGPoint(x: 163,y: 693)]],
    "right_boot": [[CGPoint(x: 294,y: 644), CGPoint(x: 325,y: 651), CGPoint(x: 350,y: 654),
                    CGPoint(x: 371,y: 706), CGPoint(x: 388,y: 742), CGPoint(x: 374,y: 760),
                    CGPoint(x: 337,y: 758), CGPoint(x: 312,y: 739), CGPoint(x: 294,y: 698),
                    CGPoint(x: 282,y: 667)]]
]

func pathFor(_ polygons: [[CGPoint]]) -> CGPath {
    let path = CGMutablePath()
    for polygon in polygons where polygon.count >= 3 {
        path.move(to: quartzPoint(polygon[0]))
        for point in polygon.dropFirst() { path.addLine(to: quartzPoint(point)) }
        path.closeSubpath()
    }
    return path
}

func boundsFor(_ polygons: [[CGPoint]], pad: CGFloat = 2) -> CGRect {
    let points = polygons.flatMap { $0 }
    let xs = points.map(\.x), ys = points.map(\.y)
    let minX = max(0, floor(xs.min()! - pad)), minY = max(0, floor(ys.min()! - pad))
    let maxX = min(CGFloat(sourceWidth), ceil(xs.max()! + pad))
    let maxY = min(CGFloat(sourceHeight), ceil(ys.max()! + pad))
    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
}

func makePart(_ name: String, source: CGImage, polygons: [[CGPoint]]) -> Part {
    let context = requireContext(width: sourceWidth, height: sourceHeight)
    context.addPath(pathFor(polygons))
    context.clip()
    context.draw(source, in: CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight))
    guard let full = context.makeImage() else { fail("Could not create masked part \(name)") }
    let bounds = boundsFor(polygons).integral
    let cropRect = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height)
    guard let cropped = full.cropping(to: cropRect) else { fail("Could not crop masked part \(name)") }
    return Part(name: name, image: cropped, rect: bounds)
}

let torsoPolygons: [[CGPoint]] = [[
    CGPoint(x: 212,y: 124), CGPoint(x: 261,y: 123), CGPoint(x: 281,y: 132),
    CGPoint(x: 300,y: 135), CGPoint(x: 322,y: 142), CGPoint(x: 340,y: 157),
    CGPoint(x: 332,y: 178), CGPoint(x: 317,y: 196), CGPoint(x: 313,y: 232),
    CGPoint(x: 316,y: 288), CGPoint(x: 314,y: 325), CGPoint(x: 304,y: 371),
    CGPoint(x: 300,y: 404), CGPoint(x: 282,y: 425), CGPoint(x: 260,y: 441),
    CGPoint(x: 238,y: 450), CGPoint(x: 217,y: 442), CGPoint(x: 193,y: 427),
    CGPoint(x: 176,y: 409), CGPoint(x: 176,y: 385), CGPoint(x: 181,y: 353),
    CGPoint(x: 184,y: 323), CGPoint(x: 190,y: 285), CGPoint(x: 190,y: 242),
    CGPoint(x: 182,y: 210), CGPoint(x: 176,y: 183), CGPoint(x: 180,y: 163),
    CGPoint(x: 195,y: 144)
]]

func makeCore(_ source: CGImage) -> Part {
    let context = requireContext(width: sourceWidth, height: sourceHeight)
    context.addPath(pathFor(torsoPolygons))
    context.clip()
    context.draw(source, in: CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight))
    guard let image = context.makeImage() else { fail("Could not create core layer") }
    return Part(name: "core", image: image,
                rect: CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight))
}

let fieldNames = ["tx","ty","body","head","ls","rs","le","re","lw","rw",
                  "lh","rh","lk","rk","la","ra","chest","palm","jets","holo","beam","front"]
struct Pose {
    var v: [Double]
    init(_ values: [String: Double] = [:]) {
        v = fieldNames.map { values[$0] ?? 0 }
    }
    subscript(_ name: String) -> Double { v[fieldNames.firstIndex(of: name)!] }
}
func pose(_ values: [String: Double] = [:]) -> Pose { Pose(values) }

let clipPoses: [String: [Pose]] = [
    "action_ready": [
        pose(), pose(["head":-10,"rs":-8,"re":18,"ls":5,"le":-8]),
        pose(["head":-17,"rs":-28,"re":46,"rw":-14]),
        pose(["head":12,"ls":18,"le":-24,"rs":-8,"re":22]),
        pose(["head":6,"ls":8,"le":-10,"rs":-3,"re":12]),
        pose(["head":-2,"ls":2,"rs":-2,"le":2,"re":2])
    ],
    "action_repulsor_shoot": [
        pose(), pose(["rs":-16,"re":10,"rw":-4,"body":-2]),
        pose(["rs":-47,"re":30,"rw":-14,"ls":8,"body":-3]),
        pose(["rs":-55,"re":20,"rw":-8,"ls":12,"body":-5,"chest":0.2,"palm":1,"beam":1]),
        pose(["rs":-31,"re":43,"rw":-16,"ls":4,"body":-2,"palm":0.25]),
        pose(["rs":-3,"re":14,"rw":0,"ls":1])
    ],
    "action_jump": [
        pose(), pose(["ty":6,"body":5,"ls":16,"rs":-16,"le":-2,"re":7,"lh":-9,"rh":9,"lk":34,"rk":34]),
        pose(["ty":-18,"body":-3,"ls":40,"rs":-41,"le":14,"re":16,"lh":8,"rh":-8,"lk":30,"rk":30]),
        pose(["ty":-92,"body":1,"ls":28,"rs":-30,"le":-8,"re":-8,"lh":14,"rh":-14,"lk":44,"rk":44,"la":-7,"ra":7]),
        pose(["ty":-42,"body":-4,"ls":8,"rs":-8,"le":25,"re":28,"lh":-5,"rh":8,"lk":28,"rk":36,"la":5,"ra":-4]),
        pose(["ty":2,"body":5,"ls":14,"rs":-13,"le":18,"re":16,"lh":-6,"rh":6,"lk":50,"rk":45,"la":-4,"ra":4])
    ],
    "action_flight": [
        pose(["ty":-34,"ls":24,"rs":-24,"le":-4,"re":-4,"lh":-6,"rh":8,"la":-10,"ra":12,"jets":0.3]),
        pose(["ty":-46,"body":-3,"ls":38,"rs":-36,"le":-4,"re":-8,"lh":-10,"rh":14,"la":-16,"ra":20,"jets":0.55]),
        pose(["ty":-58,"body":-45,"head":4,"ls":54,"rs":-47,"le":-3,"re":-15,"lh":-27,"rh":22,"lk":-13,"rk":18,"la":-12,"ra":10,"jets":1]),
        pose(["ty":-50,"body":-58,"head":7,"ls":43,"rs":-43,"le":3,"re":-8,"lh":-33,"rh":29,"lk":-9,"rk":11,"la":-10,"ra":14,"jets":1]),
        pose(["ty":-43,"body":-22,"head":-2,"ls":27,"rs":-30,"le":18,"re":16,"lh":-10,"rh":14,"lk":16,"rk":24,"la":-3,"ra":5,"jets":0.65]),
        pose(["ty":-34,"body":-2,"head":-1,"ls":22,"rs":-21,"le":-2,"re":-3,"lh":-5,"rh":7,"la":-8,"ra":10,"jets":0.3])
    ],
    "action_landing": [
        pose(["ty":-56,"jets":0.55,"ls":8,"rs":-8]),
        pose(["ty":-22,"body":3,"ls":14,"rs":-10,"le":18,"re":18,"lh":-12,"rh":11,"lk":37,"rk":47,"jets":0.25]),
        pose(["ty":3,"body":8,"ls":-24,"rs":20,"le":48,"re":40,"lh":-14,"rh":14,"lk":60,"rk":54]),
        pose(["ty":6,"body":4,"head":-5,"ls":-8,"rs":12,"le":35,"re":25,"lh":-5,"rh":8,"lk":72,"rk":38]),
        pose(["ty":2,"body":-2,"ls":4,"rs":-4,"le":16,"re":16,"lh":-5,"rh":5,"lk":27,"rk":24,"la":4,"ra":-3]),
        pose(["ty":0,"ls":2,"rs":-2,"jets":0.1])
    ],
    "action_running": [
        pose(["ls":-18,"rs":18,"le":20,"re":-5,"lh":-24,"rh":24,"lk":8,"rk":45,"la":8,"ra":-7,"ty":0]),
        pose(["ls":-4,"rs":4,"le":15,"re":-10,"lh":-8,"rh":12,"lk":58,"rk":15,"la":-4,"ra":8,"ty":-5]),
        pose(["ls":20,"rs":-20,"le":-8,"re":20,"lh":27,"rh":-27,"lk":42,"rk":4,"la":-8,"ra":4,"ty":-9]),
        pose(["ls":18,"rs":-18,"le":-4,"re":18,"lh":22,"rh":-22,"lk":6,"rk":48,"la":6,"ra":-9,"ty":-3]),
        pose(["ls":-6,"rs":6,"le":18,"re":-9,"lh":-12,"rh":14,"lk":54,"rk":12,"la":-5,"ra":7,"ty":-7]),
        pose(["ls":-16,"rs":16,"le":18,"re":-4,"lh":-20,"rh":20,"lk":11,"rk":42,"la":6,"ra":-5,"ty":-1])
    ],
    "action_dash": [
        pose(["body":-4,"ls":-18,"rs":16,"le":16,"re":18,"lh":-9,"rh":14]),
        pose(["tx":4,"body":-11,"ls":-37,"rs":32,"le":18,"re":20,"lh":-20,"rh":26,"lk":24,"rk":16]),
        pose(["tx":15,"body":-16,"ls":-42,"rs":39,"le":14,"re":22,"lh":-35,"rh":42,"lk":-5,"rk":-7,"jets":1]),
        pose(["tx":13,"body":-8,"ls":-18,"rs":16,"le":29,"re":35,"lh":-5,"rh":22,"lk":39,"rk":34,"jets":0.6]),
        pose(["tx":7,"body":3,"ls":8,"rs":-6,"le":27,"re":20,"lh":-14,"rh":13,"lk":64,"rk":52]),
        pose(["body":-3,"ls":-16,"rs":14,"le":15,"re":17,"lh":-7,"rh":12,"lk":2,"rk":1])
    ],
    "action_punch": [
        pose(["ls":-4,"rs":-10,"le":24,"re":32,"body":-2]),
        pose(["rs":-36,"re":76,"rw":18,"body":-5,"lh":-5,"rh":5]),
        pose(["rs":-48,"re":14,"rw":-8,"body":-8,"lh":-10,"rh":10]),
        pose(["rs":-16,"re":46,"ls":24,"le":18,"body":3]),
        pose(["ls":45,"le":-6,"lw":8,"body":8,"lh":12,"rh":-12]),
        pose(["ls":13,"le":24,"rs":-5,"re":26,"body":2])
    ],
    "action_block": [
        pose(), pose(["ls":8,"rs":-14,"le":-12,"re":75,"body":2,"ty":2,"front":1]),
        pose(["ls":8,"rs":-30,"le":-8,"re":132,"body":4,"ty":4,"lh":-9,"rh":9,"lk":20,"rk":20,"front":1]),
        pose(["ls":4,"rs":-25,"le":-4,"re":112,"body":-7,"ty":-3,"front":1]),
        pose(["ls":5,"rs":-15,"le":-8,"re":65,"body":-1,"ty":0,"front":1]),
        pose(["ls":4,"rs":-4,"le":13,"re":13])
    ],
    "action_chest_blast": [
        pose(["chest":0.12]), pose(["ls":-16,"rs":15,"le":26,"re":23,"chest":0.35]),
        pose(["ls":-31,"rs":29,"le":21,"re":19,"chest":0.8,"front":1]),
        pose(["ls":-42,"rs":40,"le":-1,"re":-2,"chest":1,"palm":0.5,"front":1]),
        pose(["ls":-28,"rs":26,"le":16,"re":16,"chest":0.65,"front":1]),
        pose(["ls":-6,"rs":5,"le":12,"re":12,"chest":0.16])
    ],
    "action_scan": [
        pose(), pose(["head":-14,"ls":-12,"le":28,"rs":6,"re":16]),
        pose(["head":-19,"ls":35,"le":45,"lw":8,"holo":0.65,"front":1]),
        pose(["head":-10,"ls":40,"le":42,"rs":31,"re":-20,"rw":-20,"holo":1,"front":1]),
        pose(["head":12,"ls":-11,"le":23,"rs":18,"re":-10,"holo":0.45]),
        pose(["head":4,"ls":1,"le":12,"rs":2,"re":8])
    ],
    "action_energy_charge": [
        pose(["palm":0.12]), pose(["ls":-11,"rs":12,"le":20,"re":20,"palm":0.2]),
        pose(["ls":48,"rs":-48,"le":-118,"re":118,"lw":-14,"rw":14,"palm":0.45,"front":1]),
        pose(["ls":54,"rs":-54,"le":-145,"re":145,"lw":-24,"rw":22,"palm":1,"chest":0.32,"front":1]),
        pose(["ls":47,"rs":-47,"le":-110,"re":110,"lw":-9,"rw":10,"palm":0.48,"front":1]),
        pose(["ls":-4,"rs":4,"le":13,"re":13,"palm":0.1])
    ]
]

func rotated(_ point: CGPoint, around pivot: CGPoint, degrees: Double) -> CGPoint {
    let radians = degrees * .pi / 180
    let dx = point.x - pivot.x, dy = point.y - pivot.y
    return CGPoint(x: pivot.x + CGFloat(cos(radians)) * dx - CGFloat(sin(radians)) * dy,
                   y: pivot.y + CGFloat(sin(radians)) * dx + CGFloat(cos(radians)) * dy)
}

func setRotation(_ context: CGContext, pivot: CGPoint, degrees: Double) {
    let q = quartzPoint(pivot)
    context.translateBy(x: q.x, y: q.y)
    context.rotate(by: -degrees * .pi / 180)
    context.translateBy(x: -q.x, y: -q.y)
}

func drawPart(_ context: CGContext, _ part: Part) {
    let rect = CGRect(x: part.rect.minX,
                      y: CGFloat(sourceHeight) - part.rect.maxY,
                      width: part.rect.width, height: part.rect.height)
    context.draw(part.image, in: rect)
}

func drawArms(_ context: CGContext, pose: Pose, parts: [String: Part]) {
    for side in ["left", "right"] {
        let left = side == "left"
        let shoulder = CGPoint(x: left ? 165 : 338, y: 173)
        let elbow = CGPoint(x: left ? 135 : 350, y: 256)
        let wrist = CGPoint(x: left ? 114 : 383, y: 340)
        context.saveGState()
        setRotation(context, pivot: shoulder, degrees: pose[left ? "ls" : "rs"])
        drawPart(context, parts["\(side)_upper_arm"]!)
        context.saveGState()
        setRotation(context, pivot: elbow, degrees: pose[left ? "le" : "re"])
        drawPart(context, parts["\(side)_forearm"]!)
        context.saveGState()
        setRotation(context, pivot: wrist, degrees: pose[left ? "lw" : "rw"])
        drawPart(context, parts["\(side)_hand"]!)
        context.restoreGState(); context.restoreGState(); context.restoreGState()
    }
}

func palmPoint(side: String, pose: Pose) -> CGPoint {
    let left = side == "left"
    let shoulder = CGPoint(x: left ? 165 : 338, y: 173)
    let elbow = CGPoint(x: left ? 135 : 350, y: 256)
    let wrist = CGPoint(x: left ? 114 : 383, y: 340)
    var p = CGPoint(x: left ? 116 : 384, y: 358)
    p = rotated(p, around: wrist, degrees: pose[left ? "lw" : "rw"])
    p = rotated(p, around: elbow, degrees: pose[left ? "le" : "re"])
    p = rotated(p, around: shoulder, degrees: pose[left ? "ls" : "rs"])
    return p
}

func footPoint(side: String, pose: Pose) -> CGPoint {
    let left = side == "left"
    let hip = CGPoint(x: left ? 199 : 270, y: 420)
    let knee = CGPoint(x: left ? 181 : 296, y: 525)
    let ankle = CGPoint(x: left ? 173 : 329, y: 661)
    var p = CGPoint(x: left ? 190 : 358, y: left ? 734 : 742)
    p = rotated(p, around: ankle, degrees: pose[left ? "la" : "ra"])
    p = rotated(p, around: knee, degrees: pose[left ? "lk" : "rk"])
    return rotated(p, around: hip, degrees: pose[left ? "lh" : "rh"])
}

func drawGlow(_ context: CGContext, at point: CGPoint, radius: CGFloat, strength: Double) {
    guard strength > 0.02 else { return }
    context.saveGState()
    let alpha = min(0.9, max(0, strength))
    let center = quartzPoint(point)
    context.setBlendMode(.screen)
    context.setFillColor(CGColor(red: 0.03, green: 0.82, blue: 1.0, alpha: alpha * 0.35))
    context.fillEllipse(in: CGRect(x: center.x-radius*1.7, y: center.y-radius*1.7,
                                  width: radius*3.4, height: radius*3.4))
    context.setFillColor(CGColor(red: 0.35, green: 0.96, blue: 1.0, alpha: alpha))
    context.fillEllipse(in: CGRect(x: center.x-radius*0.7, y: center.y-radius*0.7,
                                  width: radius*1.4, height: radius*1.4))
    context.restoreGState()
}

func drawEffects(_ context: CGContext, pose: Pose) {
    let chest = CGPoint(x: 237, y: 179)
    drawGlow(context, at: chest, radius: 17, strength: pose["chest"])
    if pose["chest"] > 0.35 {
        let beamEnd = CGPoint(x: 458, y: 94)
        context.saveGState(); context.setBlendMode(.screen)
        context.setStrokeColor(CGColor(red: 0.05, green: 0.68, blue: 1, alpha: pose["chest"] * 0.72))
        context.setLineWidth(14 + pose["chest"] * 8)
        context.move(to: quartzPoint(CGPoint(x: 244, y: 178)))
        context.addLine(to: quartzPoint(beamEnd))
        context.strokePath()
        context.setStrokeColor(CGColor(red: 0.65, green: 0.97, blue: 1, alpha: pose["chest"] * 0.7))
        context.setLineWidth(5)
        context.move(to: quartzPoint(CGPoint(x: 244, y: 178)))
        context.addLine(to: quartzPoint(beamEnd))
        context.strokePath(); context.restoreGState()
    }
    let leftPalm = palmPoint(side: "left", pose: pose)
    let rightPalm = palmPoint(side: "right", pose: pose)
    if pose["palm"] > 0.02 {
        drawGlow(context, at: leftPalm, radius: 12, strength: pose["palm"])
        drawGlow(context, at: rightPalm, radius: 12, strength: pose["palm"])
    }
    if pose["beam"] > 0.02 {
        let start = rightPalm
        let end = CGPoint(x: start.x + 54, y: start.y - 14)
        context.saveGState(); context.setBlendMode(.screen)
        context.setStrokeColor(CGColor(red: 0.02, green: 0.72, blue: 1, alpha: pose["beam"] * 0.56))
        context.setLineWidth(12)
        context.move(to: quartzPoint(start)); context.addLine(to: quartzPoint(end)); context.strokePath()
        context.setStrokeColor(CGColor(red: 0.78, green: 0.99, blue: 1, alpha: pose["beam"] * 0.92))
        context.setLineWidth(4)
        context.move(to: quartzPoint(start)); context.addLine(to: quartzPoint(end)); context.strokePath()
        context.restoreGState()
    }
    if pose["holo"] > 0.02 {
        let center = CGPoint(x: leftPalm.x + 48, y: leftPalm.y - 28)
        context.saveGState(); context.setBlendMode(.screen)
        context.setStrokeColor(CGColor(red: 0.12, green: 0.91, blue: 1, alpha: pose["holo"] * 0.96))
        context.setLineWidth(3)
        let q = quartzPoint(center)
        context.strokeEllipse(in: CGRect(x: q.x-25, y: q.y-20, width: 50, height: 40))
        context.strokeEllipse(in: CGRect(x: q.x-14, y: q.y-11, width: 28, height: 22))
        context.stroke(CGRect(x: q.x-43, y: q.y-32, width: 86, height: 64))
        context.setLineWidth(1)
        context.move(to: CGPoint(x: q.x-32, y: q.y)); context.addLine(to: CGPoint(x: q.x+32, y: q.y))
        context.move(to: CGPoint(x: q.x, y: q.y-23)); context.addLine(to: CGPoint(x: q.x, y: q.y+23))
        context.strokePath()
        context.restoreGState()
    }
    if pose["jets"] > 0.02 {
        for (side, direction) in [("left", -1.0), ("right", 1.0)] {
            let point = footPoint(side: side, pose: pose)
            drawGlow(context, at: CGPoint(x: point.x, y: point.y + 12), radius: 8,
                     strength: pose["jets"])
            context.saveGState(); context.setBlendMode(.screen)
            context.setStrokeColor(CGColor(red: 0.08, green: 0.75, blue: 1, alpha: pose["jets"] * 0.85))
            context.setLineWidth(3 + pose["jets"] * 5)
            context.move(to: quartzPoint(point))
            context.addLine(to: quartzPoint(CGPoint(x: point.x + CGFloat(direction * 2),
                                                    y: point.y + 23 + pose["jets"] * 20)))
            context.strokePath(); context.restoreGState()
        }
    }
}

func renderSourcePose(_ pose: Pose, parts: [String: Part]) -> CGImage {
    let context = requireContext(width: rigCanvasWidth, height: rigCanvasHeight)
    context.translateBy(x: rigOffset.x, y: rigOffset.y)
    context.saveGState()
    setRotation(context, pivot: pelvis, degrees: pose["body"])

    // Rear legs and shoulder plates sit behind the central torso.
    for left in [true, false] {
        let hip = CGPoint(x: left ? 199 : 270, y: 420)
        let knee = CGPoint(x: left ? 181 : 296, y: 525)
        let ankle = CGPoint(x: left ? 173 : 329, y: 661)
        let side = left ? "left" : "right"
        context.saveGState()
        setRotation(context, pivot: hip, degrees: pose[left ? "lh" : "rh"])
        drawPart(context, parts["\(side)_thigh"]!)
        context.saveGState()
        setRotation(context, pivot: knee, degrees: pose[left ? "lk" : "rk"])
        drawPart(context, parts["\(side)_shin"]!)
        context.saveGState()
        setRotation(context, pivot: ankle, degrees: pose[left ? "la" : "ra"])
        drawPart(context, parts["\(side)_boot"]!)
        context.restoreGState(); context.restoreGState(); context.restoreGState()
    }

    if pose["front"] < 0.5 { drawArms(context, pose: pose, parts: parts) }

    drawPart(context, parts["core"]!)
    context.saveGState(); setRotation(context, pivot: CGPoint(x: 253,y: 126), degrees: pose["head"])
    drawPart(context, parts["head"]!)
    context.restoreGState()
    if pose["front"] >= 0.5 { drawArms(context, pose: pose, parts: parts) }
    drawEffects(context, pose: pose)
    context.restoreGState()
    guard let result = context.makeImage() else { fail("Could not render source pose") }
    return result
}

func smooth(_ t: Double) -> Double { t*t*(3 - 2*t) }
func interpolate(_ a: Pose, _ b: Pose, _ t: Double) -> Pose {
    Pose(Dictionary(uniqueKeysWithValues: fieldNames.enumerated().map { index, name in
        (name, a.v[index] + (b.v[index] - a.v[index]) * t)
    }))
}

func renderFrame(_ pose: Pose, sourcePose: CGImage) -> CGImage {
    let context = requireContext(width: canvasWidth, height: canvasHeight)
    let width = CGFloat(rigCanvasWidth) * renderScale
    let height = CGFloat(rigCanvasHeight) * renderScale
    let originX = placementX + CGFloat(pose["tx"]) * renderScale - rigOffset.x * renderScale
    let originY = placementY + CGFloat(pose["ty"]) * renderScale - rigOffset.y * renderScale
    context.draw(sourcePose, in: CGRect(x: originX, y: CGFloat(canvasHeight) - originY - height,
                                        width: width, height: height))
    guard let result = context.makeImage() else { fail("Could not render output frame") }
    return result
}

func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

guard let inputSource = CGImageSourceCreateWithURL(referenceURL as CFURL, nil),
      let reference = CGImageSourceCreateImageAtIndex(inputSource, 0, nil) else {
    fail("Could not open approved reference image at \(referenceURL.path)")
}
guard reference.width == sourceWidth, reference.height == sourceHeight else {
    fail("Expected reference dimensions \(sourceWidth)x\(sourceHeight), got \(reference.width)x\(reference.height)")
}
try FileManager.default.createDirectory(at: rigRoot.appendingPathComponent("layers", isDirectory: true),
                                        withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: rigRoot.appendingPathComponent("contacts", isDirectory: true),
                                        withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: framesRoot, withIntermediateDirectories: true)

var parts: [String: Part] = [:]
for (name, polygons) in jointPolygons where name != "head" {
    let part = makePart(name, source: reference, polygons: polygons)
    parts[name] = part
    try writePNG(part.image, to: rigRoot.appendingPathComponent("layers/\(name).png"))
}
parts["head"] = makePart("head", source: reference, polygons: jointPolygons["head"]!)
try writePNG(parts["head"]!.image, to: rigRoot.appendingPathComponent("layers/head.png"))
parts["core"] = makeCore(reference)
try writePNG(parts["core"]!.image, to: rigRoot.appendingPathComponent("layers/core.png"))

let expectedClips = ["action_ready","action_repulsor_shoot","action_jump","action_flight",
                     "action_landing","action_running","action_dash","action_punch",
                     "action_block","action_chest_blast","action_scan","action_energy_charge"]
let clipArgument = CommandLine.arguments.first(where: { $0.hasPrefix("--clips=") })
let selectedClips = clipArgument.map {
    String($0.dropFirst("--clips=".count)).split(separator: ",").map(String.init)
} ?? expectedClips
guard !selectedClips.isEmpty && selectedClips.allSatisfy({ expectedClips.contains($0) }) else {
    fail("Unknown or empty --clips selection")
}
let referenceHash = sha256(try Data(contentsOf: referenceURL))
var wroteRecomposedReference = false
var manifest: [String: Any] = [
    "reference": referenceURL.path,
    "reference_sha256": referenceHash,
    "source_canvas": [sourceWidth, sourceHeight],
    "output_canvas": [canvasWidth, canvasHeight],
    "render_scale": Double(renderScale),
    "placement_xy": [Double(placementX), Double(placementY)],
    "fps": frameRate, "frame_count_per_clip": frameCount,
    "cycle_seconds": cycleSeconds,
    "joint_anchors": [
        "head_neck": [253,126], "left_shoulder": [165,173], "left_elbow": [135,257], "left_wrist": [114,340],
        "right_shoulder": [338,173], "right_elbow": [350,256], "right_wrist": [383,340],
        "left_hip": [199,420], "left_knee": [181,525], "left_ankle": [173,661],
        "right_hip": [270,420], "right_knee": [296,525], "right_ankle": [329,661]
    ] as [String: [Int]],
    "clips": [String: Any]()
]
var clipsManifest: [String: Any] = [:]
let existingManifestURL = rigRoot.appendingPathComponent("rig-manifest.json")
if let existingData = try? Data(contentsOf: existingManifestURL),
   let existing = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any],
   let existingClips = existing["clips"] as? [String: Any] {
    clipsManifest = existingClips
}

for clip in selectedClips {
    guard let keys = clipPoses[clip], keys.count == 6 else { fail("Expected six key poses for \(clip)") }
    let keyConfigHashes = Set(keys.map { $0.v.map { String(format: "%.4f", $0) }.joined(separator: ",") })
    guard keyConfigHashes.count == 6 else { fail("\(clip) does not have six distinct joint configurations") }
    let clipDir = framesRoot.appendingPathComponent(clip, isDirectory: true)
    try FileManager.default.createDirectory(at: clipDir, withIntermediateDirectories: true)
    var frameHashes: [String] = []
    var contactTiles: [CGImage] = []
    for frame in 0..<frameCount {
        let segment = frame / 10
        let localT = Double(frame % 10) / 10.0
        let blend = smooth(localT)
        let current = interpolate(keys[segment], keys[(segment + 1) % 6], blend)
        let sourcePose = renderSourcePose(current, parts: parts)
        if !wroteRecomposedReference {
            try writePNG(sourcePose, to: rigRoot.appendingPathComponent("reference-recomposed.png"))
            wroteRecomposedReference = true
        }
        let output = renderFrame(current, sourcePose: sourcePose)
        let outURL = clipDir.appendingPathComponent(String(format: "%02d.png", frame))
        try writePNG(output, to: outURL)
        frameHashes.append(sha256(try Data(contentsOf: outURL)))
        if [0,10,20,30,40,50].contains(frame) { contactTiles.append(output) }
    }
    let uniqueHashes = Set(frameHashes)
    guard uniqueHashes.count >= 54 else {
        fail("\(clip) rendered only \(uniqueHashes.count)/60 distinct frames; joint changes are too small")
    }

    // Six-pose review contact sheet on neutral gray, preserving original RGB.
    let tileW = 320, tileH = 347, titleH = 25, pad = 8
    let contactHeight = (tileH + titleH) * 2
    let contact = requireContext(width: tileW * 3, height: contactHeight)
    contact.setFillColor(CGColor(red: 0.9, green: 0.91, blue: 0.93, alpha: 1))
    contact.fill(CGRect(x: 0, y: 0, width: tileW * 3, height: (tileH + titleH) * 2))
    let label = clip.replacingOccurrences(of: "action_", with: "").replacingOccurrences(of: "_", with: " ").capitalized
    for (index, tile) in contactTiles.enumerated() {
        let x = (index % 3) * tileW, y = (index / 3) * (tileH + titleH)
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                                                    .foregroundColor: NSColor.black]
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: contact, flipped: false)
        NSString(string: "\(label) · Pose \(index+1)").draw(
            at: NSPoint(x: x + pad, y: contactHeight - y - titleH + 5), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
        contact.draw(tile, in: CGRect(x: x, y: contactHeight - y - titleH - tileH,
                                      width: tileW, height: tileH))
    }
    guard let contactImage = contact.makeImage() else { fail("Could not make contact sheet \(clip)") }
    try writePNG(contactImage, to: rigRoot.appendingPathComponent("contacts/\(clip)-poses.png"))
    clipsManifest[clip] = [
        "key_joint_configs": keys.map { $0.v },
        "distinct_key_pose_configs": keyConfigHashes.count,
        "frame_count": frameCount,
        "distinct_rendered_frames": uniqueHashes.count,
        "frame_sha256": frameHashes,
        "contact_sheet": "contacts/\(clip)-poses.png"
    ] as [String: Any]
    log("RENDERED \(clip): \(frameCount) frames, \(uniqueHashes.count) unique")
}

manifest["clips"] = clipsManifest
let json = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
try json.write(to: rigRoot.appendingPathComponent("rig-manifest.json"), options: .atomic)
log("DONE clips=\(selectedClips.count) frames=\(selectedClips.count * frameCount) output=\(framesRoot.path)")
