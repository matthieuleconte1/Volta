import AppKit
import SwiftUI

// Panel styles, on the model of Halo's skins: a style decides everything (surfaces, colors, type,
// controls, motion) through `StyleTokens`, read from the environment by every view of the panel.

/// Art direction of the panel. "Verre" follows the glass settings (material, tint, palette, accent);
/// "Atelier Glyphe" is a complete style taken from the Atelier Glyphe chart.
enum PanelStyle: String, CaseIterable, Identifiable {
    case glass, glyphe
    var id: String { rawValue }

    var title: String {
        switch self {
        case .glass: "Verre"
        case .glyphe: "Atelier Glyphe"
        }
    }

    var detail: String {
        switch self {
        case .glass: "Liquid Glass, palette et accent réglables."
        case .glyphe: "Cadre noir en retrait, un seul accent, titres élargis, couches lisibles et ressorts. La nuit, tout passe en rouge."
        }
    }

    /// Motion signature of the style (see Motion.swift).
    var reveal: RevealStyle {
        switch self {
        case .glass: .glass
        case .glyphe: .glyphe
        }
    }
}

/// Atelier Glyphe themes: the frame stays black in all of them, it carries the identity.
enum GlypheTheme: String, CaseIterable, Identifiable {
    case auto, day, dark, night
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: "Auto"
        case .day: "Jour"
        case .dark: "Sombre"
        case .night: "Nuit"
        }
    }

    /// Window appearance (native controls, menus); nil follows the system.
    var appearance: NSAppearance? {
        switch self {
        case .auto: nil
        case .day: NSAppearance(named: .aqua)
        case .dark, .night: NSAppearance(named: .darkAqua)
        }
    }
}

/// The single accent of Atelier Glyphe. It never decorates: it marks the main action, a state or an error.
enum GlypheAccent: String, CaseIterable, Identifiable {
    case orange, amber, green, coral, violet, mono
    var id: String { rawValue }

    var label: String {
        switch self {
        case .orange: "Orange"
        case .amber: "Ambre"
        case .green: "Vert"
        case .coral: "Corail"
        case .violet: "Violet"
        case .mono: "Mono"
        }
    }

    /// nil: "Mono", the accent is the text color.
    var hex: UInt32? {
        switch self {
        case .orange: 0xED6A0C
        case .amber: 0xEFB85C
        case .green: 0x78DD8B
        case .coral: 0xFF6C67
        case .violet: 0xA25BFF
        case .mono: nil
        }
    }

    /// Text on the accent: white on orange and violet, black on amber, green and coral.
    var onAccentIsWhite: Bool { self == .orange || self == .violet }

    /// Menu bar alert color (nil: Mono, the weight alone marks the alert).
    var nsColor: NSColor? { hex.map { NSColor(rgb: $0) } }
}

/// Everything a style decides. Built once per render of the panel (`PopoverView`) and passed down the environment.
struct StyleTokens {
    var style: PanelStyle
    /// Atelier Glyphe night: a single red, shape takes over (outlines, dashes, hard shadows, capitals).
    var night = false
    /// Color scheme forced on the content; nil keeps the system one (under the glass).
    var scheme: ColorScheme?

    // Surfaces
    /// Window corner radius.
    var radius: CGFloat
    var frame: Color = .clear
    var onFrame: Color = .primary
    var onFrame2: Color = .secondary
    var frameLine: Color = .clear
    /// Inset pane, laid in the frame (Glyphe).
    var pane: Color = .clear
    var paneRadius: CGFloat = 12
    var card: Color
    var cardRadius: CGFloat
    var control: Color
    var hover: Color
    var line: Color = .clear
    var line2: Color = .clear

    // Ink
    var ink: Color = .primary
    var ink2: Color = .secondary
    var ink3 = Color(nsColor: .tertiaryLabelColor)
    var inverse: Color = .primary
    var onInverse: Color = .white
    var accent: Color
    var onAccent: Color = .white
    /// Colors of the power components (CPU, GPU, display, SoC, other).
    var components: [Color]
    /// Their fills (SwiftUI) and layer colors (Core Animation): patterns at night, plain colors otherwise.
    var componentFills: [AnyShapeStyle] = []
    var componentLayers: [NSColor] = []
    /// Energy flowing into the battery, and out of it.
    var charge: NSColor = .systemGreen
    var discharge: NSColor = .systemOrange
    var positive: Color = .green

    // Type
    var numberFont: NumberFont = .rounded
    /// Text family (Red Hat Display) and display family for titles and figures (Zalando Sans Expanded).
    var textFamily: String?
    var displayFamily: String?

    var isGlass: Bool { style == .glass }

