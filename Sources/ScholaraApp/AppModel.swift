import SwiftUI
import UniformTypeIdentifiers
import ScholaraCore

@MainActor
final class AppModel: ObservableObject {
    enum Section: String, CaseIterable, Identifiable {
        case library = "Library", discover = "Discover", notes = "Notes & Highlights", vocabulary = "Vocabulary"
        var id: String { rawValue }
        var icon: String { switch self { case .library: "books.vertical"; case .discover: "globe"; case .notes: "note.text"; case .vocabulary: "character.book.closed" } }
    }
    private(set) var store: LibraryStore?
    @Published var books: [Book] = []
    @Published var activeBookID: Int64?
    @Published var section: Section = .library
    @Published var config: ModelConfiguration = .initial
    @Published var error: String?
    @Published var notice: String?
    @Published var importing = false
    @Published var pendingConsent: [Book] = []
    @Published var showConsent = false
    @Published var indexProgress: [Int64: Double] = [:]
    @Published var indexQueue: [Book] = []
    @Published var deleting: Book?
    @Published var editing: Book?
    private var indexTask: Task<Void, Never>?
    private var indexingID: Int64?
    var activeBook: Book? { books.first { $0.id == activeBookID } }
    init() {
        do {
            let override = ProcessInfo.processInfo.environment["SCHOLARA_DATA_DIRECTORY"].map { URL(fileURLWithPath: $0) }
            let store = try LibraryStore(root: override); self.store = store
            books = try store.books()
            do { config = try ModelConfiguration.load(from: store.modelsURL) } catch { self.error = "Model configuration needs attention: \(error.localizedDescription). Your file has not been overwritten." }
        } catch { store = nil; self.error = error.localizedDescription }
    }
    func perform(_ work: () throws -> Void) { do { try work() } catch { self.error = error.localizedDescription } }
    func refresh() { perform { books = try store?.books() ?? [] } }
    func open(_ book: Book) { activeBookID = book.id; section = .library; perform { try store?.savePosition(book.id, position: book.position, offset: book.offset) }; refresh() }
    func chooseBooks() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf, UTType(filenameExtension: "epub") ?? .data]
        if panel.runModal() == .OK { importFiles(panel.urls) }
    }
    func importFiles(_ urls: [URL]) {
        guard let store, !importing else { return }; importing = true
        Task {
            var imported: [Book] = []; var errors: [String] = []
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                do { let book = try await Task.detached(priority: .userInitiated) { try BookImporter.importFile(url, store: store) }.value; imported.append(book) }
                catch { errors.append("\(url.lastPathComponent): \(error.localizedDescription)") }
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
            importing = false; refresh()
            if !errors.isEmpty { error = errors.joined(separator: "\n") }
            if !imported.isEmpty { pendingConsent += imported; showConsent = true }
        }
    }
    func imported(_ book: Book) { refresh(); pendingConsent.append(book); showConsent = true }
    func consent(_ accepted: Bool) { let pending = pendingConsent; pendingConsent = []; showConsent = false; if accepted { pending.forEach(embed) } }
    func embed(_ book: Book) {
        guard indexingID != book.id, !indexQueue.contains(where: { $0.id == book.id }) else { return }
        indexQueue.append(book); indexProgress[book.id] = 0; nextIndex()
    }
    private func nextIndex() {
        guard indexingID == nil, let store, !indexQueue.isEmpty else { return }
        let book = indexQueue.removeFirst(); indexingID = book.id
        indexTask = Task {
            let work = Task.detached(priority: .utility) {
                try await NativeIndex.build(book: book, store: store) { progress in
                    await MainActor.run { self.indexProgress[book.id] = progress.fraction }
                }
            }
            do { try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() } }
            catch { if !(error is CancellationError) { self.error = "\(book.title): \(error.localizedDescription)" } }
            indexProgress.removeValue(forKey: book.id); indexingID = nil; indexTask = nil; refresh(); nextIndex()
        }
        refresh()
    }
    func cancelIndex(_ id: Int64) {
        if indexingID == id { indexTask?.cancel() }
        else { indexQueue.removeAll { $0.id == id }; indexProgress.removeValue(forKey: id) }
    }
    func deleteBook(_ book: Book) {
        guard indexProgress[book.id] == nil else { error = "Cancel embedding before deleting this book."; return }
        perform { try store?.removeBook(book); if activeBookID == book.id { activeBookID = nil }; refresh() }
    }
    func toggleReaderMode() {
        if let book = activeBook { perform { try store?.setReaderOnly(book.id, value: !book.readerOnly); refresh() } }
    }
    func saveConfig(_ config: ModelConfiguration) throws { guard let store else { return }; try config.save(to: store.modelsURL); self.config = config }
}
