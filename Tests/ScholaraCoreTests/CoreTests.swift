import Foundation
import AppKit
import PDFKit
import NaturalLanguage
import ZIPFoundation
import ScholaraCore

final class CoreTests {
    var temporary: URL!
    func setUpWithError() throws {
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent("ScholaraTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    }
    func tearDownWithError() throws { try? FileManager.default.removeItem(at: temporary) }
    func fixture(_ name: String) -> URL { Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")! }
    func store() throws -> LibraryStore { try LibraryStore(root: temporary.appendingPathComponent("Library")) }
    func book(_ store: LibraryStore, format: String = "pdf") throws -> Book { try BookImporter.importFile(fixture("sample.\(format)"), store: store) }

    func testModelPathsAreConfigurableAndRoundTripWithoutAllowlist() throws {
        let option = ModelOption(id: "new-provider/changed-model:free", name: "My model", supportsTools: false)
        let config = ModelConfiguration(selectedModel: option.id, models: [option])
        let url = temporary.appendingPathComponent("models.json")
        try config.save(to: url)
        let loaded = try ModelConfiguration.load(from: url)
        try checkEqual(loaded.models, [option]); try checkEqual(loaded.selectedModel, option.id)
        try checkFalse(ModelConfiguration.validPath("https://example.com/model"))
        try checkFalse(ModelConfiguration.validPath("bad path/model"))
        try checkFalse(ModelConfiguration.validPath("provider/"))
    }
    func testInvalidModelConfigurationDoesNotOverwriteExistingFile() throws {
        let url = temporary.appendingPathComponent("models.json")
        try ModelConfiguration.initial.save(to: url)
        let original = try Data(contentsOf: url)
        let duplicate = ModelOption(id: "a/b", name: "Duplicate")
        try checkThrows(try ModelConfiguration(selectedModel: "a/b", models: [duplicate,duplicate]).save(to: url))
        try checkEqual(try Data(contentsOf: url), original)
    }
    func testPDFImportCopiesFileAndDoesNotEmbed() throws {
        let store = try store(); let original = try Data(contentsOf: fixture("sample.pdf"))
        let imported = try book(store)
        try checkEqual(imported.format, "pdf"); try checkEqual(imported.indexStatus, "notIndexed")
        try checkTrue(try store.passages(bookID: imported.id).isEmpty)
        try checkEqual(try Data(contentsOf: URL(fileURLWithPath: imported.path)), original)
        try checkNotEqual(imported.path, fixture("sample.pdf").path)
        try checkTrue(FileManager.default.fileExists(atPath: imported.coverPath))
        try store.savePosition(imported.id, position: 1)
        try checkEqual(try store.books()[0].indexStatus, "notIndexed")
    }
    func testEPUBImportAndNativeLayout() throws {
        let store = try store(); let imported = try book(store, format: "epub")
        let epub = try BookImporter.epub(imported)
        try checkFalse(epub.chapters.isEmpty)
        let text = try epub.attributedChapter(0)
        try checkTrue(text.length > 20)
        try checkFalse(text.string.contains("<html"))
        try checkEqual(imported.indexStatus, "notIndexed")
    }
    func testEPUBWithoutCoverStillImports() throws {
        let store = try store(); let imported = try BookImporter.importFile(fixture("sample-no-cover.epub"), store: store)
        try checkFalse(try BookImporter.epub(imported).chapters.isEmpty)
    }
    func testFailedImportRemovesCopiedFiles() throws {
        let store = try store(); let broken = temporary.appendingPathComponent("broken.pdf")
        try Data("not a pdf".utf8).write(to: broken)
        try checkThrows(try BookImporter.importFile(broken, store: store))
        try checkTrue(try store.books().isEmpty)
        try checkTrue(try FileManager.default.contentsOfDirectory(atPath: store.root.appendingPathComponent("Books").path).isEmpty)
    }
    func testEPUBPathsCannotEscapeLibrary() throws {
        let root = temporary.appendingPathComponent("EPUB")
        for path in ["../secret", "/etc/passwd", "https://example.com/payload", "%2e%2e/secret"] {
            try checkThrows(try EPUBBook.containedURL(path, relativeTo: root, root: root))
        }
        try checkEqual(try EPUBBook.containedURL("../images/a.png", relativeTo: root.appendingPathComponent("Text"), root: root).path, root.appendingPathComponent("images/a.png").path)
    }
    func testEPUBArchiveRejectsTraversalBeforeExtracting() throws {
        let zip = temporary.appendingPathComponent("unsafe.epub")
        let archive = try Archive(url: zip, accessMode: .create)
        let bytes = Data("unsafe".utf8)
        try archive.addEntry(with: "../outside", type: .file, uncompressedSize: Int64(bytes.count), provider: { position, size in bytes.subdata(in: Int(position)..<Int(position)+size) })
        try checkThrows(try EPUBBook.open(at: zip, extractedTo: temporary.appendingPathComponent("Extracted")))
        try checkFalse(FileManager.default.fileExists(atPath: temporary.appendingPathComponent("outside").path))
    }
    func testNativeHTMLExcludesScriptsAndPreservesEmphasis() throws {
        let output = try EPUBBook.renderXHTML(Data("<html><head><title>Hidden</title><script>sendSecrets()</script></head><body><h1>Title</h1><p>Hello <em>reader</em>.</p></body></html>".utf8), base: temporary, root: temporary, fontSize: 18)
        try checkTrue(output.string.contains("Hello reader."))
        try checkFalse(output.string.contains("sendSecrets")); try checkFalse(output.string.contains("Hidden"))
        let range = (output.string as NSString).range(of: "reader")
        let font = output.attribute(.font, at: range.location, effectiveRange: nil) as! NSFont
        try checkTrue(font.fontDescriptor.symbolicTraits.contains(.italic))
    }
    func testNotesVocabularyThreadsAndPositionPersist() throws {
        let store = try store(); let imported = try book(store)
        try store.addNote(bookID: imported.id, position: 1, quote: "Quote", text: "Thought", anchor: "{}")
        try store.saveWord(bookID: imported.id, word: "Reader", definition: "A person who reads")
        try store.saveWord(bookID: imported.id, word: "reader", definition: "Updated")
        let thread = try store.createThread(bookID: imported.id, model: "anything/model")
        try store.addMessage(threadID: thread, role: "user", text: "Hello")
        try store.savePosition(imported.id, position: 1, offset: 100)
        let reopened = try LibraryStore(root: store.root)
        try checkEqual(try reopened.notes()[0].text, "Thought")
        try checkEqual(try reopened.vocabulary().count, 1)
        try checkEqual(try reopened.vocabulary()[0].definition, "Updated")
        try checkEqual(try reopened.messages(threadID: thread)[0].text, "Hello")
        try checkEqual(try reopened.books()[0].offset, 100)
        try checkEqual(try reopened.threads(bookID: imported.id)[0].model, "anything/model")
    }
    func testDeleteCascadesStudyDataAndKeepsSourceFile() throws {
        let store = try store(); let imported = try book(store)
        try store.addNote(bookID: imported.id, position: 0, quote: "quote", text: "")
        try store.saveWord(bookID: imported.id, word: "word", definition: "definition")
        let thread = try store.createThread(bookID: imported.id, model: "a/b")
        try store.addMessage(threadID: thread, role: "user", text: "question")
        try store.replaceIndex(imported.id, passages: [Passage(position: 0, text: "hello", vector: [1,0])], model: "test", hash: "hash")
        try store.removeBook(imported)
        try checkTrue(try store.books().isEmpty); try checkTrue(try store.notes().isEmpty); try checkTrue(try store.vocabulary().isEmpty)
        try checkTrue(try store.messages(threadID: thread).isEmpty); try checkTrue(try store.passages(bookID: imported.id).isEmpty)
        try checkTrue(FileManager.default.fileExists(atPath: fixture("sample.pdf").path))
        try checkFalse(FileManager.default.fileExists(atPath: imported.path))
    }
    func testIndexReplacementIsAtomicAndSpoilersFilterBothSearches() throws {
        let store = try store(); let imported = try book(store)
        let passages = [Passage(position: 0, text: "Earlier kingdom", vector: [1,0]), Passage(position: 5, text: "Future kingdom secret", vector: [0,1])]
        try store.replaceIndex(imported.id, passages: passages, model: "test", hash: "first")
        try checkEqual(try store.passages(bookID: imported.id, through: 0).map(\.text), ["Earlier kingdom"])
        let ids = try store.keywordIDs(bookID: imported.id, query: "kingdom", through: 0)
        try checkEqual(ids.count, 1)
        try checkEqual(try store.keywordIDs(bookID: imported.id, query: "secret", through: 0).count, 0)
        try store.replaceIndex(imported.id, passages: [Passage(position: 0, text: "Replacement", vector: [1,1])], model: "test2", hash: "next")
        try checkEqual(try store.passages(bookID: imported.id).count, 1)
        try checkTrue(try store.keywordIDs(bookID: imported.id, query: "kingdom", through: nil).isEmpty)
    }
    func testTransactionRollsBackOnFailure() throws {
        let store = try store()
        try checkThrows(try store.db.transaction {
            try store.db.execute("INSERT INTO preferences(scope,text) VALUES('global','temporary')")
            throw ScholaraError("failure")
        })
        try checkEqual(try store.preference(scope: "global"), "")
    }
    func testInterruptedIndexBecomesRetryableOnRelaunch() throws {
        let store = try store(); let imported = try book(store)
        try store.setIndexStatus(imported.id, status: "indexing")
        let reopened = try LibraryStore(root: store.root)
        try checkEqual(try reopened.books()[0].indexStatus, "notIndexed")
        try checkTrue(try reopened.books()[0].indexError.contains("interrupted"))
    }
    func testChunkerHandlesUnicodeOverlapAndInvalidConfiguration() throws {
        let text = String(repeating: "A thoughtful reader 📖 studies a passage. ", count: 80)
        let chunks = NativeIndex.chunks(text)
        try checkTrue(chunks.count > 1); try checkTrue(chunks.allSatisfy { $0.count <= 1000 })
        try checkTrue(chunks.last!.hasSuffix("passage."))
        try checkTrue(NativeIndex.chunks("abc", maximum: 0).isEmpty)
        try checkTrue(NativeIndex.chunks("abc", maximum: 10, overlap: 10).isEmpty)
    }
    func testCosineHandlesZerosAndDimensionMismatch() throws {
        try checkEqual(NativeIndex.cosine([1,0], [1,0]), 1, accuracy: 0.0001)
        try checkEqual(NativeIndex.cosine([1,0], [0,1]), 0)
        try checkEqual(NativeIndex.cosine([0,0], [1,0]), 0)
        try checkEqual(NativeIndex.cosine([1], [1,0]), 0)
    }
    func testEmbeddingAndSemanticSearchOnThisMac() async throws {
        guard NLEmbedding.sentenceEmbedding(for: .english) != nil else { throw CheckSkip("English sentence model is not installed on this Mac") }
        let store = try store(); let imported = try book(store)
        try await NativeIndex.build(book: imported, store: store) { _ in }
        try checkEqual(try store.books()[0].indexStatus, "ready")
        let passages = try store.passages(bookID: imported.id)
        try checkFalse(passages.isEmpty); try checkTrue(passages.allSatisfy { !$0.vector.isEmpty })
        let results = try NativeIndex.search(bookID: imported.id, query: "reading a book", through: 0, store: store)
        try checkFalse(results.isEmpty); try checkTrue(results.allSatisfy { $0.position <= 0 })
    }
    func testCancellationDoesNotPublishReadyIndex() async throws {
        let store = try store(); let imported = try book(store)
        let task = Task { try Task.checkCancellation(); try await NativeIndex.build(book: imported, store: store) { _ in } }
        task.cancel()
        var cancelled = false
        do { try await task.value } catch { cancelled = true }
        try checkTrue(cancelled)
        try checkNotEqual(try store.books()[0].indexStatus, "ready")
    }
    func testSSEFramingWithoutEmptyLinesAndMultilineJSON() throws {
        var decoder = SSEEvents()
        try checkEqual(try decoder.feed(": heartbeat"), nil)
        try checkEqual(try decoder.feed("data: {\"choices\":[]}"), "{\"choices\":[]}")
        try checkEqual(try decoder.feed("data: {\"choices\":"), nil)
        try checkEqual(try decoder.feed("data: []}"), "{\"choices\":\n[]}")
        try checkEqual(try decoder.feed("data: [DONE]"), "[DONE]")
        try checkFalse(decoder.hasIncompleteEvent)
    }
    func testSSEContentToolFragmentsDoneAndProviderError() throws {
        let delta = try StreamDelta.parse(#"{"choices":[{"delta":{"content":"Hello","tool_calls":[{"index":0,"id":"x","function":{"name":"search_book","arguments":"{\"query\":"}}]}}]}"#)
        try checkEqual(delta.text, "Hello"); try checkEqual(delta.toolCalls.count, 1)
        try checkTrue(try StreamDelta.parse("[DONE]").done)
        try checkThrows(try StreamDelta.parse(#"{"error":{"message":"Model unavailable"}}"#))
        try checkEqual(try StreamDelta.parse(#"{"usage":{"completion_tokens":2},"choices":[]}"#).text, "")
    }
    func testAnnotationAnchorsDistinguishRepeatedQuotesAndRejectInvalidRanges() throws {
        let text = "same quotation, same quotation"
        let range = AnnotationAnchor.range(quote: "same quotation", anchor: "{\"location\":16,\"length\":14}", in: text)
        try checkEqual(range, NSRange(location: 16, length: 14))
        let fallback = AnnotationAnchor.range(quote: "same quotation", anchor: "{\"location\":9223372036854775807,\"length\":14}", in: text)
        try checkEqual(fallback, NSRange(location: 0, length: 14))
        try checkEqual(AnnotationAnchor.range(quote: "missing", anchor: "{}", in: text), nil)
    }
    func testLegacyPositionAndMessageShapes() throws {
        try checkEqual(LegacyImport.legacyPosition(#"{"type":"pdf","locator":4}"#, format: "pdf"), 3)
        try checkEqual(LegacyImport.legacyPosition(#"{"start":{"type":"epub","locator":"epubcfi(/6/8[chapter]!/4/2)"},"end":{}}"#, format: "epub"), 3)
    }
    func testReadOnlyLegacyImportPreservesSourceAndDoesNotIndex() throws {
        let original = temporary.appendingPathComponent("Old"); try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        let dbURL = original.appendingPathComponent("scholara.db")
        do {
            let db = try Database(url: dbURL)
            try db.execute("CREATE TABLE books(id INTEGER,title TEXT,author TEXT,file_path TEXT,file_type TEXT,current_position TEXT,display_mode TEXT)")
            try db.execute("CREATE TABLE notes(id INTEGER,book_id INTEGER,page_or_position TEXT,quote_text TEXT,note_text TEXT)")
            try db.execute("CREATE TABLE vocabulary(id INTEGER,book_id INTEGER,word TEXT,definition TEXT)")
            try db.execute("INSERT INTO books VALUES(5,'Original title','Author',?,'pdf',?, 'reader')", [.text(fixture("sample.pdf").path), .text(#"{"type":"pdf","locator":2}"#)])
            try db.execute("INSERT INTO notes VALUES(1,5,?,'Quote','Note')", [.text(#"{"type":"pdf","locator":2}"#)])
            try db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        }
        let before = try Data(contentsOf: dbURL)
        let store = try store(); let report = try LegacyImport.run(directory: original, store: store)
        try checkEqual(report.books, 1); try checkEqual(report.notes, 1)
        try checkEqual(try Data(contentsOf: dbURL), before)
        try checkEqual(try store.books()[0].title, "Original title")
        try checkEqual(try store.books()[0].indexStatus, "notIndexed")
        try checkEqual(try store.books()[0].position, 1)
        try checkTrue(try store.books()[0].readerOnly)
        try checkEqual(try store.notes()[0].position, 1)
        try checkThrows(try LegacyImport.run(directory: original, store: store))
    }
}
