import AppKit
import PDFKit
import SwiftUI
import ScholaraCore

final class ReaderTextView: NSTextView {
    var pageTurn: ((Int) -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty, let pageTurn {
            if [124,125,49].contains(event.keyCode) { pageTurn(1); return }
            if [123,126].contains(event.keyCode) { pageTurn(-1); return }
        }
        super.keyDown(with: event)
    }
}
final class ReaderPDFView: PDFView {
    var pageTurn: ((Int) -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty, let pageTurn {
            if [124,125,49].contains(event.keyCode) { pageTurn(1); return }
            if [123,126].contains(event.keyCode) { pageTurn(-1); return }
        }
        super.keyDown(with: event)
    }
}

/// TextKit flows one section through fixed-size native text containers.
/// Only the visible page has an NSTextView; resizing preserves its text anchor.
@MainActor
final class PagedTextHost: NSView {
    private let storage = NSTextStorage()
    private let manager = NSLayoutManager()
    private var containers: [NSTextContainer] = []
    let text = ReaderTextView(frame: .zero)
    private var page = 0
    private var anchor = 0
    private var lastSize = NSSize.zero
    private var pendingLayout = true
    var onPage: ((Int, Int, Int) -> Void)?
    var background: NSColor = .white { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        storage.addLayoutManager(manager)
        text.isEditable = false; text.isSelectable = true; text.isRichText = true; text.drawsBackground = false
        text.isVerticallyResizable = false; text.isHorizontallyResizable = false; text.textContainerInset = .zero
        addSubview(text)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) { background.setFill(); dirtyRect.fill() }
    func setContent(_ content: NSAttributedString, anchor: Int) {
        self.anchor = max(0,anchor); storage.setAttributedString(content); pendingLayout = true; needsLayout = true
    }
    override func layout() {
        super.layout()
        let width = max(120,bounds.width - 88), height = max(120,bounds.height - 56)
        let size = NSSize(width: width, height: height)
        guard pendingLayout || abs(size.width-lastSize.width) > 1 || abs(size.height-lastSize.height) > 1 else { return }
        pendingLayout = false; lastSize = size
        for index in manager.textContainers.indices.reversed() { manager.removeTextContainer(at: index) }
        containers.removeAll(keepingCapacity: true)
        var covered = 0
        repeat {
            let container = NSTextContainer(containerSize: size); container.lineFragmentPadding = 0
            manager.addTextContainer(container); containers.append(container)
            manager.ensureLayout(for: container)
            let range = manager.glyphRange(for: container)
            let end = NSMaxRange(range)
            if end <= covered { break }; covered = end
        } while covered < manager.numberOfGlyphs && containers.count < 5000
        let desired = min(anchor, max(0, storage.length - 1))
        let glyph = storage.length > 0 ? manager.glyphIndexForCharacter(at: desired) : 0
        page = containers.firstIndex(where: { NSLocationInRange(glyph, manager.glyphRange(for: $0)) }) ?? max(0,containers.count-1)
        showPage()
    }
    private func showPage() {
        guard containers.indices.contains(page) else { return }
        text.replaceTextContainer(containers[page])
        text.frame = NSRect(x: 44, y: 28, width: lastSize.width, height: lastSize.height)
        let range = manager.characterRange(forGlyphRange: manager.glyphRange(for: containers[page]), actualGlyphRange: nil)
        anchor = range.location == NSNotFound ? 0 : range.location
        let currentPage = page, total = containers.count, start = anchor
        DispatchQueue.main.async { [weak self] in self?.onPage?(currentPage, total, start) }
        needsDisplay = true
    }
    @discardableResult func turn(_ delta: Int) -> Bool {
        let next = page + delta; guard containers.indices.contains(next) else { return false }
        page = next; showPage(); window?.makeFirstResponder(text); return true
    }
    func reveal(_ range: NSRange) {
        guard range.location < storage.length else { return }
        let glyph = manager.glyphIndexForCharacter(at: range.location)
        if let target = containers.firstIndex(where: { NSLocationInRange(glyph, manager.glyphRange(for: $0)) }) { page = target; showPage(); text.setSelectedRange(range) }
    }
}
struct EPUBPagedReader: NSViewRepresentable {
    @ObservedObject var state: ReaderState
    func makeCoordinator() -> EPUBReader.Coordinator { EPUBReader.Coordinator(state: state) }
    func makeNSView(context: Context) -> PagedTextHost {
        let host = PagedTextHost(frame: .zero); state.pagedView = host; state.textView = host.text
        host.text.delegate = context.coordinator
        host.text.pageTurn = { [weak state] delta in state?.advance(delta) }
        host.onPage = { [weak state] page, count, anchor in state?.pageLayoutChanged(page: page, count: count, anchor: anchor) }
        return host
    }
    func updateNSView(_ host: PagedTextHost, context: Context) {
        host.background = state.palette.backgroundNS
        let key = "\(state.position)-\(state.fontSize)-\(state.palette.rawValue)-\(state.notes.map(\.id))"
        if context.coordinator.key != key {
            context.coordinator.key = key; context.coordinator.updating = true
            host.setContent(state.highlightedChapter(), anchor: state.pageOffset)
            host.layoutSubtreeIfNeeded()
            context.coordinator.updating = false
        }
        if let quote = state.jumpToQuote, let range = AnnotationAnchor.range(quote: quote, anchor: state.jumpAnchor, in: state.chapterText.string) {
            host.reveal(range); DispatchQueue.main.async { state.jumpToQuote = nil }
        }
    }
}
