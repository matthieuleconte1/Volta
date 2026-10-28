import SwiftUI
import Charts

enum Component: String, CaseIterable, Identifiable {
    case cpu = "Processeur", gpu = "Graphique", display = "Écran", soc = "Puce", other = "Autres"
    var id: String { rawValue }
    var detail: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .display: "rétroéclairage"
        case .soc: "bus, contrôleur mémoire…"
        case .other: "dalle, SSD, Wi-Fi, USB…"
        }
    }
    func value(_ s: PowerSnapshot) -> Double? {
        switch self {
        case .cpu: s.cpu
        case .gpu: s.gpu
        case .display: s.display
        case .soc: s.soc
        case .other: s.other
        }
    }
    func value(_ p: HistoryPoint) -> Double {
        switch self {
        case .cpu: p.cpu
        case .gpu: p.gpu
        case .display: p.display
        case .soc: p.soc
        case .other: p.other
        }
    }
}

extension StyleTokens {
    func color(_ c: Component) -> Color { components[Component.allCases.firstIndex(of: c)!] }
    /// Fill of a component: its color, or its night pattern.
    func fill(_ c: Component) -> AnyShapeStyle { componentFills[Component.allCases.firstIndex(of: c)!] }
    func layerColor(_ c: Component) -> NSColor { componentLayers[Component.allCases.firstIndex(of: c)!] }
}

func formatWatts(_ v: Double?, signed: Bool = false) -> String {
    guard let v else { return "–" }
    let sign = signed && v > 0.05 ? "+" : ""
    if v.magnitude < 0.005 { return "0 W" }
    let format = v.magnitude >= 100 ? "%.0f W" : v.magnitude >= 1 ? "%.1f W" : "%.2f W"
    return sign + String(format: format, v)
}

private func formatDuration(_ minutes: Int) -> String {
    minutes >= 60 ? "\(minutes / 60) h \(String(format: "%02d", minutes % 60))" : "\(minutes) min"
}

// MARK: - Root

/// View-local state (kept in ObservableObjects: the @State macro plugin ships only with Xcode).
/// A fresh UIState is created each time the panel opens.
final class UIState: ObservableObject {
    @Published var showSettings = false
    @Published var appeared = false
    /// Last measured height of the main page (not published: only read when the settings page opens).
    var mainHeight: CGFloat = 640
    /// Debug snapshots: ImageRenderer can't draw scroll views.
    var snapshot = false
}

/// Chart scrubbing, kept apart so it only redraws the header.
final class ChartHover: ObservableObject {
    @Published var date: Date?
}

/// Component hovered in the breakdown, highlighted in the chart and the bar.
final class Highlight: ObservableObject {
    @Published var component: Component?
}

/// Per-row hover flag.
final class HoverFlag: ObservableObject {
    @Published var on = false
}

extension PowerStore {
    /// History point closest to the scrubbed date.
    func point(near date: Date?) -> HistoryPoint? {
        guard let date, !history.isEmpty else { return nil }
        return history.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}

struct PopoverView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var ui: UIState
    @StateObject private var hover = ChartHover()
    @StateObject private var highlight = Highlight()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var systemScheme

    private var motion: MotionLevel {
        reduceMotion && settings.motion == .full ? .subtle : settings.motion
    }

    var body: some View {
        // Once a minute: the automatic night may start or end while the panel is open.
        TimelineView(.everyMinute) { context in
            content(StyleTokens.make(settings, systemDark: systemScheme == .dark, date: context.date))
        }
    }

    private func content(_ t: StyleTokens) -> some View {
        let reveal = settings.panelStyle.reveal
        return ZStack(alignment: .top) {
            if ui.showSettings {
                SettingsView().transition(reveal.page(settings: true, level: motion))
            } else {
                MainView().transition(reveal.page(settings: false, level: motion))
            }
        }
        // Glyphe: the black frame is a thin margin around the inset pane.
        .padding(t.isGlass ? settings.density.padding : 6)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .background { if !t.isGlass { t.frame } }
        .tint(t.isGlass ? nil : t.accent)
        .environment(\.styleTokens, t)
        .environment(\.colorScheme, t.scheme ?? systemScheme)
        .environment(\.motion, motion)
        .environmentObject(hover)
        .environmentObject(highlight)
        .onAppear { ui.appeared = true }
    }
}

