import SwiftUI
import ServiceManagement

/// In-panel settings page: the tool (menu bar, sampling, sections) and its look.
/// Every change applies live; the panel resizes itself to the content.
struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var ui: UIState
    @Environment(\.motion) private var motion
    @Environment(\.styleTokens) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: t.isGlass ? 12 : 6) {
            header
                .padding(.horizontal, t.isGlass ? 0 : 8).padding(.top, t.isGlass ? 0 : 6).padding(.bottom, t.isGlass ? 0 : 4)
            Group {
                if ui.snapshot {
                    content
                } else {
                    ScrollView { content }.scrollIndicators(.never)
                }
            }
            .modifier(SettingsPane())
        }
        // Same height as the main page (when it is tall enough) so opening the settings doesn't resize the panel.
        .frame(height: ui.snapshot ? nil : max(ui.mainHeight, 520), alignment: .top)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            menuBar
            measures
            sections
            appearance
            general
        }
        .padding(.bottom, 4)
        .tint(t.accent)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(motion.animation(settings.panelStyle.reveal.navigation)) { ui.showSettings = false }
            } label: {
                Image(systemName: "chevron.left")
            }
            .iconButtonStyle(t)
            if t.night {
                // Night: large titles are drawn with a stroke.
                OutlineText(text: "Réglages", font: t.displayNSFont(17, .heavy), color: t.onFrame, lineWidth: 0.9)
            } else {
                Text("Réglages")
                    .font(t.isGlass ? .system(size: 17, weight: .semibold, design: settings.numberFont.design) : t.display(17, .heavy))
                    .foregroundStyle(t.onFrame)
            }
            Spacer()
        }
    }

    // MARK: Tool

    private var menuBar: some View {
        Card(title: "Barre des menus", symbol: "menubar.rectangle") {
            Row("Valeur affichée") {
                Picker("", selection: $settings.menuBarMetric) {
                    ForEach(MenuBarMetric.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden().fixedSize()
            }
            Row("Icône de charge") { Toggle("", isOn: $settings.menuBarIcon).labelsHidden().toggleStyle(.switch) }
            if settings.menuBarIcon {
                Row("Position de l'icône") {
                    Segmented(selection: $settings.menuBarIconSide, options: IconSide.allCases) { $0.label }
                }
                .transition(.opacity)
            }
            Row("Alerte", detail: t.isGlass ? "La valeur passe en orange au-delà du seuil" : "La valeur prend l'accent au-delà du seuil") {
                Picker("", selection: $settings.menuBarAlert) {
                    ForEach(AppSettings.alertChoices, id: \.self) { Text($0 == 0 ? "Désactivée" : "≥ \($0) W").tag($0) }
                }
                .labelsHidden().fixedSize()
            }
        }
        .motionAnimation(.smooth(duration: 0.3), value: settings.menuBarIcon)
    }

    private var measures: some View {
        Card(title: "Mesures", symbol: "waveform.path.ecg") {
            Row("Rafraîchissement", detail: "Panneau ouvert. Fermé : toutes les 5 s") {
                Segmented(selection: $settings.refreshInterval, options: AppSettings.refreshChoices) { "\(Int($0)) s" }
            }
            Row("Historique") {
                Segmented(selection: $settings.historyMinutes, options: AppSettings.historyChoices) { "\($0) min" }
            }
        }
    }

    private var sections: some View {
        Card(title: "Sections", symbol: "square.stack") {
            HStack(spacing: 6) {
                Chip("Graphique", symbol: "chart.xyaxis.line", isOn: $settings.showChart)
                Chip("Flux", symbol: "bolt.horizontal", isOn: $settings.showFlow)
                Chip("Répartition", symbol: "chart.bar", isOn: $settings.showBreakdown)
                Chip("Détails", symbol: "list.bullet", isOn: $settings.showDetails)
            }
        }
    }

    // MARK: Look

    private var appearance: some View {
        Card(title: "Apparence", symbol: "paintpalette") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Style").font(t.text(12, t.isGlass ? .regular : .medium))
                HStack(spacing: 8) {
                    ForEach(PanelStyle.allCases) { style in
                        StyleCard(style: style, selected: settings.panelStyle == style) {
                            withAnimation(motion.animation(.smooth(duration: 0.35))) { settings.panelStyle = style }
                        }
                    }
                }
                Text(settings.panelStyle.detail).font(t.text(10)).foregroundStyle(t.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if t.isGlass {
                glassOptions
            } else {
                glypheOptions
            }
            Row("Densité") { Segmented(selection: $settings.density, options: Density.allCases) { $0.label } }
            Row("Graphique") { Segmented(selection: $settings.chartStyle, options: ChartStyle.allCases) { $0.label } }
            Row("Flux d'énergie", detail: "Canal : animé par Core Animation, panneau ouvert seulement") {
                Segmented(selection: $settings.flowStyle, options: FlowStyle.allCases) { $0.label }
            }
            Row("Animations", detail: "Confiées à Core Animation : quasi gratuites") {
                Segmented(selection: $settings.motion, options: MotionLevel.allCases) { $0.label }
            }
        }
        .motionAnimation(.smooth(duration: 0.3), value: settings.glypheAutoNight)
        .motionAnimation(.smooth(duration: 0.3), value: settings.palette)
        .motionAnimation(.smooth(duration: 0.3), value: settings.accent)
    }

    @ViewBuilder
    private var glassOptions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Palette").font(.system(size: 12))
            HStack(spacing: 6) {
                ForEach(Palette.allCases) { p in PaletteSwatch(palette: p, selected: settings.palette == p) { settings.palette = p } }
            }
        }
        VStack(alignment: .leading, spacing: 6) {
            Text("Accent").font(.system(size: 12))
            HStack(spacing: 0) {
                ForEach(AccentChoice.allCases) { a in
                    AccentDot(accent: a, selected: settings.accent == a) { settings.accent = a }
                    if a != AccentChoice.allCases.last { Spacer(minLength: 0) }
                }
            }
        }
        Row("Verre") { Segmented(selection: $settings.glass, options: GlassMaterial.allCases) { $0.label } }
        Row("Teinte du verre") { Segmented(selection: $settings.glassTint, options: GlassTint.allCases) { $0.label } }
        Row("Chiffres") { Segmented(selection: $settings.numberFont, options: NumberFont.allCases, design: \.design) { $0.label } }
    }

    @ViewBuilder
    private var glypheOptions: some View {
        Row("Thème", detail: "Le cadre reste noir dans tous les thèmes") {
            Segmented(selection: $settings.glypheTheme, options: GlypheTheme.allCases) { $0.label }
        }
        Row("Nuit automatique", detail: "Passe en rouge aux heures choisies, quel que soit le thème") {
            Toggle("", isOn: $settings.glypheAutoNight).labelsHidden().toggleStyle(.switch)
        }
        if settings.glypheAutoNight {
            Row("Horaires", detail: settings.glypheNightStart == settings.glypheNightEnd ? "Choisis deux heures différentes" : nil) {
                HStack(spacing: 6) {
                    hourPicker($settings.glypheNightStart)
                    Image(systemName: "arrow.right").font(.system(size: 10, weight: t.night ? .light : .medium)).foregroundStyle(t.ink3)
                    hourPicker($settings.glypheNightEnd)
                }
            }
            .transition(.opacity)
        }
        if settings.glypheTheme == .night || settings.glypheAutoNight {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Intensité du rouge").font(t.text(12, .medium))
                    Spacer()
                    Text("\(Int((settings.glypheNightLevel * 100).rounded())) %").font(t.label(11)).monospacedDigit()
                        .foregroundStyle(t.ink2)
                }
                StepSlider(value: $settings.glypheNightLevel, range: 0.3...1, step: 0.05)
                Text("Ne s'applique qu'en version nuit. Un rouge profond garde la vision de nuit et n'envoie aucune lumière bleue.")
                    .font(t.text(10)).foregroundStyle(t.ink3).fixedSize(horizontal: false, vertical: true)
            }
            .transition(.opacity)
        }
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Accent").font(t.text(12, .medium))
                Spacer()
                Text(t.night ? "La nuit, l'accent est verrouillé sur le rouge" : "Une seule à la fois")
                    .font(t.text(10)).foregroundStyle(t.ink3)
            }
            HStack(spacing: 0) {
                ForEach(GlypheAccent.allCases) { a in
                    GlypheAccentSwatch(accent: a, selected: settings.glypheAccent == a) {
                        withAnimation(GlypheSpring.fast) { settings.glypheAccent = a }
                    }
                    if a != GlypheAccent.allCases.last { Spacer(minLength: 0) }
                }
            }
            .modifier(NightTint(t: t))
            .opacity(t.night ? 0.45 : 1)
            .allowsHitTesting(!t.night)
        }
    }

    private func hourPicker(_ hour: Binding<Int>) -> some View {
        Picker("", selection: hour) {
            ForEach(AppSettings.hourChoices, id: \.self) { Text("\($0) h").tag($0) }
        }
        .labelsHidden().fixedSize()
    }

    private var general: some View {
        Card(title: "Général", symbol: "gearshape") {
            Row("Ouvrir au démarrage") { Toggle("", isOn: launchAtLogin).labelsHidden().toggleStyle(.switch) }
            HStack(spacing: 8) {
                Button(t.caption(t.night ? "Réinitialiser" : "Réinitialiser l'apparence")) {
                    withAnimation(motion.animation()) { settings.resetAppearance() }
                }
                .textButtonStyle(t, secondary: true)
                .help("Réinitialiser l'apparence")
                Spacer()
                Button(t.caption("Quitter Volta")) { NSApp.terminate(nil) }
                    .textButtonStyle(t)
            }
        }
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { on in
                try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                ui.objectWillChange.send()
            })
    }
}

