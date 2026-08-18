import Foundation

public enum ScriptSource: String, Codable, Sendable {
    case ollama
    case template
    case user
}

public struct GeneratedScript: Codable, Equatable, Sendable {
    public var hook: String
    public var body: [String]
    public var cta: String
    public var source: ScriptSource

    public init(hook: String, body: [String], cta: String, source: ScriptSource) {
        self.hook = hook
        self.body = body
        self.cta = cta
        self.source = source
    }

    public var fullText: String {
        ([hook] + body + [cta])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    public var spokenLines: [String] {
        ([hook] + body + [cta]).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
