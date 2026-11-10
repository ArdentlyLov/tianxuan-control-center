// TUF Gaming 启动图标：用户提供的 SVG 徽记，搭配石墨灰底板与银白前景。
// 用法：swift Tools/make_icon.swift <输出目录>
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

// 与界面的 TianxuanGlyph 使用相同的原始几何和宽高比例。
func tufMark(in rect: CGRect) -> CGPath {
    let polygons: [[CGPoint]] = [
        [CGPoint(x: 78, y: 57), CGPoint(x: 78, y: 179), CGPoint(x: 142, y: 216), CGPoint(x: 142, y: 94)],
        [CGPoint(x: 158, y: 103), CGPoint(x: 158, y: 263), CGPoint(x: 221, y: 299), CGPoint(x: 221, y: 139)],
        [CGPoint(x: 382, y: 57), CGPoint(x: 319, y: 93), CGPoint(x: 319, y: 147), CGPoint(x: 382, y: 111)],
        [CGPoint(x: 382, y: 125), CGPoint(x: 319, y: 162), CGPoint(x: 319, y: 216), CGPoint(x: 382, y: 180)],
        [CGPoint(x: 302, y: 103), CGPoint(x: 239, y: 139), CGPoint(x: 239, y: 299), CGPoint(x: 302, y: 263)]
    ]
    let scale = min(rect.width / 304, rect.height / 242)
    let origin = CGPoint(x: rect.minX + (rect.width - 304 * scale) / 2,
                         y: rect.minY + (rect.height - 242 * scale) / 2)
    let path = CGMutablePath()
    for polygon in polygons {
        for (index, point) in polygon.enumerated() {
            let fitted = CGPoint(x: origin.x + (point.x - 78) * scale,
                                 y: origin.y + (point.y - 57) * scale)
            if index == 0 { path.move(to: fitted) } else { path.addLine(to: fitted) }
        }
        path.closeSubpath()
    }
    return path
}

func drawIcon(size: CGFloat) -> CGImage? {
    let space = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                              bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.scaleBy(x: size / 1024, y: size / 1024)
    // 保留 SVG 向下的坐标方向，外侧区域保持透明。
    ctx.translateBy(x: 0, y: 1024)
    ctx.scaleBy(x: 1, y: -1)
    let tile = CGPath(roundedRect: CGRect(x: 84, y: 84, width: 856, height: 856),
                      cornerWidth: 184, cornerHeight: 184, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 26,
                  color: CGColor(gray: 0, alpha: 0.24))
    ctx.setFillColor(CGColor(red: 0.09, green: 0.10, blue: 0.12, alpha: 1))
    ctx.addPath(tile); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(tile); ctx.clip()
    let colors = [CGColor(red: 0.18, green: 0.20, blue: 0.23, alpha: 1),
                  CGColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1)] as CFArray
    let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 220, y: 120),
                           end: CGPoint(x: 800, y: 930),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.addPath(tile)
    ctx.setLineWidth(3)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.08))
    ctx.strokePath()
    ctx.restoreGState()

    let mark = tufMark(in: CGRect(x: 206, y: 268, width: 612, height: 488))
    ctx.saveGState(); ctx.addPath(mark); ctx.clip()
    let silver = [CGColor(red: 0.98, green: 0.99, blue: 1, alpha: 1),
                  CGColor(red: 0.76, green: 0.79, blue: 0.83, alpha: 1)] as CFArray
    ctx.drawLinearGradient(CGGradient(colorsSpace: space, colors: silver, locations: [0, 1])!,
                           start: CGPoint(x: 280, y: 270), end: CGPoint(x: 750, y: 755),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
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
if FileManager.default.fileExists(atPath: iconset.path) {
    try FileManager.default.removeItem(at: iconset)
}
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let specs: [(Int, Int)] = [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)]
for (base, scale) in specs {
    guard let img = drawIcon(size: CGFloat(base * scale)) else { fatalError("Icon render failed") }
    let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
    writePNG(img, to: iconset.appendingPathComponent(name))
}
writePNG(drawIcon(size: 1024)!, to: directory.appendingPathComponent("Tianxuan-AppIcon.png"))
print("Generated: \(iconset.path)")