/// Glyphe: the settings live in the same inset pane as the measures.
private struct SettingsPane: ViewModifier {
    @Environment(\.styleTokens) private var t

    func body(content: Content) -> some View {
        if t.isGlass {
            content
        } else {
            content
                .padding(10)
                .frame(maxHeight: .infinity, alignment: .top)
                .insetPane(t)
                .foregroundStyle(t.ink)
        }
    }
}

private extension View {
    @ViewBuilder
    func textButtonStyle(_ t: StyleTokens, secondary: Bool = false) -> some View {
        if t.isGlass {
            buttonStyle(.glass).controlSize(.small).tint(nil)
        } else {
            buttonStyle(GlypheButtonStyle(t: t, secondary: secondary))
        }
    }
}

// MARK: - Building blocks

private struct Card<Content: View>: View {
    let title: String, symbol: String
    @ViewBuilder let content: Content
    @Environment(\.styleTokens) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Group {
                if t.isGlass {
                    Label(title, systemImage: symbol)
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                } else {
                    Label {
                        Text(title.uppercased()).tracking(t.labelTracking)
                    } icon: {
                        Image(systemName: symbol).font(.system(size: 10, weight: t.night ? .light : .regular))
                    }
                    .font(t.label(11)).foregroundStyle(t.ink3)
                    .padding(.leading, 2)
                }
            }
            VStack(alignment: .leading, spacing: 10) { content }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .planche(t, radius: t.isGlass ? 14 : 12)
        }
    }
}

