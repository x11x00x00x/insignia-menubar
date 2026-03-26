//
//  NotificationSettingsStore.swift
//  Insignia Menubar
//
//  Persists which games to notify for and which time-of-day windows to use.
//

import Foundation

/// Session start time (set at app launch). Used for "time online this session".
enum AppSession {
    static var sessionStartDate: Date?
}

/// One time range: notify only between start and end.
/// Minutes since midnight (0–1439) in the device's **local** time zone.
struct NotificationTimeRange: Codable, Equatable {
    var startMinutes: Int  // 0–1439
    var endMinutes: Int   // 0–1439
}

enum NotificationSettingsStore {
    static let refreshIntervalDidChangeNotification = Notification.Name("InsigniaMenubarRefreshIntervalDidChange")
    private static let gamesKey = "notification_games"
    private static let timeRangesKey = "notification_time_ranges"
    private static let notifyFriendsKey = "notification_friends_online"
    private static let notifyEventsKey = "notification_events"
    private static let refreshIntervalKey = "settings_refresh_interval_minutes"
    private static let totalTimeOnlineKey = "settings_total_time_online_seconds"
    private static let launchAtLoginKey = "settings_launch_at_login"

    /// When true, open the app when the user logs in (stored preference; actual registration via LaunchAtLogin).
    static var launchAtLogin: Bool {
        get {
            if UserDefaults.standard.object(forKey: launchAtLoginKey) == nil { return false }
            return UserDefaults.standard.bool(forKey: launchAtLoginKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: launchAtLoginKey) }
    }

    /// When true, show a notification when a friend comes online.
    static var notifyWhenFriendComesOnline: Bool {
        get {
            if UserDefaults.standard.object(forKey: notifyFriendsKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: notifyFriendsKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: notifyFriendsKey) }
    }

    /// When true, notify 5 minutes before events for games selected in "Notify when a lobby is up".
    static var notifyForEvents: Bool {
        get {
            if UserDefaults.standard.object(forKey: notifyEventsKey) == nil { return false }
            return UserDefaults.standard.bool(forKey: notifyEventsKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: notifyEventsKey) }
    }

    static var selectedGameNames: Set<String> {
        get {
            (UserDefaults.standard.array(forKey: gamesKey) as? [String]).map { Set($0) } ?? []
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: gamesKey)
        }
    }

    static var timeRanges: [NotificationTimeRange] {
        get {
            guard let data = UserDefaults.standard.data(forKey: timeRangesKey),
                  let decoded = try? JSONDecoder().decode([NotificationTimeRange].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(encoded, forKey: timeRangesKey)
            }
        }
    }

    /// True if we should send game notifications at the current time (within at least one range).
    /// Uses the device's local time zone so "9–5" means 9 AM–5 PM on your machine.
    static func isWithinNotificationHours(date: Date = Date()) -> Bool {
        let ranges = timeRanges
        if ranges.isEmpty { return true } // no restriction
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let nowMinutes = hour * 60 + minute
        for range in ranges {
            if nowMinutes >= range.startMinutes && nowMinutes <= range.endMinutes { return true }
            if range.startMinutes > range.endMinutes {
                // e.g. 22:00–02:00
                if nowMinutes >= range.startMinutes || nowMinutes <= range.endMinutes { return true }
            }
        }
        return false
    }

    static func toggleGame(_ name: String) {
        var set = selectedGameNames
        if set.contains(name) { set.remove(name) } else { set.insert(name) }
        selectedGameNames = set
    }

    static func isGameSelected(_ name: String) -> Bool {
        selectedGameNames.contains(name)
    }

    /// Refresh data every N minutes (1, 5, 10, 15). Default 5.
    static var refreshIntervalMinutes: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: refreshIntervalKey)
            return v > 0 ? v : 5
        }
        set {
            UserDefaults.standard.set(newValue, forKey: refreshIntervalKey)
            NotificationCenter.default.post(name: refreshIntervalDidChangeNotification, object: nil)
        }
    }

    /// Total time app has been open (seconds), accumulated across launches.
    static var totalTimeOnlineSeconds: Double {
        get { UserDefaults.standard.double(forKey: totalTimeOnlineKey) }
        set { UserDefaults.standard.set(newValue, forKey: totalTimeOnlineKey) }
    }

    /// Current session duration in seconds.
    static var currentSessionDurationSeconds: Double {
        guard let start = AppSession.sessionStartDate else { return 0 }
        return Date().timeIntervalSince(start)
    }

    /// Total time (all launches) + current session, in seconds.
    static var totalTimeIncludingCurrentSessionSeconds: Double {
        totalTimeOnlineSeconds + currentSessionDurationSeconds
    }
}
