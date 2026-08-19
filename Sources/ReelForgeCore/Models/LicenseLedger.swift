import Foundation

public struct LicenseEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: String
    public var source: String
    public var license: String
    public var clipID: String?
    public var credit: String
    public var beatID: String?

    public init(
        id: String,
        kind: String,
        source: String,
        license: String,
        clipID: String? = nil,
        credit: String,
        beatID: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.source = source
        self.license = license
        self.clipID = clipID
        self.credit = credit
        self.beatID = beatID
    }
}

public enum NicheGuard {
    public static func warning(for topic: String) -> String? {
        let lower = topic.lowercased()
        let impersonation = [
            "as a doctor", "i'm a doctor", "i am a doctor", "trust me i'm a doctor",
            "as your doctor", "speaking as a physician",
            "as a lawyer", "i'm a lawyer", "i am a lawyer", "as your attorney",
            "legal advice from a lawyer",
            "financial advisor", "i'm a cfp", "as your advisor", "i am a fiduciary",
            "political analyst", "as a senator", "speaking as a judge",
            "as a political expert"
        ]
        if impersonation.contains(where: { lower.contains($0) }) {
            return "ReelForge will not write a script that impersonates a doctor, lawyer, finance advisor, or political expert. Rephrase as a personal story or a cited explainer."
        }
        return nil
    }
}
