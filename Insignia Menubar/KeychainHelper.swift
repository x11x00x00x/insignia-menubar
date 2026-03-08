//
//  KeychainHelper.swift
//  Insignia Menubar
//
//  Session storage for Insignia Auth. Uses UserDefaults to avoid Keychain
//  access prompts; data stays in the app sandbox.
//

import Foundation

enum KeychainHelper {
    private static let sessionKeyKey = "InsigniaMenubar.SessionKey"
    private static let usernameKey = "InsigniaMenubar.Username"

    static func saveSession(sessionKey: String, username: String) {
        UserDefaults.standard.set(sessionKey, forKey: sessionKeyKey)
        UserDefaults.standard.set(username, forKey: usernameKey)
    }

    static func getSessionKey() -> String? {
        UserDefaults.standard.string(forKey: sessionKeyKey)
    }

    static func getUsername() -> String? {
        UserDefaults.standard.string(forKey: usernameKey)
    }

    static func clearSession() {
        UserDefaults.standard.removeObject(forKey: sessionKeyKey)
        UserDefaults.standard.removeObject(forKey: usernameKey)
    }

    static var isLoggedIn: Bool {
        getSessionKey() != nil
    }
}
