import Foundation
import CSQLite

public enum SQLValue: Sendable {
    case text(String), int(Int64), blob(Data), null
    public var string: String { if case .text(let s) = self { return s }; if case .int(let i) = self { return String(i) }; return "" }
    public var integer: Int64 { if case .int(let i) = self { return i }; return Int64(string) ?? 0 }
    public var data: Data { if case .blob(let d) = self { return d }; return Data() }
}
public typealias SQLRow = [String: SQLValue]
extension Dictionary where Key == String, Value == SQLValue {
    func s(_ key: String) -> String { self[key]?.string ?? "" }
    func i(_ key: String) -> Int64 { self[key]?.integer ?? 0 }
}
public final class Database: @unchecked Sendable {
    private var handle: OpaquePointer?
    private let lock = NSRecursiveLock()
    public init(url: URL, readOnly: Bool = false) throws {
        let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE
        guard sqlite3_open_v2(url.path, &handle, flags | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let handle { sqlite3_close(handle) }; handle = nil
            throw ScholaraError("Could not open the library database.")
        }
        sqlite3_busy_timeout(handle, 5000)
        if !readOnly { try execute("PRAGMA journal_mode=WAL"); try execute("PRAGMA foreign_keys=ON") }
    }
    deinit { sqlite3_close(handle) }
    @discardableResult public func execute(_ sql: String, _ values: [SQLValue] = []) throws -> Int64 {
        lock.lock(); defer { lock.unlock() }
        let statement = try prepare(sql, values); defer { sqlite3_finalize(statement) }
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW { result = sqlite3_step(statement) }
        guard result == SQLITE_DONE else { throw error() }
        return sqlite3_last_insert_rowid(handle)
    }
    public func rows(_ sql: String, _ values: [SQLValue] = []) throws -> [SQLRow] {
        lock.lock(); defer { lock.unlock() }
        let statement = try prepare(sql, values); defer { sqlite3_finalize(statement) }
        var rows: [SQLRow] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw error() }
            var row: SQLRow = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER: row[name] = .int(sqlite3_column_int64(statement, index))
                case SQLITE_TEXT: row[name] = .text(String(cString: sqlite3_column_text(statement, index)))
                case SQLITE_BLOB:
                    let count = Int(sqlite3_column_bytes(statement, index))
                    row[name] = .blob(sqlite3_column_blob(statement, index).map { Data(bytes: $0, count: count) } ?? Data())
                default: row[name] = .null
                }
            }
            rows.append(row)
        }
        return rows
    }
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        try execute("BEGIN IMMEDIATE")
        do { let value = try body(); try execute("COMMIT"); return value }
        catch { _ = try? execute("ROLLBACK"); throw error }
    }
    private func error() -> ScholaraError { ScholaraError("Library database: \(String(cString: sqlite3_errmsg(handle)))") }
    private func prepare(_ sql: String, _ values: [SQLValue]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw error() }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let code: Int32
            switch value {
            case .text(let string): code = sqlite3_bind_text(statement, index, string, -1, transient)
            case .int(let integer): code = sqlite3_bind_int64(statement, index, integer)
            case .blob(let data): code = data.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(data.count), transient) }
            case .null: code = sqlite3_bind_null(statement, index)
            }
            if code != SQLITE_OK { sqlite3_finalize(statement); throw error() }
        }
        return statement
    }
}

