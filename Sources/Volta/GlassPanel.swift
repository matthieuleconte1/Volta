import AppKit
import SwiftUI

/// Borderless panel that drops down from the menu bar, like Control Center: Liquid Glass for the "Verre" style,
/// a plain rounded surface for opaque styles (Atelier Glyphe), whose SwiftUI content draws its own frame.
/// Its SwiftUI content only exists while the panel is visible, so a closed panel costs nothing.
final class GlassPanel: NSPanel {
    var onClose: (() -> Void)?
    private let makeContent: () -> AnyView
    private var monitors: [Any] = []
    private let glass = NSGlassEffectView()
    private let plain = NSView()
    private var usesGlass = true
    private var hosting: NSView?
    private var animateResize = true
    private var closing = false
    private weak var statusButton: NSStatusBarButton?
    private var anchor = CGPoint.zero        // top-center of the panel, under the status item
    private var screenFrame = NSRect.zero

    /// `content` must have a fixed ideal size: the panel follows it, keeping its top edge in place.
    init<Content: View>(content: @escaping () -> Content) {
        var fit: ((CGSize) -> Void)?
        makeContent = {
            AnyView(content()
                .onGeometryChange(for: CGSize.self, of: \.size) { fit?($0) }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top))
        }
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        // No window shadow: macOS draws its outline as a less rounded rectangle than the glass,
        // which shows as a 1 px border around the corners. The glass has its own rim.
        hasShadow = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow

        glass.cornerRadius = 24
        glass.style = .regular
        plain.wantsLayer = true
        plain.layer?.masksToBounds = true
        plain.layer?.cornerCurve = .continuous
        contentView = glass
        fit = { [weak self] in self?.fit(to: $0) }
    }

    /// `glass` nil: opaque style, the content is clipped to `cornerRadius` and the window draws a shadow.
    func applyAppearance(glass style: NSGlassEffectView.Style?, tint: NSColor?, cornerRadius: CGFloat,
                         appearance: NSAppearance?, animateResize: Bool) {
        if let style {
            glass.style = style
            glass.tintColor = tint
        }
        glass.cornerRadius = cornerRadius
        plain.layer?.cornerRadius = cornerRadius
        self.appearance = appearance
        self.animateResize = animateResize
        if usesGlass != (style != nil) {
            usesGlass = style != nil
            // No window shadow on glass: macOS draws its outline as a less rounded rectangle than the glass,
            // which shows as a 1 px border around the corners. Opaque styles keep it (the "window" layer).
            hasShadow = !usesGlass
            install(hosting)
        }
    }

    /// Puts the SwiftUI content in the glass or in the plain container.
    /// Whatever was there before is always removed: a SwiftUI graph left in a container keeps
    /// rendering after the panel closes, and one more piles up at each opening.
    private func install(_ view: NSView?) {
        plain.subviews.forEach { $0.removeFromSuperview() }
        if usesGlass {
            glass.contentView = view
            if contentView !== glass { contentView = glass }
        } else {
            glass.contentView = nil
            if contentView !== plain { contentView = plain }
            if let view {
                view.frame = plain.bounds
                view.autoresizingMask = [.width, .height]
                plain.addSubview(view)
            }
        }
        invalidateShadow()
    }

    override var canBecomeKey: Bool { true }

    /// Visible and not fading out.
    var isShown: Bool { isVisible && !closing }

    func show(below button: NSStatusBarButton) {
        // Reopened while fading out: the pending teardown must not take the new content with it.
        closing = false
        statusButton = button
        let hosting = NSHostingView(rootView: makeContent())
        self.hosting = hosting
        install(hosting)

        let screen = button.window?.screen ?? NSScreen.main
        screenFrame = screen?.visibleFrame ?? .zero
        var buttonRect = button.window.map { $0.convertToScreen(button.convert(button.bounds, to: nil)) } ?? .zero
        // Fallback when the item isn't in the menu bar (hidden by macOS): top-right corner of the screen.
        if let full = screen?.frame, !(full.contains(CGPoint(x: buttonRect.midX, y: buttonRect.midY)) && buttonRect.midY > full.maxY - 60) {
            buttonRect = NSRect(x: screenFrame.maxX - 200, y: screenFrame.maxY, width: 0, height: 0)
        }
        let size = hosting.fittingSize
        // From now on the panel follows the SwiftUI size itself (see `fit`), so AppKit must not.
        hosting.sizingOptions = []
        anchor = CGPoint(x: buttonRect.midX, y: buttonRect.minY - 6)
        setFrame(frame(for: size), display: false)

        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            animator().alphaValue = 1
        }
        installMonitors()
    }

    func dismiss() {
        guard isVisible, !closing else { return }
        closing = true
        removeMonitors()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, closing else { return }
            closing = false
            orderOut(nil)
            hosting = nil
            install(nil)  // tear down the SwiftUI graph
            onClose?()
        })
    }

    private func frame(for size: CGSize) -> NSRect {
        let height = min(size.height, screenFrame.height - 12)
        let x = min(max(anchor.x - size.width / 2, screenFrame.minX + 8), screenFrame.maxX - size.width - 8)
        return NSRect(x: x, y: anchor.y - height, width: size.width, height: height)
    }

    /// Resizes the panel to the content (e.g. settings page, hidden sections), top edge fixed.
    private func fit(to size: CGSize) {
        guard isVisible, size.height > 0 else { return }
        let target = frame(for: size)
        guard abs(target.height - frame.height) > 0.5 || abs(target.width - frame.width) > 0.5 else { return }
        if animateResize {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animator().setFrame(target, display: true)
            } completionHandler: { [weak self] in
                self?.invalidateShadow()
            }
        } else {
            setFrame(target, display: true)
            invalidateShadow()
        }
    }

    private func installMonitors() {
        removeMonitors()
        // A click anywhere outside (other apps, desktop) closes the panel.
        // Not the status item: it toggles the panel itself, and on recent macOS its clicks also reach us as global
        // events (closing here, then reopening on its action, made a second click on the icon reopen the panel).
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            guard let self else { return }
            if let button = statusButton, let window = button.window,
               window.convertToScreen(button.convert(button.bounds, to: nil)).contains(NSEvent.mouseLocation) { return }
            dismiss()
        }) { monitors.append(m) }
        // Escape closes it too.
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            if event.keyCode == 53 { self?.dismiss(); return nil }
            return event
        }) { monitors.append(m) }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }
}