    static let glypheText = "Red Hat Display"
    static let glypheDisplay = "Zalando Sans Expanded"

    // MARK: Type

    func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        if let textFamily, let font = VariableFont.make(textFamily, size: size, weight: VariableFont.value(weight) + (night ? 30 : 0)) {
            return Font(font as CTFont)
        }
        return .system(size: size, weight: weight)
    }

    /// Titles and figures: expanded and tight in Glyphe, the user's number font under the glass.
    func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        if isGlass { return .system(size: size, weight: weight, design: numberFont.design) }
        if let displayFamily, let font = VariableFont.make(displayFamily, size: size, weight: VariableFont.value(weight), tabular: true) {
            return Font(font as CTFont)
        }
        return .system(size: size, weight: weight).width(.expanded)
    }

    /// AppKit version of `display` (rolling number), with tabular digits.
    func displayNSFont(_ size: CGFloat, _ weight: Font.Weight) -> NSFont {
        if !isGlass, let displayFamily,
           let font = VariableFont.make(displayFamily, size: size, weight: VariableFont.value(weight), tabular: true) {
            return font
        }
        let base = NSFont.systemFont(ofSize: size, weight: VariableFont.nsWeight(VariableFont.value(weight)),
                                     width: isGlass ? .standard : .expanded).fontDescriptor
        // Only the glass changes the design (asking for the default one would drop the weight and width).
        let systemDesign: NSFontDescriptor.SystemDesign? = switch isGlass ? numberFont : .standard {
        case .rounded: .rounded
        case .standard: nil
        case .mono: .monospaced
        case .serif: .serif
        }
        let descriptor = (systemDesign.flatMap { base.withDesign($0) } ?? base).addingAttributes([
            .featureSettings: [[NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector]],
        ])
        return NSFont(descriptor: descriptor, size: size) ?? .systemFont(ofSize: size, weight: .semibold)
    }

    /// Technical labels: system mono in capitals, spaced (Glyphe); small semibold capitals under the glass.
    func label(_ size: CGFloat = 11) -> Font {
        isGlass ? .system(size: size, weight: .semibold) : .system(size: size - 0.5, weight: night ? .medium : .regular, design: .monospaced)
    }

    var labelTracking: CGFloat { isGlass ? 0 : night ? 1 : 0.6 }

    /// Button and tab text: capitals at night, when color can no longer tell things apart.
    func caption(_ text: String) -> String { night ? text.uppercased() : text }

    // MARK: Factory

    static func make(_ settings: AppSettings, systemDark: Bool, date: Date = Date()) -> StyleTokens {
        var t = switch settings.panelStyle {
        case .glass: glass(settings)
        case .glyphe: glyphe(settings, systemDark: systemDark, date: date)
        }
        if t.componentFills.isEmpty {
            t.componentFills = t.components.map { AnyShapeStyle($0) }
            t.componentLayers = t.components.map { NSColor($0) }
        }
        return t
    }

    private static func glass(_ s: AppSettings) -> StyleTokens {
        StyleTokens(
            style: .glass, radius: 24,
            card: Color.primary.opacity(0.05), cardRadius: 14,
            control: Color.primary.opacity(0.06), hover: Color.primary.opacity(0.07),
            accent: s.accent.color, components: s.palette.colors, numberFont: s.numberFont)
    }

    private static func glyphe(_ s: AppSettings, systemDark: Bool, date: Date) -> StyleTokens {
        let chosen = s.glypheTheme(at: date)
        let theme: GlypheTheme = chosen == .auto ? (systemDark ? .dark : .day) : chosen
        let accent = s.glypheAccent
        var t = StyleTokens(
            style: .glyphe, scheme: theme == .day ? .light : .dark, radius: 16,
            frame: Color(rgb: 0x050403), onFrame: .white, onFrame2: .white.opacity(0.56), frameLine: .white.opacity(0.1),
            card: .clear, cardRadius: 12, control: .clear, hover: .clear,
            accent: .clear, components: [],
            textFamily: glypheText, displayFamily: glypheDisplay)

        switch theme {
        case .day:
            // The same roles on a warm paper; the frame stays black.
            t.pane = Color(rgb: 0xEFEEEC)
            t.card = .white
            t.control = Color(rgb: 0xE7E5E2)
            t.hover = Color(rgb: 0x080604, opacity: 0.05)
            t.line = Color(rgb: 0x080604, opacity: 0.07)
            t.line2 = Color(rgb: 0x080604, opacity: 0.14)
            t.ink = Color(rgb: 0x111111)
            t.ink2 = Color(rgb: 0x3D3B39)
            t.ink3 = Color(rgb: 0x6B6966)
            t.inverse = Color(rgb: 0x080604)
            t.onInverse = .white
        case .night:
            // A single red: it keeps night vision and sends no blue light. Its intensity is the user's.
            let nl = s.glypheNightLevel
            let red = Color(red: nl, green: 80 / 255 * nl, blue: 60 / 255 * nl)
            let lineRed = { (a: Double) in Color(red: 1, green: 60 / 255, blue: 40 / 255, opacity: a) }
            t.night = true
            t.cardRadius = 8
            t.paneRadius = 12
            t.frame = .black
            t.onFrame = red
            t.onFrame2 = red.opacity(0.6)
            t.frameLine = lineRed(0.3)
            t.pane = .black
            t.card = .black
            t.control = lineRed(0.1)
            t.hover = lineRed(0.1)
            t.line = lineRed(0.32)
            t.line2 = lineRed(0.58)
            t.ink = red
            t.ink2 = Color(red: 232 / 255 * nl, green: 66 / 255 * nl, blue: 49 / 255 * nl)
            t.ink3 = t.ink2
            t.inverse = red
            t.onInverse = .black
        default:
            // Warm black, stacked greys.
            t.pane = Color(rgb: 0x080604)
            t.card = Color(rgb: 0x121212)
            t.control = Color(rgb: 0x242424)
            t.hover = .white.opacity(0.05)
            t.line = .white.opacity(0.07)
            t.line2 = .white.opacity(0.14)
            t.ink = .white
            t.ink2 = Color(rgb: 0xC9C7C4)
            t.ink3 = Color(rgb: 0x909090)
            t.inverse = Color(rgb: 0xF1F1F1)
            t.onInverse = Color(rgb: 0x111111)
        }

        // At night the accent is locked on the red.
        if t.night {
            t.accent = Color(rgb: 0xFF3B24)
            t.onAccent = Color(rgb: 0x0A0000)
        } else if let hex = accent.hex {
            t.accent = Color(rgb: hex)
            t.onAccent = accent.onAccentIsWhite ? .white : Color(rgb: 0x111111)
        } else {
            t.accent = t.ink
            t.onAccent = t.card
        }

        // One color only: the accent marks the CPU (what moves the most), the rest are layered greys.
        let greys: [UInt32] = theme == .day ? [0x111111, 0x5A5754, 0x9A9792, 0xCFCBC6, 0xE2DFDB]
                                            : [0xF1F1F1, 0xA8A5A1, 0x6B6966, 0x3B3B3B, 0x2A2A2A]
        if t.night {
            // Shades of the single red, from the bright accent (CPU) down to a deep red (other). Opaque, so the
            // stacked areas of the chart don't blend into each other.
            let nl = s.glypheNightLevel
            t.components = [t.accent] + [0.78, 0.56, 0.38, 0.24].map {
                Color(red: nl * $0, green: 80 / 255 * nl * $0, blue: 60 / 255 * nl * $0)
            }
        } else if accent == .mono {
            t.components = greys.prefix(5).map { Color(rgb: $0) }
        } else {
            t.components = [t.accent] + greys.prefix(4).map { Color(rgb: $0) }
        }
        t.charge = NSColor(t.accent)
        t.discharge = NSColor(t.ink)
        t.positive = t.accent
        return t
    }
}

