//
//  InsigniaStatsService.swift
//  Insignia Menubar
//
//  Fetches game data from Insignia Stats API (e.g. /api/online-users).
//

import Foundation

enum InsigniaStatsService {
    /// Default Insignia Stats base URL (no trailing slash)
    static let defaultBaseURL = "https://xb.live"

    static var baseURL: String {
        UserDefaults.standard.string(forKey: "InsigniaStatsBaseURL") ?? defaultBaseURL
    }

    static func setBaseURL(_ url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/$", with: "", options: .regularExpression)
        UserDefaults.standard.set(trimmed.isEmpty ? defaultBaseURL : trimmed, forKey: "InsigniaStatsBaseURL")
    }

    /// Fetch current online users per game from Insignia Stats API
    static func fetchOnlineUsers(completion: @escaping (Result<OnlineUsersResponse, Error>) -> Void) {
        let urlString = "\(baseURL)/api/online-users"
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "InsigniaStats", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(NSError(domain: "InsigniaStats", code: -2, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                return
            }
            do {
                let decoded = try JSONDecoder().decode(OnlineUsersResponse.self, from: data)
                completion(.success(decoded))
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }

    /// Fetch logged-in user's total time online from Insignia Stats (GET /api/me/play-time).
    static func fetchPlayTime(username: String, completion: @escaping (Result<PlayTimeResponse, Error>) -> Void) {
        guard let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            completion(.failure(NSError(domain: "InsigniaStats", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid username"])))
            return
        }
        let urlString = "\(baseURL)/api/me/play-time?username=\(encoded)"
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "InsigniaStats", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(NSError(domain: "InsigniaStats", code: -2, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                return
            }
            do {
                let decoded = try JSONDecoder().decode(PlayTimeResponse.self, from: data)
                completion(.success(decoded))
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }

    /// Fetch logged-in user's live presence (online + current game) for Discord Rich Presence.
    /// POST /api/me/profile-live with sessionKey; server returns isOnline and game name.
    static func fetchProfileLive(sessionKey: String, completion: @escaping (Result<ProfileLiveResponse, Error>) -> Void) {
        let urlString = "\(baseURL)/api/me/profile-live"
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "InsigniaStats", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["sessionKey": sessionKey]
        request.httpBody = (try? JSONEncoder().encode(body)) ?? Data()

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                completion(.failure(NSError(domain: "InsigniaStats", code: 401, userInfo: [NSLocalizedDescriptionKey: "Session expired"])))
                return
            }
            guard let data = data else {
                completion(.failure(NSError(domain: "InsigniaStats", code: -2, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                return
            }
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let decoded = try decoder.decode(ProfileLiveResponse.self, from: data)
                completion(.success(decoded))
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }

    /// Fetch events from Insignia Stats API (GET /api/events)
    static func fetchEvents(completion: @escaping (Result<[EventInfo], Error>) -> Void) {
        let urlString = "\(baseURL)/api/events"
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "InsigniaStats", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(NSError(domain: "InsigniaStats", code: -2, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                return
            }
            do {
                let decoded = try JSONDecoder().decode([EventInfo].self, from: data)
                completion(.success(decoded))
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }
}
