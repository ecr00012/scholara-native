import Foundation
import AppKit
import ScholaraCore

final class DiscoveryStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, [String:String], Data))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, headers, data) = try Self.handler(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
extension CoreTests {
    func discoveryClient() -> GutenbergHTTP {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [DiscoveryStub.self]
        return GutenbergHTTP(session: URLSession(configuration: config))
    }
    func discoveryPage(next: String? = nil, ids: [Int]) throws -> GutenbergPage {
        let data = try JSONSerialization.data(withJSONObject: ["count":100, "next":next as Any? ?? NSNull(), "results":ids.map { ["id":$0,"title":"Test \($0)","authors":[["name":"Test Author"]],"formats":["application/epub+zip":"http://www.gutenberg.org/ebooks/\($0).epub.images", "image/jpeg":"http://www.gutenberg.org/cache/epub/\($0)/cover.jpg"]] as [String:Any] }])
        return try JSONDecoder().decode(GutenbergPage.self, from:data)
    }
    func testDiscoveryCursorIsAtomicDeduplicatesAndSecuresURLs() throws {
        var cursor = DiscoveryCursor()
        try cursor.accept(discoveryPage(next:"http://gutendex.com/books/?page=2", ids:[1,2]), reset:true)
        try checkEqual(cursor.books.count,2); try checkEqual(cursor.next?.scheme,"https")
        try checkEqual(cursor.books[0].coverURL?.scheme,"https")
        try checkThrows(try cursor.accept(discoveryPage(next:"https://bad.example/books/",ids:[3]),reset:false))
        try checkEqual(cursor.books.map(\.id),[1,2]); try checkEqual(cursor.next?.query,"page=2")
        try cursor.accept(discoveryPage(ids:[2,3]),reset:false)
        try checkEqual(cursor.books.map(\.id),[1,2,3]); try checkEqual(cursor.next,nil)
        try cursor.accept(discoveryPage(ids:[4]),reset:true); try checkEqual(cursor.books.map(\.id),[4])
        try checkFalse(Gutenberg.searchURL(" ").absoluteString.contains("search="))
        try checkEqual(Gutenberg.secureBookURL("https://gutenberg.org.attacker.example/book"),nil)
    }
    func testDiscoveryMaintenanceBackoffAndCatalogueRemainIndependent() async throws {
        var hits = 0
        DiscoveryStub.handler = { request in
            hits += 1
            return request.url!.host == "gutendex.com" ? (200,[:],Data("catalogue".utf8)) : (503,["Retry-After":"21600"],Data("maintenance".utf8))
        }
        let client = discoveryClient()
        for _ in 0..<2 {
            do { _ = try await client.data(from: URL(string:"https://www.gutenberg.org/cover.jpg")!); throw CheckFailure("Expected maintenance error") }
            catch let error as DiscoveryHTTPError { try checkEqual(error.status,503) }
        }
        try checkEqual(hits,1)
        let data = try await client.data(from:Gutenberg.searchURL("")); try checkEqual(String(decoding:data,as:UTF8.self),"catalogue")
        try checkEqual(hits,2)
    }
    func testGutenbergDownloadFallsBackImportsAndNeverEmbeds() async throws {
        let archive = try Data(contentsOf:fixture("sample.epub")); var hits = 0
        DiscoveryStub.handler = { _ in hits += 1; return hits == 1 ? (404,[:],Data()) : (200,[:],archive) }
        let store = try store(); let item = try discoveryPage(ids:[42]).results[0]; let client = discoveryClient()
        let imported = try await Gutenberg.download(item,store:store,client:client)
        try checkEqual(hits,2); try checkEqual(imported.title,"Test 42"); try checkEqual(imported.indexStatus,"notIndexed")
        try checkTrue(FileManager.default.fileExists(atPath:imported.path))
        let again = try await Gutenberg.download(item,store:store,client:client)
        try checkEqual(again.id,imported.id); try checkEqual(hits,2)
    }
    func testGutenbergRejectsMaintenanceHTMLWithoutImporting() async throws {
        DiscoveryStub.handler = { _ in (200,[:],Data("<html>maintenance</html>".utf8)) }
        let store = try store()
        var rejected = false
        do { _ = try await Gutenberg.download(discoveryPage(ids:[42]).results[0],store:store,client:discoveryClient()) } catch { rejected = true }
        try checkTrue(rejected); try checkTrue(try store.books().isEmpty)
    }
    func testDictionaryFieldsRoundTripAndLegacyTextSurvives() throws {
        let entry = DictionaryEntry.parse("many | ˈmeni | adjective a large number. ORIGIN Old English manig.",word:"many")
        try checkEqual(entry.pronunciation,"ˈmeni"); try checkEqual(entry.senses.first?.partOfSpeech,"adjective")
        try checkEqual(entry.origin,"Old English manig.")
        let grammar = DictionaryEntry.parse("noun a verb used as a name.",word:"grammar")
        try checkEqual(grammar.senses.count,1); try checkEqual(grammar.senses[0].gloss,"a verb used as a name.")
        try checkEqual(DictionaryEntry.parse(entry.stored,word:"many").plainText,entry.plainText)
        try checkEqual(DictionaryEntry.parse("A saved custom explanation.",word:"example").senses.first?.gloss,"A saved custom explanation.")
    }
    func testReadingModesAndIndependentOffsetsPersist() throws {
        let store = try store(); let imported = try book(store)
        try store.savePosition(imported.id,position:2,offset:120)
        try store.saveReadingMode(imported.id,mode:"pages"); try store.savePageOffset(imported.id,offset:345)
        let reloaded = try LibraryStore(root:store.root).books()[0]
        try checkEqual(reloaded.readingMode,"pages"); try checkEqual(reloaded.pageOffset,345); try checkEqual(reloaded.offset,120)
        try store.saveReadingMode(imported.id,mode:"scroll"); try checkEqual(try store.books()[0].pageOffset,345)
    }
    @MainActor func testPaginationCoversAllTextFitsImagesAndPreservesAnchor() throws {
        let content = NSMutableAttributedString(string:String(repeating:"Many readers enjoy a thoughtful book. ",count:100),attributes:[.font:NSFont.systemFont(ofSize:19)])
        let attachment = NSTextAttachment(); attachment.image = NSImage(size:NSSize(width:1000,height:3000)); attachment.bounds = NSRect(x:0,y:0,width:1000,height:3000)
        content.append(NSAttributedString(attachment:attachment)); content.append(NSAttributedString(string:String(repeating:"The story continues. ",count:50),attributes:[.font:NSFont.systemFont(ofSize:19)]))
        let pages = TextPagination(content:content,size:NSSize(width:420,height:500))
        try checkTrue(pages.ranges.count > 2); try checkEqual(pages.ranges.first?.location,0)
        try checkEqual(NSMaxRange(pages.ranges.last!),content.length)
        for pair in zip(pages.ranges,pages.ranges.dropFirst()) { try checkEqual(NSMaxRange(pair.0),pair.1.location) }
        let anchor = pages.ranges[2].location
        let resized = TextPagination(content:content,size:NSSize(width:600,height:600))
        try checkTrue(NSLocationInRange(anchor,resized.ranges[resized.page(containing:anchor)]))
        try checkEqual(attachment.bounds.height,3000)
        // Attaching only a visible native view must not mutate the container chain.
        let view = NSTextView(frame:.zero,textContainer:pages.containers[1]); view.isEditable = false
        try checkEqual(pages.manager.textContainers.count,pages.ranges.count)
        try checkEqual(view.string,content.string)
    }
}
extension CoreTests {
    func testEPUB2NestedNavigationLabels() throws {
        let root = temporary.appendingPathComponent("Extracted")
        try FileManager.default.createDirectory(at:root.appendingPathComponent("META-INF"),withIntermediateDirectories:true)
        let files = [
            ".complete":"",
            "META-INF/container.xml":#"<container><rootfiles><rootfile full-path="package.opf"/></rootfiles></container>"#,
            "package.opf":#"<package><metadata><title>NCX Book</title></metadata><manifest><item id="a" href="a.xhtml"/><item id="b" href="b.xhtml"/><item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/></manifest><spine><itemref idref="a"/><itemref idref="b"/></spine></package>"#,
            "toc.ncx":#"<ncx><navMap><navPoint><navLabel><text>First chapter</text></navLabel><content src="a.xhtml"/><navPoint><navLabel><text>Nested chapter</text></navLabel><content src="b.xhtml#start"/></navPoint></navPoint></navMap></ncx>"#
        ]
        for (name, text) in files { try Data(text.utf8).write(to:root.appendingPathComponent(name)) }
        let epub = try EPUBBook.open(at:fixture("sample.epub"),extractedTo:root)
        try checkEqual(epub.chapters.map(\.title),["First chapter","Nested chapter"])
    }
}