private struct MainView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var ui: UIState
    @Environment(\.styleTokens) private var t

    var body: some View {
        Group {
            if t.isGlass {
                GlassEffectContainer(spacing: 10) {
                    VStack(alignment: .leading, spacing: settings.density.spacing) {
                        HeaderView(chart: settings.showChart).entrance(0)
                        sections(from: 1)
                        FooterView().entrance(4)
                    }
                }
            } else {
                // The header and the footer sit on the black frame; the measures live in the inset pane.
                VStack(alignment: .leading, spacing: 6) {
                    HeaderView(chart: false)
                        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
                        .entrance(0)
                    VStack(alignment: .leading, spacing: settings.density.spacing + 2) {
                        if settings.showChart { HistoryChart().frame(height: 76).well(t).entrance(1) }
                        sections(from: 2)
                    }
                    .padding(settings.density.padding - 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .insetPane(t)
                    .foregroundStyle(t.ink)
                    FooterView()
                        .padding(.horizontal, 10).padding(.top, 2).padding(.bottom, 4)
                        .entrance(5)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { ui.mainHeight = $0 }
    }

    @ViewBuilder
    private func sections(from index: Int) -> some View {
        if settings.showFlow { FlowView().entrance(index) }
        if settings.showBreakdown { BreakdownView().entrance(index + 1) }
        if settings.showDetails { DetailsView().entrance(index + 2) }
    }
}

/// Sections arrive one after the other when the panel opens (one-shot), in the style's own way.
private struct Entrance: ViewModifier {
    @EnvironmentObject var ui: UIState
    @EnvironmentObject var settings: AppSettings
    @Environment(\.motion) private var motion
    let index: Int

    func body(content: Content) -> some View {
        let reveal = settings.panelStyle.reveal
        let hidden = !ui.appeared && motion != .off
        content
            .opacity(hidden ? 0 : 1)
            .offset(y: hidden && motion == .full ? reveal.entranceOffset : 0)
            .scaleEffect(hidden && motion == .full ? reveal.entranceScale : 1, anchor: .top)
            .animation(reveal.entrance(index, level: motion), value: ui.appeared)
    }
}

private extension View {
    func entrance(_ index: Int) -> some View { modifier(Entrance(index: index)) }
}

struct SectionTitle: View {
    let text: String
    var trailing: String? = nil
    @Environment(\.styleTokens) private var t

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text.uppercased()).font(t.label(11)).tracking(t.labelTracking)
                .foregroundStyle(t.isGlass ? t.ink2 : t.ink3)
            Spacer()
            if let trailing {
                Text(t.isGlass ? trailing : trailing.uppercased())
                    .font(t.isGlass ? .system(size: 11) : t.label(10)).tracking(t.labelTracking)
                    .foregroundStyle(t.ink3)
            }
        }
        .padding(.bottom, t.night ? 5 : 0)
        .overlay(alignment: .bottom) {
            if t.night { DashedLine(color: t.line2) }
        }
    }
}

/// Thin separator: the system one under the glass, the style's line in Glyphe.
struct StyledDivider: View {
    @Environment(\.styleTokens) private var t

    var body: some View {
        if t.isGlass {
            Divider()
        } else if t.night {
            DashedLine(color: t.line2)
        } else {
            Rectangle().fill(t.line2).frame(height: 1)
        }
    }
}

// MARK: - Header + chart

private struct HeaderView: View {
    /// Under the glass the chart belongs to the header; Glyphe puts it in the pane.
    let chart: Bool
    @EnvironmentObject var store: PowerStore
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var hover: ChartHover
    @EnvironmentObject var ui: UIState
    @Environment(\.motion) private var motion
    @Environment(\.styleTokens) private var t

