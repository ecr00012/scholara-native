import SwiftUI
import CryptoKit
import ScholaraCore

actor CoverCache {
    static let shared = CoverCache()
    var memory: [String: Data] = [:]
    func imageData(url: URL, directory: URL) async throws -> Data {
        let key = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        if let value = memory[key] { return value }
        let file = directory.appendingPathComponent(key + ".image")
        if let data = try? Data(contentsOf: file), NSImage(data: data) != nil { memory[key] = data; return data }
        let data = try await GutenbergHTTP.shared.data(from: url)
        guard NSImage(data: data) != nil else { throw ScholaraError("Cover image unavailable.") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
        if memory.count >= 128 { memory.removeAll(keepingCapacity: true) }
        memory[key] = data; return data
    }
}
struct GutenbergCover: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.readingPalette) private var palette
    let book: GutenbergBook
    let onUnavailable: (String) -> Void
    @State private var image: NSImage?
    @State private var unavailable = false
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(palette.surface)
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else { VStack(spacing: 8) { Image(systemName: "book.closed").font(.title2); Text(book.title).font(.custom("Iowan Old Style", size: 12)).multilineTextAlignment(.center).lineLimit(5); if unavailable { Text("Cover unavailable").font(.system(size: 9)).foregroundStyle(.secondary) } }.padding(8).foregroundStyle(palette.muted) }
        }.frame(width: 88, height: 128).clipShape(RoundedRectangle(cornerRadius: 6))
            .task(id: book.id) {
                guard let url = book.coverURL, let root = model.store?.root else { unavailable = true; return }
                do { let data = try await CoverCache.shared.imageData(url: url, directory: root.appendingPathComponent("CoverCache")); image = NSImage(data: data) }
                catch { unavailable = true; if let error = error as? DiscoveryHTTPError, error.status == 503 { onUnavailable(error.localizedDescription) } }
            }
    }
}
struct DiscoveryView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.readingPalette) private var palette
    @State private var query = ""
    @State private var cursor = DiscoveryCursor()
    @State private var loading = false
    @State private var downloading: Set<Int> = []
    @State private var request: Task<Void, Never>?
    @State private var generation = UUID()
    @State private var status = ""
    @State private var serviceNotice = ""
    @State private var lastFailedURL: URL?
    @State private var lastFailedReset = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Discover the classics").font(.largeTitle.weight(.semibold)).foregroundStyle(palette.ink)
                Text("Public-domain books from Project Gutenberg, via Gutendex.").foregroundStyle(palette.muted)
                if !serviceNotice.isEmpty { Label(serviceNotice, systemImage: "clock.badge.exclamationmark").font(.callout).foregroundStyle(palette.muted).padding(14).frame(maxWidth: .infinity, alignment: .leading).background(palette.surface, in: RoundedRectangle(cornerRadius: 12)) }
                if !status.isEmpty { HStack { Text(status).foregroundStyle(palette.muted); if let failed = lastFailedURL { Button("Retry") { load(url: failed, reset: lastFailedReset) } } } }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 310), spacing: 20)], spacing: 20) {
                    ForEach(cursor.books) { book in
                        HStack(alignment: .top, spacing: 16) {
                            GutenbergCover(book: book) { serviceNotice = $0 }
                            VStack(alignment: .leading, spacing: 9) {
                                Text(book.title).font(.headline).lineLimit(3).foregroundStyle(palette.ink); Text(book.author).font(.caption).foregroundStyle(palette.muted).lineLimit(2)
                                if downloading.contains(book.id) { ProgressView("Downloading…").controlSize(.small) }
                                else if let imported = model.books.first(where: { URL(fileURLWithPath: $0.path).lastPathComponent == "Gutenberg-\(book.id).epub" }) { Button("Open Book") { model.open(imported) } }
                                else { Button("Add to Library") { download(book) } }
                            }; Spacer(minLength: 0)
                        }.padding(16).frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading).background(palette.card, in: RoundedRectangle(cornerRadius: 14)).overlay { RoundedRectangle(cornerRadius: 14).stroke(palette.outline, lineWidth: 0.7) }
                    }
                }
                if loading { ProgressView("Loading books…").frame(maxWidth: .infinity) }
                else if let next = cursor.next { Button("Load More") { load(url: next, reset: false) }.frame(maxWidth: .infinity) }
                if !cursor.books.isEmpty { Text("\(cursor.books.count) of \(cursor.total.formatted()) books").font(.caption).foregroundStyle(palette.muted).frame(maxWidth: .infinity) }
            }.padding(32)
        }.background(palette.background).navigationTitle("Discover").searchable(text: $query, prompt: "Search Gutenberg books").onSubmit(of: .search) { load(url: Gutenberg.searchURL(query), reset: true) }
        .toolbar { Button { load(url: Gutenberg.searchURL(query), reset: true) } label: { Label("Refresh", systemImage: "arrow.clockwise") } }
        .onAppear { if cursor.books.isEmpty { loadCache(); load(url: Gutenberg.searchURL(query), reset: true) } }
        .onDisappear { request?.cancel() }
    }
    func load(url: URL, reset: Bool) {
        request?.cancel(); let token = UUID(); generation = token; loading = true; status = ""; lastFailedURL = nil
        request = Task {
            do {
                let response = try await Gutenberg.fetch(url); try Task.checkCancellation(); guard generation == token else { return }
                try cursor.accept(response, reset: reset)
                if query.trimmingCharacters(in: .whitespaces).isEmpty, reset, let store = model.store { try? JSONEncoder().encode(response).write(to: store.root.appendingPathComponent("gutenberg-cache.json"), options: .atomic) }
            } catch { if !Task.isCancelled && generation == token { status = error.localizedDescription; lastFailedURL = url; lastFailedReset = reset } }
            if generation == token { loading = false }
        }
    }
    func loadCache() { if let store = model.store, let data = try? Data(contentsOf: store.root.appendingPathComponent("gutenberg-cache.json")), let page = try? JSONDecoder().decode(GutenbergPage.self, from: data) { try? cursor.accept(page, reset: true); status = "Showing cached discovery results." } }
    func download(_ book: GutenbergBook) {
        guard let store = model.store else { return }; downloading.insert(book.id)
        Task {
            do { let result = try await Task.detached { try await Gutenberg.download(book, store: store) }.value; model.imported(result) }
            catch { model.error = error.localizedDescription }
            downloading.remove(book.id)
        }
    }
}
