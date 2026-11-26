import SwiftUI

enum ReadingPalette: String, CaseIterable, Identifiable {
    case paper = "Paper", soft = "Soft", dark = "Dark"
    var id: String { rawValue }
    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
    var background: Color { Color(nsColor: backgroundNS) }
    var surface: Color { Color(hex: self == .dark ? 0x242426 : self == .paper ? 0xFFFFFF : 0xF5F4EF) }
    var card: Color { Color(hex: self == .dark ? 0x2B2B2E : self == .paper ? 0xFFFFFF : 0xFAFAF7) }
    var selected: Color { self == .dark ? Color(hex: 0x414145) : .white }
    var ink: Color { Color(nsColor: inkNS) }
    var muted: Color { ink.opacity(0.70) }
    var outline: Color { Color(hex: self == .dark ? 0x4B4843 : self == .paper ? 0xDDDEE2 : 0xE7DFC8) }
    var accent: Color { Color(hex: self == .dark ? 0xE9A367 : 0xC8702C) }
    var pronunciation: Color { Color(hex: self == .dark ? 0x88BEDB : self == .paper ? 0x326B91 : 0x527A87) }
    var origin: Color { Color(hex: self == .dark ? 0xC6A4DB : self == .paper ? 0x806091 : 0x8A6C85) }
    var backgroundNS: NSColor { NSColor(hex: self == .dark ? 0x1C1C1E : self == .paper ? 0xFFFFFF : 0xFAFAF7) }
    var inkNS: NSColor { NSColor(hex: self == .dark ? 0xEEEAE4 : self == .paper ? 0x202124 : 0x1F1B16) }
    static var current: Self { Self(rawValue: UserDefaults.standard.string(forKey: "readingPalette") ?? "Soft") ?? .soft }
}
private struct PaletteKey: EnvironmentKey { static let defaultValue = ReadingPalette.soft }
extension EnvironmentValues { var readingPalette: ReadingPalette { get { self[PaletteKey.self] } set { self[PaletteKey.self] = newValue } } }
extension Color { init(hex: UInt32) { self.init(nsColor: NSColor(hex: hex)) } }
extension NSColor {
    convenience init(hex: UInt32) { self.init(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1) }
}
