//
//  DiscordPresenceManager.swift
//  Insignia Menubar
//
//  Periodically fetches profile-live and updates Discord Rich Presence (same logic as XBLBeacon).
//

import Foundation

private let checkIntervalActive: TimeInterval = 120   // 2 min when user is online
private let checkIntervalIdle: TimeInterval = 300    // 5 min when user is offline

enum DiscordPresenceManager {
    private static var workItem: DispatchWorkItem?
    private static let queue = DispatchQueue(label: "com.insignia.discordpresence")

    static func startChecking() {
        queue.async {
            workItem?.cancel()
            workItem = nil
            // Give Discord a moment to be "ready" after connect (like XBLBeacon's ready + setTimeout 1s)
            queue.asyncAfter(deadline: .now() + 1.0) {
                checkAndUpdatePresence()
                scheduleNext()
            }
        }
    }

    static func stopChecking() {
        queue.async {
            workItem?.cancel()
            workItem = nil
        }
        if DiscordRPCService.connected {
            _ = DiscordRPCService.clearActivity()
        }
        DiscordPresenceStore.presenceActive = false
        DiscordPresenceStore.presenceStartTimestamp = nil
        DiscordPresenceStore.lastGameName = nil
    }

    private static func scheduleNext() {
        workItem?.cancel()
        let interval = DiscordPresenceStore.presenceActive ? checkIntervalActive : checkIntervalIdle
        let item = DispatchWorkItem {
            if DiscordRPCService.connected, KeychainHelper.getSessionKey() != nil {
                checkAndUpdatePresence()
            }
            scheduleNext()
        }
        workItem = item
        queue.asyncAfter(deadline: .now() + interval, execute: item)
    }

    static func checkAndUpdatePresence() {
        guard let sessionKey = KeychainHelper.getSessionKey(),
              let username = KeychainHelper.getUsername(), !username.isEmpty,
              DiscordRPCService.connected else {
            clearPresence()
            return
        }

        InsigniaStatsService.fetchProfileLive(sessionKey: sessionKey) { result in
            switch result {
            case .success(let profile):
                let isOnline = profile.isOnline ?? false
                let gameName = (profile.game?.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 }

                if isOnline {
                    let wasActive = DiscordPresenceStore.presenceActive
                    let setNewTimestamp = !wasActive
                    updatePresence(username: username, gameName: gameName, setNewTimestamp: setNewTimestamp)
                } else {
                    clearPresence()
                }
            case .failure:
                clearPresence()
            }
        }
    }

    private static func updatePresence(username: String, gameName: String?, setNewTimestamp: Bool) {
        guard DiscordRPCService.connected else { return }

        var startTimestamp = DiscordPresenceStore.presenceStartTimestamp
        if setNewTimestamp || startTimestamp == nil {
            startTimestamp = Date()
            DiscordPresenceStore.presenceStartTimestamp = startTimestamp
        }
        guard let start = startTimestamp else { return }

        let gameDisplay = (gameName?.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? "OG Xbox" : $0 } ?? "OG Xbox"
        let details = gameName != nil && !(gameName?.isEmpty ?? true) ? "Playing \(gameName!)" : "Online on xb.live"
        let state = "Online as \(username)"

        let success = DiscordRPCService.setActivity(
            details: details,
            state: state,
            startTimestamp: start,
            largeImageKey: "logo",
            largeImageText: gameDisplay,
            smallImageKey: "online",
            smallImageText: "xb.live"
        )
        if success {
            DiscordPresenceStore.presenceActive = true
            DiscordPresenceStore.lastCheck = ISO8601DateFormatter().string(from: Date())
            DiscordPresenceStore.lastGameName = gameName
        }
    }

    private static func clearPresence() {
        if DiscordRPCService.connected {
            _ = DiscordRPCService.clearActivity()
        }
        DiscordPresenceStore.presenceActive = false
        DiscordPresenceStore.presenceStartTimestamp = nil
        DiscordPresenceStore.lastGameName = nil
    }
}
