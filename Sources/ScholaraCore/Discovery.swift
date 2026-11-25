import Foundation

public struct GutenbergBook: Codable, Identifiable, Sendable {
    public struct Author: Codable, Sendable { public let name: String }
    public let id: Int
    public let title: String
    public let authors: [Author]
    public let formats: [String: String]
    public var author: String { authors.map(\.name).joined(separator: ", ") }
    public var epubURL: URL? { formats.first { $0.key.hasPrefix("application/epub+zip") }.flatMap { Gutenberg.secureBookURL($0.value) } }
    public var coverURL: URL? { formats["image/jpeg"].flatMap(Gutenberg.secureBookURL) }
}
public struct GutenbergPage: Codable, Sendable {
    public let count: Int
    public let next: String?
    public let results: [GutenbergBook]
}
public struct DiscoveryHTTPError: LocalizedError, Sendable {
    public let status: Int
    public let message: String
    public var errorDescription: String? { message }
}
/// A small request pool prevents a grid of covers from overwhelming the service.
/// A Retry-After maintenance response suppresses further Gutenberg traffic.
public actor GutenbergHTTP {
    public static let shared = GutenbergHTTP()
    private let session: URLSession
    private var maintenanceUntil: Date?
    private var active = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    public init(session: URLSession? = nil) {
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 120
            let cache = (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory).appendingPathComponent("ScholaraNative/HTTP", isDirectory: true)
            config.urlCache = URLCache(memoryCapacity: 12_000_000, diskCapacity: 80_000_000, diskPath: cache.path)
            config.httpAdditionalHeaders = ["User-Agent": "Scholara/0.2 (+https://github.com/ecr00012/scholara-native)"]
            self.session = URLSession(configuration: config)
        }
    }
    private func acquire() async {
        if active < 4 { active += 1; return }
        await withCheckedContinuation { waiting.append($0) }
    }
    private func release() { if waiting.isEmpty { active -= 1 } else { waiting.removeFirst().resume() } }
    public func data(from url: URL) async throws -> Data {
        await acquire(); defer { release() }
        try Task.checkCancellation()
        let isGutenberg = Gutenberg.isBookHost(url.host)
        if isGutenberg, let until = maintenanceUntil, until > Date() { throw Self.maintenanceError }
        var request = URLRequest(url: url); request.setValue("Scholara/0.2 (+https://github.com/ecr00012/scholara-native)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ScholaraError("The book service returned an invalid response.") }
        if http.statusCode == 503 && isGutenberg {
            let seconds = TimeInterval(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 120
            maintenanceUntil = Date().addingTimeInterval(min(max(seconds,30),21600)); throw Self.maintenanceError
        }
        guard (200..<300).contains(http.statusCode) else { throw DiscoveryHTTPError(status: http.statusCode, message: "\(isGutenberg ? "Project Gutenberg" : "Gutendex") returned HTTP \(http.statusCode). Your library and current results are unchanged; retry later.") }
        guard data.count <= 200_000_000 else { throw ScholaraError("This book exceeds the 200 MB download limit.") }
        return data
    }
    private static var maintenanceError: DiscoveryHTTPError { DiscoveryHTTPError(status: 503, message: "Project Gutenberg is temporarily down for maintenance. Its cover images and EPUB downloads are unavailable. Cached books remain readable; try the download again after the service returns.") }
}
public enum Gutenberg {
    public static func isBookHost(_ host: String?) -> Bool { guard let host else { return false }; return host == "gutenberg.org" || host.hasSuffix(".gutenberg.org") }
    public static func secureBookURL(_ raw: String) -> URL? {
        guard var url = URLComponents(string: raw), isBookHost(url.host), ["http", "https"].contains(url.scheme ?? "") else { return nil }
        url.scheme = "https"; return url.url
    }
    public static func searchURL(_ query: String, page: Int = 1) -> URL {
        var url = URLComponents(string: "https://gutendex.com/books/")!
        url.queryItems = [.init(name: "sort", value: "popular"), .init(name: "page", value: String(max(1,page)))]
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { url.queryItems?.append(.init(name: "search", value: trimmed)) }
        return url.url!
    }
    public static func nextPageURL(_ raw: String) throws -> URL {
        guard var url = URLComponents(string: raw), url.host == "gutendex.com", url.path == "/books/", ["http", "https"].contains(url.scheme ?? "") else { throw ScholaraError("Gutendex returned an invalid next-page link.") }
        url.scheme = "https"; return url.url!
    }
    public static func search(_ query: String, page: Int = 1, client: GutenbergHTTP = .shared) async throws -> GutenbergPage { try await fetch(searchURL(query, page: page), client: client) }
    public static func fetch(_ url: URL, client: GutenbergHTTP = .shared) async throws -> GutenbergPage {
        let trusted = try nextPageURL(url.absoluteString)
        return try JSONDecoder().decode(GutenbergPage.self, from: await client.data(from: trusted))
    }
    public static func epubCandidates(_ book: GutenbergBook) -> [URL] {
        let raw = [book.epubURL?.absoluteString,
            "https://www.gutenberg.org/ebooks/\(book.id).epub3.images",
            "https://www.gutenberg.org/ebooks/\(book.id).epub.images",
            "https://www.gutenberg.org/ebooks/\(book.id).epub.noimages",
            "https://www.gutenberg.org/cache/epub/\(book.id)/pg\(book.id)-images.epub"].compactMap { $0 }
        var seen: Set<String> = []; return raw.filter { seen.insert($0).inserted }.compactMap(secureBookURL)
    }
    public static func download(_ book: GutenbergBook, store: LibraryStore, client: GutenbergHTTP = .shared) async throws -> Book {
        if let existing = try store.books().first(where: { URL(fileURLWithPath: $0.path).lastPathComponent == "Gutenberg-\(book.id).epub" }) { return existing }
        var archive: Data?
        for url in epubCandidates(book) {
            do {
                let data = try await client.data(from: url)
                guard data.starts(with: [0x50,0x4b]) else { throw ScholaraError("Gutenberg returned a web page instead of an EPUB. Please retry when the service is available.") }
                archive = data; break
            } catch let error as DiscoveryHTTPError where error.status == 404 { continue }
        }
        guard let archive else { throw ScholaraError("No EPUB edition is currently available for this Gutenberg book.") }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let epub = folder.appendingPathComponent("Gutenberg-\(book.id).epub")
        try archive.write(to: epub)
        let imported = try BookImporter.importFile(epub, store: store)
        try store.updateMetadata(imported.id, title: book.title, author: book.author)
        return try store.books().first { $0.id == imported.id }!
    }
}

public struct DiscoveryCursor: Sendable {
    public private(set) var books: [GutenbergBook] = []
    public private(set) var next: URL?
    public private(set) var total = 0
    public init() {}
    /// Only call after a successful response. Failures never advance the cursor.
    public mutating func accept(_ page: GutenbergPage, reset: Bool) throws {
        let next = try page.next.map(Gutenberg.nextPageURL)
        var seen = Set(reset ? [] : books.map(\.id))
        let additions = page.results.filter { seen.insert($0.id).inserted }
        books = (reset ? [] : books) + additions; self.next = next; total = page.count
    }
}
