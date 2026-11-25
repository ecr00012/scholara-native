import SwiftUI
import PDFKit
import CoreServices
import ScholaraCore

@MainActor
final class ReaderState: ObservableObject {
    let book: Book
    let store: LibraryStore
    @Published var pdf: PDFDocument?
    @Published var epub: EPUBBook?
    @Published var chapterText = NSAttributedString(string: "")
    @Published var position: Int
    @Published var offset: Int
    @Published var selection = ""
    @Published var anchor = ""
    var selectionPosition: Int?
    var jumpAnchor = ""
    var pendingScrollAnchor: Int?
    var unchangedScrollAnchor: Int?
    @Published var pageText = ""
    @Published var notes: [Note] = []
    @Published var words: [Vocabulary] = []
    @Published var error: String?
    @Published var loading = true
    @Published var noteDraft = ""
    @Published var tab = "Scholar"
    @Published var jumpToQuote: String?
    @Published var definition = ""
    @Published var word = ""
    @Published var showDefinition = false
    @Published var fontSize: CGFloat = 19
    @Published var readingMode: String
    @Published var visiblePage = 0
    @Published var visiblePageCount = 1
    @Published var pageOffset: Int
    @Published var palette = ReadingPalette.current
    @Published var definitionSaved = false
    weak var pagedView: PagedTextHost?
    @Published var find = ""
    weak var pdfView: PDFView?
    weak var textView: NSTextView?
    private var saveTask: Task<Void, Never>?
    private var chapterTask: Task<Void, Never>?
    var count: Int { pdf?.pageCount ?? epub?.chapters.count ?? 0 }
    var positionLabel: String {
        let section = "\(book.format == "pdf" ? "Page" : "Section") \(position + 1) of \(count)"
        return readingMode == "pages" && book.format == "epub" ? section + " · Page \(visiblePage + 1) of \(visiblePageCount)" : section
    }
    init(book: Book, store: LibraryStore) { self.book = book; self.store = store; position = book.position; offset = book.offset; readingMode = book.readingMode; pageOffset = book.pageOffset }
    func load(fontSize: Double) async {
        self.fontSize = fontSize
        do {
            if book.format == "pdf" {
                let path = book.path
                guard let pdf = await Task.detached(priority: .userInitiated, operation: { PDFDocument(url: URL(fileURLWithPath: path)) }).value else { throw ScholaraError("The PDF could not be opened.") }
                self.pdf = pdf; position = min(max(0, position), max(0, pdf.pageCount - 1)); pageText = pdf.page(at: position)?.string ?? ""
            } else {
                let book = book
                epub = try await Task.detached(priority: .userInitiated) { try BookImporter.epub(book) }.value
                position = min(max(0, position), max(0, count - 1)); try loadChapter()
            }
            reloadStudy(); loading = false
        } catch { self.error = error.localizedDescription; loading = false }
    }
    func reloadStudy() { do { notes = try store.notes(bookID: book.id); words = try store.vocabulary(bookID: book.id) } catch { self.error = error.localizedDescription } }
    func loadChapter() throws {
        guard let epub else { return }
        let text = NSMutableAttributedString(attributedString: try epub.attributedChapter(position, fontSize: fontSize))
        text.addAttribute(.foregroundColor, value: palette.inkNS, range: NSRange(location: 0, length: text.length))
        chapterText = text; pageText = text.string
    }
    func go(_ target: Int, offset: Int = 0, pageOffset: Int = 0) {
        guard count > 0 else { return }
        let target = min(max(0, target), count - 1)
        if target != position { selection = ""; anchor = ""; selectionPosition = nil; find = "" }
        position = target; self.offset = offset; self.pageOffset = pageOffset
        if let pdf, let page = pdf.page(at: target) { pdfView?.go(to: page); pageText = page.string ?? "" }
        else { do { try loadChapter() } catch { self.error = error.localizedDescription } }
        saveSoon()
    }
    func advance(_ delta: Int) {
        if readingMode == "pages", epub != nil {
            if pagedView?.turn(delta) == true { return }
            let next = position + delta
            guard next >= 0, next < count else { return }
            go(next, pageOffset: delta < 0 ? Int.max : 0)
        } else { go(position + delta) }
    }
    func changeReadingMode(_ mode: String) {
        guard mode != readingMode else { return }
        if epub != nil {
            if mode == "pages", let anchor = unchangedScrollAnchor { pageOffset = anchor; unchangedScrollAnchor = nil }
            else if mode == "pages", let view = textView, let manager = view.layoutManager, let container = view.textContainer {
                let origin = view.visibleRect.origin
                let point = NSPoint(x: max(0, origin.x - view.textContainerInset.width), y: max(0, origin.y - view.textContainerInset.height))
                let glyph = manager.glyphIndex(for: point, in: container)
                pageOffset = manager.numberOfGlyphs > 0 ? manager.characterIndexForGlyph(at: min(glyph,manager.numberOfGlyphs-1)) : 0
            } else { pendingScrollAnchor = pageOffset; unchangedScrollAnchor = pageOffset }
        }
        readingMode = mode
        do { try store.saveReadingMode(book.id, mode: mode) } catch { self.error = error.localizedDescription }
    }
    func pageLayoutChanged(page: Int, count: Int, anchor: Int) {
        if visiblePage != page { visiblePage = page }
        if visiblePageCount != count { visiblePageCount = count }
        if pageOffset != anchor { pageOffset = anchor; saveSoon() }
    }
    func highlightedChapter() -> NSAttributedString {
        let text = NSMutableAttributedString(attributedString: chapterText)
        for note in notes where note.position == position && !note.quote.isEmpty {
            if let range = AnnotationAnchor.range(quote: note.quote, anchor: note.anchor, in: text.string) { text.addAttribute(.backgroundColor, value: NSColor(hex: 0xC8702C).withAlphaComponent(0.16), range: range) }
        }
        return text
    }
    func pageChanged(_ index: Int) {
        guard index != position else { return }; position = index; offset = 0; pageText = pdf?.page(at: index)?.string ?? ""; saveSoon()
    }
    func scrollChanged(_ offset: Int) { if self.offset != offset { unchangedScrollAnchor = nil; self.offset = offset; saveSoon() } }
    func saveSoon() {
        saveTask?.cancel(); saveTask = Task { try? await Task.sleep(for: .milliseconds(350)); guard !Task.isCancelled else { return }; flush() }
    }
    func flush() { do { try store.savePosition(book.id, position: position, offset: offset); try store.savePageOffset(book.id, offset: pageOffset == Int.max ? 0 : pageOffset) } catch { self.error = error.localizedDescription } }
    func saveNote(highlightOnly: Bool = false) {
        do {
            try store.addNote(bookID: book.id, position: selection.isEmpty ? position : (selectionPosition ?? position), quote: selection, text: highlightOnly ? "" : noteDraft, anchor: anchor)
            noteDraft = ""; reloadStudy(); tab = "Notes"
        } catch { self.error = error.localizedDescription }
    }
    func show(_ note: Note) { go(note.position); jumpAnchor = note.anchor; jumpToQuote = note.quote }
    func lookup() {
        word = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }; definitionSaved = false
        if let existing = words.first(where: { $0.word.caseInsensitiveCompare(word) == .orderedSame }) {
            definition = existing.definition; definitionSaved = true; showDefinition = true; return
        }
        let range = CFRange(location: 0, length: (word as NSString).length)
        if let value = DCSCopyTextDefinition(nil, word as CFString, range)?.takeRetainedValue() {
            definition = DictionaryEntry.parse(value as String, word: word).stored
            saveDefinition(dismiss: false)
        } else { definition = DictionaryEntry(word: word, senses: [DictionarySense(gloss: "No offline dictionary entry was found. Choose Edit Definition to add your own.")]).stored }
        showDefinition = true
    }
    func saveDefinition(dismiss: Bool = true) {
        do { try store.saveWord(bookID: book.id, word: word, definition: definition); definitionSaved = true; if dismiss { showDefinition = false }; reloadStudy() } catch { self.error = error.localizedDescription }
    }
    func findNext() {
        guard !find.isEmpty else { return }
        if let pdf {
            let next = pdf.findString(find, fromSelection: pdfView?.currentSelection, withOptions: .caseInsensitive)
                ?? pdf.findString(find, fromSelection: nil, withOptions: .caseInsensitive)
            guard let next else { return }
            pdfView?.setCurrentSelection(next, animate: true); pdfView?.scrollSelectionToVisible(nil)
        } else if let textView {
            let text = textView.string as NSString
            let start = NSMaxRange(textView.selectedRange())
            var range = text.range(of: find, options: .caseInsensitive, range: NSRange(location: min(start,text.length), length: max(0,text.length-start)))
            if range.location == NSNotFound { range = text.range(of: find, options: .caseInsensitive) }
            if range.location != NSNotFound { if readingMode == "pages" { pagedView?.reveal(range) } else { textView.setSelectedRange(range); textView.scrollRangeToVisible(range) } }
        }
    }
}

