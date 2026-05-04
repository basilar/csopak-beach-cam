import Foundation
import Security
import SwiftUI

@MainActor
final class WindguruCredentialsStore: ObservableObject {
    static let shared = WindguruCredentialsStore()

    @Published private(set) var username: String = ""
    @Published private(set) var hasPassword: Bool = false

    private static let service = "windguru-pro"
    private static let usernameDefaultsKey = "windguru.username"

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.usernameDefaultsKey) ?? ""
        self.username = stored
        self.hasPassword = (Self.readPassword(account: stored) != nil) && !stored.isEmpty
    }

    func currentCredentials() -> (user: String, password: String)? {
        guard !username.isEmpty,
              let pw = Self.readPassword(account: username),
              !pw.isEmpty
        else { return nil }
        return (username, pw)
    }

    func save(username newUsername: String, password newPassword: String) {
        let trimmedUser = newUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedUser != username, !username.isEmpty {
            Self.deletePassword(account: username)
        }
        UserDefaults.standard.set(trimmedUser, forKey: Self.usernameDefaultsKey)
        username = trimmedUser
        if trimmedUser.isEmpty || newPassword.isEmpty {
            Self.deletePassword(account: trimmedUser)
            hasPassword = false
        } else {
            Self.writePassword(account: trimmedUser, password: newPassword)
            hasPassword = true
        }
    }

    func clear() {
        if !username.isEmpty {
            Self.deletePassword(account: username)
        }
        UserDefaults.standard.removeObject(forKey: Self.usernameDefaultsKey)
        username = ""
        hasPassword = false
    }

    // MARK: - Keychain

    private static func writePassword(account: String, password: String) {
        guard let data = password.data(using: .utf8) else { return }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let attrs: [CFString: Any] = [kSecValueData: data]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private static func readPassword(account: String) -> String? {
        guard !account.isEmpty else { return nil }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deletePassword(account: String) {
        guard !account.isEmpty else { return }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