    var body: some View {
        let hovered = store.point(near: hover.date)
        let watts = hovered?.system ?? store.snapshot.system
        let trigger = motion == .full ? store.history.last?.date : nil
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: t.isGlass ? 0 : 6) {
                    HStack(spacing: t.isGlass ? 5 : 8) {
                        if t.isGlass {
                            PulseDot(color: t.accent, trigger: trigger).frame(width: 6, height: 6)
                            Text(hovered.map { ago($0.date) } ?? "Consommation du Mac")
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(t.onFrame2)
                        } else {
                            Text((hovered.map { ago($0.date) } ?? "Consommation du Mac").uppercased())
                                .font(t.label(10.5)).tracking(t.labelTracking).foregroundStyle(t.onFrame2)
                        }
                    }
                    if ui.snapshot {
                        if t.night {
                            OutlineText(text: formatWatts(watts), font: t.displayNSFont(32, .heavy), color: t.onFrame, lineWidth: 1.2)
                        } else {
                            Text(formatWatts(watts))
                                .font(t.display(t.isGlass ? 34 : 32, t.isGlass ? .semibold : .heavy)).monospacedDigit()
                                .foregroundStyle(t.onFrame)
                        }
                    } else {
                        // No roll while scrubbing the chart: the value follows the pointer.
                        RollingNumber(text: formatWatts(watts), value: watts ?? 0,
                                      font: t.displayNSFont(t.isGlass ? 34 : 32, t.isGlass ? .semibold : .heavy),
                                      color: t.isGlass ? nil : NSColor(t.onFrame),
                                      outline: t.night ? 1.2 : nil,
                                      animated: hovered == nil && motion != .off)
                    }
                }
                Spacer()
                Group {
                    if let p = hovered {
                        VStack(alignment: .trailing, spacing: 1) {
                            ForEach(Component.allCases.reversed()) { c in
                                HStack(spacing: 5) {
                                    Circle().fill(t.fill(c)).frame(width: 5, height: 5)
                                    Text(c.rawValue).foregroundStyle(t.onFrame2)
                                    Text(formatWatts(c.value(p))).monospacedDigit().frame(minWidth: 44, alignment: .trailing)
                                        .foregroundStyle(t.onFrame)
                                }
                            }
                        }
                        .font(t.text(10))
                        .transition(.opacity)
                    } else {
                        Text(t.isGlass ? statusLine : statusLine.uppercased())
                            .font(t.isGlass ? .system(size: 11) : t.label(10)).tracking(t.labelTracking)
                            .lineSpacing(t.isGlass ? 0 : 2)
                            .foregroundStyle(t.onFrame2).multilineTextAlignment(.trailing)
                            .padding(.top, t.isGlass ? 0 : 1)
                            .contentTransition(.opacity)
                            .transition(.opacity)
                    }
                }
                .motionAnimation(.easeOut(duration: 0.18), value: hovered == nil)
                .motionAnimation(value: statusLine)
            }

            if chart {
                HistoryChart().frame(height: 72)
            }
        }
    }

    private func ago(_ date: Date) -> String {
        let s = max(0, Int(-date.timeIntervalSinceNow))
        return s < 60 ? "Il y a \(s) s" : "Il y a \(s / 60) min \(String(format: "%02d", s % 60))"
    }

    private var statusLine: String {
        let s = store.snapshot
        guard let b = s.batteryInfo else { return "" }
        let sep = t.isGlass ? " · " : "\n"
        if (s.battery ?? 0) > 0.3 {
            return b.minutesRemaining.map { "Charge\(sep)plein dans \(formatDuration($0))" } ?? "En charge"
        }
        if s.onAC { return b.fullyCharged ? "Sur secteur\(sep)chargée" : "Sur secteur\(sep)charge en pause" }
        return b.minutesRemaining.map { "Sur batterie\(sep)\(formatDuration($0)) restantes" } ?? "Sur batterie"
    }
}

/// History of the last minutes, stacked by component (or total). Scrubbing it drives the header.
private struct HistoryChart: View {
    @EnvironmentObject var store: PowerStore
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var hover: ChartHover
    @EnvironmentObject var highlight: Highlight
    @Environment(\.styleTokens) private var t

    /// At most ~60 points: the chart stays cheap to redraw.
    private var chartPoints: [HistoryPoint] {
        let h = store.history
        guard h.count > 60 else { return h }
        let step = Int((Double(h.count) / 60).rounded(.up))
        var points = stride(from: h.count - 1, through: 0, by: -step).map { h[$0] }
        points.reverse()
        return points
    }

