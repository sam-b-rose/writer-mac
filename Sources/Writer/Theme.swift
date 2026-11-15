import AppKit
import CoreText
import WriterCore

enum Theme {
    static func color(_ light: UInt32, _ dark: UInt32, alpha: CGFloat = 1) -> NSColor {
        func make(_ hex: UInt32) -> NSColor {
            NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha)
        }
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? make(dark) : make(light)
        }
    }

    static let background = color(0xFFFFFF, 0x141414)
    static let text = color(0x1A1A1A, 0xCCCCCC)
    static let markup = color(0xB4B4B4, 0x5A5A5A)
    static let dim = color(0xCFCFCF, 0x404040)
    static let caret = color(0x00AAFF, 0x00D3FE)
    static let selection = color(0x00AAFF, 0x00D3FE, alpha: 0.22)
    static let accent = color(0x1D88D4, 0x5DB4F2)
    static let muted = color(0x8C8C8C, 0x767676)
    static let highlight = color(0xFFE066, 0x7A6A1F, alpha: 0.55)
    static let codeBackground = color(0xF5F5F5, 0x1E1E1E)
    static let styleMark = color(0x0096E6, 0x00D3FE, alpha: 0.75)
    static let ai = color(0x7A68D6, 0xA497F2)
    static let reference = color(0x2E9E8F, 0x58C7B8)
    static let otherAuthor = color(0xC27A2C, 0xE0A566)

    static let partsOfSpeech: [PartOfSpeech: NSColor] = [
        .adjectives: color(0xB07A1E, 0xD6A24E),
        .nouns: color(0xD23A4F, 0xF0707F),
        .adverbs: color(0x9A46C4, 0xC584E6),
        .verbs: color(0x1D88D4, 0x5DB4F2),
        .conjunctions: color(0x1F9A58, 0x5CCC8D),
    ]

    static func authorColor(_ key: String) -> NSColor {
        switch key {
        case Author.ai: return ai
        case Author.reference: return reference
        default: return otherAuthor
        }
    }

    static func registerFonts() {
        guard let fonts = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: fonts, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "ttf" {
            CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
        }
    }

    static func family(_ key: String) -> String {
        switch key {
        case "mono": return "iA Writer Mono S"
        case "quattro": return "iA Writer Quattro S"
        default: return "iA Writer Duo S"
        }
    }

    static func font(bold: Bool = false, italic: Bool = false, family key: String? = nil) -> NSFont {
        let size = CGFloat(Settings.shared.size)
        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        return NSFontManager.shared.font(withFamily: family(key ?? Settings.shared.font), traits: traits, weight: bold ? 9 : 5, size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
    }

    static var characterWidth: CGFloat {
        ("0" as NSString).size(withAttributes: [.font: font()]).width
    }

    static func applyAppearance() {
        switch Settings.shared.appearance {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }
}
