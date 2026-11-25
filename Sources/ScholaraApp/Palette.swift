import SwiftUI

enum ReadingPalette: String, CaseIterable, Identifiable {
    case paper = "Paper", soft = "Soft"
    var id: String { rawValue }
    var background: Color { Color(nsColor: backgroundNS) }
    var surface: Color { self == .paper ? .white : Color(hex: 0xF5F4EF) }
    var card: Color { self == .paper ? .white : Color(hex: 0xFAFAF7) }
    var ink: Color { self == .paper ? Color(hex: 0x202124) : Color(hex: 0x1F1B16) }
    var muted: Color { ink.opacity(0.70) }
    var outline: Color { self == .paper ? Color(hex: 0xDDDEE2) : Color(hex: 0xE7DFC8) }
    var accent: Color { Color(hex: 0xC8702C) }
    var pronunciation: Color { self == .paper ? Color(hex: 0x326B91) : Color(hex: 0x527A87) }
    var origin: Color { self == .paper ? Color(hex: 0x806091) : Color(hex: 0x8A6C85) }
    var backgroundNS: NSColor { self == .paper ? .white : NSColor(hex: 0xFAFAF7) }
    var inkNS: NSColor { self == .paper ? NSColor(hex: 0x202124) : NSColor(hex: 0x1F1B16) }
    static var current: Self { Self(rawValue: UserDefaults.standard.string(forKey: "readingPalette") ?? "Soft") ?? .soft }
}
private struct PaletteKey: EnvironmentKey { static let defaultValue = ReadingPalette.soft }
extension EnvironmentValues { var readingPalette: ReadingPalette { get { self[PaletteKey.self] } set { self[PaletteKey.self] = newValue } } }
extension Color { init(hex: UInt32) { self.init(nsColor: NSColor(hex: hex)) } }
extension NSColor {
    convenience init(hex: UInt32) { self.init(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1) }
}