    var body: some View {
        let points = chartPoints
        let hovered = store.point(near: hover.date)
        let accent = t.accent
        let focus = highlight.component
        Chart {
            switch settings.chartStyle {
            case .stacked:
                ForEach(points) { p in
                    ForEach(Component.allCases) { c in
                        AreaMark(x: .value("Heure", p.date), y: .value("Watts", c.value(p)), stacking: .standard)
                            .foregroundStyle(by: .value("Composant", c.rawValue))
                            .interpolationMethod(.monotone)
                            .opacity(focus == nil || focus == c ? 1 : 0.22)
                    }
                }
            case .total:
                ForEach(points) { p in
                    AreaMark(x: .value("Heure", p.date), y: .value("Watts", p.system))
                        .foregroundStyle(LinearGradient(colors: [accent.opacity(0.4), accent.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Heure", p.date), y: .value("Watts", p.system))
                        .foregroundStyle(accent)
                        .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
            }
            if hovered == nil, let last = points.last {
                PointMark(x: .value("Heure", last.date), y: .value("Watts", last.system))
                    .symbolSize(22)
                    .foregroundStyle(settings.chartStyle == .total ? accent : t.ink.opacity(0.8))
            }
            if let p = hovered {
                RuleMark(x: .value("Heure", p.date))
                    .foregroundStyle(t.ink.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("Heure", p.date), y: .value("Watts", p.system))
                    .symbolSize(28)
                    .foregroundStyle(t.ink)
            }
        }
        .chartForegroundStyleScale(domain: Component.allCases.map(\.rawValue), range: t.componentFills)
        .chartLegend(.hidden)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                AxisGridLine(stroke: StrokeStyle(lineWidth: t.isGlass ? 0.5 : 1, dash: t.night ? [2, 3] : []))
                    .foregroundStyle(t.isGlass ? Color.secondary.opacity(0.25) : t.line2)
                AxisValueLabel {
                    if let w = v.as(Double.self) {
                        Text("\(Int(w)) W").font(t.isGlass ? .system(size: 9) : t.label(9)).foregroundStyle(t.ink3)
                    }
                }
            }
        }
        .chartXSelection(value: $hover.date)
        .motionAnimation(.easeOut(duration: 0.2), value: focus)
        .overlay {
            if store.history.count < 2 {
                if t.isGlass {
                    Text("Collecte des mesures…").font(.caption).foregroundStyle(.tertiary)
                } else {
                    HStack(spacing: 8) {
                        DotComet(t: t, size: 16)
                        Text("COLLECTE DES MESURES").font(t.label(10)).tracking(t.labelTracking).foregroundStyle(t.ink3)
                    }
                }
            }
        }
    }
}

// MARK: - Power flow (charger → Mac ⇄ battery)

private struct FlowView: View {
    @EnvironmentObject var store: PowerStore
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var ui: UIState
    @Environment(\.motion) private var motion
    @Environment(\.styleTokens) private var t

    var body: some View {
        let s = store.snapshot
        let b = s.batteryInfo
        let adapterActive = (s.adapterIn ?? 0) > 0.3
        let battery = s.battery ?? 0
        // Energy channel only with full animations; the dotted connectors otherwise (lighter).
        let channel = settings.flowStyle == .channel && motion == .full && !ui.snapshot
        let batteryColor: NSColor = battery > 0 ? t.charge : t.discharge
        let idle = NSColor(t.isGlass ? Color(nsColor: .tertiaryLabelColor) : t.ink3.opacity(0.5))

        HStack(spacing: 4) {
            FlowNode(
                symbol: s.onAC ? "powerplug.fill" : "powerplug",
                title: "Chargeur",
                value: s.onAC ? s.adapterIn : nil,
                subtitle: s.onAC ? (b?.adapter?.watts.map { "max \(Int($0)) W" } ?? "branché") : "débranché",
                active: adapterActive,
                tint: .green)
            FlowConnector(direction: adapterActive ? .right : .none, watts: s.adapterIn ?? 0, color: t.charge, idle: idle,
                          animated: motion != .off && !channel)
                .frame(width: 18, height: 8)
                .opacity(channel ? 0 : 1)
            FlowNode(symbol: "laptopcomputer", title: "Mac", value: s.system, subtitle: "consomme", active: true, tint: nil, emphasis: true)
            FlowConnector(direction: battery > 0.3 ? .right : battery < -0.3 ? .left : .none,
                          watts: abs(battery), color: batteryColor, idle: idle,
                          animated: motion != .off && !channel)
                .frame(width: 18, height: 8)
                .opacity(channel ? 0 : 1)
            FlowNode(
                symbol: batterySymbol(b?.percent ?? 0, charging: battery > 0.3),
                title: "Batterie \(b?.percent ?? 0) %",
                value: battery,
                signed: true,
                subtitle: battery > 0.3 ? "en charge" : battery < -0.3 ? "se décharge" : "au repos",
                active: abs(battery) > 0.3,
                tint: battery > 0.3 ? .green : .orange)
        }
        // Behind the nodes: the channel shows through the glass edges, blurred (it passes under the Glyphe cards).
        .background {
            if channel {
                EnergyChannel(links: [
                    EnergyLink(from: 0, to: 1, watts: s.adapterIn ?? 0, color: t.charge, idle: idle, active: adapterActive),
                    EnergyLink(from: battery > 0 ? 1 : 2, to: battery > 0 ? 2 : 1, watts: abs(battery),
                               color: batteryColor, idle: idle, active: abs(battery) > 0.3),
                ], gap: 26)
            }
        }
    }

    private func batterySymbol(_ p: Int, charging: Bool) -> String {
        if charging { return "battery.100percent.bolt" }
        return p > 87 ? "battery.100percent" : p > 62 ? "battery.75percent" : p > 37 ? "battery.50percent" : p > 12 ? "battery.25percent" : "battery.0percent"
    }
}

private struct FlowNode: View {
    let symbol: String, title: String
    let value: Double?
    var signed = false
    let subtitle: String, active: Bool
    let tint: Color?
    /// The node the others feed (the Mac): hatched at night.
    var emphasis = false
    @Environment(\.motion) private var motion
    @Environment(\.styleTokens) private var t

    var body: some View {
        // Glyphe: the accent only marks a state (charging, charger delivering).
        let signal = !t.isGlass && active && tint == .green
        VStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 18, weight: t.night ? .light : .regular)).frame(height: 22)
                .foregroundStyle(signal ? t.accent : active ? t.ink : t.ink2)
                // Plugging / unplugging: the icon morphs and bounces once.
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: active)
                .symbolEffectsRemoved(motion != .full)
            Group {
                if t.isGlass {
                    Text(title).font(.system(size: 10, weight: .medium))
                } else {
                    Text(title.uppercased()).font(t.label(9.5)).tracking(t.labelTracking * 0.6)
                }
            }
            .foregroundStyle(t.ink2).lineLimit(1)
            Text(value.map { formatWatts($0, signed: signed) } ?? "—")
                .font(t.isGlass ? t.display(15, .semibold) : t.display(14, .bold)).monospacedDigit()
                .foregroundStyle(active ? t.ink : t.ink2)
            Text(subtitle).font(t.text(10)).foregroundStyle(t.ink2).lineLimit(1)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .modifier(NodeSurface(active: active, tint: tint, signal: signal, emphasis: emphasis))
        // Only on state changes (plugged / unplugged, charging…), never on each sample.
        .motionAnimation(value: symbol)
        .motionAnimation(value: active)
    }
}