private struct StyleTokensKey: EnvironmentKey {
    static let defaultValue = StyleTokens.make(AppSettings.shared, systemDark: true)
}

extension EnvironmentValues {
    var styleTokens: StyleTokens {
        get { self[StyleTokensKey.self] }
        set { self[StyleTokensKey.self] = newValue }
    }
}

extension Color {
    init(rgb: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double(rgb >> 16 & 0xff) / 255, green: Double(rgb >> 8 & 0xff) / 255,
                  blue: Double(rgb & 0xff) / 255, opacity: opacity)
    }
}

extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(srgbRed: CGFloat(rgb >> 16 & 0xff) / 255, green: CGFloat(rgb >> 8 & 0xff) / 255,
                  blue: CGFloat(rgb & 0xff) / 255, alpha: 1)
    }
}

// MARK: - Surfaces

extension View {
    /// Glyphe "planche": a raised card with a one-pixel ring, a two-step shadow and a highlight on top.
    /// At night: drawn with a stroke, the offset of a hard shadow tells the height of the layer.
    /// Under the glass: the soft fill used so far.
    @ViewBuilder
    func planche(_ t: StyleTokens, radius: CGFloat? = nil, raised: Bool = true, level: Int = 1, emphasis: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: t.night ? min(radius ?? 8, 8) : radius ?? t.cardRadius, style: .continuous)
        if t.isGlass {
            background(shape.fill(t.card))
        } else if t.night {
            // Drawn with a stroke; the hard shadow's offset tells the layer height; hatching for emphasis.
            background {
                Group {
                    if emphasis {
                        shape.fill(Color.black).hatched(t, shape)
                    } else {
                        shape.fill(Color.black)
                    }
                }
                .overlay(shape.strokeBorder(t.line2, lineWidth: 1))
                .hardShadow(t, shape, level: raised ? level : 0)
            }
        } else {
            background {
                shape.fill(t.card)
                    .overlay(shape.strokeBorder(t.line2, lineWidth: 1))
                    .overlay(alignment: .top) {
                        // Highlight: a light line along the top of the surface.
                        shape.strokeBorder(LinearGradient(colors: [.white.opacity(t.scheme == .light ? 0.9 : 0.06), .clear],
                                                          startPoint: .top, endPoint: .center), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(raised ? (t.scheme == .light ? 0.05 : 0.5) : 0), radius: 1, y: 1)
                    .shadow(color: .black.opacity(raised ? (t.scheme == .light ? 0.06 : 0.3) : 0), radius: 8, y: 6)
            }
        }
    }

