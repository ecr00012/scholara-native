import Foundation

public struct LegacyImportReport: Sendable {
    public let books: Int
    public let notes: Int
    public let messages: Int
    public let warnings: [String]
}
public enum LegacyImport {
    /// Explicit, read-only import. Never opens the original database in write mode.
    public static func run(directory: URL, store: LibraryStore) throws -> LegacyImportReport {
        let source = directory.appendingPathComponent("scholara.db")
        guard FileManager.default.fileExists(atPath: source.path) else { throw ScholaraError("Choose the old Scholara data folder containing scholara.db.") }
        let sourceKey = source.resolvingSymlinksInPath().path
        guard try store.db.rows("SELECT source FROM legacy_imports WHERE source=?", [.text(sourceKey)]).isEmpty else { throw ScholaraError("This library was already imported. Import is intentionally one-time to avoid duplicate notes and conversations.") }
        let legacy = try Database(url: source, readOnly: true)
        var imported: [Book] = []; var noteCount = 0; var messageCount = 0; var warnings: [String] = []
        do {
            try store.db.transaction {
                var bookMap: [Int64: Int64] = [:]
                for row in try legacy.rows("SELECT * FROM books") {
                    let raw = row.s("file_path")
                    var url = URL(fileURLWithPath: raw)
                    if !FileManager.default.fileExists(atPath: url.path) { url = directory.appendingPathComponent(raw) }
                    guard FileManager.default.fileExists(atPath: url.path) else { throw ScholaraError("Cannot find \(row.s("title")) at \(raw). Restore the file before importing; no partial import was kept.") }
                    let book = try BookImporter.importFile(url, store: store); imported.append(book); bookMap[row.i("id")] = book.id
                    try store.updateMetadata(book.id, title: row.s("title"), author: row.s("author"))
                    let position = legacyPosition(row.s("current_position"), format: row.s("file_type"))
                    try store.savePosition(book.id, position: position)
                    try store.setReaderOnly(book.id, value: row.s("display_mode") == "reader")
                    if row.s("file_type") == "epub" && !row.s("current_position").isEmpty { warnings.append("\(book.title): EPUB position was mapped to its chapter; exact epub.js text offsets are not portable.") }
                }
                for row in try legacy.rows("SELECT * FROM notes") {
                    guard let bookID = bookMap[row.i("book_id")] else { continue }
                    let anchor = row.s("page_or_position")
                    try store.addNote(bookID: bookID, position: legacyPosition(anchor, format: ""), quote: row.s("quote_text"), text: row.s("note_text"), anchor: anchor); noteCount += 1
                }
                for row in try legacy.rows("SELECT * FROM vocabulary") {
                    guard let bookID = bookMap[row.i("book_id")] else { continue }
                    try store.saveWord(bookID: bookID, word: row.s("word"), definition: row.s("definition"))
                }
                let tables = Set(try legacy.rows("SELECT name FROM sqlite_master WHERE type='table'").map { $0.s("name") })
                var threadMap: [Int64: Int64] = [:]
                if tables.contains("threads") {
                    for row in try legacy.rows("SELECT * FROM threads") {
                        guard let bookID = bookMap[row.i("book_id")] else { continue }
                        let id = try store.createThread(bookID: bookID, title: row.s("title").isEmpty ? "Imported conversation" : row.s("title"), model: row.s("model"))
                        try store.updateThread(id, title: row.s("title"), model: row.s("model"), spoilers: row.i("spoiler_mode") != 0)
                        threadMap[row.i("id")] = id
                    }
                    for row in try legacy.rows("SELECT * FROM messages ORDER BY id") {
                        guard let threadID = threadMap[row.i("thread_id")], ["user", "assistant"].contains(row.s("role")) else { continue }
                        let raw = row.s("content").isEmpty ? row.s("content_legacy") : row.s("content")
                        let text = messageText(raw)
                        if !text.isEmpty { try store.addMessage(threadID: threadID, role: row.s("role"), text: text); messageCount += 1 }
                    }
                }
                if tables.contains("conversations") {
                    var olderThreads: [Int64: Int64] = [:]
                    for row in try legacy.rows("SELECT * FROM conversations ORDER BY id") {
                        guard let bookID = bookMap[row.i("book_id")] else { continue }
                        let threadID: Int64
                        if let existing = olderThreads[bookID] { threadID = existing }
                        else { threadID = try store.createThread(bookID: bookID, title: "Earlier conversations", model: "openrouter/auto"); olderThreads[bookID] = threadID }
                        try store.addMessage(threadID: threadID, role: row.s("role"), text: row.s("content")); messageCount += 1
                    }
                }
                if tables.contains("preferences") {
                    for row in try legacy.rows("SELECT * FROM preferences") {
                        let scope = row.s("scope") == "global" ? "global" : bookMap[row.i("book_id")].map { "book:\($0)" } ?? ""
                        if !scope.isEmpty { let old = try store.preference(scope: scope); try store.savePreference(scope: scope, text: old + (old.isEmpty ? "" : "\n") + row.s("text")) }
                    }
                }
                if tables.contains("reader_profile") {
                    for row in try legacy.rows("SELECT * FROM reader_profile") {
                        let old = row.s("scope"); let scope: String
                        if old == "global" { scope = old }
                        else if let id = Int64(old.replacingOccurrences(of: "book:", with: "")), let mapped = bookMap[id] { scope = "book:\(mapped)" }
                        else { continue }
                        try store.saveProfile(scope: scope, text: row.s("summary"))
                    }
                }
                try store.db.execute("INSERT INTO legacy_imports(source) VALUES(?)", [.text(sourceKey)])
            }
        } catch {
            for book in imported { try? FileManager.default.removeItem(at: URL(fileURLWithPath: book.path).deletingLastPathComponent()) }
            throw error
        }
        warnings.append("Legacy MiniLM embeddings are not compatible with Apple's models. Books were not automatically re-embedded; use each book's Embed menu.")
        return LegacyImportReport(books: imported.count, notes: noteCount, messages: messageCount, warnings: warnings)
    }
    static func messageText(_ raw: String) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) else { return raw }
        if let value = json as? [String: Any] { return value["text"] as? String ?? "" }
        if let blocks = json as? [[String: Any]] { return blocks.compactMap { $0["text"] as? String }.joined(separator: "\n") }
        return raw
    }
    public static func legacyPosition(_ raw: String, format: String) -> Int {
        guard var value = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any] else { return 0 }
        if let start = value["start"] as? [String: Any] { value = start }
        if let page = value["locator"] as? Int { return max(0, page - 1) }
        if let locator = value["locator"] as? String, locator.hasPrefix("epubcfi("), let component = locator.split(separator: "!").first?.split(separator: "/").last {
            let number = component.prefix { $0.isNumber }; return max(0, (Int(number) ?? 2) / 2 - 1)
        }
        return 0
    }
}
