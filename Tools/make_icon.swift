// 天选风格原创图标：月耀白底板、装甲盾与薄荷青 T 形徽记。
// 用法：swift Tools/make_icon.swift <输出目录>
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

func polygon(_ points: [(CGFloat, CGFloat)]) -> CGPath {
    let path = CGMutablePath()
    for (index, p) in points.enumerated() {
        let point = CGPoint(x: p.0, y: p.1)
        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.closeSubpath()
    return path
}

func drawIcon(size: CGFloat) -> CGImage? {
    let space = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                              bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.scaleBy(x: size / 1024, y: size / 1024)
    // Match the downward coordinate system of the SwiftUI emblem.
    ctx.translateBy(x: 0, y: 1024)
    ctx.scaleBy(x: 1, y: -1)
    let tile = CGPath(roundedRect: CGRect(x: 84, y: 84, width: 856, height: 856),
                      cornerWidth: 184, cornerHeight: 184, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28,
                  color: CGColor(gray: 0.12, alpha: 0.20))
    ctx.setFillColor(CGColor(red: 0.94, green: 0.97, blue: 0.96, alpha: 1))
    ctx.addPath(tile); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(tile); ctx.clip()
    let colors = [CGColor(red: 1, green: 1, blue: 1, alpha: 1),
                  CGColor(red: 0.86, green: 0.93, blue: 0.91, alpha: 1)] as CFArray
    let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 220, y: 120),
                           end: CGPoint(x: 800, y: 930), options: [])
    // Recessed corner accents echo the panels in the control center.
    ctx.setLineWidth(16); ctx.setLineCap(.butt)
    ctx.setStrokeColor(CGColor(red: 0.20, green: 0.79, blue: 0.67, alpha: 1))
    ctx.move(to: CGPoint(x: 178, y: 337)); ctx.addLine(to: CGPoint(x: 178, y: 242))
    ctx.addLine(to: CGPoint(x: 238, y: 182)); ctx.addLine(to: CGPoint(x: 337, y: 182)); ctx.strokePath()
    ctx.move(to: CGPoint(x: 846, y: 687)); ctx.addLine(to: CGPoint(x: 846, y: 782))
    ctx.addLine(to: CGPoint(x: 786, y: 842)); ctx.addLine(to: CGPoint(x: 687, y: 842)); ctx.strokePath()
    let shield = polygon([(287, 229), (737, 229), (795, 287), (795, 644),
                          (735, 709), (512, 817), (289, 709), (229, 644), (229, 287)])
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 20,
                  color: CGColor(gray: 0, alpha: 0.22))
    ctx.setFillColor(CGColor(red: 0.08, green: 0.16, blue: 0.18, alpha: 1))
    ctx.addPath(shield); ctx.fillPath(); ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(shield); ctx.clip()
    let armor = [CGColor(red: 0.17, green: 0.27, blue: 0.28, alpha: 1),
                 CGColor(red: 0.06, green: 0.12, blue: 0.14, alpha: 1)] as CFArray
    ctx.drawLinearGradient(CGGradient(colorsSpace: space, colors: armor, locations: [0, 1])!,
                           start: CGPoint(x: 300, y: 220), end: CGPoint(x: 700, y: 800), options: [])
    ctx.restoreGState()
    ctx.addPath(shield); ctx.setLineWidth(3)
    ctx.setStrokeColor(CGColor(red: 0.43, green: 0.66, blue: 0.63, alpha: 0.5)); ctx.strokePath()
    let glyph: [(CGFloat, CGFloat)] = [(0.07,0.19),(0.40,0.19),(0.49,0.30),(0.60,0.19),(0.93,0.19),
       (0.80,0.39),(0.61,0.39),(0.54,0.50),(0.54,0.74),(0.43,0.86),(0.43,0.50),(0.36,0.39),(0.20,0.39)]
    let mark = polygon(glyph.map { (252 + $0.0 * 520, 247 + $0.1 * 520) })
    ctx.saveGState(); ctx.addPath(mark); ctx.clip()
    let mint = [CGColor(red: 0.63, green: 1, blue: 0.86, alpha: 1),
                CGColor(red: 0.12, green: 0.76, blue: 0.65, alpha: 1)] as CFArray
    ctx.drawLinearGradient(CGGradient(colorsSpace: space, colors: mint, locations: [0, 1])!,
                           start: CGPoint(x: 350, y: 330), end: CGPoint(x: 650, y: 715), options: [])
    ctx.restoreGState()
    ctx.restoreGState()
    return ctx.makeImage()
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("Cannot create PNG: \(url.path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    precondition(CGImageDestinationFinalize(dest), "PNG write failed")
}
let directory = URL(fileURLWithPath: outDir)
let iconset = directory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let specs: [(Int, Int)] = [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)]
for (base, scale) in specs {
    guard let img = drawIcon(size: CGFloat(base * scale)) else { fatalError("Icon render failed") }
    let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
    writePNG(img, to: iconset.appendingPathComponent(name))
}
writePNG(drawIcon(size: 1024)!, to: directory.appendingPathComponent("Tianxuan-AppIcon.png"))
print("Generated: \(iconset.path)")
