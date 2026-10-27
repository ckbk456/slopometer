import Foundation
import Security
import SlopometerCore

/// A saved token's nonsecret details; the value itself lives only in Keychain.
struct TokenEntry: Codable, Equatable, Identifiable {
    let id: String
    var label: String
    var kind: AccessToken.Kind
    /// The GitHub login that owns the token, from the last check that reached GitHub.
    /// Nonsecret; nil until checked, and cleared when GitHub rejects the token.
    var owner: String?
}

/// GitHub tokens kept in Keychain, one item per token. The list of entries is
/// nonsecret and kept in preferences.
enum TokenStore {
    /// `vn.infinitex.slopometer.github-token` in releases; Debug builds keep their own.
    static let service =
        (Bundle.main.bundleIdentifier ?? "vn.infinitex.slopometer") + ".github-token"
    private static let entriesKey = "tokenEntries"

    static func entries() -> [TokenEntry] {
        guard let data = UserDefaults.standard.data(forKey: entriesKey),
            let saved = try? JSONDecoder().decode([TokenEntry].self, from: data)
        else { return [] }
        return saved
    }

    /// Saved tokens with their values, in the order they were added.
    static func tokens() -> [AccessToken] {
        entries().compactMap { entry in read(entry.id).map { AccessToken(id: entry.id, value: $0) }
        }
    }

    static func add(_ value: String, label: String) -> TokenEntry? {
        let entry = TokenEntry(
            id: UUID().uuidString, label: label, kind: AccessToken.Kind(of: value))
        var item = query(entry.id)
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { return nil }
        persist(entries() + [entry])
        return entry
    }

    /// Remembers each token's owner from a sync; `nil` forgets it (the token was rejected).
    static func setOwners(_ owners: [String: String?]) {
        let updated = entries().map { entry in
            guard let owner = owners[entry.id] else { return entry }
            var changed = entry
            changed.owner = owner
            return changed
        }
        persist(updated)
    }

    /// False when Keychain refused to delete the item; the entry is kept so the token stays
    /// visible and the removal can be tried again.
    static func remove(_ id: String) -> Bool {
        let status = SecItemDelete(query(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { return false }
        persist(entries().filter { $0.id != id })
        return true
    }

    /// Deletes every Keychain item under the service, including any whose entry was lost,
    /// then the entries. False when Keychain refused, leaving items behind.
    static func removeAll() -> Bool {
        let all: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        // The file-based Keychain can delete one match per call, so repeat until none remain.
        for _ in 0..<100 {
            let status = SecItemDelete(all as CFDictionary)
            if status == errSecItemNotFound {
                UserDefaults.standard.removeObject(forKey: entriesKey)
                return true
            }
            guard status == errSecSuccess else { return false }
        }
        return false
    }

    private static func read(_ id: String) -> String? {
        var request = query(id)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func query(_ id: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
        ]
    }

    private static func persist(_ entries: [TokenEntry]) {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: entriesKey)
        }
    }
}
