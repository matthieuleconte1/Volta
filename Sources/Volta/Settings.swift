import AppKit
import SwiftUI

// MARK: - Options

enum Palette: String, CaseIterable, Identifiable {
    case classic, ocean, neon, pastel, mono
    var id: String { rawValue }
    var label: String {
        switch self {
        case .classic: "Classique"
        case .ocean: "Océan"
        case .neon: "Néon"
        case .pastel: "Pastel"
        case .mono: "Mono"
        }
    }

    /// (light, dark) pairs in `Component.allCases` order: CPU, GPU, display, SoC, other.
    private var hexes: [(UInt32, UInt32)] {
        switch self {
        case .classic: [(0x2a78d6, 0x3987e5), (0xeb6834, 0xd95926), (0x1baf7a, 0x199e70), (0xeda100, 0xc98500), (0x9a9994, 0x6f6e69)]
        case .ocean: [(0x1f6fd1, 0x4a93f0), (0x6a4fd6, 0x8f7af0), (0x0f9e9e, 0x2fc0bf), (0x5aa469, 0x6fbf7e), (0x8b95a1, 0x5f6873)]
        case .neon: [(0x0096d6, 0x00d4ff), (0xe8177d, 0xff3d9a), (0x19b34a, 0x39ff88), (0xd6a400, 0xffe23d), (0x8a8a99, 0x5d5d70)]
        case .pastel: [(0x7fa7e0, 0x9dbcf0), (0xf2a07b, 0xf5b393), (0x86cfa8, 0x9adbb6), (0xe8c872, 0xf0d68e), (0xb9b6b0, 0x8a8883)]
        case .mono: [(0x3a3a3c, 0xe5e5ea), (0x636366, 0xaeaeb2), (0x8e8e93, 0x8e8e93), (0xaeaeb2, 0x636366), (0xd1d1d6, 0x48484a)]
        }
    }

    /// Built once per palette: dynamic colors resolve light / dark at draw time.
    private static let tables: [Palette: [Color]] = Dictionary(uniqueKeysWithValues: allCases.map { p in
        (p, p.hexes.map { dynamicColor($0.0, $0.1) })
    })

    var colors: [Color] { Self.tables[self]! }
    func color(_ c: Component) -> Color { colors[Component.allCases.firstIndex(of: c)!] }
}

enum AccentChoice: String, CaseIterable, Identifiable {
    case system, blue, purple, pink, red, orange, yellow, green, mint, graphite
    var id: String { rawValue }
    var nsColor: NSColor {
        switch self {
        case .system: .controlAccentColor
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .pink: .systemPink
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .mint: .systemMint
        case .graphite: .systemGray
        }
    }
    var color: Color { Color(nsColor: nsColor) }
}

enum IconSide: String, CaseIterable, Identifiable {
    case left, right
    var id: String { rawValue }
    var label: String { self == .left ? "À gauche" : "À droite" }
}

enum FlowStyle: String, CaseIterable, Identifiable {
    case channel, dots
    var id: String { rawValue }
    var label: String { self == .channel ? "Canal" : "Points" }
}

enum GlassMaterial: String, CaseIterable, Identifiable {
    case regular, clear
    var id: String { rawValue }
    var label: String { self == .regular ? "Givré" : "Transparent" }
}

enum GlassTint: String, CaseIterable, Identifiable {
    case none, light, strong
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: "Aucune"
        case .light: "Légère"
        case .strong: "Marquée"
        }
    }
    var alpha: CGFloat {
        switch self {
        case .none: 0
        case .light: 0.10
        case .strong: 0.24
        }
    }
}

enum Density: String, CaseIterable, Identifiable {
    case comfortable, compact
    var id: String { rawValue }
    var label: String { self == .comfortable ? "Aérée" : "Compacte" }
    var spacing: CGFloat { self == .comfortable ? 14 : 10 }
    var padding: CGFloat { self == .comfortable ? 18 : 13 }
}

enum NumberFont: String, CaseIterable, Identifiable {
    case rounded, standard, mono, serif
    var id: String { rawValue }
    var label: String {
        switch self {
        case .rounded: "Arrondie"
        case .standard: "Standard"
        case .mono: "Mono"
        case .serif: "Serif"
        }
    }
    var design: Font.Design {
        switch self {
        case .rounded: .rounded
        case .standard: .default
        case .mono: .monospaced
        case .serif: .serif
        }
    }
}

