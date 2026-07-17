import Foundation
import Security

// MARK: - KeychainHelper

/// Thin wrapper around Security framework generic password operations.
/// Service identifier: "com.scoot.app"
enum KeychainHelper {
    private static let service = "com.scoot.app"

    // MARK: Write

    /// Saves (or updates) a string value in the keychain.
    @discardableResult
    static func set(_ value: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Try to update an existing item first.
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let attributes: [CFString: Any] = [kSecValueData: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecSuccess {
            return true
        }

        // If not found, add a new item.
        var addQuery = query
        addQuery[kSecValueData] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        return addStatus == errSecSuccess
    }

    // MARK: Read

    /// Returns the stored string for the given account, or nil if not found.
    static func get(account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    // MARK: Delete

    /// Removes the keychain entry for the given account. Returns true if deleted or not found.
    @discardableResult
    static func delete(account: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
