import Foundation

public enum AnnotationAnchor {
    /// Prefer the recorded UTF-16 range to distinguish repeated quotations.
    /// Older imports without a native range fall back to a textual match.
    public static func range(quote: String, anchor: String, in text: String) -> NSRange? {
        guard !quote.isEmpty else { return nil }
        let content = text as NSString
        if let json = (try? JSONSerialization.jsonObject(with: Data(anchor.utf8))) as? [String: Any],
           let location = json["location"] as? Int, let length = json["length"] as? Int,
           location >= 0, length > 0, location <= content.length, length <= content.length - location {
            let range = NSRange(location: location, length: length)
            if content.substring(with: range) == quote { return range }
        }
        let range = content.range(of: quote)
        return range.location == NSNotFound ? nil : range
    }
}
