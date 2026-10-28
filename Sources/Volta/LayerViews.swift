import AppKit
import SwiftUI

// Live-data animations (every sample) are handed to Core Animation: the app commits the new
// state once and the render server interpolates it. The same animations done in SwiftUI are
// re-rendered by the app on the CPU at every frame (measured: 20–30 % CPU with the panel open).

private func animate(_ animated: Bool, duration: CFTimeInterval, _ changes: () -> Void) {
    CATransaction.begin()
    if animated {
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1))
    } else {
        CATransaction.setDisableActions(true)
    }
    changes()
    CATransaction.commit()
}

// MARK: - Segmented bar

/// Horizontal bar made of colored segments whose widths glide to new values.
struct SegmentBar: NSViewRepresentable {
    /// Fraction of the full width for each segment (≤ 0.005 hides it).
    let fractions: [Double]
    /// Layer colors.
    let colors: [NSColor]
    var focus: Int? = nil
    var gap: CGFloat = 2
    var radius: CGFloat = 3
    var minWidth: CGFloat = 3
    let animated: Bool

    func makeNSView(context: Context) -> SegmentBarView { SegmentBarView() }
    func updateNSView(_ view: SegmentBarView, context: Context) {
        view.update(fractions: fractions, colors: colors, focus: focus,
                    gap: gap, radius: radius, minWidth: minWidth, animated: animated)
    }
}

final class SegmentBarView: NSView {
    private var segments: [CALayer] = []
    private var fractions: [Double] = []
    private var colors: [NSColor] = []
    private var focus: Int?
    private var gap: CGFloat = 2, radius: CGFloat = 3, minWidth: CGFloat = 3

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func update(fractions: [Double], colors: [NSColor], focus: Int?, gap: CGFloat, radius: CGFloat, minWidth: CGFloat, animated: Bool) {
        let colorsChanged = colors != self.colors
        guard fractions != self.fractions || colorsChanged || focus != self.focus else { return }
        self.fractions = fractions
        self.colors = colors
        self.focus = focus
        self.gap = gap
        self.radius = radius
        self.minWidth = minWidth
        while segments.count < fractions.count {
            let l = CALayer()
            segments.append(l)
            layer?.addSublayer(l)
        }
        animate(animated && window != nil && bounds.width > 0, duration: 0.5) {
            if colorsChanged { applyColors() }
            placeSegments()
        }
    }

    override func layout() {
        super.layout()
        animate(false, duration: 0) { placeSegments() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        animate(false, duration: 0) { applyColors() }
    }

    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            for (l, c) in zip(segments, colors) { l.backgroundColor = c.cgColor }
        }
    }

    private func placeSegments() {
        let shown = fractions.map { $0 > 0.005 ? $0 : 0 }
        let count = shown.filter { $0 > 0 }.count
        let available = max(0, bounds.width - CGFloat(max(0, count - 1)) * gap)
        var widths = shown.map { $0 > 0 ? max(minWidth, available * $0) : 0 }
        let total = widths.reduce(0, +)
        if total > available, total > 0 { widths = widths.map { $0 * available / total } }
        var x: CGFloat = 0
        for (i, l) in segments.enumerated() {
            let w = i < widths.count ? widths[i] : 0
            l.frame = CGRect(x: x, y: 0, width: w, height: bounds.height)
            l.cornerRadius = min(radius, bounds.height / 2)
            l.opacity = focus == nil || focus == i ? 1 : 0.3
            if w > 0 { x += w + gap }
        }
    }
}

// MARK: - Pulse dot

/// Small dot that beats once each time `trigger` changes.
struct PulseDot: NSViewRepresentable {
    let color: Color
    let trigger: Date?

    func makeNSView(context: Context) -> PulseDotView { PulseDotView() }
    func updateNSView(_ view: PulseDotView, context: Context) {
        view.update(color: NSColor(color), trigger: trigger)
    }
}

