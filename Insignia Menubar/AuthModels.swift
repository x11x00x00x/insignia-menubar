//
//  AuthModels.swift
//  Insignia Menubar
//
//  Models for Insignia Auth API (login, friends).
//

import Foundation

struct LoginRequest: Encodable {
    let email: String
    let password: String
}

struct LoginResponse: Decodable {
    let success: Bool?
    let sessionKey: String?
    let username: String?
    let email: String?
    let error: String?
}

struct Friend: Decodable {
    let gamertag: String?
    /// API may return "username" or "name" instead of "gamertag"; we use displayName for UI and identity.
    let username: String?
    let name: String?
    let status: String?
    let isOnline: Bool?
    /// Some API responses use "online" instead of "isOnline"; we treat either as online for display.
    let online: Bool?
    let game: String?
    let duration: String?
    let lastSeen: String?

    var displayName: String {
        let raw = (gamertag ?? username ?? name ?? "").trimmingCharacters(in: .whitespaces)
        return raw.isEmpty ? "—" : raw
    }

    var isCurrentlyOnline: Bool {
        isOnline == true || online == true
    }
}

struct FriendsResponse: Decodable {
    let friends: [Friend]?
    let lastUpdated: String?
    let count: Int?
}
