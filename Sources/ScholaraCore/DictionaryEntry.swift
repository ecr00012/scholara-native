import Foundation

public struct DictionarySense: Codable, Sendable {
    public var partOfSpeech: String
    public var gloss: String
    public init(partOfSpeech: String = "", gloss: String) { self.partOfSpeech = partOfSpeech; self.gloss = gloss }
}
public struct DictionaryEntry: Codable, Sendable {
    public var word: String
    public var pronunciation: String
    public var origin: String
    public var senses: [DictionarySense]
    public var source: String
    public init(word: String, pronunciation: String = "", origin: String = "", senses: [DictionarySense], source: String = "macOS Dictionary") {
        self.word = word; self.pronunciation = pronunciation; self.origin = origin; self.senses = senses; self.source = source
    }
    public var stored: String { (try? JSONEncoder().encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? plainText }
    public var plainText: String { ([pronunciation] + senses.map { ($0.partOfSpeech.isEmpty ? "" : "\($0.partOfSpeech) · ") + $0.gloss } + [origin.isEmpty ? "" : "Origin: " + origin]).filter { !$0.isEmpty }.joined(separator: "\n") }
    public static func parse(_ raw: String, word: String) -> Self {
        if let decoded = try? JSONDecoder().decode(Self.self, from: Data(raw.utf8)) { return decoded }
        var body = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var pronunciation = "", origin = ""
        if let range = body.range(of: " ORIGIN ") { origin = String(body[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines); body = String(body[..<range.lowerBound]) }
        if let first = body.firstIndex(of: "|"), let second = body[body.index(after: first)...].firstIndex(of: "|") {
            // macOS dictionary entries begin with a headword, then | pronunciation |.
            let prefix = String(body[..<first])
            if prefix.count < 120 { pronunciation = String(body[body.index(after: first)..<second]).trimmingCharacters(in: .whitespaces); body = String(body[body.index(after: second)...]).trimmingCharacters(in: .whitespaces) }
        }
        let pos = "(?:plural noun|singular noun|noun|verb|adjective|adverb|pronoun|determiner|preposition|conjunction|interjection|exclamation|auxiliary verb|modal verb|abbreviation)"
        let pattern = "(?m)^\\s*\\(?" + pos + "(?:, " + pos + ")*\\)?(?=\\s)"
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let ns = body as NSString
        let matches = regex?.matches(in: body, range: NSRange(location: 0, length: ns.length)) ?? []
        var senses: [DictionarySense] = []
        for (index, match) in matches.enumerated() {
            let start = NSMaxRange(match.range); let end = index + 1 < matches.count ? matches[index + 1].range.location : ns.length
            let tag = ns.substring(with: match.range).trimmingCharacters(in: CharacterSet(charactersIn: "() \n\r\t"))
            let gloss = ns.substring(with: NSRange(location: start, length: end-start)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !gloss.isEmpty { senses.append(DictionarySense(partOfSpeech: tag, gloss: gloss)) }
        }
        if senses.isEmpty { senses = [DictionarySense(gloss: body)] }
        return DictionaryEntry(word: word, pronunciation: pronunciation, origin: origin, senses: senses, source: "Dictionary")
    }
}
