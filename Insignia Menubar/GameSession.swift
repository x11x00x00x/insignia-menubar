//
//  GameSession.swift
//  Insignia Menubar
//
//  Created by Anis360 on 12/6/2025.
//

import Foundation

struct GameSession: Codable {
    let code: String
    let name: String
    let active_users: Int
    let active_sessions: Int
    let online_users: Int
}