final class PulseDotView: NSView {
    private let dot = CALayer()
    private var color: NSColor = .controlAccentColor
    private var trigger: Date?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        dot.opacity = 0.65
        layer?.addSublayer(dot)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        animate(false, duration: 0) {
            dot.frame = bounds
            dot.cornerRadius = bounds.height / 2
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColor()
    }

    func update(color: NSColor, trigger: Date?) {
        if color != self.color {
            self.color = color
            applyColor()
        }
        guard trigger != self.trigger else { return }
        let first = self.trigger == nil
        self.trigger = trigger
        guard !first, trigger != nil, window != nil else { return }
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [1, 1.7, 1]
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0.65, 1, 0.65]
        let beat = CAAnimationGroup()
        beat.animations = [scale, opacity]
        beat.duration = 0.6
        beat.timingFunction = CAMediaTimingFunction(name: .easeOut)
        dot.add(beat, forKey: "beat")
    }

    private func applyColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            animate(false, duration: 0) { dot.backgroundColor = color.cgColor }
        }
    }
}

// MARK: - Rolling number

/// Big number that rolls up (value rising) or down (falling) when it changes.
struct RollingNumber: NSViewRepresentable {
    let text: String
    let value: Double
    /// From the style (`StyleTokens.displayNSFont`), with tabular digits.
    let font: NSFont
    /// nil: label color (follows the appearance).
    var color: NSColor? = nil
    /// Stroke width: the number is drawn as an outline (Glyphe night titles). nil: filled.
    var outline: CGFloat? = nil
    let animated: Bool

    func makeNSView(context: Context) -> RollingNumberView { RollingNumberView() }
    func updateNSView(_ view: RollingNumberView, context: Context) {
        view.update(text: text, value: value, font: font, color: color, outline: outline, animated: animated)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: RollingNumberView, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }
}

/// Two text layers in a clipped container: the old value slides out and fades, the new one slides in.
/// Outlined numbers use shape layers built from the glyph outlines instead of text layers.
final class RollingNumberView: NSView {
    private var current: CALayer?
    private var outline: CGFloat?
    private var text = ""
    private var value = 0.0
    private var font = NSFont.systemFont(ofSize: 34)
    private var color: NSColor?
    private var shownAt: CFTimeInterval = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Wide enough for "88.8 W": the width stays stable while values change, so nothing reflows.
    override var intrinsicContentSize: NSSize {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let width = max((text as NSString).size(withAttributes: attributes).width,
                        ("88.8 W" as NSString).size(withAttributes: attributes).width)
        return NSSize(width: ceil(width) + 2, height: lineHeight)
    }

