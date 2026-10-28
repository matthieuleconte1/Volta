import AppKit
import CoreText
import SwiftUI

// Atelier Glyphe night grammar. Everything is one red, so shape takes over in the interface (data keeps shades of red).
// Filled = chosen, main action · solid stroke = available · dotted = secondary, work area ·
// hatching = emphasis (replaces the inverse surfaces) · offset of a hard shadow = height of the layer ·
// outline = large titles drawn with a stroke · capitals for labels and buttons.

/// Hatching of the night: diagonal lines (135°) behind emphasised surfaces, drawn once per color as a small tile.
enum NightHatch {
    private static var tiles: [NSColor: NSImage] = [:]

    static func paint(_ color: NSColor) -> ImagePaint {
        if let tile = tiles[color] { return ImagePaint(image: Image(nsImage: tile)) }
        let size: CGFloat = 7
        let tile = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            color.set()
            // Three copies of the diagonal so the tile repeats without seams.
            for k in -1...1 {
                let o = CGFloat(k) * size
                let path = NSBezierPath()
                path.move(to: NSPoint(x: o - 1, y: -1))
                path.line(to: NSPoint(x: o + size + 1, y: size + 1))
                path.lineWidth = 1.5
                path.stroke()
            }
            return true
        }
        tiles[color] = tile
        return ImagePaint(image: Image(nsImage: tile))
    }
}

extension View {
    /// Night elevation: a hard shadow, offset by the height of the layer (1 rest, 2 raised, 3 floating, 4 window).
    func hardShadow<S: Shape>(_ t: StyleTokens, _ shape: S, level: Int) -> some View {
        let offsets: [CGFloat] = [0, 1, 3, 5, 8]
        let alphas = [0, 0.3, 0.32, 0.36, 0.4]
        let i = min(max(level, 0), 4)
        return background(shape.fill(Color(red: 1, green: 0.235, blue: 0.157, opacity: alphas[i])).offset(x: offsets[i], y: offsets[i]))
    }

    /// Night hatching behind emphasised surfaces (what the inverse color does by day).
    func hatched<S: Shape>(_ t: StyleTokens, _ shape: S) -> some View {
        overlay(shape.fill(NightHatch.paint(NSColor(red: 1, green: 0.235, blue: 0.157, alpha: 0.17))).allowsHitTesting(false))
    }
}

/// Dotted line: secondary separations at night.
struct DashedLine: View {
    let color: Color

    var body: some View {
        GeometryReader { geo in
            Path { p in
                p.move(to: CGPoint(x: 0, y: 0.5))
                p.addLine(to: CGPoint(x: geo.size.width, y: 0.5))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        .frame(height: 1)
    }
}

/// Outline of a string, glyph by glyph (baseline at y = 0, y up, as Core Text draws it).
enum GlyphPath {
    static func make(_ text: String, font: NSFont) -> CGPath {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        let path = CGMutablePath()
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let runFont = attributes[kCTFontAttributeName] as! CTFont
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            for i in 0..<count {
                if let glyph = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) {
                    path.addPath(glyph, transform: CGAffineTransform(translationX: positions[i].x, y: positions[i].y))
                }
            }
        }
        return path
    }

    static func width(_ text: String, font: NSFont) -> CGFloat {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }
}

/// Large title drawn with a stroke (night): "Contour · grands titres tracés au trait".
struct OutlineText: View {
    let text: String
    let font: NSFont
    let color: Color
    var lineWidth: CGFloat = 1.1

    var body: some View {
        let height = ceil(font.ascender - font.descender)
        OutlineShape(glyphs: Path(GlyphPath.make(text, font: font)), ascender: font.ascender)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
            .frame(width: ceil(GlyphPath.width(text, font: font)) + lineWidth, height: height)
    }

    private struct OutlineShape: Shape {
        let glyphs: Path
        let ascender: CGFloat

        func path(in rect: CGRect) -> Path {
            // Core Text is y-up from the baseline; SwiftUI is y-down from the top.
            glyphs.applying(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: ascender))
        }
    }
}

/// Stepped slider of the chart (intensity of the night red): one segment per step, filled up to the value.
/// At night, the empty segments are drawn with a stroke.
struct StepSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    @Environment(\.styleTokens) private var t

    var body: some View {
        let count = Int(((range.upperBound - range.lowerBound) / step).rounded()) + 1
        let current = Int(((value - range.lowerBound) / step).rounded())
        HStack(spacing: 3) {
            ForEach(0..<count, id: \.self) { i in
                let on = i <= current
                let shape = RoundedRectangle(cornerRadius: i == current ? 4 : 2, style: .continuous)
                Group {
                    if on {
                        shape.fill(i == current ? t.accent : t.ink)
                    } else if t.night {
                        shape.strokeBorder(t.line2, lineWidth: 1)
                    } else {
                        shape.fill(t.control)
                    }
                }
                .frame(height: i == current ? 20 : 14)
            }
        }
        .frame(height: 20)
        .overlay {
            // Click or drag anywhere along the segments.
            GeometryReader { geo in
                Color.clear.contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                        let i = min(count - 1, max(0, Int(drag.location.x / geo.size.width * CGFloat(count))))
                        let new = range.lowerBound + Double(i) * step
                        if new != value { value = new }
                    })
            }
        }
        .animation(GlypheSpring.fast, value: current)
    }
}