private struct Row<Control: View>: View {
    let title: String
    let detail: String?
    let control: Control
    @Environment(\.styleTokens) private var t

    init(_ title: String, detail: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(t.text(12, t.isGlass ? .regular : .medium))
                if let detail { Text(detail).font(t.text(10)).foregroundStyle(t.ink3) }
            }
            Spacer(minLength: 6)
            control.controlSize(.small)
        }
    }
}

/// Compact segmented control whose selection slides between options.
/// Glass: a tinted capsule. Glyphe: the chosen option is filled with the inverse color and gets rounder corners
/// (corners round up when you choose), the group sits in a soft rectangle — no pills.
struct Segmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let design: ((Value) -> Font.Design)?
    /// Options share the full width (tabs).
    let fill: Bool
    let label: (Value) -> String
    @Environment(\.motion) private var motion
    @Environment(\.styleTokens) private var t
    @Namespace private var pill

    /// `design`: renders each option in its own font design (live preview).
    init(selection: Binding<Value>, options: [Value], design: ((Value) -> Font.Design)? = nil, fill: Bool = false,
         label: @escaping (Value) -> String) {
        _selection = selection
        self.options = options
        self.design = design
        self.fill = fill
        self.label = label
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Text(t.caption(label(option)))
                    .font(t.isGlass ? .system(size: 11, weight: selected ? .semibold : .regular, design: design?(option) ?? .default)
                                    : t.text(fill ? 11.5 : 11, selected ? .bold : .medium))
                    .tracking(t.night ? 0.6 : 0)
                    .foregroundStyle(t.isGlass ? (selected ? Color.primary : Color.secondary) : (selected ? t.onInverse : t.night ? t.ink : t.ink2))
                    .padding(.horizontal, 8)
                    .padding(.vertical, t.isGlass ? 3 : fill ? 5 : 3.5)
                    .frame(maxWidth: fill ? .infinity : nil)
                    .background {
                        if selected {
                            if t.isGlass {
                                Capsule().fill(.tint.opacity(0.25))
                                    .overlay(Capsule().strokeBorder(.tint.opacity(0.5), lineWidth: 0.5))
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            } else {
                                RoundedRectangle(cornerRadius: fill ? 7 : 6, style: .continuous).fill(t.inverse)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        } else if t.night {
                            // Night: each option is its own outlined button, tight inside, rounder at the ends.
                            nightShape(option).strokeBorder(t.line2, lineWidth: 1)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(motion.animation(t.isGlass ? .snappy(duration: 0.3) : GlypheSpring.standard)) { selection = option }
                    }
            }
        }
        .padding(t.night ? 0 : 2)
        .background {
            if t.isGlass {
                Capsule().fill(Color.primary.opacity(0.06))
            } else if t.night {
                EmptyView()
            } else {
                RoundedRectangle(cornerRadius: fill ? 9 : 8, style: .continuous).fill(t.control)
                    .overlay(RoundedRectangle(cornerRadius: fill ? 9 : 8, style: .continuous).strokeBorder(t.line, lineWidth: 1))
            }
        }
        .fixedSize(horizontal: !fill, vertical: false)
    }

    private func nightShape(_ option: Value) -> UnevenRoundedRectangle {
        let first = option == options.first, last = option == options.last
        return UnevenRoundedRectangle(topLeadingRadius: first ? 6 : 2, bottomLeadingRadius: first ? 6 : 2,
                                      bottomTrailingRadius: last ? 6 : 2, topTrailingRadius: last ? 6 : 2, style: .continuous)
    }
}

