import Foundation
import AppKit
import PDFKit
import ZIPFoundation
import CryptoKit

public struct Chapter: Identifiable, Sendable {
    public let id: Int
    public let title: String
    public let path: String
}
public struct EPUBBook: Sendable {
    public let title: String
    public let author: String
    public let chapters: [Chapter]
    public let cover: String
    public let root: URL
    public static func open(at source: URL, extractedTo destination: URL) throws -> EPUBBook {
        if !FileManager.default.fileExists(atPath: destination.appendingPathComponent(".complete").path) {
            try extract(source, to: destination)
        }
        let container = XMLTreeParser()
        try container.parse(Data(contentsOf: destination.appendingPathComponent("META-INF/container.xml")))
        guard let package = container.elements.first(where: { $0.name == "rootfile" })?.attributes["full-path"] else { throw ScholaraError("The EPUB has no package document.") }
        let packageURL = try containedURL(package, relativeTo: destination, root: destination)
        let parser = XMLTreeParser(); try parser.parse(Data(contentsOf: packageURL))
        let base = packageURL.deletingLastPathComponent()
        let items = parser.elements.filter { $0.name == "item" }
        var chapters: [Chapter] = []
        for ref in parser.elements.filter({ $0.name == "itemref" && $0.attributes["linear"] != "no" }) {
            guard let item = items.first(where: { $0.attributes["id"] == ref.attributes["idref"] }), let href = item.attributes["href"] else { continue }
            let url = try containedURL(href, relativeTo: base, root: destination)
            let title = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ")
            chapters.append(Chapter(id: chapters.count, title: title, path: url.path))
        }
        guard !chapters.isEmpty else { throw ScholaraError("The EPUB has no readable chapters. DRM-protected books are not supported.") }
        // EPUB3 navigation labels and EPUB2 NCX are both used without a browser.
        var labels: [String: String] = [:]
        if let nav = items.first(where: { ($0.attributes["properties"] ?? "").split(separator: " ").contains("nav") }), let href = nav.attributes["href"] {
            let navURL = try containedURL(href, relativeTo: base, root: destination)
            let navParser = XMLTreeParser(); try navParser.parse(Data(contentsOf: navURL))
            for link in navParser.elements where link.name == "a" {
                if let href = link.attributes["href"], let url = try? containedURL(href, relativeTo: navURL.deletingLastPathComponent(), root: destination) { labels[url.path] = link.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        }
        if let ncx = items.first(where: { $0.attributes["media-type"] == "application/x-dtbncx+xml" }), let href = ncx.attributes["href"] {
            let url = try containedURL(href, relativeTo: base, root: destination)
            let navigation = NCXParser(); try navigation.parse(Data(contentsOf: url))
            for (href, label) in navigation.labels {
                if let target = try? containedURL(href, relativeTo: url.deletingLastPathComponent(), root: destination), labels[target.path] == nil { labels[target.path] = label }
            }
        }
        let coverID = parser.elements.first { $0.name == "meta" && $0.attributes["name"] == "cover" }?.attributes["content"]
        let coverItem = items.first { ($0.attributes["properties"] ?? "").contains("cover-image") || (coverID != nil && $0.attributes["id"] == coverID) }
        let cover = try coverItem?.attributes["href"].map { try containedURL($0, relativeTo: base, root: destination).path } ?? ""
        // Prefer navigation labels, then semantic front matter and actual headings.
        // Keep spine IDs stable so existing notes and reading positions stay valid.
        chapters = chapters.map { chapter in
            let title = labels[chapter.path]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !title.isEmpty { return Chapter(id: chapter.id, title: title, path: chapter.path) }
            let document = XMLTreeParser()
            if let data = try? Data(contentsOf: URL(fileURLWithPath: chapter.path)), (try? document.parse(data)) != nil {
                let isCover = document.elements.contains { element in
                    guard ["img", "image"].contains(element.name), let href = element.attributes["src"] ?? element.attributes["href"] ?? element.attributes["xlink:href"],
                          let url = try? containedURL(href, relativeTo: URL(fileURLWithPath: chapter.path).deletingLastPathComponent(), root: destination) else { return false }
                    return !cover.isEmpty && url.path == cover
                }
                let semantic = document.elements.compactMap { $0.attributes["epub:type"] }.joined(separator: " ").split(separator: " ")
                let heading = document.elements.first { ["h1", "h2", "h3"].contains($0.name) && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?.text
                let label = isCover || semantic.contains("cover") ? "Cover" : semantic.contains("titlepage") ? "Title Page" : heading
                if let label { return Chapter(id: chapter.id, title: label.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines), path: chapter.path) }
            }
            return Chapter(id: chapter.id, title: "Section \(chapter.id + 1)", path: chapter.path)
        }
        return EPUBBook(title: parser.elements.first { $0.name == "title" }?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? "", author: parser.elements.first { $0.name == "creator" }?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? "", chapters: chapters, cover: cover, root: destination)
    }
    public static func renderXHTML(_ data: Data, base: URL, root: URL, fontSize: CGFloat = 19, fontFamily: ReaderFont = .serif) throws -> NSAttributedString {
        let parser = NativeHTMLParser(base: base, root: root, fontSize: fontSize, fontFamily: fontFamily)
        try parser.parse(data)
        return parser.output
    }
    public func attributedChapter(_ index: Int, fontSize: CGFloat = 19, fontFamily: ReaderFont = .serif) throws -> NSAttributedString {
        guard chapters.indices.contains(index) else { throw ScholaraError("Chapter is out of range.") }
        let url = URL(fileURLWithPath: chapters[index].path)
        let parser = NativeHTMLParser(base: url.deletingLastPathComponent(), root: root, fontSize: fontSize, fontFamily: fontFamily)
        try parser.parse(Data(contentsOf: url))
        return parser.output
    }
    /// Skip truly empty spine sections without renumbering chapters or annotations.
    public func readableChapter(startingAt index: Int, direction: Int = 1, fontSize: CGFloat = 19, fontFamily: ReaderFont = .serif) throws -> (index: Int, text: NSAttributedString) {
        guard chapters.indices.contains(index) else { throw ScholaraError("Chapter is out of range.") }
        var candidate = index
        let step = direction < 0 ? -1 : 1
        while chapters.indices.contains(candidate) {
            let text = try attributedChapter(candidate, fontSize: fontSize, fontFamily: fontFamily)
            if !text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return (candidate, text) }
            candidate += step
        }
        // A trailing blank should lead to the previous readable section, not an empty screen.
        candidate = index - step
        while chapters.indices.contains(candidate) {
            let text = try attributedChapter(candidate, fontSize: fontSize, fontFamily: fontFamily)
            if !text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return (candidate, text) }
            candidate -= step
        }
        throw ScholaraError("This EPUB has no displayable text or cover images.")
    }
    public static func containedURL(_ path: String, relativeTo base: URL, root: URL) throws -> URL {
        let clean = String(path.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]).removingPercentEncoding ?? path
        guard !clean.contains("://"), !clean.hasPrefix("/"), !clean.contains("\0") else { throw ScholaraError("The EPUB contains an unsafe resource path.") }
        let url = base.appendingPathComponent(clean).standardizedFileURL
        guard url.path.hasPrefix(root.standardizedFileURL.path + "/") else { throw ScholaraError("The EPUB resource escapes its book folder.") }
        return url
    }
    private static func extract(_ source: URL, to destination: URL) throws {
        let archive = try Archive(url: source, accessMode: .read)
        var size: UInt64 = 0; var count = 0
        for entry in archive {
            count += 1; size += UInt64(entry.uncompressedSize)
            guard count <= 20000, size <= 1_073_741_824, entry.type != .symlink else { throw ScholaraError("This EPUB exceeds safe archive limits or contains symbolic links.") }
            _ = try containedURL(entry.path, relativeTo: destination, root: destination)
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        do {
            for entry in archive {
                let url = try containedURL(entry.path, relativeTo: destination, root: destination)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                _ = try archive.extract(entry, to: url)
            }
            try Data().write(to: destination.appendingPathComponent(".complete"))
        } catch { try? FileManager.default.removeItem(at: destination); throw error }
    }
}

