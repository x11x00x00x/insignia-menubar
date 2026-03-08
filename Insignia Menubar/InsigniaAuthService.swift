//
//  InsigniaAuthService.swift
//  Insignia Menubar
//
//  Login and friends via Insignia Auth API.
//

import Foundation

enum InsigniaAuthService {
    static let defaultAuthAPIURL = "https://auth.insigniastats.live/api"

    static var authAPIURL: String {
        UserDefaults.standard.string(forKey: "InsigniaAuthAPIURL") ?? defaultAuthAPIURL
    }

    /// Login with email and password
    static func login(email: String, password: String, completion: @escaping (Result<(sessionKey: String, username: String), Error>) -> Void) {
        let urlString = "\(authAPIURL)/auth/login"
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "InsigniaAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid auth URL"])))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(LoginRequest(email: email, password: password))

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(NSError(domain: "InsigniaAuth", code: -2, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                return
            }
            do {
                let decoded = try JSONDecoder().decode(LoginResponse.self, from: data)
                if decoded.success == true, let key = decoded.sessionKey, let username = decoded.username ?? decoded.email {
                    completion(.success((key, username)))
                } else {
                    let message = decoded.error ?? "Login failed"
                    completion(.failure(NSError(domain: "InsigniaAuth", code: 401, userInfo: [NSLocalizedDescriptionKey: message])))
                }
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }

    /// Fetch friends list (requires valid session in Keychain)
    static func fetchFriends(completion: @escaping (Result<FriendsResponse, Error>) -> Void) {
        guard let sessionKey = KeychainHelper.getSessionKey() else {
            completion(.failure(NSError(domain: "InsigniaAuth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not logged in"])))
            return
        }
        let urlString = "\(authAPIURL)/auth/friends"
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "InsigniaAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(sessionKey, forHTTPHeaderField: "X-Session-Key")

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                KeychainHelper.clearSession()
                completion(.failure(NSError(domain: "InsigniaAuth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Session expired"])))
                return
            }
            guard let data = data else {
                completion(.failure(NSError(domain: "InsigniaAuth", code: -2, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                return
            }
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let decoded = try decoder.decode(FriendsResponse.self, from: data)
                completion(.success(decoded))
            } catch {
                if let fallback = Self.parseFriendsFallback(data: data) {
                    completion(.success(fallback))
                } else {
                    completion(.failure(error))
                }
            }
        }
        task.resume()
    }

    /// If the API returns a different shape, try to extract a friends array and decode each element.
    private static func parseFriendsFallback(data: Data) -> FriendsResponse? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = json["friends"] as? [[String: Any]] ?? json["friend_list"] as? [[String: Any]]
                ?? (json["data"] as? [String: Any]).flatMap({ $0["friends"] as? [[String: Any]] }) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        var friends: [Friend] = []
        for item in arr {
            guard let itemData = try? JSONSerialization.data(withJSONObject: item),
                  let friend = try? decoder.decode(Friend.self, from: itemData) else { continue }
            friends.append(friend)
        }
        return friends.isEmpty ? nil : FriendsResponse(friends: friends, lastUpdated: nil, count: nil)
    }
}
