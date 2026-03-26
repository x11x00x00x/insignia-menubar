//
//  DiscordPresenceStore.swift
//  Insignia Menubar
//
//  Persists Discord connection and presence state (mirrors XBLBeacon store keys).
//

import Foundation

enum DiscordPresenceStore {
    private static let discordUserKey = "InsigniaMenubar.DiscordUser"
    private static let presenceActiveKey = "InsigniaMenubar.DiscordPresenceActive"
    private static let presenceStartTimestampKey = "InsigniaMenubar.DiscordPresenceStartTimestamp"
    private static let lastGameNameKey = "InsigniaMenubar.DiscordLastGameName"
    private static let lastCheckKey = "InsigniaMenubar.DiscordLastCheck"

    static var discordUser: DiscordUser? {
        get {
            guard let data = UserDefaults.standard.data(forKey: discordUserKey),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                  let username = dict["username"],
                  let id = dict["id"] else { return nil }
            return DiscordUser(username: username, id: id)
        }
        set {
            if let u = newValue {
                let dict = ["username": u.username, "id": u.id]
                if let data = try? JSONSerialization.data(withJSONObject: dict) {
                    UserDefaults.standard.set(data, forKey: discordUserKey)
                }
            } else {
                UserDefaults.standard.removeObject(forKey: discordUserKey)
            }
        }
    }

    static var presenceActive: Bool {
        get { UserDefaults.standard.bool(forKey: presenceActiveKey) }
        set { UserDefaults.standard.set(newValue, forKey: presenceActiveKey) }
    }

    static var presenceStartTimestamp: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: presenceStartTimestampKey)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set {
            if let d = newValue {
                UserDefaults.standard.set(d.timeIntervalSince1970, forKey: presenceStartTimestampKey)
            } else {
                UserDefaults.standard.removeObject(forKey: presenceStartTimestampKey)
            }
        }
    }

    static var lastGameName: String? {
        get { UserDefaults.standard.string(forKey: lastGameNameKey) }
        set {
            if let s = newValue { UserDefaults.standard.set(s, forKey: lastGameNameKey) }
            else { UserDefaults.standard.removeObject(forKey: lastGameNameKey) }
        }
    }

    static var lastCheck: String? {
        get { UserDefaults.standard.string(forKey: lastCheckKey) }
        set {
            if let s = newValue { UserDefaults.standard.set(s, forKey: lastCheckKey) }
            else { UserDefaults.standard.removeObject(forKey: lastCheckKey) }
        }
    }

    static func clearOnLogout() {
        discordUser = nil
        presenceActive = false
        presenceStartTimestamp = nil
        lastGameName = nil
        lastCheck = nil
    }
}
