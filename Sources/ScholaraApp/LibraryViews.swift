import SwiftUI
import ScholaraCore

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.readingPalette) private var palette
    @State private var search = ""
    private enum Destination: Hashable { case section(AppModel.Section), book(Int64) }
    private var destination: Binding<Destination?> {
        Binding(get: { model.activeBookID.map(Destination.book) ?? .section(model.section) }, set: { destination in
            switch destination {
            case .book(let id): if let book = model.books.first(where: { $0.id == id }) { model.open(book) }
            case .section(let section): model.activeBookID = nil; model.section = section
            case nil: break
            }
        })
    }
    var body: some View {
        NavigationSplitView {
            List(selection: destination) {
                Section("Scholara") {
                    ForEach(AppModel.Section.allCases) { section in Label(section.rawValue, systemImage: section.icon).tag(Destination.section(section)) }
                }
                if !model.books.isEmpty {
                    Section("Continue reading") {
                        ForEach(model.books.prefix(8)) { book in
                            Label(book.title, systemImage: book.format == "pdf" ? "doc.richtext" : "book.closed")
                                .lineLimit(2).padding(.vertical, 3).tag(Destination.book(book.id))
                        }
                    }
                }
            }
            .listStyle(.sidebar).scrollContentBackground(.hidden).background(palette.surface)
            .navigationSplitViewColumnWidth(min: 190, ideal: 230, max: 300)
            .safeAreaInset(edge: .bottom) {
                HStack { SettingsLink { Label("Settings", systemImage: "gearshape") }; Spacer(); Text(model.books.count == 1 ? "1 book" : "\(model.books.count) books").foregroundStyle(.secondary).font(.caption) }.padding()
            }
        } detail: {
            Group {
                if model.section == .library, let book = model.activeBook, let store = model.store { ReaderView(book: book, store: store).id(book.id) }
                else {
                    switch model.section {
                    case .library: LibraryView(search: $search)
                    case .discover: DiscoveryView()
                    case .notes: CollectionView(vocabulary: false)
                    case .vocabulary: CollectionView(vocabulary: true)
                    }
                }
            }
            .background(palette.background)
        }
        .tint(palette.accent)
        .onChange(of: model.section) { _, newValue in if newValue != .library { model.activeBookID = nil } }
        .alert("Scholara", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
        .alert("Library update", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) { Button("OK") { model.notice = nil } } message: { Text(model.notice ?? "") }
        .sheet(isPresented: $model.showConsent) {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "sparkles.rectangle.stack").font(.system(size: 40)).foregroundStyle(.orange)
                Text("Enable Agent Scholar?").font(.title2.bold())
                Text("Embed \(model.pendingConsent.count == 1 ? model.pendingConsent[0].title : "these \(model.pendingConsent.count) books") on this Mac so Agent Scholar can find and discuss relevant passages.")
                Text("Embedding uses local processing and can take a few minutes. Book text stays on your Mac. When you send a chat message, relevant passages and your message are sent to OpenRouter.").foregroundStyle(.secondary)
                Text("You can read immediately and embed later from each book’s three-dot menu.").font(.callout)
                HStack { Button("Not Now") { model.consent(false) }.keyboardShortcut(.cancelAction); Spacer(); Button("Embed & Enable") { model.consent(true) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
            }.padding(30).frame(width: 480).interactiveDismissDisabled()
        }
        .confirmationDialog("Delete \(model.deleting?.title ?? "book")?", isPresented: Binding(get: { model.deleting != nil }, set: { if !$0 { model.deleting = nil } }), titleVisibility: .visible) {
            Button("Delete Book and Study Data", role: .destructive) { if let book = model.deleting { model.deleteBook(book) }; model.deleting = nil }
        } message: { Text("This removes the native library’s copy, notes, vocabulary, conversations, and embeddings. Your original file is kept.") }
        .sheet(item: $model.editing) { book in MetadataEditor(book: book) }
    }
}
struct LibraryView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.readingPalette) private var palette
    @Binding var search: String
    @State private var sort = "Recent"
    var filtered: [Book] {
        let books = model.books.filter { search.isEmpty || ($0.title + $0.author).localizedCaseInsensitiveContains(search) }
        return sort == "Title" ? books.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending } : books
    }
    var body: some View {
        Group {
            if model.books.isEmpty {
                ContentUnavailableView {
                    Label("Your reading life, in one place", systemImage: "books.vertical")
                } description: { Text("Bring your PDF and EPUB books. Read, annotate, and study with a local-first library.") } actions: { Button("Import Books…") { model.chooseBooks() }.buttonStyle(.borderedProminent) }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack(alignment: .firstTextBaseline) { VStack(alignment: .leading, spacing: 4) { Text("Your Library").font(.largeTitle.weight(.semibold)); Text("A little room for deeper reading.").foregroundStyle(.secondary) }; Spacer(); Picker("Sort", selection: $sort) { Text("Recent").tag("Recent"); Text("Title").tag("Title") }.frame(width: 150) }
                        if filtered.isEmpty { ContentUnavailableView.search(text: search) }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 215), spacing: 28)], alignment: .leading, spacing: 30) {
                            ForEach(filtered) { book in BookCard(book: book) }
                        }
                    }.padding(32)
                }
            }
        }
        .navigationTitle("Library")
        .searchable(text: $search, prompt: "Search your library")
        .toolbar {
            if model.importing { ProgressView().controlSize(.small); Text("Importing…").font(.caption) }
            Button { model.chooseBooks() } label: { Label("Import Books", systemImage: "plus") }.help("Import PDF or EPUB (⌘O)")
        }
        .dropDestination(for: URL.self) { urls, _ in model.importFiles(urls); return true }
    }
}
struct BookCard: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.readingPalette) private var palette
    let book: Book
    @State private var cover: NSImage?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { model.open(book) } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(palette.card)
                    if let cover { Image(nsImage: cover).resizable().aspectRatio(contentMode: .fit).padding(2) }
                    else {
                        LinearGradient(colors: [.orange.opacity(0.25), .brown.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        VStack(spacing: 16) { Image(systemName: "book.closed").font(.largeTitle); Text(book.title).font(.system(.title3, design: .serif)).multilineTextAlignment(.center).lineLimit(5); Text(book.author).font(.caption).lineLimit(2) }.padding(20)
                    }
                }.frame(height: 240).clipShape(RoundedRectangle(cornerRadius: 8)).shadow(color: .black.opacity(0.10), radius: 6, y: 4)
            }.buttonStyle(.plain).accessibilityLabel("Read \(book.title)")
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) { Text(book.title).font(.headline).lineLimit(2); Text(book.author.isEmpty ? "Unknown author" : book.author).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                Spacer(minLength: 0)
                Menu { BookMenu(book: book) } label: { Image(systemName: "ellipsis").frame(width: 22, height: 22) }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Actions for \(book.title)")
            }
            HStack(spacing: 5) {
                Text(book.format.uppercased()).font(.caption2.weight(.semibold)).padding(.horizontal, 5).padding(.vertical, 2).background(.quaternary, in: Capsule())
                if let progress = model.indexProgress[book.id] { ProgressView(value: progress).frame(width: 60); Text(progress == 0 ? "Queued" : "\(Int(progress * 100))%").font(.caption2) }
                else if book.indexStatus == "ready" { Label("Scholar ready", systemImage: "sparkles").font(.caption2).foregroundStyle(.secondary) }
                else if book.indexStatus == "failed" { Label("Embedding failed", systemImage: "exclamationmark.circle").font(.caption2).foregroundStyle(.orange).help(book.indexError) }
            }
        }.contextMenu { BookMenu(book: book) }.task(id: book.coverPath) { if !book.coverPath.isEmpty { cover = NSImage(contentsOfFile: book.coverPath) } }
    }
}
struct BookMenu: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.readingPalette) private var palette
    let book: Book
    var body: some View {
        Button("Open Book") { model.open(book) }
        if model.indexProgress[book.id] != nil { Button("Cancel Embedding") { model.cancelIndex(book.id) } }
        else { Button(book.indexStatus == "ready" ? "Re-embed for Agent Scholar" : "Embed to Enable Agent Scholar") { model.embed(book) } }
        Divider()
        Button("Edit Title and Author…") { model.editing = book }
        Button("Reveal Book in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: book.path)]) }
        Divider()
        Button("Delete Book…", role: .destructive) { model.deleting = book }.disabled(model.indexProgress[book.id] != nil)
    }
}
struct MetadataEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.readingPalette) private var palette
    @Environment(\.dismiss) var dismiss
    let book: Book
    @State private var title = ""
    @State private var author = ""
    var body: some View {
        Form { Text("Book Details").font(.title2); TextField("Title", text: $title); TextField("Author", text: $author); HStack { Button("Cancel") { dismiss() }; Spacer(); Button("Save") { model.perform { try model.store?.updateMetadata(book.id, title: title, author: author); model.refresh(); dismiss() } }.keyboardShortcut(.defaultAction).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } }.padding(24).frame(width: 420).onAppear { title = book.title; author = book.author }
    }
}
struct CollectionView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.readingPalette) private var palette
    let vocabulary: Bool
    @State private var notes: [Note] = []
    @State private var words: [Vocabulary] = []
    @State private var search = ""
    var body: some View {
        List {
            if vocabulary {
                ForEach(words.filter { search.isEmpty || ($0.word + $0.definition).localizedCaseInsensitiveContains(search) }) { word in
                    VStack(alignment: .leading, spacing: 7) { DefinitionContent(entry: DictionaryEntry.parse(word.definition, word: word.word), compact: true); bookButton(word.bookID) }.padding(.vertical, 6)
                        .contextMenu { Button("Delete", role: .destructive) { model.perform { try model.store?.deleteWord(word.id); reload() } } }
                }
            } else {
                ForEach(notes.filter { search.isEmpty || ($0.quote + $0.text).localizedCaseInsensitiveContains(search) }) { note in
                    VStack(alignment: .leading, spacing: 7) { if !note.quote.isEmpty { Text(note.quote).font(.system(.body, design: .serif)).foregroundStyle(.secondary) }; if !note.text.isEmpty { Text(note.text) }; HStack { bookButton(note.bookID); Text("Position \(note.position + 1)").font(.caption).foregroundStyle(.secondary) } }.padding(.vertical, 8).textSelection(.enabled)
                        .contextMenu { Button("Delete", role: .destructive) { model.perform { try model.store?.deleteNote(note.id); reload() } } }
                }
            }
        }.overlay { if (vocabulary ? words.isEmpty : notes.isEmpty) { ContentUnavailableView(vocabulary ? "Your words, collected" : "Your ideas, collected", systemImage: vocabulary ? "character.book.closed" : "note.text", description: Text("Select text while reading to save a highlight, note, or definition.")) } }
        .navigationTitle(vocabulary ? "Vocabulary" : "Notes & Highlights").searchable(text: $search).onAppear(perform: reload)
    }
    func bookButton(_ id: Int64) -> some View { Button(model.books.first { $0.id == id }?.title ?? "Book") { if let book = model.books.first(where: { $0.id == id }) { model.open(book) } }.buttonStyle(.link).font(.caption) }
    func reload() { model.perform { notes = try model.store?.notes() ?? []; words = try model.store?.vocabulary() ?? [] } }
}
