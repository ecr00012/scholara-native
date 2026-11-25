import Foundation

public struct ScholaraError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct Book: Identifiable, Hashable, Sendable {
    public let id: Int64
    public var title: String
    public var author: String
    public let path: String
    public let format: String
    public var position: Int
    public var offset: Int
    public var indexStatus: String
    public var indexError: String
    public var readerOnly: Bool
    public var lastOpened: String
    public var coverPath: String
    public var readingMode: String
    public var pageOffset: Int
}

public struct Note: Identifiable, Sendable {
    public let id: Int64
    public let bookID: Int64
    public let position: Int
    public let quote: String
    public let text: String
    public let anchor: String
}
public struct Vocabulary: Identifiable, Sendable {
    public let id: Int64
    public let bookID: Int64
    public let word: String
    public let definition: String
}
public struct Conversation: Identifiable, Sendable {
    public let id: Int64
    public let bookID: Int64
    public let title: String
    public let model: String
    public let spoilerMode: Bool
}
public struct Message: Identifiable, Sendable {
    public let id: Int64
    public let role: String
    public let text: String
}
public struct Passage: Identifiable, Sendable {
    public let id: Int64
    public let position: Int
    public let text: String
    public let vector: [Float]
    public init(id: Int64 = 0, position: Int, text: String, vector: [Float] = []) {
        self.id = id; self.position = position; self.text = text; self.vector = vector
    }
}
public struct ModelOption: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var supportsTools: Bool
    public init(id: String, name: String, supportsTools: Bool = true) {
        self.id = id; self.name = name; self.supportsTools = supportsTools
    }
}
public struct ModelConfiguration: Codable, Sendable {
    public var selectedModel: String
    public var models: [ModelOption]
    public static let initial = ModelConfiguration(selectedModel: "openrouter/auto", models: [
        ModelOption(id: "openrouter/auto", name: "OpenRouter Auto"),
        ModelOption(id: "openai/gpt-oss-120b:free", name: "GPT OSS 120B (free)")
    ])
    public init(selectedModel: String, models: [ModelOption]) { self.selectedModel = selectedModel; self.models = models }
    public func validated() throws -> Self {
        guard !models.isEmpty else { throw ScholaraError("Add at least one model.") }
        guard Set(models.map(\.id)).count == models.count else { throw ScholaraError("Model paths must be unique.") }
        for model in models {
            guard Self.validPath(model.id), !model.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ScholaraError("Enter a label and an OpenRouter path such as provider/model-name.")
            }
        }
        guard models.contains(where: { $0.id == selectedModel }) else { throw ScholaraError("Choose a default model from your configuration.") }
        return self
    }
    public static func validPath(_ value: String) -> Bool {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count >= 2 && parts.allSatisfy { !$0.isEmpty } && !value.contains(where: { $0.isWhitespace || $0.isNewline }) && !value.contains("://")
    }
    public static func load(from url: URL) throws -> Self {
        if !FileManager.default.fileExists(atPath: url.path) { try initial.save(to: url); return initial }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url)).validated()
    }
    public func save(to url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(validated()).write(to: url, options: .atomic)
    }
}