    private var lineHeight: CGFloat { ceil(font.ascender - font.descender + font.leading) }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        shownAt = CACurrentMediaTime()
        current?.contentsScale = window?.backingScaleFactor ?? 2
    }

    override func layout() {
        super.layout()
        animate(false, duration: 0) { current?.frame = textFrame }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        animate(false, duration: 0) { applyColor(current) }
    }

    private func applyColor(_ l: CALayer?) {
        if let text = l as? CATextLayer { text.foregroundColor = textColor }
        if let shape = l as? CAShapeLayer { shape.strokeColor = textColor }
    }

    private var textFrame: CGRect { CGRect(x: 0, y: bounds.height - lineHeight, width: max(bounds.width, intrinsicContentSize.width), height: lineHeight) }

    private var textColor: CGColor {
        let base = self.color ?? .labelColor
        var color = base.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { color = base.cgColor }
        return color
    }

    private func makeLayer() -> CALayer {
        if let outline {
            let l = CAShapeLayer()
            // Baseline where the text layer would put it: one ascender below the top of the line.
            var shift = CGAffineTransform(translationX: outline / 2, y: lineHeight - font.ascender)
            l.path = GlyphPath.make(text, font: font).copy(using: &shift)
            l.fillColor = nil
            l.strokeColor = textColor
            l.lineWidth = outline
            l.lineJoin = .round
            l.contentsScale = window?.backingScaleFactor ?? 2
            l.frame = textFrame
            return l
        }
        let l = CATextLayer()
        l.string = text
        l.font = font
        l.fontSize = font.pointSize
        l.foregroundColor = textColor
        l.contentsScale = window?.backingScaleFactor ?? 2
        l.alignmentMode = .left
        l.frame = textFrame
        return l
    }

    func update(text: String, value: Double, font: NSFont, color: NSColor?, outline: CGFloat?, animated: Bool) {
        if color != self.color {
            self.color = color
            animate(false, duration: 0) { applyColor(current) }
        }
        let outlineChanged = outline != self.outline
        self.outline = outline
        guard text != self.text || font != self.font || outlineChanged else { return }
        // No roll for the first real value, while the panel is appearing, or when the style changes.
        let roll = animated && window != nil && font == self.font && !outlineChanged && !self.text.isEmpty && self.text != "–"
            && CACurrentMediaTime() - shownAt > 0.8
        let rising = value >= self.value
        self.text = text
        self.value = value
        let fontChanged = font != self.font
        self.font = font
        if fontChanged { invalidateIntrinsicContentSize() }

        let old = current
        let new = makeLayer()
        current = new
        animate(false, duration: 0) { layer?.addSublayer(new) }
        guard roll, let old else {
            old?.removeFromSuperlayer()
            return
        }

        // Layer coordinates: y goes up. Rising: the new value comes from below, the old one leaves upward.
        let distance = lineHeight * 0.55 * (rising ? 1 : -1)
        let duration = 0.36
        let timing = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
        func slide(_ l: CALayer, from: CGFloat, to: CGFloat, opacity: (Float, Float)) {
            let move = CABasicAnimation(keyPath: "transform.translation.y")
            move.fromValue = from
            move.toValue = to
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = opacity.0
            fade.toValue = opacity.1
            let group = CAAnimationGroup()
            group.animations = [move, fade]
            group.duration = duration
            group.timingFunction = timing
            l.add(group, forKey: "roll")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { old.removeFromSuperlayer() }
        old.opacity = 0
        old.transform = CATransform3DMakeTranslation(0, distance, 0)
        slide(old, from: 0, to: distance, opacity: (1, 0))
        slide(new, from: -distance, to: 0, opacity: (0, 1))
        CATransaction.commit()
    }
}

// MARK: - Energy channel

/// One energy link between two of the three flow nodes (0 = charger, 1 = Mac, 2 = battery).
struct EnergyLink: Equatable {
    var from: Int
    var to: Int
    var watts: Double
    var color: NSColor
    /// Color of the empty tube.
    var idle: NSColor = .tertiaryLabelColor
    var active: Bool
}

/// A straight channel between the flow nodes in which soft highlights stream like water,
/// in the direction of the energy (faster with more watts). Drawn behind the glass nodes.
/// Pure Core Animation: the render server animates it, and it only exists while the panel is open.
struct EnergyChannel: NSViewRepresentable {
    let links: [EnergyLink]
    /// Must match the HStack of FlowView: three equal nodes separated by `gap`.
    let gap: CGFloat

    func makeNSView(context: Context) -> EnergyChannelView { EnergyChannelView() }
    func updateNSView(_ view: EnergyChannelView, context: Context) {
        view.update(links: links, gap: gap)
    }
}

final class EnergyChannelView: NSView {
    private final class Lane {
        let channel = CALayer()          // the tube: rounded, tinted, clips the stream
        let stream = CAGradientLayer()   // repeating soft highlights, one period wider than the tube
        var link: EnergyLink?
        var key = ""                     // what the running animation was built for

        init() {
            channel.masksToBounds = true
            stream.startPoint = CGPoint(x: 0, y: 0.5)
            stream.endPoint = CGPoint(x: 1, y: 0.5)
            channel.addSublayer(stream)
        }
    }

