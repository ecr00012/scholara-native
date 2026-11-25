import AppKit

/// Finite TextKit containers preserve selection and exact character anchors.
/// Images are copied and fitted before layout, so a tall illustration cannot
/// prevent the remainder of a section from flowing into subsequent pages.
public final class TextPagination {
    public let storage: NSTextStorage
    public let manager = NSLayoutManager()
    public private(set) var containers: [NSTextContainer] = []
    public private(set) var ranges: [NSRange] = []
    public init(content: NSAttributedString, size: NSSize) {
        let size = NSSize(width: max(120, size.width), height: max(120, size.height))
        storage = NSTextStorage(attributedString: content)
        content.enumerateAttribute(.attachment, in: NSRange(location: 0, length: content.length)) { value, range, _ in
            guard let original = value as? NSTextAttachment, let image = original.image else { return }
            let attachment = NSTextAttachment()
            attachment.image = image
            let originalSize = original.bounds.size.width > 0 ? original.bounds.size : image.size
            let scale = min(1, size.width / max(1, originalSize.width), (size.height - 30) / max(1, originalSize.height))
            attachment.bounds = NSRect(x: 0, y: 0, width: originalSize.width * scale, height: originalSize.height * scale)
            storage.addAttribute(.attachment, value: attachment, range: range)
        }
        storage.addLayoutManager(manager)
        var covered = 0
        repeat {
            let container = NSTextContainer(containerSize: size); container.lineFragmentPadding = 0
            manager.addTextContainer(container); containers.append(container)
            manager.ensureLayout(for: container)
            let glyphs = manager.glyphRange(for: container)
            ranges.append(manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil))
            let end = NSMaxRange(glyphs)
            if end <= covered { break }
            covered = end
        } while covered < manager.numberOfGlyphs
    }
    public func page(containing character: Int) -> Int {
        let anchor = min(max(0, character), max(0, storage.length - 1))
        return ranges.firstIndex(where: { NSLocationInRange(anchor, $0) }) ?? max(0, ranges.count - 1)
    }
}
