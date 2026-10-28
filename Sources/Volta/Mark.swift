import AppKit
import SwiftUI

/// Atelier Glyphe signature loader: a comet of dots running along a nine-lobed cookie that turns slowly.
/// The head takes the accent. Only shown while a first measure is being taken (a few seconds).
/// Core Animation runs it in the render server: drawn in SwiftUI, it was re-rendered by the app at every frame.
struct DotComet: NSViewRepresentable {
    let t: StyleTokens
    var count = 9
    var size: CGFloat = 18

    func makeNSView(context: Context) -> DotCometView { DotCometView() }
    func updateNSView(_ view: DotCometView, context: Context) {
        view.update(count: count, size: size, ink: NSColor(t.ink), accent: NSColor(t.accent),
                    animated: context.environment.motion != .off)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: DotCometView, context: Context) -> CGSize? {
        CGSize(width: size, height: size)
    }
}

final class DotCometView: NSView {
    /// Turns the whole cookie (36°/s); the dots run along it inside.
    private let spinner = CALayer()
    private var dots: [CALayer] = []
    private var key = ""
    private var ink: NSColor = .labelColor
    private var accent: NSColor = .controlAccentColor
    private var size: CGFloat = 18
    private var animated = true

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(spinner)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func update(count: Int, size: CGFloat, ink: NSColor, accent: NSColor, animated: Bool) {
        self.ink = ink
        self.accent = accent
        self.size = size
        self.animated = animated
        if dots.count != count {
            dots.forEach { $0.removeFromSuperlayer() }
            dots = (0..<count).map { _ in CALayer() }
            dots.forEach(spinner.addSublayer)
        }
        build()
    }

    override func layout() {
        super.layout()
        build()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        key = ""  // animations are dropped when the layer leaves the window
        build()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        key = ""
        build()
    }

    /// Rebuilds the animations only when something they depend on changed.
    private func build() {
        guard bounds.width > 0, window != nil else { return }
        let newKey = "\(bounds.size)|\(dots.count)|\(ink)|\(accent)|\(animated)"
        guard newKey != key else { return }
        key = newKey

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        spinner.frame = bounds
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2 * 0.8
        // One lap of the cookie, sampled evenly in angle: the dots keep the speed profile of the drawn version.
        let steps = 72
        let lap: [NSValue] = (0...steps).map { k in
            let u = Double(k) / Double(steps) * 2 * .pi
            let r = radius * (1 - 0.12 * (1 - cos(9 * u)) / 2)
            return NSValue(point: CGPoint(x: center.x + r * cos(u), y: center.y + r * sin(u)))
        }
        let lapDuration = 1 / 0.62
        let count = dots.count
        effectiveAppearance.performAsCurrentDrawingAppearance {
            for (i, dot) in dots.enumerated() {
                let f = count > 1 ? Double(i) / Double(count - 1) : 1
                let d = size * 0.09 * (0.32 + 0.68 * pow(f, 1.3))
                dot.bounds = CGRect(x: 0, y: 0, width: 2 * d, height: 2 * d)
                dot.cornerRadius = d
                dot.backgroundColor = (i == count - 1 ? accent : ink).withAlphaComponent(0.1 + 0.9 * pow(f, 1.6)).cgColor
                let start = Int((f * 0.78 * Double(steps)).rounded()) % steps
                dot.position = lap[start].pointValue
                dot.removeAllAnimations()
                guard animated else { continue }
                let run = CAKeyframeAnimation(keyPath: "position")
                run.values = lap
                run.calculationMode = .linear
                run.duration = lapDuration
                run.repeatCount = .infinity
                // Each dot trails the head by its share of 78 % of a lap.
                run.timeOffset = f * 0.78 * lapDuration
                dot.add(run, forKey: "run")
            }
        }
        spinner.removeAllAnimations()
        if animated {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = 2 * Double.pi
            spin.duration = 10
            spin.repeatCount = .infinity
            spinner.add(spin, forKey: "spin")
        }
        CATransaction.commit()
    }
}

/// Loading indicator of the style: the system spinner under the glass, the dot comet in Glyphe.
struct StyledProgress: View {
    let t: StyleTokens

    var body: some View {
        if t.isGlass {
            ProgressView().controlSize(.small)
        } else {
            DotComet(t: t)
        }
    }
}