    private static let period: CGFloat = 24
    private static let thickness: CGFloat = 5
    private var lanes: [Lane] = []
    private var links: [EnergyLink] = []
    private var gap: CGFloat = 26

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(links: [EnergyLink], gap: CGFloat) {
        guard links != self.links || gap != self.gap else { return }
        self.links = links
        self.gap = gap
        while lanes.count < links.count {
            let lane = Lane()
            layer?.addSublayer(lane.channel)
            lanes.append(lane)
        }
        for (i, lane) in lanes.enumerated() { lane.link = i < links.count ? links[i] : nil }
        configure()
    }

    override func layout() {
        super.layout()
        configure(force: true)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        configure(force: true)
    }

    private func configure(force: Bool = false) {
        guard bounds.width > 0 else { return }
        let nodeWidth = (bounds.width - 2 * gap) / 3
        func center(_ node: Int) -> CGFloat { nodeWidth / 2 + CGFloat(node) * (nodeWidth + gap) }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for lane in lanes {
            guard let link = lane.link else {
                lane.channel.isHidden = true
                continue
            }
            lane.channel.isHidden = false
            let rightward = link.to > link.from
            // From inside the source node to inside the destination node, passing under the glass edges.
            let a = center(link.from) + (rightward ? 1 : -1) * nodeWidth * 0.2
            let b = center(link.to) - (rightward ? 1 : -1) * nodeWidth * 0.2
            let h = Self.thickness
            let frame = CGRect(x: min(a, b), y: bounds.midY - h / 2, width: abs(b - a), height: h)

            // Stream speed: 5 W ≈ 20 pt/s, 60 W ≈ 70 pt/s (quantized: no restart on tiny changes).
            let speed = link.active ? (min(70, 12 + link.watts * 1.2) / 4).rounded() * 4 : 0
            let key = "\(frame)|\(rightward)|\(speed)|\(link.active)|\(link.color)"
            guard force || key != lane.key else { continue }
            lane.key = key

            let p = Self.period
            lane.channel.frame = frame
            lane.channel.cornerRadius = h / 2
            lane.stream.frame = CGRect(x: rightward ? -p : 0, y: 0, width: frame.width + p, height: h)

            var bed = NSColor.gray.cgColor, clear = NSColor.gray.cgColor, glint = NSColor.gray.cgColor
            effectiveAppearance.performAsCurrentDrawingAppearance {
                let base = link.active ? link.color : link.idle
                bed = base.withAlphaComponent(link.active ? 0.28 : 0.2).cgColor
                clear = base.withAlphaComponent(0).cgColor
                glint = base.withAlphaComponent(0.95).cgColor
            }
            lane.channel.backgroundColor = bed

            lane.stream.removeAllAnimations()
            guard link.active else {
                lane.stream.colors = nil
                continue
            }
            // Soft highlight in the middle of each period: clear → glint → clear, repeated.
            let periods = Int((lane.stream.bounds.width / p).rounded(.up))
            var colors: [CGColor] = []
            var locations: [NSNumber] = []
            let total = CGFloat(periods) * p
            for k in 0..<periods {
                let start = CGFloat(k) * p / total, width = p / total
                colors += [clear, glint, clear]
                locations += [start + width * 0.1, start + width * 0.5, start + width * 0.9].map { NSNumber(value: Double($0)) }
            }
            lane.stream.frame.size.width = total
            lane.stream.colors = colors
            lane.stream.locations = locations

            // Shift by exactly one period, forever: a seamless flow.
            let flow = CABasicAnimation(keyPath: "position.x")
            let x = lane.stream.position.x
            flow.fromValue = x
            flow.toValue = x + (rightward ? p : -p)
            flow.duration = Double(p / max(speed, 1))
            flow.repeatCount = .infinity
            lane.stream.add(flow, forKey: "flow")
        }
        CATransaction.commit()
    }
}
