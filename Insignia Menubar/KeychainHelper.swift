//
//  KeychainHelper.swift
//  Insignia Menubar
//
//  Persists Insignia session in the Keychain so users stay logged in across app restarts.
//  Migrates existing UserDefaults session to Keychain on first read.
//

import Foundation
import Security

enum KeychainHelper {
    private static let keychainService = "com.xbl.insignia.menubar.session"
    private static let sessionKeyAccount = "sessionKey"
    private static let usernameAccount = "username"

    // Legacy UserDefaults keys (for migration only)
    private static let legacySessionKeyKey = "InsigniaMenubar.SessionKey"
    private static let legacyUsernameKey = "InsigniaMenubar.Username"

    static func saveSession(sessionKey: String, username: String) {
        let sessionData = Data(sessionKey.utf8)
        let usernameData = Data(username.utf8)
        saveToKeychain(account: sessionKeyAccount, data: sessionData)
        saveToKeychain(account: usernameAccount, data: usernameData)
        // Clear legacy storage so we don't have two sources of truth
        UserDefaults.standard.removeObject(forKey: legacySessionKeyKey)
        UserDefaults.standard.removeObject(forKey: legacyUsernameKey)
    }

    static func getSessionKey() -> String? {
        if let key = readFromKeychain(account: sessionKeyAccount) {
            return key
        }
        // Migrate from legacy UserDefaults
        if let legacy = UserDefaults.standard.string(forKey: legacySessionKeyKey) {
            let username = UserDefaults.standard.string(forKey: legacyUsernameKey) ?? ""
            saveSession(sessionKey: legacy, username: username)
            return legacy
        }
        return nil
    }

    static func getUsername() -> String? {
        if let name = readFromKeychain(account: usernameAccount) {
            return name
        }
        // Trigger migration in getSessionKey (copies both to Keychain), then re-read
        _ = getSessionKey()
        return readFromKeychain(account: usernameAccount)
    }

    static func clearSession() {
        deleteFromKeychain(account: sessionKeyAccount)
        deleteFromKeychain(account: usernameAccount)
        UserDefaults.standard.removeObject(forKey: legacySessionKeyKey)
        UserDefaults.standard.removeObject(forKey: legacyUsernameKey)
    }

    static var isLoggedIn: Bool {
        getSessionKey() != nil
    }

    // MARK: - Keychain helpers

    private static func saveToKeychain(account: String, data: Data) {
        deleteFromKeychain(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func readFromKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    private static func deleteFromKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