/// Glass bubble, or a Glyphe card whose ring takes the accent when it signals a state.
private struct NodeSurface: ViewModifier {
    let active: Bool
    let tint: Color?
    let signal: Bool
    let emphasis: Bool
    @Environment(\.styleTokens) private var t

    func body(content: Content) -> some View {
        if t.isGlass {
            content.glassEffect(.regular.tint(active ? tint?.opacity(0.22) : nil), in: .rect(cornerRadius: 16))
        } else {
            content
                .planche(t, radius: 12, level: emphasis ? 2 : 1, emphasis: emphasis)
                .overlay {
                    RoundedRectangle(cornerRadius: t.night ? 8 : 12, style: .continuous)
                        .strokeBorder(t.accent, lineWidth: signal ? 1.5 : 0)
                        .opacity(signal ? 1 : 0)
                }
        }
    }
}

/// Dots flowing in the direction of the energy, faster with more watts.
/// Driven by Core Animation, so the render server animates it without waking the app.
private struct FlowConnector: NSViewRepresentable {
    enum Direction { case left, right, none }
    let direction: Direction
    let watts: Double
    let color: NSColor
    let idle: NSColor
    let animated: Bool

    func makeNSView(context: Context) -> FlowConnectorView { FlowConnectorView() }
    func updateNSView(_ view: FlowConnectorView, context: Context) {
        view.configure(direction: direction, watts: watts, color: color, idle: idle, animated: animated)
    }
}

fileprivate final class FlowConnectorView: NSView {
    private let dots = CAShapeLayer()
    private static let period: CGFloat = 6
    private var direction: FlowConnector.Direction = .none
    private var duration: CFTimeInterval = 0
    private var animated = true
    private var color: NSColor = .labelColor
    private var idle: NSColor = .tertiaryLabelColor

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        dots.fillColor = nil
        dots.lineWidth = 3
        dots.lineCap = .round
        dots.lineDashPattern = [0, NSNumber(value: Double(Self.period))]
        layer?.addSublayer(dots)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        dots.frame = bounds
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 1.5, y: bounds.midY))
        path.addLine(to: CGPoint(x: bounds.width - 1.5, y: bounds.midY))
        dots.path = path
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColor()
    }

    func configure(direction: FlowConnector.Direction, watts: Double, color: NSColor, idle: NSColor, animated: Bool) {
        // 5 W → ~1.1 s per step, 60 W → 0.3 s; quantized so small changes don't restart it.
        let newDuration = direction == .none ? 0 : (min(1.2, max(0.3, 5.5 / max(watts, 1))) * 10).rounded() / 10
        let colorChanged = color != self.color || idle != self.idle
        self.color = color
        self.idle = idle
        if colorChanged || direction != self.direction { applyColor(active: direction != .none) }
        guard direction != self.direction || newDuration != duration || animated != self.animated else { return }
        self.direction = direction
        self.animated = animated
        duration = newDuration
        dots.removeAnimation(forKey: "flow")
        guard direction != .none, animated else { return }
        let animation = CABasicAnimation(keyPath: "lineDashPhase")
        animation.fromValue = 0
        animation.toValue = direction == .right ? -Self.period : Self.period
        animation.duration = newDuration
        animation.repeatCount = .infinity
        dots.add(animation, forKey: "flow")
    }

    private func applyColor(active: Bool? = nil) {
        let isActive = active ?? (direction != .none)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            // The standalone layer cross-fades the color by itself (implicit Core Animation).
            dots.strokeColor = (isActive ? color : idle).cgColor
        }
    }
}