struct PDFReader: NSViewRepresentable {
    @ObservedObject var state: ReaderState
    func makeCoordinator() -> Coordinator { Coordinator(state: state) }
    func makeNSView(context: Context) -> PDFView {
        let view = ReaderPDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous; view.displayDirection = .vertical; view.displaysPageBreaks = true; view.backgroundColor = state.palette.backgroundNS
        view.document = state.pdf; state.pdfView = view
        if let page = state.pdf?.page(at: state.position) { view.go(to: page) }
        context.coordinator.observe(view); return view
    }
    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== state.pdf { view.document = state.pdf }
        let mode: PDFDisplayMode = state.readingMode == "pages" ? .singlePage : .singlePageContinuous
        if view.displayMode != mode { view.displayMode = mode; if let page = state.pdf?.page(at: state.position) { view.go(to: page) }; view.autoScales = true }
        view.backgroundColor = state.palette.backgroundNS
        (view as? ReaderPDFView)?.pageTurn = state.readingMode == "pages" ? { delta in state.advance(delta) } : nil
        context.coordinator.highlights(view)
        if let quote = state.jumpToQuote, !quote.isEmpty, let page = state.pdf?.page(at: state.position), let text = page.string as NSString? {
            let range = text.range(of: quote)
            if range.location != NSNotFound, let selection = page.selection(for: range) { view.setCurrentSelection(selection, animate: true); view.scrollSelectionToVisible(nil) }
            DispatchQueue.main.async { state.jumpToQuote = nil }
        }
    }
    @MainActor final class Coordinator: NSObject {
        let state: ReaderState
        var tokens: [NSObjectProtocol] = []
        var noteKey = ""
        init(state: ReaderState) { self.state = state }
        deinit { tokens.forEach(NotificationCenter.default.removeObserver) }
        @MainActor func observe(_ view: PDFView) {
            tokens.append(NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak self, weak view] _ in
                MainActor.assumeIsolated { guard let self, let view, let page = view.currentPage, let doc = view.document else { return }; self.state.pageChanged(doc.index(for: page)) }
            })
            tokens.append(NotificationCenter.default.addObserver(forName: .PDFViewSelectionChanged, object: view, queue: .main) { [weak self, weak view] _ in
                MainActor.assumeIsolated {
                    guard let self, let view else { return }
                    guard let selection = view.currentSelection, let doc = view.document else {
                        self.state.selection = ""; self.state.anchor = ""; self.state.selectionPosition = nil; return
                    }
                    self.state.selection = selection.string ?? ""
                    self.state.selectionPosition = selection.pages.first.map { doc.index(for: $0) }
                    let rects = selection.selectionsByLine().flatMap { line in line.pages.map { page -> [String: Any] in
                        let bounds = line.bounds(for: page); return ["page": doc.index(for: page), "x": bounds.minX, "y": bounds.minY, "width": bounds.width, "height": bounds.height]
                    } }
                    if let data = try? JSONSerialization.data(withJSONObject: ["pdfRects": rects]) { self.state.anchor = String(decoding: data, as: UTF8.self) }
                }
            })
        }
        @MainActor func highlights(_ view: PDFView) {
            let key = state.notes.map { "\($0.id):\($0.text):\($0.quote)" }.joined(separator: "|"); guard key != noteKey, let doc = view.document else { return }; noteKey = key
            for index in 0..<doc.pageCount {
                guard let page = doc.page(at: index) else { continue }
                page.annotations.filter { $0.userName == "ScholaraNative" }.forEach(page.removeAnnotation)
            }
            for note in state.notes where !note.quote.isEmpty {
                let data = (try? JSONSerialization.jsonObject(with: Data(note.anchor.utf8))) as? [String: Any]
                if let rects = data?["pdfRects"] as? [[String: Any]] {
                    for rect in rects {
                        guard let index = rect["page"] as? Int, let page = doc.page(at: index), let x = rect["x"] as? Double, let y = rect["y"] as? Double, let width = rect["width"] as? Double, let height = rect["height"] as? Double else { continue }
                        add(on: page, bounds: NSRect(x: x, y: y, width: width, height: height), text: note.text)
                    }
                } else if let pages = data?["pages"] as? [[String: Any]] {
                    for item in pages {
                        guard let number = item["page"] as? Int, let page = doc.page(at: max(0, number - 1)), let rects = item["rects"] as? [[String: Double]] else { continue }
                        for rect in rects {
                            guard let x = rect["x"], let y = rect["y"], let w = rect["w"], let h = rect["h"] else { continue }
                            add(on: page, bounds: NSRect(x: x, y: y, width: w, height: h), text: note.text)
                        }
                    }
                } else if let page = doc.page(at: note.position), let text = page.string as NSString? {
                    let range = text.range(of: note.quote)
                    if range.location != NSNotFound, let selection = page.selection(for: range) { for line in selection.selectionsByLine() { add(on: page, bounds: line.bounds(for: page), text: note.text) } }
                }
            }
        }
        func add(on page: PDFPage, bounds: NSRect, text: String) { let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil); annotation.color = .systemOrange.withAlphaComponent(0.3); annotation.userName = "ScholaraNative"; annotation.contents = text; page.addAnnotation(annotation) }
    }
}