enum ChartStyle: String, CaseIterable, Identifiable {
    case stacked, total
    var id: String { rawValue }
    var label: String { self == .stacked ? "Empilé" : "Total" }
}

enum MotionLevel: String, CaseIterable, Identifiable {
    case full, subtle, off
    var id: String { rawValue }
    var label: String {
        switch self {
        case .full: "Complètes"
        case .subtle: "Discrètes"
        case .off: "Aucune"
        }
    }
}

// MARK: - Store

/// User preferences, persisted in UserDefaults. Only read by the UI while the panel is open,
/// and by the menu bar / sampler when a value changes.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // Outil
    @Published var menuBarMetric: MenuBarMetric { didSet { save(menuBarMetric, "menuBarMetric") } }
    @Published var menuBarIcon: Bool { didSet { save(menuBarIcon, "menuBarIcon") } }
    @Published var menuBarIconSide: IconSide { didSet { save(menuBarIconSide, "menuBarIconSide") } }
    @Published var menuBarAlert: Int { didSet { save(menuBarAlert, "menuBarAlert") } }     // W, 0 = off
    @Published var refreshInterval: Double { didSet { save(refreshInterval, "refreshInterval") } }
    @Published var historyMinutes: Int { didSet { save(historyMinutes, "historyMinutes") } }
    @Published var showChart: Bool { didSet { save(showChart, "showChart") } }
    @Published var showFlow: Bool { didSet { save(showFlow, "showFlow") } }
    @Published var showBreakdown: Bool { didSet { save(showBreakdown, "showBreakdown") } }
    @Published var showDetails: Bool { didSet { save(showDetails, "showDetails") } }
    // Apparence
    @Published var panelStyle: PanelStyle { didSet { save(panelStyle, "panelStyle") } }
    @Published var glypheTheme: GlypheTheme { didSet { save(glypheTheme, "glypheTheme") } }
    @Published var glypheAccent: GlypheAccent { didSet { save(glypheAccent, "glypheAccent") } }
    /// Night: switches on by itself between `glypheNightStart` and `glypheNightEnd` (hours), whatever the theme.
    @Published var glypheAutoNight: Bool { didSet { save(glypheAutoNight, "glypheAutoNight") } }
    @Published var glypheNightStart: Int { didSet { save(glypheNightStart, "glypheNightStart") } }
    @Published var glypheNightEnd: Int { didSet { save(glypheNightEnd, "glypheNightEnd") } }
    /// Intensity of the night red, 0.3…1 (only applies at night).
    @Published var glypheNightLevel: Double { didSet { save(glypheNightLevel, "glypheNightLevel") } }
    @Published var palette: Palette { didSet { save(palette, "palette") } }
    @Published var accent: AccentChoice { didSet { save(accent, "accent") } }
    @Published var glass: GlassMaterial { didSet { save(glass, "glass") } }
    @Published var glassTint: GlassTint { didSet { save(glassTint, "glassTint") } }
    @Published var density: Density { didSet { save(density, "density") } }
    @Published var numberFont: NumberFont { didSet { save(numberFont, "numberFont") } }
    @Published var chartStyle: ChartStyle { didSet { save(chartStyle, "chartStyle") } }
    @Published var flowStyle: FlowStyle { didSet { save(flowStyle, "flowStyle") } }
    @Published var motion: MotionLevel { didSet { save(motion, "motion") } }

    static let refreshChoices: [Double] = [1, 2, 5]
    static let historyChoices = [5, 15, 30]
    static let alertChoices = [0, 10, 15, 20, 30, 45, 60]

    private init() {
        let d = UserDefaults.standard
        Self.migrateFromWattchdog(d)
        func e<T: RawRepresentable>(_ key: String, _ def: T) -> T where T.RawValue == String {
            d.string(forKey: key).flatMap(T.init) ?? def
        }
        func b(_ key: String, _ def: Bool) -> Bool { d.object(forKey: key) == nil ? def : d.bool(forKey: key) }
        menuBarMetric = e("menuBarMetric", .system)
        menuBarIcon = b("menuBarIcon", true)
        menuBarIconSide = e("menuBarIconSide", .left)
        menuBarAlert = d.integer(forKey: "menuBarAlert")
        refreshInterval = d.object(forKey: "refreshInterval") == nil ? 2 : max(1, d.double(forKey: "refreshInterval"))
        historyMinutes = d.object(forKey: "historyMinutes") == nil ? 5 : max(1, d.integer(forKey: "historyMinutes"))
        showChart = b("showChart", true)
        showFlow = b("showFlow", true)
        showBreakdown = b("showBreakdown", true)
        showDetails = b("showDetails", true)
        panelStyle = e("panelStyle", .glass)
        glypheTheme = e("glypheTheme", .auto)
        glypheAccent = e("glypheAccent", .orange)
        glypheAutoNight = b("glypheAutoNight", false)
        glypheNightStart = d.object(forKey: "glypheNightStart") == nil ? 21 : d.integer(forKey: "glypheNightStart")
        glypheNightEnd = d.object(forKey: "glypheNightEnd") == nil ? 7 : d.integer(forKey: "glypheNightEnd")
        glypheNightLevel = d.object(forKey: "glypheNightLevel") == nil ? 0.85 : min(1, max(0.3, d.double(forKey: "glypheNightLevel")))
        palette = e("palette", .classic)
        accent = e("accent", .system)
        glass = e("glass", .regular)
        glassTint = e("glassTint", .none)
        density = e("density", .comfortable)
        numberFont = e("numberFont", .rounded)
        chartStyle = e("chartStyle", .stacked)
        flowStyle = e("flowStyle", .channel)
        motion = e("motion", .full)
    }

    /// Resets the look of the current style (the style itself is kept).
    func resetAppearance() {
        glypheTheme = .auto
        glypheAccent = .orange
        glypheNightLevel = 0.85
        palette = .classic
        accent = .system
        glass = .regular
        glassTint = .none
        density = .comfortable
        numberFont = .rounded
        chartStyle = .stacked
        flowStyle = .channel
        motion = .full
    }

    /// Glyphe theme in effect at `date`: the chosen one, or Night during the automatic night hours.
    func glypheTheme(at date: Date) -> GlypheTheme {
        guard glypheAutoNight, glypheNightStart != glypheNightEnd else { return glypheTheme }
        let hour = Calendar.current.component(.hour, from: date)
        let inside = glypheNightStart < glypheNightEnd
            ? hour >= glypheNightStart && hour < glypheNightEnd
            : hour >= glypheNightStart || hour < glypheNightEnd
        return inside ? .night : glypheTheme
    }

    static let hourChoices = Array(0..<24)

    /// The app used to be called Wattchdog (bundle dev.wattchdog.app): bring its settings over, once.
    private static func migrateFromWattchdog(_ d: UserDefaults) {
        guard !d.bool(forKey: "migratedFromWattchdog") else { return }
        for (key, value) in d.persistentDomain(forName: "dev.wattchdog.app") ?? [:] where d.object(forKey: key) == nil {
            d.set(value, forKey: key)
        }
        d.set(true, forKey: "migratedFromWattchdog")
    }

    private func save<T: RawRepresentable>(_ v: T, _ key: String) where T.RawValue == String {
        UserDefaults.standard.set(v.rawValue, forKey: key)
    }
    private func save(_ v: Any, _ key: String) { UserDefaults.standard.set(v, forKey: key) }
}

func dynamicColor(_ light: UInt32, _ dark: UInt32) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        return NSColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    })
}

// MARK: - Motion

private struct MotionKey: EnvironmentKey { static let defaultValue = MotionLevel.full }

extension EnvironmentValues {
    /// Effective animation level (user choice, capped by the system "Reduce motion" setting).
    var motion: MotionLevel {
        get { self[MotionKey.self] }
        set { self[MotionKey.self] = newValue }
    }
}

extension MotionLevel {
    /// The animation to use for a change, or nil when animations are off.
    func animation(_ full: Animation = .smooth(duration: 0.4)) -> Animation? {
        switch self {
        case .full: full
        case .subtle: .easeOut(duration: 0.2)
        case .off: nil
        }
    }
}

extension View {
    /// Implicit animation that honours the user's motion setting.
    func motionAnimation<V: Equatable>(_ animation: Animation = .smooth(duration: 0.4), value: V) -> some View {
        modifier(MotionAnimation(animation: animation, value: value))
    }
}

private struct MotionAnimation<V: Equatable>: ViewModifier {
    @Environment(\.motion) private var motion
    let animation: Animation
    let value: V
    func body(content: Content) -> some View {
        content.animation(motion.animation(animation), value: value)
    }
}
