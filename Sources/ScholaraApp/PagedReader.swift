import AppKit
import PDFKit
import SwiftUI
import ScholaraCore

final class ReaderTextView: NSTextView {
    var focusOnAttach = false
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard focusOnAttach, window != nil else { return }
        focusOnAttach = false
        DispatchQueue.main.async { [weak self] in
            guard let self, self.superview != nil else { return }
            self.window?.makeFirstResponder(self)
        }
    }
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
    var focusOnAttach = false
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard focusOnAttach, window != nil else { return }
        focusOnAttach = false
        DispatchQueue.main.async { [weak self] in
            guard let self, self.superview != nil else { return }
            self.window?.makeFirstResponder(self)
        }
    }
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
    private var pagination: TextPagination?
    private var content = NSAttributedString(string: "")
    private var containers: [NSTextContainer] { pagination?.containers ?? [] }
    private(set) var text = ReaderTextView(frame: .zero)
    var configureText: ((ReaderTextView) -> Void)?
    private var page = 0
    private var anchor = 0
    private var lastSize = NSSize.zero
    private var pendingLayout = true
    private var retainReaderFocus = false
    private var revision = 0
    private var needsInitialFocus = true
    var onPage: ((Int, Int, Int, NSSize) -> Void)?
    var background: NSColor = .white { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        clipsToBounds = true
        text.isEditable = false; text.isSelectable = true; text.isRichText = true; text.drawsBackground = false
        text.isVerticallyResizable = false; text.isHorizontallyResizable = false; text.textContainerInset = .zero
        addSubview(text)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) { background.setFill(); dirtyRect.intersection(bounds).fill() }
    func setContent(_ content: NSAttributedString, anchor: Int) {
        retainReaderFocus = retainReaderFocus || window?.firstResponder === text
        revision += 1
        self.anchor = max(0,anchor); self.content = content; pendingLayout = true; needsLayout = true
    }
    override func layout() {
        super.layout()
        let width = max(120,bounds.width - 88), height = max(120,bounds.height - 56)
        let size = NSSize(width: width, height: height)
        guard pendingLayout || abs(size.width-lastSize.width) > 1 || abs(size.height-lastSize.height) > 1 else { return }
        pendingLayout = false; lastSize = size
        pagination = TextPagination(content: content, size: size)
        page = pagination?.page(containing: anchor) ?? 0
        showPage()
    }
    private func showPage() {
        guard containers.indices.contains(page) else { return }
        let initialFocus = needsInitialFocus || text.focusOnAttach
        let restoreFocus = retainReaderFocus || window?.firstResponder === text
        retainReaderFocus = false
        text.delegate = nil; text.removeFromSuperview(); text.textContainer?.textView = nil
        text = ReaderTextView(frame: NSRect(x: 44, y: 28, width: lastSize.width, height: lastSize.height), textContainer: containers[page])
        text.isEditable = false; text.isSelectable = true; text.isRichText = true; text.drawsBackground = false
        text.isVerticallyResizable = false; text.isHorizontallyResizable = false; text.textContainerInset = .zero
        containers[page].widthTracksTextView = false; containers[page].heightTracksTextView = false
        text.focusOnAttach = initialFocus; needsInitialFocus = false
        configureText?(text); addSubview(text)
        if restoreFocus { window?.makeFirstResponder(text) }
        let range = pagination!.ranges[page]
        anchor = range.location == NSNotFound ? 0 : range.location
        revision += 1
        let currentPage = page, total = containers.count, start = anchor, token = revision, size = lastSize
        DispatchQueue.main.async { [weak self] in
            guard let self, self.revision == token else { return }
            self.onPage?(currentPage, total, start, size)
        }
        needsDisplay = true
    }
    @discardableResult func turn(_ delta: Int) -> Bool {
        let next = page + delta; guard containers.indices.contains(next) else { return false }
        page = next; showPage(); window?.makeFirstResponder(text); return true
    }
    func reveal(_ range: NSRange) {
        guard range.location < content.length, let pagination else { return }
        page = pagination.page(containing: range.location); showPage(); text.setSelectedRange(range)
    }
}
struct EPUBPagedReader: NSViewRepresentable {
    @ObservedObject var state: ReaderState
    func makeCoordinator() -> EPUBReader.Coordinator { EPUBReader.Coordinator(state: state) }
    func makeNSView(context: Context) -> PagedTextHost {
        let host = PagedTextHost(frame: .zero); state.pagedView = host; state.textView = host.text
        host.configureText = { [weak state, weak coordinator = context.coordinator] text in
            text.delegate = coordinator; state?.textView = text
            text.pageTurn = { [weak state] delta in state?.advance(delta) }
        }
        host.onPage = { [weak state] page, count, anchor, size in
            state?.pageLayoutChanged(page: page, count: count, anchor: anchor)
            state?.updatePagination(size: size)
        }
        return host
    }
    func updateNSView(_ host: PagedTextHost, context: Context) {
        host.background = state.palette.backgroundNS
        let key = "\(state.position)-\(state.fontSize)-\(state.fontFamily.rawValue)-\(state.palette.rawValue)-\(state.notes.map(\.id))"
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
