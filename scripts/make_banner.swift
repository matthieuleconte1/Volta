// Generates the README banner (docs/banner.png): the bolt of the app icon, the wordmark and a power trace.
// Usage: swift scripts/make_banner.swift docs/banner.png
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/banner.png"
let width = 2560, height = 960
let full = CGRect(x: 0, y: 0, width: width, height: height)
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255,
                                           CGFloat(hex & 0xFF) / 255, a])!
}
func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
}

let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

// Warm black background, green glow behind the icon.
ctx.setFillColor(rgb(0x0D0F0E))
ctx.fill(full)
let iconCenter = CGPoint(x: 640, y: 480)
ctx.drawRadialGradient(gradient([rgb(0x31BA59, 0.30), rgb(0x31BA59, 0)], [0, 1]),
                       startCenter: iconCenter, startRadius: 0, endCenter: iconCenter, endRadius: 720, options: [])

// Power trace along the bottom: a stacked history like the panel's chart (CPU, GPU, display, SoC, other).
let samples = 96
func load(_ i: Int) -> Double {
    let x = Double(i) / Double(samples)
    return 0.32 + 0.16 * sin(x * 9.1) + 0.1 * sin(x * 23.7 + 1.3) + 0.22 * exp(-pow((x - 0.68) * 7, 2))
}
let bands: [(UInt32, Double)] = [(0x2A78D6, 0.22), (0xEB6834, 0.12), (0x1BAF7A, 0.06), (0xEDA100, 0.3), (0x6F6E69, 0.3)]
let traceHeight: CGFloat = 300
func y(_ i: Int, upTo band: Int) -> CGFloat {
    CGFloat(load(i) * bands.prefix(band).reduce(0) { $0 + $1.1 }) * traceHeight
}
for band in stride(from: bands.count, to: 0, by: -1) {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 0, y: 0))
    for i in 0...samples { path.addLine(to: CGPoint(x: CGFloat(i) / CGFloat(samples) * CGFloat(width), y: y(i, upTo: band))) }
    path.addLine(to: CGPoint(x: CGFloat(width), y: 0))
    path.closeSubpath()
    ctx.addPath(path)
    ctx.setFillColor(rgb(bands[band - 1].0, 0.20))
    ctx.fillPath()
}

// The app icon (same drawing as scripts/make_icon.swift), large.
let iconSize: CGFloat = 520
let body = CGRect(x: iconCenter.x - iconSize / 2, y: iconCenter.y - iconSize / 2, width: iconSize, height: iconSize)
let squircle = NSBezierPath(roundedRect: body, xRadius: iconSize * 0.225, yRadius: iconSize * 0.225)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
shadow.shadowOffset = NSSize(width: 0, height: -14)
shadow.shadowBlurRadius = 40
shadow.set()
NSColor(srgbRed: 0.13, green: 0.62, blue: 0.29, alpha: 1).setFill()
squircle.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(colors: [
    NSColor(srgbRed: 0.40, green: 0.87, blue: 0.47, alpha: 1),
    NSColor(srgbRed: 0.19, green: 0.73, blue: 0.35, alpha: 1),
    NSColor(srgbRed: 0.09, green: 0.53, blue: 0.25, alpha: 1),
])!.draw(in: squircle, angle: -90)
NSGraphicsContext.saveGraphicsState()
squircle.addClip()
NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0)])!
    .draw(in: NSBezierPath(ovalIn: CGRect(x: body.minX - iconSize * 0.25, y: body.midY - iconSize * 0.05,
                                          width: iconSize * 1.5, height: iconSize * 1.1)), angle: -90)
NSGraphicsContext.restoreGraphicsState()
NSColor.white.withAlphaComponent(0.35).setStroke()
let rim = NSBezierPath(roundedRect: body.insetBy(dx: 2, dy: 2), xRadius: iconSize * 0.225, yRadius: iconSize * 0.225)
rim.lineWidth = 3
rim.stroke()
let config = NSImage.SymbolConfiguration(pointSize: iconSize * 0.46, weight: .semibold).applying(.init(paletteColors: [.white]))
if let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
    let s = bolt.size
    NSGraphicsContext.saveGraphicsState()
    let glyphShadow = NSShadow()
    glyphShadow.shadowColor = NSColor(srgbRed: 0.02, green: 0.30, blue: 0.12, alpha: 0.45)
    glyphShadow.shadowOffset = NSSize(width: 0, height: -6)
    glyphShadow.shadowBlurRadius = 14
    glyphShadow.set()
    bolt.draw(in: CGRect(x: body.midX - s.width / 2, y: body.midY - s.height / 2, width: s.width, height: s.height))
    NSGraphicsContext.restoreGraphicsState()
}

// Wordmark and tagline.
NSAttributedString(string: "Volta", attributes: [
    .font: NSFont.systemFont(ofSize: 300, weight: .semibold),
    .foregroundColor: NSColor(srgbRed: 0.95, green: 0.97, blue: 0.95, alpha: 1),
    .kern: -12,
]).draw(at: NSPoint(x: 1040, y: 430))
NSAttributedString(string: "Ce que consomme ton Mac, en direct, dans la barre des menus.", attributes: [
    .font: NSFont.systemFont(ofSize: 54, weight: .regular),
    .foregroundColor: NSColor(srgbRed: 0.95, green: 0.97, blue: 0.95, alpha: 0.62),
]).draw(at: NSPoint(x: 1052, y: 350))
// A menu bar reading, as the app shows it.
let pill = CGRect(x: 1052, y: 210, width: 250, height: 84)
ctx.addPath(CGPath(roundedRect: pill, cornerWidth: 22, cornerHeight: 22, transform: nil))
ctx.setFillColor(rgb(0xFFFFFF, 0.08))
ctx.fillPath()
NSAttributedString(string: "14.7 W", attributes: [
    .font: NSFont.monospacedDigitSystemFont(ofSize: 50, weight: .medium),
    .foregroundColor: NSColor(srgbRed: 0.95, green: 0.97, blue: 0.95, alpha: 0.9),
]).draw(at: NSPoint(x: pill.minX + 44, y: pill.minY + 14))

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("✓ \(output)")
