import SwiftUI
import PDFKit
import ScholaraCore

struct ReaderView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.readingPalette) private var palette
    let book: Book
    @StateObject private var state: ReaderState
    @State private var showContents = false
    @State private var showScholar = false
    @State private var pageEntry = ""
    @AppStorage("readerFontSize") private var fontSize = 19.0
    init(book: Book, store: LibraryStore) { self.book = book; _state = StateObject(wrappedValue: ReaderState(book: book, store: store)) }
    var readerOnly: Bool { model.activeBook?.readerOnly ?? book.readerOnly }
    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Button { showContents.toggle() } label: { Image(systemName: "list.bullet") }.help("Table of contents")
                        .popover(isPresented: $showContents) { contents.frame(width: 320, height: 420) }
                    Text(state.positionLabel).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    TextField("Find in \(book.format == "pdf" ? "book" : "chapter")", text: $state.find).textFieldStyle(.roundedBorder).frame(maxWidth: 200).onSubmit { state.findNext() }
                    Button { state.findNext() } label: { Image(systemName: "magnifyingglass") }.help("Find next match")
                    if book.format == "pdf" {
                        Button { state.pdfView?.zoomOut(nil) } label: { Image(systemName: "minus.magnifyingglass") }
                        Button { state.pdfView?.zoomIn(nil) } label: { Image(systemName: "plus.magnifyingglass") }
                    }
                    Button { state.advance(-1) } label: { Image(systemName: "chevron.left") }.disabled(state.position <= 0 && (state.readingMode != "pages" || state.visiblePage <= 0)).help("Previous page or chapter")
                    Button { state.advance(1) } label: { Image(systemName: "chevron.right") }.disabled(state.position >= state.count - 1 && (state.readingMode != "pages" || state.visiblePage >= state.visiblePageCount - 1)).help("Next page or chapter")
                }.padding(.horizontal, 16).padding(.vertical, 10).background(palette.surface)
                if state.loading { ProgressView("Opening book…").frame(maxWidth: .infinity, maxHeight: .infinity) }
                else if let error = state.error, state.pdf == nil && state.epub == nil { ContentUnavailableView("Could not open book", systemImage: "exclamationmark.triangle", description: Text(error)) }
                else if book.format == "pdf" { PDFReader(state: state) }
                else if state.readingMode == "pages" { EPUBPagedReader(state: state) }
                else { EPUBReader(state: state) }
                if !state.selection.isEmpty {
                    HStack(spacing: 14) {
                        Text(state.selection).lineLimit(1).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Highlight", systemImage: "highlighter") { state.saveNote(highlightOnly: true) }
                        Button("Add Note", systemImage: "square.and.pencil") { state.tab = "Notes"; if readerOnly { model.toggleReaderMode() } }
                        Button("Define", systemImage: "character.book.closed") { state.lookup() }.disabled(state.selection.count > 150)
                    }.padding(12).background(palette.surface)
                }
                if readerOnly {
                    HStack { Spacer(); Button { showScholar.toggle() } label: { Label("Ask Agent Scholar", systemImage: "sparkles") }.buttonStyle(.borderedProminent).popover(isPresented: $showScholar) { ChatView(state: state).environmentObject(model).frame(width: 420, height: 580) }; Spacer() }.padding(10).background(palette.surface)
                }
            }.frame(minWidth: 480)
            if !readerOnly {
                VStack(spacing: 0) {
                    HStack(spacing: 4) {
                        ForEach(["Scholar", "Notes", "Dictionary"], id: \.self) { tab in
                            Button { state.tab = tab } label: {
                                Text(tab).font(.system(size: 14, weight: state.tab == tab ? .medium : .regular))
                                    .foregroundStyle(state.tab == tab ? palette.ink : palette.muted)
                                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                                    .background(state.tab == tab ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 19))
                                    .shadow(color: .black.opacity(state.tab == tab ? 0.04 : 0), radius: 3, y: 2)
                            }.buttonStyle(.plain).accessibilityAddTraits(state.tab == tab ? [.isSelected] : [])
                        }
                    }.padding(5).background(palette.card, in: RoundedRectangle(cornerRadius: 24))
                        .overlay { RoundedRectangle(cornerRadius: 24).stroke(palette.outline, lineWidth: 1) }.padding(12)
                    if state.tab == "Scholar" { ChatView(state: state) }
                    else if state.tab == "Notes" { NotesPanel(state: state) }
                    else { WordsPanel(state: state) }
                }.frame(minWidth: 300, idealWidth: 360, maxWidth: 500)
            }
        }
        .navigationTitle(book.title).navigationSubtitle(book.author)
        .toolbar {
            Button { state.flush(); model.activeBookID = nil; model.refresh() } label: { Label("Library", systemImage: "books.vertical") }
            Picker("Reading layout", selection: Binding(get: { state.readingMode }, set: { state.changeReadingMode($0) })) {
                Text("Scroll").tag("scroll")
                Text("Pages").tag("pages")
            }.pickerStyle(.segmented).frame(width: 170).help("Scroll through the book, or turn one page at a time")
            Button { model.toggleReaderMode() } label: { Label(readerOnly ? "Show Study Panel" : "Focus on Reading", systemImage: "sidebar.right") }
            Menu { BookMenu(book: model.activeBook ?? book); if book.format == "pdf" { Divider(); Button("Print…") { state.pdfView?.print(with: NSPrintInfo.shared, autoRotate: true) } } } label: { Image(systemName: "ellipsis.circle") }
        }
        .background(palette.background)
        .task { state.palette = palette; await state.load(fontSize: fontSize) }
        .onChange(of: palette) { _, palette in state.palette = palette; do { try state.loadChapter() } catch { state.error = error.localizedDescription } }
        .onChange(of: fontSize) { _, size in state.fontSize = size; do { try state.loadChapter() } catch { state.error = error.localizedDescription } }
        .onDisappear { state.flush() }
        .overlay(alignment: .top) {
            if state.showDefinition {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.06).onTapGesture { state.showDefinition = false }
                    DefinitionCard(state: state).padding(28).transition(.move(edge: .top).combined(with: .opacity))
                }.animation(.easeOut(duration: 0.18), value: state.showDefinition)
            }
        }
        .alert("Reader", isPresented: Binding(get: { state.error != nil && !state.loading && (state.pdf != nil || state.epub != nil) }, set: { if !$0 { state.error = nil } })) { Button("OK") { state.error = nil } } message: { Text(state.error ?? "") }
    }
    var contents: some View {
        VStack(alignment: .leading) {
            Text("Contents").font(.headline).padding()
            HStack { TextField("Page or chapter", text: $pageEntry).onSubmit { jump() }; Button("Go") { jump() } }.padding(.horizontal)
            List {
                if let epub = state.epub { ForEach(epub.chapters) { chapter in Button("\(chapter.id + 1). \(chapter.title)") { state.go(chapter.id); showContents = false }.buttonStyle(.plain) } }
                else if let outline = state.pdf?.outlineRoot { PDFOutlineRows(outline: outline, state: state, dismiss: { showContents = false }) }
                else { Text("Use the page field to jump to a page.").foregroundStyle(.secondary) }
            }
        }
    }
    func jump() { if let page = Int(pageEntry) { state.go(page - 1); showContents = false } }
}
struct PDFOutlineRows: View {
    let outline: PDFOutline
    @ObservedObject var state: ReaderState
    let dismiss: () -> Void
    var body: some View {
        ForEach(0..<outline.numberOfChildren, id: \.self) { index in
            if let child = outline.child(at: index) {
                Button(child.label ?? "Section") { if let page = child.destination?.page, let doc = state.pdf { state.go(doc.index(for: page)); dismiss() } }.buttonStyle(.plain)
                if child.numberOfChildren > 0 { DisclosureGroup("Sections") { PDFOutlineRows(outline: child, state: state, dismiss: dismiss) } }
            }
        }
    }
}
struct NotesPanel: View {
    @Environment(\.readingPalette) private var palette
    @ObservedObject var state: ReaderState
    @State private var editing: Note?
    @State private var editText = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !state.selection.isEmpty { Text(state.selection).font(.system(.callout, design: .serif)).foregroundStyle(.secondary).lineLimit(4).padding(.horizontal) }
            TextEditor(text: $state.noteDraft).frame(height: 85).padding(.horizontal).overlay(alignment: .topLeading) { if state.noteDraft.isEmpty { Text("Write a note about this passage…").font(.callout).foregroundStyle(.tertiary).padding(.leading, 22).padding(.top, 6).allowsHitTesting(false) } }
            HStack { Text(state.positionLabel).font(.caption).foregroundStyle(.secondary); Spacer(); Button("Save Note") { state.saveNote() }.disabled((state.selection + state.noteDraft).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }.padding(.horizontal)
            Divider()
            List(state.notes) { note in
                VStack(alignment: .leading, spacing: 8) {
                    if !note.quote.isEmpty { Text(note.quote).font(.system(.callout, design: .serif)).foregroundStyle(.secondary).lineLimit(8) }
                    if !note.text.isEmpty { Text(note.text) }
                    Button("\(state.book.format == "pdf" ? "Page" : "Section") \(note.position + 1)") { state.show(note) }.buttonStyle(.link).font(.caption)
                }.padding(.vertical, 6).textSelection(.enabled).contextMenu {
                    Button("Edit Note…") { editing = note; editText = note.text }
                    Button("Delete", role: .destructive) { do { try state.store.deleteNote(note.id); state.reloadStudy() } catch { state.error = error.localizedDescription } }
                }
            }.overlay { if state.notes.isEmpty { ContentUnavailableView("Keep a thought", systemImage: "note.text", description: Text("Select a passage to highlight it, or write a note above.")) } }
        }.sheet(item: $editing) { note in VStack { Text("Edit Note").font(.headline); TextEditor(text: $editText).frame(height: 180); HStack { Button("Cancel") { editing = nil }; Spacer(); Button("Save") { do { try state.store.editNote(note.id, text: editText); state.reloadStudy(); editing = nil } catch { state.error = error.localizedDescription } } } }.padding(24).frame(width: 420) }
    }
}
struct WordsPanel: View {
    @Environment(\.readingPalette) private var palette
    @ObservedObject var state: ReaderState
    @State private var expanded: Set<Int64> = []
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(state.words) { word in
                    let entry = DictionaryEntry.parse(word.definition, word: word.word)
                    VStack(alignment: .leading, spacing: 10) {
                        DefinitionContent(entry: entry, compact: true).frame(maxHeight: expanded.contains(word.id) ? nil : 240, alignment: .top).clipped()
                        HStack { Button(expanded.contains(word.id) ? "Show less" : "Show more") { if expanded.contains(word.id) { expanded.remove(word.id) } else { expanded.insert(word.id) } }.buttonStyle(.plain).font(.caption).foregroundStyle(palette.accent); Spacer(); Button { do { try state.store.deleteWord(word.id); state.reloadStudy() } catch { state.error = error.localizedDescription } } label: { Image(systemName: "trash").font(.caption) }.buttonStyle(.plain).foregroundStyle(palette.muted).accessibilityLabel("Delete \(word.word)") }
                    }.padding(16).background(palette.card, in: RoundedRectangle(cornerRadius: 18)).overlay { RoundedRectangle(cornerRadius: 18).stroke(palette.outline, lineWidth: 1) }
                }
            }.padding(12)
        }.overlay { if state.words.isEmpty { ContentUnavailableView("Words worth keeping", systemImage: "character.book.closed", description: Text("Select a word in the book and choose Define. Definitions use your Mac’s offline dictionary.")) } }
    }
}