// MARK: - Breakdown (acts as the chart legend)

private struct BreakdownView: View {
    @EnvironmentObject var store: PowerStore
    @EnvironmentObject var highlight: Highlight
    @EnvironmentObject var ui: UIState
    @Environment(\.motion) private var motion
    @Environment(\.styleTokens) private var t

    var body: some View {
        let s = store.snapshot
        let total = max(s.system ?? 0, 0.01)
        let focus = highlight.component
        let shares = Component.allCases.map { max(0, $0.value(s) ?? 0) / total }
        VStack(alignment: .leading, spacing: 7) {
            SectionTitle(text: "Répartition")
            if ui.snapshot {
                Capsule().fill(.quaternary).frame(height: 8)  // ImageRenderer can't draw AppKit views
            } else {
                SegmentBar(fractions: shares, colors: t.componentLayers,
                           focus: focus.flatMap { Component.allCases.firstIndex(of: $0) },
                           radius: t.isGlass ? 3 : 2, animated: motion != .off)
                    .frame(height: 8)
            }
            ForEach(Component.allCases) { c in
                BreakdownRow(component: c, value: c.value(s), total: total, focused: focus == c, dimmed: focus != nil && focus != c)
            }
        }
        .motionAnimation(.easeOut(duration: 0.2), value: focus)
    }
}

private struct BreakdownRow: View {
    let component: Component
    let value: Double?
    let total: Double
    let focused: Bool, dimmed: Bool
    @EnvironmentObject var highlight: Highlight
    @Environment(\.styleTokens) private var t

    var body: some View {
        let percent = value.map { Int(($0 / total * 100).rounded()) }
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(t.fill(component)).frame(width: 10, height: 10)
                .overlay {
                    // Glyphe: the darkest greys get a ring so they still read on the pane.
                    if !t.isGlass { RoundedRectangle(cornerRadius: 2).strokeBorder(t.line2, lineWidth: 1) }
                }
                .scaleEffect(focused ? 1.25 : 1)
            Text(component.rawValue).font(t.text(12, t.isGlass ? .regular : .medium))
            Text(component.detail).font(t.text(11)).foregroundStyle(t.ink3)
            Spacer()
            if let percent {
                Text("\(percent) %").font(t.text(11)).foregroundStyle(t.ink2).monospacedDigit()
            }
            Text(formatWatts(value)).font(t.text(12, t.isGlass ? .medium : .semibold)).monospacedDigit().frame(width: 52, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(RoundedRectangle(cornerRadius: t.isGlass ? 6 : 4).fill(focused ? t.hover : .clear))
        .padding(.horizontal, -6)
        .opacity(dimmed ? 0.5 : 1)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { highlight.component = component } else if highlight.component == component { highlight.component = nil }
        }
    }
}

// MARK: - Apps

private struct AppsView: View {
    @EnvironmentObject var store: PowerStore
    @Environment(\.styleTokens) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: "Les plus gourmandes", trailing: "CPU · GPU")
            if !store.appsReady {
                HStack {
                    StyledProgress(t: t)
                    Text("Mesure en cours…").font(t.text(11)).foregroundStyle(t.ink2)
                }
                .frame(maxWidth: .infinity, minHeight: 60)
                .transition(.opacity)
            } else {
                let top = store.apps
                let maxW = max(top.first?.watts ?? 1, 0.01)
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(top) { app in
                            AppRow(app: app, maxWatts: maxW, colors: [t.layerColor(.cpu), t.layerColor(.gpu)]).equatable()
                        }
                    }
                    .padding(.trailing, 2)
                }
                .scrollIndicators(.automatic)
                .transition(.opacity)
            }
        }
        .motionAnimation(value: store.appsReady)
    }
}

/// Equatable on what is actually displayed, so rows whose rounded values didn't change are not re-rendered.
private struct AppRow: View, Equatable {
    let app: AppPower
    let maxWatts: Double
    /// CPU and GPU bar colors.
    let colors: [NSColor]
    @Environment(\.motion) private var motion
    @Environment(\.styleTokens) private var t
    private static let barWidth: CGFloat = 150

    static func == (l: AppRow, r: AppRow) -> Bool {
        l.app.id == r.app.id && l.app.processCount == r.app.processCount && l.colors == r.colors
            && Int(l.app.cpuPercent.rounded()) == Int(r.app.cpuPercent.rounded())
            && Int(l.app.gpuPercent.rounded()) == Int(r.app.gpuPercent.rounded())
            && formatWatts(l.app.watts) == formatWatts(r.app.watts)
            && l.cpuBar == r.cpuBar && l.gpuBar == r.gpuBar
    }

