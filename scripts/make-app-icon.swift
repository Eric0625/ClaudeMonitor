#!/usr/bin/env swift
// Renders design/AppIcon.svg into the AppIcon asset catalog set.
// Usage: swift scripts/make-app-icon.swift [svg] [appiconset]

import AppKit

let arguments = CommandLine.arguments
let svgPath = arguments.count > 1 ? arguments[1] : "design/AppIcon.svg"
let outputPath = arguments.count > 2 ? arguments[2] : "App/Assets.xcassets/AppIcon.appiconset"

struct IconSlot {
    let points: Int
    let scale: Int

    var pixels: Int { points * scale }
    var fileName: String { scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@\(scale)x.png" }
}

let slots = [16, 32, 128, 256, 512].flatMap { points in
    [IconSlot(points: points, scale: 1), IconSlot(points: points, scale: 2)]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func renderPNG(_ image: NSImage, pixels: Int) -> Data {
    guard
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else {
        fail("cannot create a \(pixels) px bitmap")
    }
    context.interpolationQuality = .high
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    guard let cgImage = context.makeImage(),
          let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    else {
        fail("cannot encode a \(pixels) px PNG")
    }
    return data
}

guard let image = NSImage(contentsOf: URL(fileURLWithPath: svgPath)) else {
    fail("cannot read \(svgPath)")
}

let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true)
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

let catalogURL = outputURL.deletingLastPathComponent()
let catalogContentsURL = catalogURL.appendingPathComponent("Contents.json")
if catalogURL.pathExtension == "xcassets", !FileManager.default.fileExists(atPath: catalogContentsURL.path) {
    try Data(#"{"info":{"author":"xcode","version":1}}"#.utf8).write(to: catalogContentsURL)
}

var entries: [[String: String]] = []
for slot in slots {
    try renderPNG(image, pixels: slot.pixels).write(to: outputURL.appendingPathComponent(slot.fileName))
    entries.append([
        "filename": slot.fileName,
        "idiom": "mac",
        "scale": "\(slot.scale)x",
        "size": "\(slot.points)x\(slot.points)",
    ])
}

let contents: [String: Any] = ["images": entries, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outputURL.appendingPathComponent("Contents.json"))

print("Wrote \(slots.count) images to \(outputPath)")