    /// Work area sunk into a surface (chart): a dotted outline at night, nothing otherwise.
    @ViewBuilder
    func well(_ t: StyleTokens) -> some View {
        if t.night {
            padding(8)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(t.line, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
        } else {
            self
        }
    }

    /// Glyphe inset pane: the content lives in a rounded panel laid in the black frame.
    func insetPane(_ t: StyleTokens) -> some View {
        let shape = RoundedRectangle(cornerRadius: t.paneRadius, style: .continuous)
        return background(shape.fill(t.pane))
            .overlay(shape.strokeBorder(t.night ? t.line2 : t.frameLine, lineWidth: 1).allowsHitTesting(false))
    }
}

// MARK: - Controls

/// Glyphe icon button: a soft square whose corners tighten and which sinks a little when pressed.
struct GlypheIconButtonStyle: ButtonStyle {
    let t: StyleTokens
    var onFrame = true

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        // At night the corners are tighter, and the button sits on a one-pixel hard shadow.
        let shape = RoundedRectangle(cornerRadius: t.night ? (pressed ? 3 : 6) : pressed ? 5 : 9, style: .continuous)
        configuration.label
            .font(.system(size: 13, weight: t.night ? .light : .medium))
            .foregroundStyle(onFrame ? t.onFrame : t.ink)
            .frame(width: 30, height: 30)
            .background {
                if t.night {
                    shape.fill(Color.black).overlay(shape.strokeBorder(t.line2, lineWidth: 1))
                        .hardShadow(t, shape, level: pressed ? 0 : 1)
                } else {
                    shape.fill(onFrame ? Color.white.opacity(pressed ? 0.14 : 0.08) : t.control)
                        .overlay(shape.strokeBorder(onFrame ? t.frameLine : t.line, lineWidth: 1))
                }
            }
            .contentShape(shape)
            .scaleEffect(pressed ? 0.92 : 1)
            .animation(GlypheSpring.fast, value: pressed)
    }
}

/// Glyphe text button (settings): rectangle with soft corners, tighter when pressed.
struct GlypheButtonStyle: ButtonStyle {
    let t: StyleTokens
    /// Secondary action: a dotted outline at night ("tonal" button).
    var secondary = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: t.night ? (pressed ? 2 : 6) : pressed ? 4 : 8, style: .continuous)
        configuration.label
            .font(t.text(t.night ? 11 : 11.5, .bold))
            .tracking(t.night ? 0.7 : 0)
            .foregroundStyle(t.ink)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background {
                if t.night && secondary {
                    shape.stroke(t.line2, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                } else if t.night {
                    shape.fill(Color.black).overlay(shape.strokeBorder(t.line2, lineWidth: 1))
                        .hardShadow(t, shape, level: pressed ? 0 : 1)
                } else {
                    shape.fill(t.control).overlay(shape.strokeBorder(t.line, lineWidth: 1))
                }
            }
            .contentShape(shape)
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(GlypheSpring.fast, value: pressed)
    }
}

extension View {
    /// Round glass button, or a Glyphe icon button.
    @ViewBuilder
    func iconButtonStyle(_ t: StyleTokens, onFrame: Bool = true) -> some View {
        if t.isGlass {
            buttonStyle(.glass).buttonBorderShape(.circle)
        } else {
            buttonStyle(GlypheIconButtonStyle(t: t, onFrame: onFrame))
        }
    }
}