    /// Bar widths, quantized to 1/50 so tiny changes don't redraw the row.
    private var cpuBar: CGFloat { CGFloat(Int(min(1, app.cpuWatts / maxWatts) * 50)) / 50 }
    private var gpuBar: CGFloat { app.gpuWatts / maxWatts > 0.01 ? CGFloat(Int(min(1, app.gpuWatts / maxWatts) * 50)) / 50 : 0 }

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let icon = app.icon {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "gearshape.2").resizable().scaledToFit().padding(2).foregroundStyle(t.ink2)
                }
            }
            .frame(width: 20, height: 20)
            // At night, app icons go monochrome red too.
            .grayscale(t.night ? 1 : 0)
            .colorMultiply(t.night ? t.ink : .white)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(app.name).font(t.text(12, t.isGlass ? .regular : .medium)).lineLimit(1).truncationMode(.middle)
                    if app.processCount > 1 {
                        Text("×\(app.processCount)").font(t.text(10)).foregroundStyle(t.ink3)
                    }
                }
                SegmentBar(fractions: [max(cpuBar, 0.01), gpuBar], colors: colors,
                           gap: 1, radius: 1.5, minWidth: 2, animated: motion != .off)
                    .frame(width: Self.barWidth, height: 3)
            }

            Spacer(minLength: 4)
            Text("\(Int(app.cpuPercent.rounded())) % · \(Int(app.gpuPercent.rounded())) %")
                .font(t.text(10)).foregroundStyle(t.ink2).monospacedDigit()
            Text(formatWatts(app.watts))
                .font(t.text(12, t.isGlass ? .medium : .semibold)).monospacedDigit()
                .frame(width: 58, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .hoverHighlight()
    }
}

/// Subtle background under the hovered row.
private struct HoverHighlight: ViewModifier {
    @StateObject private var hover = HoverFlag()
    @Environment(\.motion) private var motion
    @Environment(\.styleTokens) private var t

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: t.isGlass ? 8 : 5).fill(hover.on ? t.hover : .clear))
            .padding(.horizontal, -6)
            .onHover { inside in
                withAnimation(motion.animation(.easeOut(duration: 0.15))) { hover.on = inside }
            }
    }
}

extension View {
    func hoverHighlight() -> some View { modifier(HoverHighlight()) }
}

// MARK: - Tabs: apps / battery & charger / ports

enum DetailTab: String, CaseIterable, Identifiable {
    case apps = "Apps", battery = "Batterie", ports = "Ports & USB"
    var id: String { rawValue }
}

private struct DetailsView: View {
    @EnvironmentObject var store: PowerStore
    @EnvironmentObject var settings: AppSettings
    @AppStorage("detailTab") private var tab: DetailTab = .apps
    @Environment(\.motion) private var motion
    @Environment(\.styleTokens) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if t.isGlass {
                Picker("", selection: $tab) {
                    ForEach(DetailTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .tint(settings.accent == .system ? nil : settings.accent.color)
            } else {
                Segmented(selection: $tab, options: DetailTab.allCases, fill: true) { $0.rawValue }
            }

            // Fixed height: switching tabs never resizes the panel, long content scrolls.
            ZStack(alignment: .top) {
                Group {
                    switch tab {
                    case .apps: AppsView()
                    case .battery: ScrollView { BatteryDetails(snapshot: store.snapshot) }
                    case .ports: ScrollView { PortsDetails(ports: store.ports, devices: store.usbDevices) }
                    }
                }
                .id(tab)
                .transition(motion != .full ? .opacity
                            : t.isGlass ? AnyTransition(.blurReplace) : .opacity.combined(with: .offset(y: 8)))
            }
            .frame(height: 236, alignment: .top)
            .clipped()
            .motionAnimation(t.isGlass ? .smooth(duration: 0.3) : GlypheSpring.standard, value: tab)
        }
    }
}

private struct InfoRow: View {
    let label: String, value: String
    @Environment(\.styleTokens) private var t

    var body: some View {
        HStack {
            Text(label).foregroundStyle(t.ink2)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(t.text(11, t.isGlass ? .regular : .medium))
    }
}

private struct BatteryDetails: View {
    let snapshot: PowerSnapshot
    @Environment(\.styleTokens) private var t

