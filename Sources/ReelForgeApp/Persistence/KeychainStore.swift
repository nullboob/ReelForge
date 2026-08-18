import Foundation
import Security

enum KeychainStore {
    static let service = "app.reelforge.ReelForge"
    static let unsplashAccount = "unsplash-access-key"
    static let pexelsAccount = "pexels-api-key"
    static let youtubeAccount = "youtube-api-key"

    static func string(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        SecItemAdd(add as CFDictionary, nil)
    }

    static var unsplashAccessKey: String? {
        let env = ProcessInfo.processInfo.environment["REELFORGE_UNSPLASH_ACCESS_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let env, !env.isEmpty { return env }
        let stored = string(account: unsplashAccount)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let stored, !stored.isEmpty { return stored }
        return nil
    }

    static var pexelsAPIKey: String? {
        envOrKeychain("REELFORGE_PEXELS_API_KEY", account: pexelsAccount)
    }

    static var youtubeAPIKey: String? {
        envOrKeychain("REELFORGE_YOUTUBE_API_KEY", account: youtubeAccount)
    }

    private static func envOrKeychain(_ envName: String, account: String) -> String? {
        let env = ProcessInfo.processInfo.environment[envName]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let env, !env.isEmpty { return env }
        let stored = string(account: account)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let stored, !stored.isEmpty { return stored }
        return nil
    }
}