final class ReaderScrollView: NSScrollView {
    var afterLayout: ((ReaderScrollView) -> Void)?
    override func layout() { super.layout(); afterLayout?(self) }
}
struct EPUBReader: NSViewRepresentable {
    @ObservedObject var state: ReaderState
    func makeCoordinator() -> Coordinator { Coordinator(state: state) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = ReaderScrollView(); scroll.afterLayout = { [weak coordinator = context.coordinator] scroll in coordinator?.layout(scroll) }; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = true; scroll.backgroundColor = state.palette.backgroundNS
        let text = ReaderTextView(frame: .zero); text.isEditable = false; text.isSelectable = true; text.isRichText = true; text.usesFindBar = true; text.isVerticallyResizable = true; text.isHorizontallyResizable = false; text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true; text.textContainerInset = NSSize(width: 44, height: 34); text.delegate = context.coordinator
        text.minSize = NSSize(width: 0, height: 0); text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = text; state.textView = text
        scroll.contentView.postsBoundsChangedNotifications = true
        context.coordinator.observe(scroll); return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? NSTextView else { return }
        scroll.backgroundColor = state.palette.backgroundNS; text.backgroundColor = state.palette.backgroundNS
        let key = "\(state.position)-\(state.fontSize)-\(state.palette.rawValue)-\(state.notes.map(\.id))"
        if context.coordinator.key != key {
            let changedChapter = context.coordinator.position != state.position
            context.coordinator.key = key; context.coordinator.position = state.position; context.coordinator.updating = true
            let attributed = NSMutableAttributedString(attributedString: state.chapterText)
            for note in state.notes where note.position == state.position && !note.quote.isEmpty {
                if let range = AnnotationAnchor.range(quote: note.quote, anchor: note.anchor, in: attributed.string) {
                    attributed.addAttribute(.backgroundColor, value: NSColor.systemOrange.withAlphaComponent(0.18), range: range)
                }
            }
            text.textStorage?.setAttributedString(attributed)
            if changedChapter || !context.coordinator.restored || state.pendingScrollAnchor != nil {
                context.coordinator.restoreOffset = state.offset
                context.coordinator.restoreAnchor = state.pendingScrollAnchor
                context.coordinator.needsRestore = true
                state.pendingScrollAnchor = nil
            }
            context.coordinator.updating = false
            scroll.needsLayout = true
        }
        if let quote = state.jumpToQuote, !quote.isEmpty {
            if let range = AnnotationAnchor.range(quote: quote, anchor: state.jumpAnchor, in: text.string) { text.setSelectedRange(range); text.scrollRangeToVisible(range) }
            DispatchQueue.main.async { state.jumpToQuote = nil }
        }
    }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        let state: ReaderState
        var key = ""; var position = -1; var restored = false; var updating = false
        var observer: NSObjectProtocol?
        var needsRestore = false; var restoreOffset = 0; var restoreAnchor: Int?
        private var layingOut = false
        func layout(_ scroll: NSScrollView) {
            guard !layingOut, scroll.contentSize.width > 200, let text = scroll.documentView as? NSTextView,
                  let manager = text.layoutManager, let container = text.textContainer else { return }
            layingOut = true; updating = true
            defer { layingOut = false; updating = false }
            text.setFrameSize(NSSize(width: scroll.contentSize.width, height: text.frame.height))
            container.containerSize = NSSize(width: max(120, scroll.contentSize.width - 2 * text.textContainerInset.width), height: .greatestFiniteMagnitude)
            manager.ensureLayout(for: container)
            text.setFrameSize(NSSize(width: scroll.contentSize.width, height: max(scroll.contentSize.height, manager.usedRect(for: container).height + 2 * text.textContainerInset.height)))
            if needsRestore {
                var y = CGFloat(restoreOffset)
                if let anchor = restoreAnchor, text.string.utf16.count > 0 {
                    let glyph = manager.glyphIndexForCharacter(at: min(anchor,text.string.utf16.count-1))
                    y = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY + text.textContainerInset.height
                }
                needsRestore = false; restored = true
                scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0,min(y,text.frame.height-scroll.contentSize.height))))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        }
        init(state: ReaderState) { self.state = state }
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
        @MainActor func observe(_ scroll: NSScrollView) {
            observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak self, weak scroll] _ in
                MainActor.assumeIsolated { guard let self, !self.updating, let scroll else { return }; self.state.scrollChanged(Int(scroll.contentView.bounds.origin.y)) }
            }
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard !updating, let view = notification.object as? NSTextView else { return }
            let range = view.selectedRange(); guard range.location != NSNotFound, NSMaxRange(range) <= (view.string as NSString).length else { return }
            state.selection = (view.string as NSString).substring(with: range)
            state.selectionPosition = state.position
            state.anchor = "{\"location\":\(range.location),\"length\":\(range.length)}"
        }
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = link as? URL else { return false }
            if url.isFileURL, let index = state.epub?.chapters.firstIndex(where: { $0.path == url.path }) { state.go(index); return true }
            if ["https", "http", "mailto"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
            return true
        }
    }
}