    var body: some View {
        let b = snapshot.batteryInfo
        VStack(alignment: .leading, spacing: 3) {
            if let b {
                if let h = b.health { InfoRow(label: "Santé", value: String(format: "%.1f %%", h * 100)) }
                if let c = b.cycleCount { InfoRow(label: "Cycles", value: "\(c)") }
                if let full = b.fullChargeCapacity, let design = b.designCapacity {
                    InfoRow(label: "Capacité", value: "\(b.currentCapacity.map { "\($0) / " } ?? "")\(full) mAh (neuve : \(design))")
                }
                if let t = b.temperature { InfoRow(label: "Température", value: String(format: "%.1f °C", t)) }
                InfoRow(label: "Tension · courant", value: String(format: "%.2f V · %+.2f A", b.voltage, b.amperage))
                if let a = b.adapter {
                    StyledDivider().padding(.vertical, 2)
                    InfoRow(label: "Chargeur", value: [a.manufacturer, a.name].compactMap { $0 }.joined(separator: " ").ifEmpty("Inconnu"))
                    if let w = a.watts { InfoRow(label: "Puissance nominale", value: "\(Int(w)) W") }
                    if let v = a.voltage, let i = a.current {
                        InfoRow(label: "Profil négocié", value: String(format: "%.0f V · %.2f A", v, i))
                    }
                    if let v = b.inputVoltage, let i = b.inputCurrent, v > 0 {
                        InfoRow(label: "Entrée mesurée", value: String(format: "%.1f V · %.2f A", v, i))
                    }
                }
            } else {
                Text("Aucune batterie détectée").font(t.text(11)).foregroundStyle(t.ink2)
            }
        }
    }
}

private struct PortsDetails: View {
    let ports: [PortInfo]
    let devices: [USBDeviceInfo]
    @Environment(\.styleTokens) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(ports) { port in
                HStack(spacing: 6) {
                    Circle().fill(port.connected ? t.positive : t.ink3.opacity(0.4)).frame(width: 6, height: 6)
                    Text(port.name).font(t.text(11, t.isGlass ? .regular : .medium))
                    Spacer()
                    Text(portDescription(port)).font(t.text(11)).foregroundStyle(t.ink2)
                }
            }
            if !devices.isEmpty {
                StyledDivider().padding(.vertical, 2)
                ForEach(devices) { d in
                    HStack(spacing: 6) {
                        Image(systemName: "cable.connector.horizontal").font(.system(size: 10)).foregroundStyle(t.ink2)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(d.name).font(t.text(11)).lineLimit(1)
                            if let info = [d.vendor, d.speed].compactMap({ $0 }).joined(separator: " · ").nilIfEmpty {
                                Text(info).font(t.text(10)).foregroundStyle(t.ink3).lineLimit(1)
                            }
                        }
                        Spacer()
                        Text(d.allocatedWatts.map { String(format: "≤ %.1f W", $0) } ?? "–")
                            .font(t.text(11)).monospacedDigit()
                    }
                }
            }
            Text("macOS ne mesure pas la consommation réelle de chaque port : la valeur USB est le budget réservé par l'appareil. Leur conso réelle est incluse dans « Autres ».")
                .font(t.text(10)).foregroundStyle(t.ink3).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    private func portDescription(_ p: PortInfo) -> String {
        guard p.connected else { return "libre" }
        var parts = p.transports.map { t -> String in
            switch t {
            case "CIO": "Thunderbolt"
            case "USB2": "USB 2"
            case "USB3": "USB 3"
            default: t
            }
        }
        if let ma = p.sourcingMilliamps { parts.append(String(format: "fournit ≤ %.1f W", Double(ma) * 5 / 1000)) }
        if parts.isEmpty { parts.append(p.isMagSafe ? "chargeur" : "connecté") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Footer

private struct FooterView: View {
    @EnvironmentObject var store: PowerStore
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var ui: UIState
    @Environment(\.motion) private var motion
    @Environment(\.styleTokens) private var t

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if t.isGlass {
                    Text(energyLine)
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                } else {
                    Text(energyLine.uppercased())
                        .font(t.label(10)).tracking(t.labelTracking).foregroundStyle(t.onFrame2)
                }
            }
            .monospacedDigit()
            .lineLimit(1)
            .help("Énergie consommée et puissance moyenne depuis le lancement de Volta")
            Spacer()
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
            } label: {
                Image(systemName: "chart.bar.xaxis")
            }
            .help("Moniteur d'activité")
            .iconButtonStyle(t)
            Button {
                withAnimation(motion.animation(settings.panelStyle.reveal.navigation)) { ui.showSettings = true }
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Réglages")
            .iconButtonStyle(t)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Energy and mean power since launch (the tooltip says since when: the full sentence doesn't fit).
    private var energyLine: String {
        guard let average = store.averageWatts else { return String(format: "%.2f Wh depuis le lancement", store.energyWh) }
        return String(format: "%.2f Wh · moy. ", store.energyWh) + formatWatts(average)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
