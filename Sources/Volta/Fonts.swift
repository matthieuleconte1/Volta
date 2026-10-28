import AppKit
import CoreText
import SwiftUI

/// Fonts of the styles (Red Hat Display, Zalando Sans Expanded…), set axis by axis and cached.
/// Fonts shipped in the app (Resources/Fonts) are registered for this process only; otherwise the
/// fonts installed on the Mac are used, and a missing family falls back to the system font.
enum VariableFont {
    private static var bundled: [String: NSFontDescriptor] = [:]
    private static var cache: [String: NSFont] = [:]
    private static var missing = Set<String>()

    static func registerBundled() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for url in urls where ["ttf", "otf"].contains(url.pathExtension.lowercased()) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? []
            for descriptor in descriptors {
                let d = descriptor as NSFontDescriptor
                if let family = d.object(forKey: .family) as? String, bundled[family] == nil { bundled[family] = d }
            }
        }
    }

    /// `weight`: CSS scale (100…900). `tabular`: digits of equal width (values that change in place).
    static func make(_ family: String, size: CGFloat, weight: CGFloat, tabular: Bool = false) -> NSFont? {
        let key = "\(family)|\(size)|\(weight)|\(tabular)"
        if let font = cache[key] { return font }
        guard !missing.contains(family) else { return nil }
        var descriptor: NSFontDescriptor
        if let base = bundled[family] {
            // Variable font shipped with the app: the weight axis is set exactly.
            descriptor = base.addingAttributes([.variation: [tag("wght"): weight]])
        } else {
            // Installed on the Mac (static files or variable font): the closest weight.
            descriptor = NSFontDescriptor(fontAttributes: [.family: family, .traits: [NSFontDescriptor.TraitKey.weight: nsWeight(weight)]])
        }
        if tabular {
            descriptor = descriptor.addingAttributes([.featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector]]])
        }
        guard let font = NSFont(descriptor: descriptor, size: size), font.familyName == family else {
            missing.insert(family)
            return nil
        }
        cache[key] = font
        return font
    }

    static func value(_ weight: Font.Weight) -> CGFloat {
        switch weight {
        case .ultraLight: 200
        case .thin: 250
        case .light: 300
        case .medium: 500
        case .semibold: 600
        case .bold: 700
        case .heavy: 800
        case .black: 900
        default: 400
        }
    }

    static func nsWeight(_ value: CGFloat) -> NSFont.Weight {
        switch value {
        case ..<250: .ultraLight
        case ..<350: .light
        case ..<450: .regular
        case ..<550: .medium
        case ..<650: .semibold
        case ..<750: .bold
        case ..<850: .heavy
        default: .black
        }
    }

    private static func tag(_ name: String) -> NSNumber {
        NSNumber(value: name.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
    }
}