private struct Chip: View {
    let title: String, symbol: String
    @Binding var isOn: Bool
    @Environment(\.motion) private var motion
    @Environment(\.styleTokens) private var t

    init(_ title: String, symbol: String, isOn: Binding<Bool>) {
        self.title = title
        self.symbol = symbol
        _isOn = isOn
    }

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 14, weight: t.night ? .light : .regular)).frame(height: 18)
                .symbolEffect(.bounce, value: isOn)
                .symbolEffectsRemoved(motion != .full)
            Text(t.caption(title)).font(t.isGlass ? .system(size: 10, weight: .medium) : t.text(t.night ? 9 : 10, .semibold))
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(t.isGlass ? (isOn ? Color.primary : Color.secondary) : (isOn ? t.onInverse : t.ink2))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background { background }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(motion.animation(t.isGlass ? .snappy(duration: 0.3) : GlypheSpring.fast)) { isOn.toggle() }
        }
    }

    @ViewBuilder
    private var background: some View {
        if t.isGlass {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isOn ? AnyShapeStyle(.tint.opacity(0.22)) : AnyShapeStyle(Color.primary.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isOn ? AnyShapeStyle(.tint.opacity(0.55)) : AnyShapeStyle(.clear), lineWidth: 1))
        } else {
            // Filled = chosen, ring = available; corners round up when chosen.
            let shape = RoundedRectangle(cornerRadius: t.night ? (isOn ? 6 : 4) : isOn ? 12 : 6, style: .continuous)
            shape.fill(isOn ? t.inverse : t.night ? .clear : t.control)
                .overlay(shape.strokeBorder(isOn ? .clear : t.night ? t.line2 : t.line, lineWidth: 1))
        }
    }
}