struct XMLElementValue {
    var name: String
    var attributes: [String: String]
    var text: String = ""
}
final class XMLTreeParser: NSObject, XMLParserDelegate {
    var elements: [XMLElementValue] = []
    var stack: [XMLElementValue] = []
    func parse(_ data: Data) throws {
        let parser = XMLParser(data: data); parser.shouldResolveExternalEntities = false; parser.delegate = self
        guard parser.parse() else { throw ScholaraError("Could not read EPUB XML: \(parser.parserError?.localizedDescription ?? "invalid document")") }
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) { stack.append(XMLElementValue(name: elementName.components(separatedBy: ":").last!, attributes: attributeDict)) }
    func parser(_ parser: XMLParser, foundCharacters string: String) { for index in stack.indices { stack[index].text += string } }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { if let value = stack.popLast() { elements.append(value) } }
}

/// Native attributed text, with no HTML importer (which would load WebKit).
final class NativeHTMLParser: NSObject, XMLParserDelegate {
    let output = NSMutableAttributedString(string: "")
    let base: URL; let root: URL; let fontSize: CGFloat; let fontFamily: ReaderFont
    var tags: [String] = []
    var links: [String?] = []
    var preformatted = false
    init(base: URL, root: URL, fontSize: CGFloat, fontFamily: ReaderFont) { self.base = base; self.root = root; self.fontSize = fontSize; self.fontFamily = fontFamily }
    func parse(_ data: Data) throws {
        let parser = XMLParser(data: data); parser.shouldResolveExternalEntities = false; parser.delegate = self
        guard parser.parse() else { throw ScholaraError("This chapter is not valid EPUB XHTML: \(parser.parserError?.localizedDescription ?? "invalid markup")") }
    }
    var hidden: Bool { tags.contains(where: { ["head", "script", "style", "svg"].contains($0) }) }
    func breakLine() { if output.length > 0 && !output.string.hasSuffix("\n") { output.append(NSAttributedString(string: "\n")) } }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attrs: [String: String]) {
        let tag = elementName.components(separatedBy: ":").last!.lowercased(); tags.append(tag); links.append(attrs["href"])
        // Many EPUB covers wrap a raster image in SVG. Load only local images;
        // vector scripts and SVG text remain excluded from the native renderer.
        if tag == "image", tags.contains("svg"), !tags.contains(where: { ["head", "script", "style"].contains($0) }), let path = attrs["href"] ?? attrs["xlink:href"] { appendImage(path) }
        if hidden { return }
        if ["p", "div", "section", "h1", "h2", "h3", "h4", "blockquote", "li", "tr", "br"].contains(tag) { breakLine() }
        if tag == "li" { append("• ") }
        if tag == "td" || tag == "th" { append("\t") }
        if tag == "img", let path = attrs["src"] { appendImage(path) }
    }
    private func appendImage(_ path: String) {
        guard let url = try? EPUBBook.containedURL(path, relativeTo: base, root: root), let image = NSImage(contentsOf: url) else { return }
        breakLine()
        let attachment = NSTextAttachment(); let scale = min(1, 620 / max(1, image.size.width))
        attachment.image = image; attachment.bounds = NSRect(x: 0, y: 0, width: image.size.width * scale, height: image.size.height * scale)
        let imageText = NSMutableAttributedString(attachment: attachment)
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        imageText.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: imageText.length))
        output.append(imageText); breakLine()
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard !hidden else { return }
        let text = tags.contains("pre") ? string : string.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if (output.length == 0 || output.string.hasSuffix("\n") || output.string.hasSuffix(" ")) && text.hasPrefix(" ") { append(String(text.dropFirst())) } else { append(text) }
    }
    func append(_ string: String) {
        var size = fontSize
        if tags.contains("h1") { size *= 1.65 } else if tags.contains("h2") { size *= 1.4 } else if tags.contains("h3") { size *= 1.2 }
        var font = fontFamily.font(size: size)
        if tags.contains(where: { ["b", "strong", "h1", "h2", "h3", "h4", "th"].contains($0) }) { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
        if tags.contains("i") || tags.contains("em") { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        if tags.contains("code") || tags.contains("pre") { font = .monospacedSystemFont(ofSize: fontSize * 0.85, weight: .regular) }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 6; paragraph.paragraphSpacing = 14
        if tags.contains("blockquote") { paragraph.headIndent = 24; paragraph.firstLineHeadIndent = 24 }
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
        if let href = links.compactMap({ $0 }).last {
            if let url = URL(string: href), ["http", "https", "mailto"].contains(url.scheme ?? "") { attrs[.link] = url }
            else if let url = try? EPUBBook.containedURL(href, relativeTo: base, root: root) { attrs[.link] = url }
        }
        output.append(NSAttributedString(string: string, attributes: attrs))
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let tag = tags.last ?? ""
        if !hidden && ["p", "div", "section", "h1", "h2", "h3", "h4", "blockquote", "li", "tr"].contains(tag) { breakLine() }
        _ = tags.popLast(); _ = links.popLast()
    }
}

public enum BookImporter {
    public static func importFile(_ source: URL, store: LibraryStore) throws -> Book {
        let type = source.pathExtension.lowercased()
        guard ["pdf", "epub"].contains(type) else { throw ScholaraError("Choose a PDF or EPUB book.") }
        let folder = store.root.appendingPathComponent("Books").appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(source.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: source, to: file)
            var title = source.deletingPathExtension().lastPathComponent; var author = ""; var cover = ""
            if type == "pdf" {
                guard let pdf = PDFDocument(url: file), !pdf.isLocked, pdf.pageCount > 0 else { throw ScholaraError("This PDF is damaged or password protected. Import an unlocked copy.") }
                if let value = pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String, !value.isEmpty { title = value }
                author = pdf.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String ?? ""
                if let page = pdf.page(at: 0), let tiff = page.thumbnail(of: NSSize(width: 240, height: 340), for: .cropBox).tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
                    let url = folder.appendingPathComponent("cover.png"); try png.write(to: url); cover = url.path
                }
            } else {
                let epub = try EPUBBook.open(at: file, extractedTo: folder.appendingPathComponent("EPUB"))
                if !epub.title.isEmpty { title = epub.title }; author = epub.author; cover = epub.cover
            }
            return try store.addBook(title: title, author: author, path: file.path, format: type, cover: cover)
        } catch { try? FileManager.default.removeItem(at: folder); throw error }
    }
    public static func epub(_ book: Book) throws -> EPUBBook {
        let file = URL(fileURLWithPath: book.path)
        return try EPUBBook.open(at: file, extractedTo: file.deletingLastPathComponent().appendingPathComponent("EPUB"))
    }
}

/// EPUB 2 navigation points can be nested; each label belongs to its own point.
final class NCXParser: NSObject, XMLParserDelegate {
    var labels: [(String, String)] = []
    private var points: [(href: String, label: String)] = []
    private var inText = false
    func parse(_ data: Data) throws {
        let parser = XMLParser(data: data); parser.shouldResolveExternalEntities = false; parser.delegate = self
        guard parser.parse() else { throw ScholaraError("Could not read the EPUB table of contents.") }
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String:String]) {
        let name = name.components(separatedBy: ":").last!
        if name == "navPoint" { points.append(("", "")) }
        if name == "text" { inText = true }
        if name == "content", !points.isEmpty { points[points.count-1].href = attributes["src"] ?? "" }
    }
    func parser(_ parser: XMLParser, foundCharacters text: String) { if inText, !points.isEmpty { points[points.count-1].label += text } }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let name = name.components(separatedBy: ":").last!
        if name == "text" { inText = false }
        if name == "navPoint", let point = points.popLast(), !point.href.isEmpty { labels.append((point.href, point.label.trimmingCharacters(in: .whitespacesAndNewlines))) }
    }
}
