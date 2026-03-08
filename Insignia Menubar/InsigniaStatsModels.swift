//
//  InsigniaStatsModels.swift
//  Insignia Menubar
//
//  Models for Insignia Stats API (e.g. /api/online-users).
//

import Foundation

/// One game entry from GET /api/online-users
struct GameInfo: Codable {
    let name: String
    let online: Int
    let titleId: String?
    let image: String?
    let publisher: String?
    let activeLobbies: Int?
    let hasActiveSession: Bool?
    let sessionCount: Int?
    let activeLobbyPlayers: Int?
    /// Display names of current lobby hosts (when available from match DB).
    let lobbyHostNames: [String]?
}

/// Response is a dictionary keyed by game name
typealias OnlineUsersResponse = [String: GameInfo]

/// Response from GET /api/me/play-time?username=...
struct PlayTimeResponse: Codable {
    let totalMinutes: Double?
    let byGame: [String: Double]?
    let lastState: String?
    let currentGame: String?
}

/// One event from GET /api/events (event_date YYYY-MM-DD, start_time/end_time optional)
struct EventInfo: Codable {
    let id: Int?
    let title: String?
    let event_date: String?
    let start_time: String?
    let end_time: String?
    let game_name: String?
    let title_id: String?
}
