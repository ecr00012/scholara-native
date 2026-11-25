import Foundation
import NaturalLanguage
import PDFKit
import CryptoKit
import Accelerate

public struct IndexProgress: Sendable {
    public let done: Int
    public let total: Int
    public var fraction: Double { total > 0 ? Double(done) / Double(total) : 0 }
}
public enum NativeIndex {
    public static func chunks(_ text: String, maximum: Int = 1000, overlap: Int = 140) -> [String] {
        guard maximum > 0, overlap >= 0, overlap < maximum else { return [] }
        let chars = Array(text); var result: [String] = []; var start = 0
        while start < chars.count {
            var end = min(start + maximum, chars.count)
            if end < chars.count, let boundary = (max(start + maximum / 2, start)..<end).last(where: { chars[$0].isWhitespace }) { end = boundary }
            let piece = String(chars[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { result.append(piece) }
            if end == chars.count { break }
            start = max(start + 1, end - overlap)
        }
        return result
    }
    public static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, aa: Float = 0, bb: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count)); vDSP_svesq(a, 1, &aa, vDSP_Length(a.count)); vDSP_svesq(b, 1, &bb, vDSP_Length(b.count))
        return aa > 0 && bb > 0 ? dot / sqrt(aa * bb) : 0
    }
    static func vector(_ text: String, using embedding: NLEmbedding) -> [Float]? {
        // Sentence-level pooling avoids silently truncating long passage inputs.
        let tokenizer = NLTokenizer(unit: .sentence); tokenizer.string = text
        var vectors: [[Double]] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            for part in chunks(String(text[range]), maximum: 500, overlap: 0) {
                if let vector = embedding.vector(for: part) { vectors.append(vector) }
            }
            return true
        }
        guard let first = vectors.first else { return nil }
        var sum = Array(repeating: Float(0), count: first.count)
        for vector in vectors { for i in sum.indices { sum[i] += Float(vector[i]) } }
        let norm = sqrt(sum.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return nil }
        return sum.map { $0 / norm }
    }
    public static func build(book: Book, store: LibraryStore, progress: @escaping @Sendable (IndexProgress) async -> Void) async throws {
        try store.setIndexStatus(book.id, status: "indexing")
        do {
            let pdf = book.format == "pdf" ? PDFDocument(url: URL(fileURLWithPath: book.path)) : nil
            let epub = book.format == "epub" ? try BookImporter.epub(book) : nil
            let count = pdf?.pageCount ?? epub?.chapters.count ?? 0
            guard count > 0 else { throw ScholaraError("No readable pages were found.") }
            var passages: [Passage] = []; var embedding: NLEmbedding?; var language: NLLanguage?
            var hasher = SHA256()
            for index in 0..<count {
                try Task.checkCancellation()
                let text: String = try autoreleasepool {
                    if let pdf { return pdf.page(at: index)?.string ?? "" }
                    return try epub!.attributedChapter(index).string
                }
                hasher.update(data: Data(text.utf8))
                if embedding == nil && text.trimmingCharacters(in: .whitespacesAndNewlines).count > 30 {
                    let recognized = NLLanguageRecognizer.dominantLanguage(for: String(text.prefix(4000))) ?? .english
                    language = recognized; embedding = NLEmbedding.sentenceEmbedding(for: recognized)
                    guard embedding != nil else { throw ScholaraError("macOS has no local sentence embedding model for \(recognized.rawValue). This book remains readable; no text was uploaded.") }
                }
                if let embedding {
                    for chunk in chunks(text) {
                        try Task.checkCancellation()
                        guard let vector = vector(chunk, using: embedding) else { continue }
                        passages.append(Passage(position: index, text: chunk, vector: vector))
                    }
                }
                await progress(IndexProgress(done: index + 1, total: count))
            }
            guard let embedding, let language, !passages.isEmpty else { throw ScholaraError("No extractable text was found. Scanned PDFs need OCR before embedding.") }
            try Task.checkCancellation()
            let model = "apple-sentence:\(language.rawValue):\(embedding.revision):pooled-v1"
            try store.replaceIndex(book.id, passages: passages, model: model, hash: hasher.finalize().map { String(format: "%02x", $0) }.joined())
        } catch {
            try? store.setIndexStatus(book.id, status: error is CancellationError ? "notIndexed" : "failed", error: error is CancellationError ? "Embedding cancelled. You can retry from the book menu." : error.localizedDescription)
            throw error
        }
    }
    public static func search(bookID: Int64, query: String, through position: Int?, store: LibraryStore, limit: Int = 6) throws -> [Passage] {
        let model = try store.indexModel(bookID).split(separator: ":")
        guard model.count == 4, model[0] == "apple-sentence", let revision = Int(model[2]) else { throw ScholaraError("Embed this book to enable Agent Scholar.") }
        let embedding = NLEmbedding.sentenceEmbedding(for: NLLanguage(rawValue: String(model[1])), revision: revision)
        guard let embedding, let queryVector = vector(query, using: embedding) else { throw ScholaraError("The local embedding model is unavailable. Re-embed the book from its menu.") }
        let passages = try store.passages(bookID: bookID, through: position)
        let keyword = try store.keywordIDs(bookID: bookID, query: query, through: position)
        let ranks = Dictionary(uniqueKeysWithValues: keyword.enumerated().map { ($0.element, $0.offset) })
        return passages.map { passage -> (Passage, Float) in
            let semantic = cosine(queryVector, passage.vector)
            let bonus = ranks[passage.id].map { Float(0.3) / Float($0 + 1) } ?? 0
            return (passage, semantic + bonus)
        }.sorted { $0.1 > $1.1 }.prefix(max(0, limit)).map(\.0)
    }
}
