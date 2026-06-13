// 生成 Fluent 的 App 图标：蓝紫渐变圆角方 + 双语字 "A文"（白 + 浅青），点明"翻译"。
// 用法：swift tools/make-icon.swift
// 输出：Resources/AppIcon.iconset 全套 PNG + Resources/preview.png
import AppKit
import Foundation

let root = FileManager.default.currentDirectoryPath
let outDir = "\(root)/Resources/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func drawIcon(size S: CGFloat) {
    // 圆角方背景（squircle），蓝紫渐变
    let inset = S * 0.06
    let rect = NSRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset)
    let radius = rect.width * 0.225
    let bg = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    let grad = NSGradient(colors: [
        NSColor(srgbRed: 0.39, green: 0.40, blue: 0.95, alpha: 1),  // 靛
        NSColor(srgbRed: 0.15, green: 0.39, blue: 0.92, alpha: 1)   // 蓝
    ])!
    grad.draw(in: bg, angle: -90)

    // 双语字：A（白） + 文（浅青），并排居中
    let fontSize = S * 0.40
    let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
    let aAttr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
    let cAttr: [NSAttributedString.Key: Any] = [.font: font,
        .foregroundColor: NSColor(srgbRed: 0.62, green: 0.91, blue: 1.0, alpha: 1)]
    let a = NSAttributedString(string: "A", attributes: aAttr)
    let c = NSAttributedString(string: "文", attributes: cAttr)
    let aSize = a.size()
    let cSize = c.size()
    let gap = S * 0.02
    let totalW = aSize.width + gap + cSize.width
    let baseY = (S - max(aSize.height, cSize.height)) / 2
    let startX = (S - totalW) / 2
    a.draw(at: NSPoint(x: startX, y: baseY))
    c.draw(at: NSPoint(x: startX + aSize.width + gap, y: baseY))
}

func renderPNG(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    drawIcon(size: CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
for (name, px) in sizes {
    try! renderPNG(pixels: px).write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}
try! renderPNG(pixels: 512).write(to: URL(fileURLWithPath: "\(root)/Resources/preview.png"))
print("done")