/// Preview of a style in the settings: a tiny panel drawn in its material.
private struct StyleCard: View {
    let style: PanelStyle
    let selected: Bool
    let action: () -> Void
    @Environment(\.styleTokens) private var t

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                preview
                    // Night: a single red, previews included.
                    .modifier(NightTint(t: t))
                    .frame(height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(selected ? t.accent : t.isGlass ? Color.primary.opacity(0.12) : t.line2,
                                          lineWidth: selected ? 2 : 1)
                    }
                Text(t.caption(style.title))
                    .font(t.isGlass ? .system(size: 11, weight: selected ? .semibold : .regular) : t.text(11, selected ? .bold : .medium))
                    .foregroundStyle(selected ? t.ink : t.ink2)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(style.detail)
    }

    @ViewBuilder
    private var preview: some View {
        switch style {
        case .glass:
            ZStack {
                LinearGradient(colors: [Color(rgb: 0x1B1F4B), Color(rgb: 0x3B1E5C), Color(rgb: 0x0E3B4F)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(alignment: .leading, spacing: 5) {
                    Text("12.4 W").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                    HStack(spacing: 1.5) {
                        ForEach(Array(Palette.classic.colors.enumerated()), id: \.offset) { i, c in
                            c.frame(width: [26, 16, 10, 8, 6][i])
                        }
                    }
                    .frame(height: 5).clipShape(Capsule())
                }
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.14)))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
                .padding(8)
            }
        case .glyphe:
            let sample = StyleTokens.make(AppSettings.shared, systemDark: true)
            let accent = sample.style == .glyphe ? sample.accent : Color(rgb: 0xED6A0C)
            ZStack(alignment: .topLeading) {
                Color(rgb: 0x050403)
                VStack(alignment: .leading, spacing: 4) {
                    Text("12.4 W").font(.system(size: 11, weight: .heavy).width(.expanded)).foregroundStyle(.white)
                        .padding(.leading, 4)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(rgb: 0x080604))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 1))
                        .overlay(alignment: .leading) {
                            HStack(spacing: 1.5) {
                                accent.frame(width: 26)
                                Color(rgb: 0xF1F1F1).frame(width: 14)
                                Color(rgb: 0xA8A5A1).frame(width: 9)
                                Color(rgb: 0x6B6966).frame(width: 7)
                            }
                            .frame(height: 5).clipShape(RoundedRectangle(cornerRadius: 1))
                            .padding(.horizontal, 7)
                        }
                }
                .padding(5)
            }
        }
    }
}

/// Night: any color left (previews, swatches, app icons) is turned into shades of the single red.
struct NightTint: ViewModifier {
    let t: StyleTokens

    func body(content: Content) -> some View {
        if t.night {
            content.grayscale(1).colorMultiply(t.ink)
        } else {
            content
        }
    }
}

/// Glyphe accent swatch: a soft square that turns round once chosen.
private struct GlypheAccentSwatch: View {
    let accent: GlypheAccent
    let selected: Bool
    let action: () -> Void
    @Environment(\.styleTokens) private var t

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: selected ? 13 : 7, style: .continuous)
        ZStack {
            if let hex = accent.hex {
                shape.fill(Color(rgb: hex))
            } else {
                // Mono: the text color itself.
                shape.fill(t.ink)
            }
        }
        .overlay(shape.strokeBorder(t.line2, lineWidth: 1))
        .frame(width: 26, height: 26)
        .padding(3)
        .overlay(RoundedRectangle(cornerRadius: selected ? 16 : 10, style: .continuous)
            .strokeBorder(selected ? t.ink : .clear, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .help(accent.label)
    }
}

private struct PaletteSwatch: View {
    let palette: Palette
    let selected: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 1.5) {
                ForEach(Array(palette.colors.enumerated()), id: \.offset) { _, color in
                    Rectangle().fill(color)
                }
            }
            .frame(height: 16)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text(palette.label).font(.system(size: 10, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(selected ? 0.08 : 0)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 1.5))
        .scaleEffect(selected ? 1 : 0.96)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

private struct AccentDot: View {
    let accent: AccentChoice
    let selected: Bool
    let action: () -> Void

    var body: some View {
        ZStack {
            if accent == .system {
                // "Follow the system": multicolor dot.
                Circle().fill(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red], center: .center))
            } else {
                Circle().fill(accent.color)
            }
            if selected {
                Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 18, height: 18)
        .padding(3)
        .overlay(Circle().strokeBorder(selected ? Color.primary.opacity(0.55) : .clear, lineWidth: 1.5))
        .scaleEffect(selected ? 1.08 : 1)
        .contentShape(Circle())
        .onTapGesture(perform: action)
        .help(accent == .system ? "Couleur du système" : "")
    }
}
