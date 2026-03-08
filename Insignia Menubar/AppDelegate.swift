//
//  AppDelegate.swift
//  Insignia Menubar
//
//  Created by Anis360 on 15/5/2025.
//

import Foundation
import AppKit
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem?
    var statusMenu: NSMenu!
    private var popover: NSPopover?
    private var popoverContentVC: StatusBarPopoverViewController?
    private var loginWindowController: LoginWindowController?
    private var notificationSettingsWindowController: NotificationSettingsWindowController?
    private var lastOnlineUsers: OnlineUsersResponse = [:]
    private var lastFriends: FriendsResponse?
    /// Last known set of online friend gamertags; nil = first run (don’t notify for everyone).
    private var lastOnlineFriendGamertags: Set<String>?
    /// Last known “has lobby” state per game (for “lobby is up” notifications).
    private var lastGameHadLobby: [String: Bool] = [:]
    private var refreshTimer: Timer?

    static let windowDidCloseNotification = Notification.Name("InsigniaMenubarWindowDidClose")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "Insignia Stats"
        statusItem?.button?.target = self
        statusItem?.button?.action = #selector(togglePopover)

        statusMenu = NSMenu()
        statusMenu.delegate = self

        popover = NSPopover()
        popover?.behavior = .transient
        popover?.delegate = self
        popoverContentVC = StatusBarPopoverViewController()
        popoverContentVC?.appDelegate = self
        popover?.contentViewController = popoverContentVC
        popover?.contentSize = NSSize(width: 280, height: 400)

        requestNotificationPermissionIfNeeded()
        NotificationCenter.default.addObserver(self, selector: #selector(menubarWindowDidClose), name: AppDelegate.windowDidCloseNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshIntervalDidChange), name: NotificationSettingsStore.refreshIntervalDidChangeNotification, object: nil)

        AppSession.sessionStartDate = Date()
        startRefreshTimer()
        fetchAndUpdateMenu()
        hideOrCloseEmptySwiftUIWindow()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        hideOrCloseEmptySwiftUIWindow()
        DispatchQueue.main.async { [weak self] in
            self?.hideOrCloseEmptySwiftUIWindow()
        }
    }

    /// When user clicks the dock icon, open Settings instead of the blank SwiftUI window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        closePopover()
        hideOrCloseEmptySwiftUIWindow()
        showNotificationSettingsWindowFromPopover()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let start = AppSession.sessionStartDate {
            NotificationSettingsStore.totalTimeOnlineSeconds += Date().timeIntervalSince(start)
        }
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        let interval = TimeInterval(NotificationSettingsStore.refreshIntervalMinutes * 60)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.fetchAndUpdateMenu()
        }
    }

    @objc private func refreshIntervalDidChange() {
        startRefreshTimer()
    }

    private func requestNotificationPermissionIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Call this when the user enables a notification option (e.g. checks "friend comes online" or a game for lobby notifications).
    /// If permission is not determined, shows the system prompt; if denied, opens System Settings to this app's Notifications pane.
    func ensureNotificationPermissionWhenEnablingNotifications() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .notDetermined:
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
                case .denied:
                    self?.openAppNotificationSettings()
                default:
                    break
                }
            }
        }
    }

    private func openAppNotificationSettings() {
        let bundleId = Bundle.main.bundleIdentifier ?? ""
        // Opens System Settings → Notifications and scrolls to this app (undocumented URL; may vary by macOS version).
        let path = "x-apple.systempreferences:com.apple.preference.notifications?id=\(bundleId)"
        if let url = URL(string: path) {
            NSWorkspace.shared.open(url)
        } else {
            if let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                NSWorkspace.shared.open(fallback)
            }
        }
    }

    @objc func openURL(_ sender: NSMenuItem) {
        if let urlString = sender.representedObject as? String, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func refreshData() {
        fetchAndUpdateMenu(completion: nil)
    }

    /// Call completion on main queue when refresh (games + optional friends) has finished.
    func refreshDataWithCompletion(_ completion: @escaping () -> Void) {
        fetchAndUpdateMenu(completion: completion)
    }

    @objc func togglePopover() {
        if popover?.isShown == true {
            closePopover()
            return
        }
        popoverContentVC?.appDelegate = self
        let games = lastOnlineUsers.values
            .filter { $0.online > 0 || ($0.activeLobbies ?? 0) > 0 || ($0.hasActiveSession ?? false) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        popoverContentVC?.rebuildContent(
            games: games,
            friends: (lastFriends?.friends ?? []).filter(\.isCurrentlyOnline),
            isLoggedIn: KeychainHelper.isLoggedIn
        )
        if let button = statusItem?.button {
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        // Refresh data so friends and games are up to date; update popover when fetch completes.
        fetchAndUpdateMenu { [weak self] in
            guard let self = self, self.popover?.isShown == true else { return }
            let (games, friends, isLoggedIn) = self.currentPopoverGamesAndFriends()
            self.popoverContentVC?.rebuildContent(games: games, friends: friends, isLoggedIn: isLoggedIn)
        }
    }

    @objc func closePopover() {
        popover?.performClose(nil)
    }

    func showLoginWindowFromPopover() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if loginWindowController == nil {
            loginWindowController = LoginWindowController()
            loginWindowController?.delegate = self
        }
        guard let wc = loginWindowController else { return }
        wc.loadWindow()
        wc.showWindow(nil)
        guard let window = wc.window else { return }
        window.center()
        window.orderFrontRegardless()
        window.makeKey()
    }

    func showNotificationSettingsWindowFromPopover() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if notificationSettingsWindowController == nil {
            let wc = NotificationSettingsWindowController()
            wc.appDelegate = self
            notificationSettingsWindowController = wc
        }
        notificationSettingsWindowController?.setGameList(from: lastOnlineUsers)
        guard let wc = notificationSettingsWindowController else { return }
        wc.loadWindow()
        wc.showWindow(nil)
        guard let window = wc.window else { return }
        window.center()
        window.orderFrontRegardless()
        window.makeKey()
        closeEmptySwiftUIWindowIfNeeded()
    }

    /// Hide or close the empty SwiftUI WindowGroup window so it never flashes. Run synchronously at launch and on activate.
    private func hideOrCloseEmptySwiftUIWindow() {
        let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Insignia Menubar"
        var keep = Set<NSWindow>()
        if let w = notificationSettingsWindowController?.window { keep.insert(w) }
        if let w = loginWindowController?.window { keep.insert(w) }
        if let popoverWindow = popover?.contentViewController?.view.window { keep.insert(popoverWindow) }
        for w in NSApp.windows where !keep.contains(w) {
            let title = w.title
            if title == appName || title.isEmpty {
                w.orderOut(nil)
                w.close()
            }
        }
    }

    /// Close any other visible window when we show Settings.
    private func closeEmptySwiftUIWindowIfNeeded() {
        let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Insignia Menubar"
        var keep = Set<NSWindow>()
        if let w = notificationSettingsWindowController?.window { keep.insert(w) }
        if let w = loginWindowController?.window { keep.insert(w) }
        if let popoverWindow = popover?.contentViewController?.view.window { keep.insert(popoverWindow) }
        for w in NSApp.windows where w.isVisible && !keep.contains(w) {
            if w.title == appName { w.close() }
        }
    }

    @objc func loginToInsigniaStats() {
        closePopover()
        showLoginWindowFromPopover()
    }

    @objc func openNotificationSettings() {
        closePopover()
        showNotificationSettingsWindowFromPopover()
    }

    @objc func logout() {
        KeychainHelper.clearSession()
        lastFriends = nil
        lastOnlineFriendGamertags = nil
        fetchAndUpdateMenu()
        closePopover()
        let (games, _, isLoggedIn) = currentPopoverGamesAndFriends()
        popoverContentVC?.rebuildContent(games: games, friends: [], isLoggedIn: isLoggedIn)
    }

    @objc private func menubarWindowDidClose() {
        hideOrCloseEmptySwiftUIWindow()
        let loginVisible = loginWindowController?.window?.isVisible ?? false
        let settingsVisible = notificationSettingsWindowController?.window?.isVisible ?? false
        if !loginVisible && !settingsVisible {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        fetchAndUpdateMenu()
    }

    func fetchAndUpdateMenu(completion: (() -> Void)? = nil) {
        let group = DispatchGroup()

        group.enter()
        InsigniaStatsService.fetchOnlineUsers { [weak self] result in
            guard let self = self else { group.leave(); return }
            switch result {
            case .success(let users):
                self.lastOnlineUsers = users
                self.checkAndNotifyGameActivity(with: users)
                DispatchQueue.main.async {
                    self.updateGamesSection(with: users)
                    self.updateFriendsAndAuthSection()
                }
            case .failure:
                DispatchQueue.main.async {
                    self.updateGamesSection(with: self.lastOnlineUsers)
                    self.updateFriendsAndAuthSection()
                    self.updateStatusTitle(activeCount: nil, error: true)
                }
            }
            group.leave()
        }

        if KeychainHelper.isLoggedIn {
            group.enter()
            InsigniaAuthService.fetchFriends { [weak self] result in
                guard let self = self else { group.leave(); return }
                switch result {
                case .success(let response):
                    self.lastFriends = response
                    self.checkAndNotifyFriendsCameOnline(response: response)
                case .failure:
                    self.lastFriends = nil
                }
                DispatchQueue.main.async {
                    self.updateFriendsAndAuthSection()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.fetchAndScheduleEventNotificationsIfEnabled()
            completion?()
        }
    }

    /// Events are stored in America/New_York. Returns local Date for (event_date + start_time) or nil.
    private static func eventStartDateLocal(event_date: String?, start_time: String?) -> Date? {
        guard let dateStr = event_date, dateStr.count >= 10 else { return nil }
        let parts = dateStr.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]),
              let m = Int(parts[1]),
              let d = Int(parts[2]) else { return nil }
        var hour = 0
        var minute = 0
        if let timeStr = start_time?.trimmingCharacters(in: .whitespaces), !timeStr.isEmpty {
            let t = timeStr.split(separator: ":")
            if t.count >= 1 { hour = Int(t[0]) ?? 0 }
            if t.count >= 2 { minute = Int(t[1]) ?? 0 }
        }
        guard let tz = TimeZone(identifier: "America/New_York") else { return nil }
        var comp = DateComponents()
        comp.year = y
        comp.month = m
        comp.day = d
        comp.hour = hour
        comp.minute = minute
        comp.timeZone = tz
        let cal = Calendar(identifier: .gregorian)
        guard let dateInNY = cal.date(from: comp) else { return nil }
        return dateInNY
    }

    private func fetchAndScheduleEventNotificationsIfEnabled() {
        guard NotificationSettingsStore.notifyForEvents else { return }
        let selected = NotificationSettingsStore.selectedGameNames
        if selected.isEmpty { return }
        InsigniaStatsService.fetchEvents { [weak self] result in
            guard case .success(let events) = result else { return }
            self?.scheduleEventNotifications(events: events, selectedGames: selected)
        }
    }

    private func scheduleEventNotifications(events: [EventInfo], selectedGames: Set<String>) {
        let now = Date()
        let fiveMinutes: TimeInterval = 5 * 60
        let cal = Calendar.current
        for event in events {
            guard let gameName = event.game_name?.trimmingCharacters(in: .whitespaces), !gameName.isEmpty else { continue }
            guard selectedGames.contains(gameName) else { continue }
            guard let startDate = Self.eventStartDateLocal(event_date: event.event_date, start_time: event.start_time) else { continue }
            let notifyAt = startDate.addingTimeInterval(-fiveMinutes)
            if notifyAt.timeIntervalSince(now) < 30 { continue }
            let eventId = event.id ?? 0
            let identifier = "event-\(eventId)-5min"
            let content = UNMutableNotificationContent()
            content.title = "Event starting soon: \(event.title ?? "Event")"
            content.body = "\(gameName) — in 5 minutes"
            content.sound = .default
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: notifyAt)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
        }
    }

    /// Current games and friends for the popover (after a refresh or when opening).
    func currentPopoverGamesAndFriends() -> (games: [GameInfo], friends: [Friend], isLoggedIn: Bool) {
        let games = lastOnlineUsers.values
            .filter { $0.online > 0 || ($0.activeLobbies ?? 0) > 0 || ($0.hasActiveSession ?? false) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let onlineFriends = (lastFriends?.friends ?? []).filter(\.isCurrentlyOnline)
        return (games, onlineFriends, KeychainHelper.isLoggedIn)
    }

    private func checkAndNotifyFriendsCameOnline(response: FriendsResponse) {
        let friends = response.friends ?? []
        let nowOnline = Set(friends.filter(\.isCurrentlyOnline).map(\.displayName))
        guard let previous = lastOnlineFriendGamertags else {
            lastOnlineFriendGamertags = nowOnline
            return
        }
        let newlyOnline = nowOnline.subtracting(previous)
        lastOnlineFriendGamertags = nowOnline
        guard NotificationSettingsStore.notifyWhenFriendComesOnline else { return }
        for gamertag in newlyOnline {
            let friend = friends.first { $0.displayName == gamertag }
            let gamePart = friend?.game.map { " – \($0)" } ?? ""
            notifyFriendCameOnline(gamertag: gamertag, game: friend?.game, subtitle: gamePart.isEmpty ? nil : "Playing\(gamePart)")
        }
    }

    private func notifyFriendCameOnline(gamertag: String, game: String?, subtitle: String?) {
        let content = UNMutableNotificationContent()
        content.title = "\(gamertag) is now online"
        if let subtitle = subtitle {
            content.subtitle = subtitle
        }
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request = UNNotificationRequest(identifier: "friend-online-\(gamertag)-\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    /// Resolves a selected game name to the API key (exact match, or case-insensitive trim match).
    private func resolveGameKey(_ name: String, in users: OnlineUsersResponse) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if users[name] != nil { return name }
        let lower = trimmed.lowercased()
        return users.keys.first { $0.trimmingCharacters(in: .whitespaces).lowercased() == lower }
    }

    private func checkAndNotifyGameActivity(with users: OnlineUsersResponse) {
        guard NotificationSettingsStore.isWithinNotificationHours() else { return }
        let selected = NotificationSettingsStore.selectedGameNames
        if selected.isEmpty { return }
        for name in selected {
            guard let key = resolveGameKey(name, in: users) else { continue }
            let info = users[key]
            let lobbies = info?.activeLobbies ?? 0
            let hasSession = info?.hasActiveSession ?? false
            let nowHasLobby = lobbies > 0 || hasSession
            let hadLobbyBefore = lastGameHadLobby[key] ?? false
            if !hadLobbyBefore && nowHasLobby {
                let content = UNMutableNotificationContent()
                content.title = "Lobby is up in \(key)"
                let hostNames = info?.lobbyHostNames ?? []
                if lobbies > 0 {
                    if let first = hostNames.first, !first.isEmpty {
                        if hostNames.count == 1 {
                            content.body = "Hosted by \(first)."
                        } else {
                            content.body = "Hosted by \(first) (+\(hostNames.count - 1) more)."
                        }
                    } else {
                        content.body = "\(lobbies) lobby\(lobbies == 1 ? "" : "ies") active."
                    }
                } else {
                    content.body = "Session active."
                }
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
                let request = UNNotificationRequest(identifier: "game-lobby-\(key)-\(UUID().uuidString)", content: content, trigger: trigger)
                UNUserNotificationCenter.current().add(request)
            }
            lastGameHadLobby[key] = nowHasLobby
        }
        let keys = Set(users.keys)
        lastGameHadLobby = lastGameHadLobby.filter { keys.contains($0.key) }
    }

    private func updateStatusTitle(activeCount: Int?, error: Bool) {
        if error {
            statusItem?.button?.title = "Insignia Stats (error)"
            return
        }
        if let count = activeCount {
            statusItem?.button?.title = "\(count) game(s) · Insignia"
        } else {
            statusItem?.button?.title = "Insignia Stats"
        }
    }

    private func updateGamesSection(with users: OnlineUsersResponse) {
        let games = users.values
            .filter { $0.online > 0 || ($0.activeLobbies ?? 0) > 0 || ($0.hasActiveSession ?? false) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let activeCount = games.count
        updateStatusTitle(activeCount: activeCount, error: false)

        // Remove only game items and separator after them (keep Friends, Login/Logout, Refresh, Quit)
        let toRemove = statusMenu.items.filter { item in
            guard !item.isSeparatorItem else { return false }
            let title = item.title
            if title == "Refresh" || title == "Quit" || title == "Login to Insignia Stats…" { return false }
            if title.hasPrefix("Friends") || title == "No friends online" { return false }
            if item.submenu != nil { return false }
            return true
        }
        for item in toRemove {
            statusMenu.removeItem(item)
        }
        // Remove trailing separator before "Friends" or "Login" if present
        if let last = statusMenu.items.last, last.isSeparatorItem, statusMenu.items.count > 1 {
            let prev = statusMenu.items[statusMenu.items.count - 2]
            if prev.title == "Refresh" || prev.title.hasPrefix("Friends") {
                statusMenu.removeItem(last)
            }
        }

        var insertIndex = 0
        for game in games {
            let lobbies = game.activeLobbies ?? 0
            let sessions = game.sessionCount ?? 0
            var title = "\(game.name): \(game.online) online"
            if lobbies > 0 || sessions > 0 {
                let lobbyStr = lobbies == 1 ? "1 lobby" : "\(lobbies) lobbies"
                let sessionStr = sessions == 1 ? "1 session" : "\(sessions) sessions"
                let parts = [lobbies > 0 ? lobbyStr : nil, sessions > 0 ? sessionStr : nil].compactMap { $0 }
                title += " · " + parts.joined(separator: ", ")
            }
            let item = NSMenuItem(title: title, action: #selector(openURL), keyEquivalent: "")
            item.target = self
            let base = InsigniaStatsService.baseURL
            let urlString: String
            if let tid = game.titleId, !tid.isEmpty {
                let encoded = tid.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? tid
                urlString = "\(base)/game?titleId=\(encoded)"
            } else {
                let gameNameEncoded = game.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? game.name
                urlString = "\(base)/game/\(gameNameEncoded)"
            }
            item.representedObject = urlString
            statusMenu.insertItem(item, at: insertIndex)
            insertIndex += 1
        }

        if insertIndex > 0 {
            statusMenu.insertItem(NSMenuItem.separator(), at: insertIndex)
        }
    }

    private func updateFriendsAndAuthSection() {
        // Remove Friends submenu item, "No friends online", Login, Logout, and any separator before Refresh
        let toRemove = statusMenu.items.filter { item in
            let title = item.title
            return title == "Login to Insignia Stats…" || title == "Logout" || title == "No friends online"
                || title.hasPrefix("Friends") || title == "Notification Settings…"
                || (item.submenu != nil && title == "Friends")
        }
        for item in toRemove {
            statusMenu.removeItem(item)
        }
        // Remove duplicate separators before Refresh
        while statusMenu.items.count >= 2 {
            let last = statusMenu.items[statusMenu.items.count - 1]
            let prev = statusMenu.items[statusMenu.items.count - 2]
            if prev.isSeparatorItem && (last.title == "Refresh" || last.title == "Quit" || last.title == "Notification Settings…") {
                statusMenu.removeItem(prev)
            } else {
                break
            }
        }

        var insertIndex = statusMenu.items.firstIndex(where: { $0.title == "Refresh" }) ?? statusMenu.items.count
        let notificationItem = NSMenuItem(title: "Notification Settings…", action: #selector(openNotificationSettings), keyEquivalent: "")
        notificationItem.target = self
        statusMenu.insertItem(notificationItem, at: insertIndex)
        statusMenu.insertItem(NSMenuItem.separator(), at: insertIndex)
        insertIndex = statusMenu.items.firstIndex(where: { $0.title == "Refresh" }) ?? statusMenu.items.count

        if KeychainHelper.isLoggedIn {
            let friends = (lastFriends?.friends ?? []).filter(\.isCurrentlyOnline)
            let friendsItem = NSMenuItem(title: "Friends", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            if friends.isEmpty {
                let none = NSMenuItem(title: "No friends online", action: nil, keyEquivalent: "")
                none.isEnabled = false
                submenu.addItem(none)
            } else {
                for friend in friends {
                    let gamePart = friend.game.map { " · \($0)" } ?? ""
                    let durationPart = friend.duration.map { " (\($0))" } ?? ""
                    let status = "Online\(gamePart)\(durationPart)"
                    let title = "\(friend.displayName) – \(status)"
                    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                    item.isEnabled = false
                    submenu.addItem(item)
                }
            }
            friendsItem.submenu = submenu
            statusMenu.insertItem(friendsItem, at: insertIndex)
        } else {
            let loginItem = NSMenuItem(title: "Login to Insignia Stats…", action: #selector(loginToInsigniaStats), keyEquivalent: "")
            loginItem.target = self
            statusMenu.insertItem(loginItem, at: insertIndex)
        }

        if statusMenu.indexOfItem(withTitle: "Refresh") == -1 {
            statusMenu.addItem(NSMenuItem.separator())
            let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshData), keyEquivalent: "")
            refreshItem.target = self
            statusMenu.addItem(refreshItem)
        }
        if statusMenu.indexOfItem(withTitle: "Quit") == -1 {
            statusMenu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApp.terminate), keyEquivalent: "q"))
        }
    }
}

extension AppDelegate: LoginWindowControllerDelegate {
    func loginDidSucceed(username: String) {
        lastFriends = nil
        fetchAndUpdateMenu()
    }

    func loginDidCancel() {}
}
