import AppKit
import Combine
import SwiftUI
import UserNotifications

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private let store = PowerStore()
    private let settings = AppSettings.shared
    private var settingsObserver: AnyCancellable?
    private var statusItem: NSStatusItem!
    private var panel: GlassPanel!
    private var menuState: MenuBarState?
    private var shownTitle: String?
    private var shownSymbol: String??
    private var shownAlert = false
    private var shownAlertColor: NSColor?
    private var requestedNotifications = false
    /// The next opening lands on the settings page (menu item "Réglages…").
    private var openOnSettings = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        VariableFont.registerBundled()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Volta")
        }

        panel = GlassPanel { [weak self, store, settings] in
            let ui = UIState()
            ui.showSettings = ProcessInfo.processInfo.environment["VOLTA_SETTINGS"] != nil || self?.openOnSettings == true
            self?.openOnSettings = false
            // The automatic night started or ended while the panel is open: native controls follow.
            ui.onThemeChange = { self?.applyPanelAppearance() }
            return PopoverView().environmentObject(store).environmentObject(settings).environmentObject(ui)
        }
        panel.onClose = { [weak self] in self?.store.setPanelOpen(false) }

        store.onMenuBarUpdate = { [weak self] state in
            self?.menuState = state
            self?.updateStatusItem()
        }
        store.onSustainedLoad = { LoadNotifier.post($0) }
        if LoadNotifier.available { UNUserNotificationCenter.current().delegate = self }
        // objectWillChange fires before the new value is stored: apply on the next runloop turn.
        settingsObserver = settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applySettings() }

        store.start()
        applySettings()

        if ProcessInfo.processInfo.environment["VOLTA_OPEN"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.togglePanel() }
        }
        if let path = ProcessInfo.processInfo.environment["VOLTA_SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { self.store.publishNow() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 9) { self.snapshotPanel(to: path) }
        }
    }

    /// Debug helper: renders the panel content to a PNG.
    @MainActor private func snapshotPanel(to path: String) {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let ui = UIState()
        ui.appeared = true
        ui.snapshot = true
        ui.showSettings = ProcessInfo.processInfo.environment["VOLTA_SETTINGS"] != nil
        let content = PopoverView()
            .environmentObject(store).environmentObject(settings).environmentObject(ui)
            .background(Color(white: dark ? 0.17 : 0.95))
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return }
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    /// Menu bar format: "8.4 W" below 10 W, "12 W" above.
    static func menuBarText(_ v: Double?, signed: Bool) -> String {
        guard let v else { return "– W" }
        let sign = signed && v >= 0.05 ? "+" : ""
        return sign + String(format: v.magnitude >= 9.95 ? "%.0f W" : "%.1f W", v)
    }

    private func applySettings() {
        store.configure(openInterval: settings.refreshInterval, historyMinutes: settings.historyMinutes,
                        sustainedAlert: settings.sustainedAlert, alertOnBatteryOnly: settings.sustainedAlertOnBattery)
        if settings.sustainedAlert > 0, !requestedNotifications {
            requestedNotifications = true
            LoadNotifier.requestAuthorization()
        }
        applyPanelAppearance()
        updateStatusItem()
    }

    /// Also run at each opening: the automatic night may have started since the last change.
    private func applyPanelAppearance() {
        let glass = settings.panelStyle == .glass
        panel.applyAppearance(
            glass: glass ? (settings.glass == .clear ? .clear : .regular) : nil,
            tint: settings.glassTint == .none ? nil : settings.accent.nsColor.withAlphaComponent(settings.glassTint.alpha),
            cornerRadius: glass ? 24 : 16,
            appearance: glass ? nil : settings.glypheTheme(at: Date()).appearance,
            animateResize: settings.motion != .off && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    /// Only touches the status item when the text or icon actually changes
    /// (every change makes macOS re-snapshot the item).
    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let metric = settings.menuBarMetric
        let showIcon = settings.menuBarIcon
        let imagePosition: NSControl.ImagePosition = settings.menuBarIconSide == .left ? .imageLeading : .imageTrailing
        if button.imagePosition != imagePosition { button.imagePosition = imagePosition }
        let state = menuState

        let value: Double? = switch metric {
        case .system: state?.system
        case .adapter: state?.adapter
        case .battery: state?.battery
        }
        let title = Self.menuBarText(value, signed: metric == .battery)
        // Alert: the value turns orange (Glyphe: the accent, red at night) above the user's threshold.
        let alert = settings.menuBarAlert > 0 && abs(value ?? 0) >= Double(settings.menuBarAlert)
        let alertColor: NSColor? = switch settings.panelStyle {
        case .glass: .systemOrange
        case .glyphe: settings.glypheTheme(at: Date()) == .night ? .nightAccent(level: settings.glypheNightLevel) : settings.glypheAccent.nsColor
        }
        if title != shownTitle || alert != shownAlert || alertColor != shownAlertColor {
            shownTitle = title
            shownAlert = alert
            shownAlertColor = alertColor
            var attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize - 0.5, weight: alert ? .semibold : .medium),
                .baselineOffset: 0.5,
            ]
            if alert, let alertColor { attributes[.foregroundColor] = alertColor }
            button.attributedTitle = NSAttributedString(string: title, attributes: attributes)
        }

        // No battery icon: only show charging / plugged-in states.
        var symbol: String?
        if showIcon, let state {
            symbol = state.charging ? "bolt.fill" : state.onAC ? "powerplug.fill" : nil
        }
        if shownSymbol != .some(symbol) || button.toolTip != "Volta — " + metric.label {
            shownSymbol = .some(symbol)
            button.image = symbol.flatMap {
                let image = NSImage(systemSymbolName: $0, accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
                image?.isTemplate = true
                return image
            }
            button.toolTip = "Volta — " + metric.label
        }
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            togglePanel()
        }
    }

    @objc private func togglePanel() {
        if panel.isShown {
            panel.dismiss()
        } else {
            openPanel()
        }
    }

    private func openPanel() {
        guard let button = statusItem.button, !panel.isShown else { return }
        store.setPanelOpen(true)
        store.publishNow()
        applyPanelAppearance()
        panel.show(below: button)
    }

    // MARK: - Right-click menu

    private func showMenu() {
        guard let button = statusItem.button else { return }
        if panel.isShown { panel.dismiss() }
        let menu = NSMenu()
        let header = NSMenuItem(title: L("Valeur affichée"), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for metric in MenuBarMetric.allCases {
            let item = NSMenuItem(title: metric.label, action: #selector(chooseMetric(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = metric.rawValue
            item.state = settings.menuBarMetric == metric ? .on : .off
            item.indentationLevel = 1
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(item(L("Remettre à zéro le compteur d'énergie"), #selector(resetEnergy)))
        menu.addItem(item(L("Moniteur d'activité"), #selector(openActivityMonitor)))
        menu.addItem(item(L("Réglages…"), #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item(L("Quitter Volta"), #selector(quit), key: "q"))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func chooseMetric(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let metric = MenuBarMetric(rawValue: raw) else { return }
        settings.menuBarMetric = metric
    }

    @objc private func resetEnergy() { store.resetEnergy() }

    @objc private func openActivityMonitor() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
    }

    @objc private func openSettings() {
        openOnSettings = true
        openPanel()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Volta is always "frontmost" for macOS (no Dock icon): show the banner anyway.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    /// Clicking the alert opens the panel on the apps.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async {
            UserDefaults.standard.set(DetailTab.apps.rawValue, forKey: "detailTab")
            self.openPanel()
        }
        completionHandler()
    }
}
