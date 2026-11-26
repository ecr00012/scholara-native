import AppKit

/// Only compact page counts survive indexing; chapter text/layout is released each pass.
public struct BookPagination: Sendable {
    public let chapterCounts: [Int]
    public let chapterStarts: [Int]
    public let total: Int
    public init(chapterCounts: [Int]) {
        self.chapterCounts = chapterCounts.map { max(0, $0) }
        var offset = 0
        chapterStarts = self.chapterCounts.map { count in defer { offset += count }; return offset }
        total = offset
    }
    public func page(chapter: Int, localPage: Int) -> Int {
        guard chapterCounts.indices.contains(chapter), total > 0 else { return 0 }
        return min(total, chapterStarts[chapter] + min(max(0, localPage), max(0, chapterCounts[chapter] - 1)) + 1)
    }
    /// Run off the UI thread with a separate TextKit graph for every chapter.
    public static func build(book: EPUBBook, size: NSSize, fontSize: CGFloat, fontFamily: ReaderFont) throws -> BookPagination {
        var counts: [Int] = []
        for chapter in book.chapters {
            try Task.checkCancellation()
            let count: Int = try autoreleasepool {
                let text = try book.attributedChapter(chapter.id, fontSize: fontSize, fontFamily: fontFamily)
                guard !text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return 0 }
                return TextPagination(content: text, size: size).ranges.count
            }
            counts.append(count)
        }
        return BookPagination(chapterCounts: counts)
    }
}
