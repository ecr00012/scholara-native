import AppKit

public enum ReaderFont: String, CaseIterable, Identifiable, Sendable {
    case serif = "Literary", georgia = "Georgia", sans = "System Sans", mono = "Monospaced"
    public var id: String { rawValue }
    public func font(size: CGFloat) -> NSFont {
        switch self {
        case .serif: return NSFont(name: "IowanOldStyle-Roman", size: size) ?? NSFont(name: "Georgia", size: size) ?? .systemFont(ofSize: size)
        case .georgia: return NSFont(name: "Georgia", size: size) ?? .systemFont(ofSize: size)
        case .sans: return .systemFont(ofSize: size)
        case .mono: return .monospacedSystemFont(ofSize: size, weight: .regular)
        }
    }
}