public final class LibraryStore: @unchecked Sendable {
    public let root: URL
    public let db: Database
    public var modelsURL: URL { root.appendingPathComponent("models.json") }
    public init(root: URL? = nil) throws {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ScholaraNative", isDirectory: true)
        try FileManager.default.createDirectory(at: self.root.appendingPathComponent("Books"), withIntermediateDirectories: true)
        db = try Database(url: self.root.appendingPathComponent("scholara-native.sqlite"))
        try schema()
    }
    private func schema() throws {
        let statements = [
            "CREATE TABLE IF NOT EXISTS books(id INTEGER PRIMARY KEY, title TEXT NOT NULL, author TEXT NOT NULL DEFAULT '', path TEXT NOT NULL UNIQUE, format TEXT NOT NULL, position INTEGER NOT NULL DEFAULT 0, offset INTEGER NOT NULL DEFAULT 0, index_status TEXT NOT NULL DEFAULT 'notIndexed', index_error TEXT NOT NULL DEFAULT '', index_model TEXT NOT NULL DEFAULT '', content_hash TEXT NOT NULL DEFAULT '', reader_only INTEGER NOT NULL DEFAULT 0, last_opened TEXT NOT NULL DEFAULT '', cover_path TEXT NOT NULL DEFAULT '')",
            "CREATE TABLE IF NOT EXISTS notes(id INTEGER PRIMARY KEY, book_id INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE, position INTEGER NOT NULL, quote TEXT NOT NULL DEFAULT '', text TEXT NOT NULL DEFAULT '', anchor TEXT NOT NULL DEFAULT '')",
            "CREATE INDEX IF NOT EXISTS notes_book ON notes(book_id,position)",
            "CREATE TABLE IF NOT EXISTS vocabulary(id INTEGER PRIMARY KEY, book_id INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE, word TEXT NOT NULL, definition TEXT NOT NULL, UNIQUE(book_id,word COLLATE NOCASE))",
            "CREATE TABLE IF NOT EXISTS threads(id INTEGER PRIMARY KEY, book_id INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE, title TEXT NOT NULL, model TEXT NOT NULL, spoiler_mode INTEGER NOT NULL DEFAULT 1)",
            "CREATE TABLE IF NOT EXISTS messages(id INTEGER PRIMARY KEY, thread_id INTEGER NOT NULL REFERENCES threads(id) ON DELETE CASCADE, role TEXT NOT NULL, text TEXT NOT NULL)",
            "CREATE INDEX IF NOT EXISTS messages_thread ON messages(thread_id,id)",
            "CREATE TABLE IF NOT EXISTS chunks(id INTEGER PRIMARY KEY, book_id INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE, position INTEGER NOT NULL, text TEXT NOT NULL, vector BLOB NOT NULL)",
            "CREATE INDEX IF NOT EXISTS chunks_book ON chunks(book_id,position)",
            "CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(text, content='chunks', content_rowid='id')",
            "CREATE TRIGGER IF NOT EXISTS chunks_ai AFTER INSERT ON chunks BEGIN INSERT INTO chunks_fts(rowid,text) VALUES(new.id,new.text); END",
            "CREATE TRIGGER IF NOT EXISTS chunks_ad AFTER DELETE ON chunks BEGIN INSERT INTO chunks_fts(chunks_fts,rowid,text) VALUES('delete',old.id,old.text); END",
            "CREATE TABLE IF NOT EXISTS preferences(scope TEXT PRIMARY KEY, text TEXT NOT NULL)",
            "CREATE TABLE IF NOT EXISTS profiles(scope TEXT PRIMARY KEY, summary TEXT NOT NULL)",
            "CREATE TABLE IF NOT EXISTS legacy_imports(source TEXT PRIMARY KEY, imported_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)"
        ]
        for sql in statements { try db.execute(sql) }
        let columns = Set(try db.rows("PRAGMA table_info(books)").map { $0.s("name") })
        if !columns.contains("reading_mode") { try db.execute("ALTER TABLE books ADD COLUMN reading_mode TEXT NOT NULL DEFAULT 'scroll'") }
        if !columns.contains("page_offset") { try db.execute("ALTER TABLE books ADD COLUMN page_offset INTEGER NOT NULL DEFAULT 0") }
        try db.execute("UPDATE books SET index_status='notIndexed', index_error='Indexing was interrupted. Use Embed to retry.' WHERE index_status='indexing'")
    }
    public func books() throws -> [Book] {
        try db.rows("SELECT * FROM books ORDER BY last_opened DESC,title COLLATE NOCASE").map {
            Book(id: $0.i("id"), title: $0.s("title"), author: $0.s("author"), path: $0.s("path"), format: $0.s("format"), position: Int($0.i("position")), offset: Int($0.i("offset")), indexStatus: $0.s("index_status"), indexError: $0.s("index_error"), readerOnly: $0.i("reader_only") != 0, lastOpened: $0.s("last_opened"), coverPath: $0.s("cover_path"), readingMode: $0.s("reading_mode"), pageOffset: Int($0.i("page_offset")))
        }
    }
    public func addBook(title: String, author: String, path: String, format: String, cover: String = "") throws -> Book {
        let id = try db.execute("INSERT INTO books(title,author,path,format,cover_path) VALUES(?,?,?,?,?)", [.text(title), .text(author), .text(path), .text(format), .text(cover)])
        return try books().first { $0.id == id }!
    }
    public func updateMetadata(_ id: Int64, title: String, author: String) throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ScholaraError("A book needs a title.") }
        try db.execute("UPDATE books SET title=?,author=? WHERE id=?", [.text(title), .text(author), .int(id)])
    }
    public func savePosition(_ id: Int64, position: Int, offset: Int = 0) throws {
        try db.execute("UPDATE books SET position=?,offset=?,last_opened=CURRENT_TIMESTAMP WHERE id=?", [.int(Int64(max(0,position))), .int(Int64(max(0,offset))), .int(id)])
    }
    public func saveReadingMode(_ id: Int64, mode: String) throws {
        guard ["scroll", "pages"].contains(mode) else { throw ScholaraError("Unknown reading mode.") }
        try db.execute("UPDATE books SET reading_mode=? WHERE id=?", [.text(mode), .int(id)])
    }
    public func savePageOffset(_ id: Int64, offset: Int) throws { try db.execute("UPDATE books SET page_offset=? WHERE id=?", [.int(Int64(max(0,offset))), .int(id)]) }
    public func setReaderOnly(_ id: Int64, value: Bool) throws { try db.execute("UPDATE books SET reader_only=? WHERE id=?", [.int(value ? 1 : 0), .int(id)]) }
    public func removeBook(_ book: Book) throws {
        try db.execute("DELETE FROM books WHERE id=?", [.int(book.id)])
        // Only remove files owned by this library, never arbitrary imported paths.
        let url = URL(fileURLWithPath: book.path).standardizedFileURL
        if url.path.hasPrefix(root.appendingPathComponent("Books").path + "/") { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    }
    public func notes(bookID: Int64? = nil) throws -> [Note] {
        try db.rows("SELECT * FROM notes" + (bookID == nil ? "" : " WHERE book_id=?") + " ORDER BY id DESC", bookID.map { [.int($0)] } ?? []).map {
            Note(id: $0.i("id"), bookID: $0.i("book_id"), position: Int($0.i("position")), quote: $0.s("quote"), text: $0.s("text"), anchor: $0.s("anchor"))
        }
    }
    public func addNote(bookID: Int64, position: Int, quote: String, text: String, anchor: String = "") throws {
        guard !(quote + text).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ScholaraError("Select a passage or write a note first.") }
        try db.execute("INSERT INTO notes(book_id,position,quote,text,anchor) VALUES(?,?,?,?,?)", [.int(bookID), .int(Int64(position)), .text(quote), .text(text), .text(anchor)])
    }
    public func editNote(_ id: Int64, text: String) throws { try db.execute("UPDATE notes SET text=? WHERE id=?", [.text(text), .int(id)]) }
    public func deleteNote(_ id: Int64) throws { try db.execute("DELETE FROM notes WHERE id=?", [.int(id)]) }
    public func vocabulary(bookID: Int64? = nil) throws -> [Vocabulary] {
        try db.rows("SELECT * FROM vocabulary" + (bookID == nil ? "" : " WHERE book_id=?") + " ORDER BY id DESC", bookID.map { [.int($0)] } ?? []).map {
            Vocabulary(id: $0.i("id"), bookID: $0.i("book_id"), word: $0.s("word"), definition: $0.s("definition"))
        }
    }
    public func saveWord(bookID: Int64, word: String, definition: String) throws {
        try db.execute("INSERT INTO vocabulary(book_id,word,definition) VALUES(?,?,?) ON CONFLICT(book_id,word) DO UPDATE SET definition=excluded.definition", [.int(bookID), .text(word), .text(definition)])
    }
    public func deleteWord(_ id: Int64) throws { try db.execute("DELETE FROM vocabulary WHERE id=?", [.int(id)]) }
    public func threads(bookID: Int64) throws -> [Conversation] {
        try db.rows("SELECT * FROM threads WHERE book_id=? ORDER BY id DESC", [.int(bookID)]).map { Conversation(id: $0.i("id"), bookID: bookID, title: $0.s("title"), model: $0.s("model"), spoilerMode: $0.i("spoiler_mode") != 0) }
    }
    public func createThread(bookID: Int64, title: String = "New conversation", model: String) throws -> Int64 {
        try db.execute("INSERT INTO threads(book_id,title,model) VALUES(?,?,?)", [.int(bookID), .text(title), .text(model)])
    }
    public func updateThread(_ id: Int64, title: String, model: String, spoilers: Bool) throws {
        try db.execute("UPDATE threads SET title=?,model=?,spoiler_mode=? WHERE id=?", [.text(title), .text(model), .int(spoilers ? 1 : 0), .int(id)])
    }
    public func deleteThread(_ id: Int64) throws { try db.execute("DELETE FROM threads WHERE id=?", [.int(id)]) }
    public func messages(threadID: Int64) throws -> [Message] {
        try db.rows("SELECT * FROM messages WHERE thread_id=? ORDER BY id", [.int(threadID)]).map { Message(id: $0.i("id"), role: $0.s("role"), text: $0.s("text")) }
    }
    public func addMessage(threadID: Int64, role: String, text: String) throws {
        try db.execute("INSERT INTO messages(thread_id,role,text) VALUES(?,?,?)", [.int(threadID), .text(role), .text(text)])
    }
    public func setIndexStatus(_ id: Int64, status: String, error: String = "") throws {
        try db.execute("UPDATE books SET index_status=?,index_error=? WHERE id=?", [.text(status), .text(error), .int(id)])
    }
    public func replaceIndex(_ id: Int64, passages: [Passage], model: String, hash: String) throws {
        try db.transaction {
            try db.execute("DELETE FROM chunks WHERE book_id=?", [.int(id)])
            for p in passages {
                let data = p.vector.withUnsafeBytes { Data($0) }
                try db.execute("INSERT INTO chunks(book_id,position,text,vector) VALUES(?,?,?,?)", [.int(id), .int(Int64(p.position)), .text(p.text), .blob(data)])
            }
            try db.execute("UPDATE books SET index_status='ready',index_error='',index_model=?,content_hash=? WHERE id=?", [.text(model), .text(hash), .int(id)])
        }
    }
    public func indexModel(_ id: Int64) throws -> String { try db.rows("SELECT index_model FROM books WHERE id=?", [.int(id)]).first?.s("index_model") ?? "" }
    public func passages(bookID: Int64, through position: Int? = nil) throws -> [Passage] {
        try db.rows("SELECT * FROM chunks WHERE book_id=?" + (position == nil ? "" : " AND position<=?"), [.int(bookID)] + (position.map { [.int(Int64($0))] } ?? [])).map { row in
            let data = row["vector"]?.data ?? Data()
            let vector = stride(from: 0, to: data.count - data.count % 4, by: 4).map { offset in data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: Float.self) } }
            return Passage(id: row.i("id"), position: Int(row.i("position")), text: row.s("text"), vector: vector)
        }
    }
    public func keywordIDs(bookID: Int64, query: String, through position: Int?) throws -> [Int64] {
        let terms = query.split { !$0.isLetter && !$0.isNumber }.prefix(16).map { "\"\($0)\"" }.joined(separator: " OR ")
        if terms.isEmpty { return [] }
        return try db.rows("SELECT c.id FROM chunks_fts JOIN chunks c ON c.id=chunks_fts.rowid WHERE chunks_fts MATCH ? AND c.book_id=?" + (position == nil ? "" : " AND c.position<=?") + " ORDER BY bm25(chunks_fts) LIMIT 24", [.text(terms), .int(bookID)] + (position.map { [.int(Int64($0))] } ?? [])).map { $0.i("id") }
    }
    public func preference(scope: String) throws -> String { try db.rows("SELECT text FROM preferences WHERE scope=?", [.text(scope)]).first?.s("text") ?? "" }
    public func savePreference(scope: String, text: String) throws { try db.execute("INSERT INTO preferences(scope,text) VALUES(?,?) ON CONFLICT(scope) DO UPDATE SET text=excluded.text", [.text(scope), .text(text)]) }
    public func profile(scope: String) throws -> String { try db.rows("SELECT summary FROM profiles WHERE scope=?", [.text(scope)]).first?.s("summary") ?? "" }
    public func saveProfile(scope: String, text: String) throws { try db.execute("INSERT INTO profiles(scope,summary) VALUES(?,?) ON CONFLICT(scope) DO UPDATE SET summary=excluded.summary", [.text(scope), .text(text)]) }
}
