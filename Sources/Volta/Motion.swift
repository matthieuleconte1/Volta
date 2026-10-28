import SwiftUI

/// Atelier Glyphe springs (M3 Expressive tokens: damping, stiffness). Everything that moves follows
/// a physical spring, not a fixed curve: it arrives, it settles.
enum GlypheSpring {
    /// Presses, toggles, small controls (damping 0.62, stiffness 800).
    static let fast = Animation.spring(response: 0.22, dampingFraction: 0.62)
    /// Selection, tabs, page changes (0.78, 380).
    static let standard = Animation.spring(response: 0.32, dampingFraction: 0.78)
    /// Large surfaces, reveals (0.82, 200).
    static let slow = Animation.spring(response: 0.44, dampingFraction: 0.82)
}

/// Motion signature of a style: how the sections arrive when the panel opens,
/// how pages change and how selections move.
enum RevealStyle {
    /// Verre: sections fade and slide in one after the other, the panel resizes smoothly.
    case glass
    /// Atelier Glyphe: sections rise from below on a slow spring, staggered; pages slide along a shared axis.
    case glyphe

    /// Arrival of section `order` when the panel opens.
    func entrance(_ order: Int, level: MotionLevel) -> Animation? {
        switch self {
        case .glass: level.animation(.spring(response: 0.5, dampingFraction: 0.8))?.delay(Double(order) * 0.045)
        case .glyphe: level.animation(GlypheSpring.slow)?.delay(0.06 + Double(order) * 0.034)
        }
    }

    /// How far below a section starts, and at which scale.
    var entranceOffset: CGFloat { self == .glass ? 12 : 22 }
    var entranceScale: CGFloat { self == .glass ? 0.97 : 0.985 }

    /// Main page ⇄ settings page: the settings live on the right, the main page on the left.
    func page(settings: Bool, level: MotionLevel) -> AnyTransition {
        let side: CGFloat = settings ? 1 : -1
        switch level {
        case .off: return .identity
        case .subtle: return .opacity
        case .full:
            switch self {
            case .glass:
                return .offset(x: 28 * side).combined(with: .opacity)
            case .glyphe:
                // Shared axis: both pages move along the same line, the incoming one settles from slightly smaller.
                return .offset(x: 26 * side).combined(with: .opacity).combined(with: .scale(scale: 0.985))
            }
        }
    }

    /// Page change animation.
    var navigation: Animation {
        switch self {
        case .glass: .smooth(duration: 0.38)
        case .glyphe: GlypheSpring.standard
        }
    }

    /// Selection moving inside a control (segmented, tabs, swatches).
    var selection: Animation {
        switch self {
        case .glass: .snappy(duration: 0.3)
        case .glyphe: GlypheSpring.standard
        }
    }
}
