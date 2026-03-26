//
//  NotificationSettingsWindowController.swift
//  Insignia Menubar
//
//  Settings: time online, refresh interval, notifications, games, time ranges.
//

import AppKit

private final class FlippedClipView: NSView {
    override var isFlipped: Bool { true }
}

final class NotificationSettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    override var windowNibName: NSNib.Name? { nil }

    weak var appDelegate: AppDelegate?
    private var gameNames: [String] = []
    private let gamesTable = NSTableView()
    private var editTimeRangeSheet: NSWindow?
    private var editTimeRangeStartPicker: NSDatePicker?
    private var editTimeRangeEndPicker: NSDatePicker?
    private var editTimeRangeRow: Int = -1
    private var gamesScrollView: NSScrollView!
    private let timeRangesTable = NSTableView()
    private var timeRangesScrollView: NSScrollView!
    private let addTimeRangeButton = NSButton(title: "Add time range", target: nil, action: nil)
    private let refreshGamesButton = NSButton(title: "Refresh game list", target: nil, action: nil)
    private var friendsNotificationCheckbox: NSButton?
    private var eventsNotificationCheckbox: NSButton?
    private var timeRangeData: [(start: Int, end: Int)] = [] // minutes since midnight
    private var sessionTimeLabel: NSTextField?
    private var totalTimeLabel: NSTextField?
    private var insigniaTimeOnlineLabel: NSTextField?
    private var refreshIntervalPopUp: NSPopUpButton?
    private var timeUpdateTimer: Timer?
    private var mainScrollView: NSScrollView!
    private var discordStatusLabel: NSTextField?
    private var discordPresenceStatusLabel: NSTextField?  // "Showing as: Online" / "Showing as: Offline"
    private var discordGameLabel: NSTextField?            // "Game: Halo 2" or "Game: —"
    private var discordLastCheckLabel: NSTextField?     // "Last checked: 3:45 PM"
    private var discordConnectButton: NSButton?
    private var discordDisconnectButton: NSButton?
    private var launchAtLoginCheckbox: NSButton?

    func setGameList(from onlineUsers: OnlineUsersResponse) {
        gameNames = onlineUsers.keys.sorted()
        gamesTable.reloadData()
    }

    override func loadWindow() {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 820),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.level = .floating
        window.delegate = self
        window.center()
        self.window = window

        let contentView = window.contentView!
        let stack = NSStackView(views: [])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        // --- Time online & app settings ---
        let statsLabel = NSTextField(labelWithString: "Time online")
        statsLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        stack.addArrangedSubview(statsLabel)

        let sessionLabel = NSTextField(labelWithString: "This session: —")
        sessionLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        sessionTimeLabel = sessionLabel
        stack.addArrangedSubview(sessionLabel)

        let totalLabel = NSTextField(labelWithString: "Total time open: —")
        totalLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        totalTimeLabel = totalLabel
        stack.addArrangedSubview(totalLabel)

        let insigniaLabel = NSTextField(labelWithString: "Total time online (Insignia): —")
        insigniaLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        insigniaTimeOnlineLabel = insigniaLabel
        stack.addArrangedSubview(insigniaLabel)

        let refreshRow = NSStackView(views: [])
        refreshRow.orientation = .horizontal
        refreshRow.spacing = 8
        refreshRow.alignment = .centerY
        let refreshPrefLabel = NSTextField(labelWithString: "Refresh data every:")
        refreshPrefLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
        popUp.addItems(withTitles: ["1 minute", "3 minutes", "5 minutes", "10 minutes", "15 minutes"])
        popUp.target = self
        popUp.action = #selector(refreshIntervalChanged(_:))
        refreshIntervalPopUp = popUp
        refreshRow.addArrangedSubview(refreshPrefLabel)
        refreshRow.addArrangedSubview(popUp)
        stack.addArrangedSubview(refreshRow)

        let launchAtLoginCheck = NSButton(checkboxWithTitle: "Open at login", target: self, action: #selector(launchAtLoginToggled(_:)))
        launchAtLoginCheck.state = LaunchAtLogin.isEnabled ? .on : .off
        launchAtLoginCheckbox = launchAtLoginCheck
        stack.addArrangedSubview(launchAtLoginCheck)

        let sep1 = NSBox()
        sep1.boxType = .separator
        stack.addArrangedSubview(sep1)

        // Discord Rich Presence
        let discordLabel = NSTextField(labelWithString: "Discord Rich Presence")
        discordLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        stack.addArrangedSubview(discordLabel)
        let discordDesc = NSTextField(labelWithString: "Show your Insignia status (game and username) on Discord. Requires Discord app to be running.")
        discordDesc.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        discordDesc.textColor = .secondaryLabelColor
        discordDesc.maximumNumberOfLines = 2
        stack.addArrangedSubview(discordDesc)
        let discordStatus = NSTextField(labelWithString: "Not connected")
        discordStatus.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        discordStatusLabel = discordStatus
        stack.addArrangedSubview(discordStatus)
        let discordPresenceStatus = NSTextField(labelWithString: "")
        discordPresenceStatus.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        discordPresenceStatusLabel = discordPresenceStatus
        stack.addArrangedSubview(discordPresenceStatus)
        let discordGame = NSTextField(labelWithString: "")
        discordGame.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        discordGame.textColor = .secondaryLabelColor
        discordGameLabel = discordGame
        stack.addArrangedSubview(discordGame)
        let discordLastCheck = NSTextField(labelWithString: "")
        discordLastCheck.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        discordLastCheck.textColor = .secondaryLabelColor
        discordLastCheckLabel = discordLastCheck
        stack.addArrangedSubview(discordLastCheck)
        let discordBtnRow = NSStackView(views: [])
        discordBtnRow.orientation = .horizontal
        discordBtnRow.spacing = 8
        let connectBtn = NSButton(title: "Connect to Discord", target: self, action: #selector(discordConnectTapped))
        connectBtn.bezelStyle = .rounded
        discordConnectButton = connectBtn
        let disconnectBtn = NSButton(title: "Disconnect", target: self, action: #selector(discordDisconnectTapped))
        disconnectBtn.bezelStyle = .rounded
        discordDisconnectButton = disconnectBtn
        discordBtnRow.addArrangedSubview(connectBtn)
        discordBtnRow.addArrangedSubview(disconnectBtn)
        stack.addArrangedSubview(discordBtnRow)
        updateDiscordUI()

        let sep1b = NSBox()
        sep1b.boxType = .separator
        stack.addArrangedSubview(sep1b)

        // Friends notification
        let friendsCheck = NSButton(checkboxWithTitle: "Notify when a friend comes online", target: self, action: #selector(friendsNotificationToggled(_:)))
        friendsCheck.state = NotificationSettingsStore.notifyWhenFriendComesOnline ? .on : .off
        friendsNotificationCheckbox = friendsCheck
        stack.addArrangedSubview(friendsCheck)

        let eventsCheck = NSButton(checkboxWithTitle: "Notify 5 minutes before events for selected games below", target: self, action: #selector(eventNotificationsToggled(_:)))
        eventsCheck.state = NotificationSettingsStore.notifyForEvents ? .on : .off
        eventsNotificationCheckbox = eventsCheck
        stack.addArrangedSubview(eventsCheck)

        // Games section
        let gamesLabel = NSTextField(labelWithString: "Notify when a lobby is up in these games:")
        gamesLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        stack.addArrangedSubview(gamesLabel)

        let gamesTableContainer = NSView()
        gamesTableContainer.translatesAutoresizingMaskIntoConstraints = false
        gamesScrollView = NSScrollView(frame: .zero)
        gamesScrollView.hasVerticalScroller = true
        gamesScrollView.hasHorizontalScroller = false
        gamesScrollView.autohidesScrollers = true
        gamesScrollView.borderType = .bezelBorder
        gamesScrollView.translatesAutoresizingMaskIntoConstraints = false
        gamesTable.headerView = NSTableHeaderView()
        if gamesTable.tableColumns.isEmpty {
            let notifyCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("notify"))
            notifyCol.title = "Notify"
            notifyCol.width = 50
            let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
            nameCol.title = "Game"
            nameCol.width = 700
            gamesTable.addTableColumn(notifyCol)
            gamesTable.addTableColumn(nameCol)
        }
        gamesTable.dataSource = self
        gamesTable.delegate = self
        gamesTable.usesAlternatingRowBackgroundColors = true
        gamesScrollView.documentView = gamesTable
        gamesTableContainer.addSubview(gamesScrollView)
        NSLayoutConstraint.activate([
            gamesScrollView.topAnchor.constraint(equalTo: gamesTableContainer.topAnchor),
            gamesScrollView.leadingAnchor.constraint(equalTo: gamesTableContainer.leadingAnchor),
            gamesScrollView.trailingAnchor.constraint(equalTo: gamesTableContainer.trailingAnchor),
            gamesScrollView.bottomAnchor.constraint(equalTo: gamesTableContainer.bottomAnchor),
        ])
        stack.addArrangedSubview(gamesTableContainer)
        gamesTableContainer.heightAnchor.constraint(equalToConstant: 160).isActive = true
        gamesTableContainer.widthAnchor.constraint(equalToConstant: 780).isActive = true

        refreshGamesButton.target = self
        refreshGamesButton.action = #selector(refreshGameList)
        stack.addArrangedSubview(refreshGamesButton)

        // Time ranges section
        let timeLabel = NSTextField(labelWithString: "Only notify during these hours — local time (leave empty = all day):")
        timeLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        stack.addArrangedSubview(timeLabel)

        let timeTableContainer = NSView()
        timeTableContainer.translatesAutoresizingMaskIntoConstraints = false
        timeRangesScrollView = NSScrollView(frame: .zero)
        timeRangesScrollView.hasVerticalScroller = true
        timeRangesScrollView.hasHorizontalScroller = false
        timeRangesScrollView.autohidesScrollers = true
        timeRangesScrollView.borderType = .bezelBorder
        timeRangesScrollView.translatesAutoresizingMaskIntoConstraints = false
        timeRangesTable.headerView = NSTableHeaderView()
        if timeRangesTable.tableColumns.isEmpty {
            let startCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("start"))
            startCol.title = "From"
            startCol.width = 120
            let endCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("end"))
            endCol.title = "To"
            endCol.width = 120
            let removeCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("remove"))
            removeCol.title = ""
            removeCol.width = 160
            timeRangesTable.addTableColumn(startCol)
            timeRangesTable.addTableColumn(endCol)
            timeRangesTable.addTableColumn(removeCol)
        }
        timeRangesTable.dataSource = self
        timeRangesTable.delegate = self
        timeRangesTable.usesAlternatingRowBackgroundColors = true
        timeRangesScrollView.documentView = timeRangesTable
        timeTableContainer.addSubview(timeRangesScrollView)
        NSLayoutConstraint.activate([
            timeRangesScrollView.topAnchor.constraint(equalTo: timeTableContainer.topAnchor),
            timeRangesScrollView.leadingAnchor.constraint(equalTo: timeTableContainer.leadingAnchor),
            timeRangesScrollView.trailingAnchor.constraint(equalTo: timeTableContainer.trailingAnchor),
            timeRangesScrollView.bottomAnchor.constraint(equalTo: timeTableContainer.bottomAnchor),
        ])
        stack.addArrangedSubview(timeTableContainer)
        timeTableContainer.heightAnchor.constraint(equalToConstant: 100).isActive = true
        timeTableContainer.widthAnchor.constraint(equalToConstant: 780).isActive = true

        addTimeRangeButton.target = self
        addTimeRangeButton.action = #selector(addTimeRange)
        stack.addArrangedSubview(addTimeRangeButton)

        let sep2 = NSBox()
        sep2.boxType = .separator
        stack.addArrangedSubview(sep2)

        let logoutButton = NSButton(title: "Logout", target: self, action: #selector(logoutTapped))
        logoutButton.bezelStyle = .rounded
        stack.addArrangedSubview(logoutButton)

        let closeButton = NSButton(title: "Close", target: self, action: #selector(closeWindow))
        closeButton.keyEquivalent = "\u{1B}"
        stack.addArrangedSubview(closeButton)

        // Scroll view so "Only notify during these hours", time table, Add time range, and Close are always reachable
        mainScrollView = NSScrollView()
        mainScrollView.hasVerticalScroller = true
        mainScrollView.hasHorizontalScroller = false
        mainScrollView.autohidesScrollers = true
        mainScrollView.borderType = .noBorder
        mainScrollView.drawsBackground = false
        mainScrollView.translatesAutoresizingMaskIntoConstraints = false

        let docView = FlippedClipView()
        docView.translatesAutoresizingMaskIntoConstraints = false
        docView.addSubview(stack)
        mainScrollView.documentView = docView

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: docView.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: docView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: docView.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: docView.bottomAnchor, constant: -20),
        ])

        contentView.addSubview(mainScrollView)
        NSLayoutConstraint.activate([
            mainScrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            mainScrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            mainScrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            mainScrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        // Document view needs a frame; width matches content, height large enough to fit all content
        let docHeight: CGFloat = 900
        docView.setFrameSize(NSSize(width: 780, height: docHeight))
    }

    private func scrollToTop() {
        mainScrollView?.contentView.scroll(to: NSPoint(x: 0, y: 0))
    }

    @objc private func friendsNotificationToggled(_ sender: NSButton) {
        NotificationSettingsStore.notifyWhenFriendComesOnline = (sender.state == .on)
        if sender.state == .on {
            appDelegate?.ensureNotificationPermissionWhenEnablingNotifications()
        }
    }

    @objc private func eventNotificationsToggled(_ sender: NSButton) {
        NotificationSettingsStore.notifyForEvents = (sender.state == .on)
        if sender.state == .on {
            appDelegate?.ensureNotificationPermissionWhenEnablingNotifications()
        }
    }

    @objc private func launchAtLoginToggled(_ sender: NSButton) {
        let enabled = (sender.state == .on)
        NotificationSettingsStore.launchAtLogin = enabled
        _ = LaunchAtLogin.setEnabled(enabled)
        launchAtLoginCheckbox?.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    @objc private func refreshIntervalChanged(_ sender: NSPopUpButton) {
        let minutes = [1, 3, 5, 10, 15][sender.indexOfSelectedItem]
        NotificationSettingsStore.refreshIntervalMinutes = minutes
    }

    private func updateTimeLabels() {
        let sessionSec = NotificationSettingsStore.currentSessionDurationSeconds
        let totalSec = NotificationSettingsStore.totalTimeIncludingCurrentSessionSeconds
        sessionTimeLabel?.stringValue = "This session: \(formatDuration(sessionSec))"
        totalTimeLabel?.stringValue = "Total time open: \(formatDuration(totalSec))"
    }

    private func fetchAndShowInsigniaTimeOnline() {
        guard let username = KeychainHelper.getUsername(), !username.isEmpty else {
            insigniaTimeOnlineLabel?.stringValue = "Total time online (Insignia): — (log in to see)"
            return
        }
        InsigniaStatsService.fetchPlayTime(username: username) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    let minutes = response.totalMinutes ?? 0
                    let sec = minutes * 60
                    self?.insigniaTimeOnlineLabel?.stringValue = "Total time online (Insignia): \(self?.formatDuration(sec) ?? "—")"
                case .failure:
                    self?.insigniaTimeOnlineLabel?.stringValue = "Total time online (Insignia): —"
                }
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let mins = (total % 3600) / 60
        if hours > 0 {
            return "\(hours) h \(mins) min"
        }
        return "\(mins) min"
    }

    private func updateDiscordUI() {
        let connected = DiscordPresenceStore.discordUser != nil && DiscordRPCService.connected
        if connected {
            discordStatusLabel?.stringValue = "Connected" + (DiscordPresenceStore.discordUser.map { " as \($0.username)" } ?? "")
            let active = DiscordPresenceStore.presenceActive
            discordPresenceStatusLabel?.stringValue = "Showing as: " + (active ? "Online" : "Offline")
            discordPresenceStatusLabel?.isHidden = false
            if active, let game = DiscordPresenceStore.lastGameName, !game.isEmpty {
                discordGameLabel?.stringValue = "Game: \(game)"
            } else if active {
                discordGameLabel?.stringValue = "Game: OG Xbox"
            } else {
                discordGameLabel?.stringValue = "Insignia reports you're offline. Go online in a game to see status on Discord."
            }
            discordGameLabel?.isHidden = false
            if let lastCheck = DiscordPresenceStore.lastCheck, let date = ISO8601DateFormatter().date(from: lastCheck) {
                let formatter = DateFormatter()
                formatter.dateStyle = .none
                formatter.timeStyle = .short
                discordLastCheckLabel?.stringValue = "Last checked: \(formatter.string(from: date))"
            } else {
                discordLastCheckLabel?.stringValue = ""
            }
            discordLastCheckLabel?.isHidden = (discordLastCheckLabel?.stringValue.isEmpty ?? true)
            discordConnectButton?.isHidden = true
            discordDisconnectButton?.isHidden = false
        } else {
            discordStatusLabel?.stringValue = "Not connected"
            discordPresenceStatusLabel?.isHidden = true
            discordGameLabel?.isHidden = true
            discordLastCheckLabel?.isHidden = true
            discordConnectButton?.isHidden = false
            discordDisconnectButton?.isHidden = true
        }
    }

    @objc private func discordConnectTapped() {
        discordConnectButton?.isEnabled = false
        discordConnectButton?.title = "Connecting…"
        appDelegate?.connectDiscord { [weak self] result in
            DispatchQueue.main.async {
                self?.discordConnectButton?.isEnabled = true
                self?.discordConnectButton?.title = "Connect to Discord"
                self?.updateDiscordUI()
                if case .failure(let error) = result {
                    let alert = NSAlert()
                    alert.messageText = "Discord connection failed"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }

    @objc private func discordDisconnectTapped() {
        appDelegate?.disconnectDiscord()
        updateDiscordUI()
    }

    override func showWindow(_ sender: Any?) {
        loadWindow()
        loadTimeRanges()
        timeRangesTable.reloadData()
        updateDiscordUI()
        friendsNotificationCheckbox?.state = NotificationSettingsStore.notifyWhenFriendComesOnline ? .on : .off
        eventsNotificationCheckbox?.state = NotificationSettingsStore.notifyForEvents ? .on : .off
        let launchEnabled = LaunchAtLogin.isEnabled
        launchAtLoginCheckbox?.state = launchEnabled ? .on : .off
        NotificationSettingsStore.launchAtLogin = launchEnabled
        let idx = [1, 3, 5, 10, 15].firstIndex(of: NotificationSettingsStore.refreshIntervalMinutes) ?? 2
        refreshIntervalPopUp?.selectItem(at: idx)
        updateTimeLabels()
        fetchAndShowInsigniaTimeOnline()
        timeUpdateTimer?.invalidate()
        timeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.updateTimeLabels()
        }
        RunLoop.main.add(timeUpdateTimer!, forMode: .common)
        if gameNames.isEmpty { refreshGameList() }
        super.showWindow(sender)
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
        window?.contentView?.layoutSubtreeIfNeeded()
        DispatchQueue.main.async { [weak self] in
            self?.scrollToTop()
        }
    }

    func windowWillClose(_ notification: Notification) {
        timeUpdateTimer?.invalidate()
        timeUpdateTimer = nil
        NotificationCenter.default.post(name: AppDelegate.windowDidCloseNotification, object: nil)
    }

    private func loadTimeRanges() {
        timeRangeData = NotificationSettingsStore.timeRanges.map { ($0.startMinutes, $0.endMinutes) }
    }

    private func saveTimeRanges() {
        NotificationSettingsStore.timeRanges = timeRangeData.map { NotificationTimeRange(startMinutes: $0.start, endMinutes: $0.end) }
    }

    @objc private func refreshGameList() {
        InsigniaStatsService.fetchOnlineUsers { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let users):
                    self?.setGameList(from: users)
                case .failure:
                    break
                }
            }
        }
    }

    @objc private func addTimeRange() {
        timeRangeData.append((9 * 60, 17 * 60)) // 09:00–17:00
        saveTimeRanges()
        timeRangesTable.reloadData()
    }

    @objc private func logoutTapped() {
        appDelegate?.logout()
        window?.close()
    }

    @objc private func closeWindow() {
        window?.close()
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        f.timeZone = TimeZone.current
        f.locale = Locale.current
        return f
    }()

    private func minutesToTimeString(_ minutes: Int) -> String {
        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        let today = cal.startOfDay(for: Date())
        guard let date = cal.date(byAdding: .minute, value: minutes, to: today) else {
            let h = minutes / 60
            let m = minutes % 60
            return String(format: "%d:%02d", h, m)
        }
        return Self.timeFormatter.string(from: date)
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === gamesTable { return gameNames.count }
        if tableView === timeRangesTable { return timeRangeData.count }
        return 0
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === gamesTable {
            guard let col = tableColumn else { return nil }
            let id = col.identifier.rawValue
            if id == "notify" {
                let cell = tableView.makeView(withIdentifier: col.identifier, owner: self) as? NSTableCellView
                if let cell = cell {
                    (cell.subviews.first as? NSButton)?.state = NotificationSettingsStore.isGameSelected(gameNames[row]) ? .on : .off
                    return cell
                }
                let newCell = NSTableCellView()
                newCell.identifier = col.identifier
                let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(gameCheckboxChanged(_:)))
                button.translatesAutoresizingMaskIntoConstraints = false
                newCell.addSubview(button)
                NSLayoutConstraint.activate([
                    button.centerYAnchor.constraint(equalTo: newCell.centerYAnchor),
                    button.leadingAnchor.constraint(equalTo: newCell.leadingAnchor, constant: 8),
                ])
                return newCell
            }
            if id == "name" {
                let cell = tableView.makeView(withIdentifier: col.identifier, owner: self) as? NSTableCellView
                if let cell = cell {
                    cell.textField?.stringValue = gameNames[row]
                    return cell
                }
                let newCell = NSTableCellView()
                newCell.identifier = col.identifier
                let tf = NSTextField(labelWithString: gameNames[row])
                tf.translatesAutoresizingMaskIntoConstraints = false
                newCell.textField = tf
                newCell.addSubview(tf)
                NSLayoutConstraint.activate([
                    tf.centerYAnchor.constraint(equalTo: newCell.centerYAnchor),
                    tf.leadingAnchor.constraint(equalTo: newCell.leadingAnchor, constant: 4),
                ])
                return newCell
            }
        }
        if tableView === timeRangesTable {
            guard let col = tableColumn else { return nil }
            let id = col.identifier.rawValue

            if id == "start" {
                let cell = tableView.makeView(withIdentifier: col.identifier, owner: self) as? NSTableCellView
                if let cell = cell {
                    cell.textField?.stringValue = minutesToTimeString(timeRangeData[row].start)
                    return cell
                }
                let newCell = NSTableCellView()
                newCell.identifier = col.identifier
                let tf = NSTextField(labelWithString: minutesToTimeString(timeRangeData[row].start))
                tf.translatesAutoresizingMaskIntoConstraints = false
                newCell.textField = tf
                newCell.addSubview(tf)
                NSLayoutConstraint.activate([
                    tf.centerYAnchor.constraint(equalTo: newCell.centerYAnchor),
                    tf.leadingAnchor.constraint(equalTo: newCell.leadingAnchor, constant: 4),
                ])
                return newCell
            }
            if id == "end" {
                let cell = tableView.makeView(withIdentifier: col.identifier, owner: self) as? NSTableCellView
                if let cell = cell {
                    cell.textField?.stringValue = minutesToTimeString(timeRangeData[row].end)
                    return cell
                }
                let newCell = NSTableCellView()
                newCell.identifier = col.identifier
                let tf = NSTextField(labelWithString: minutesToTimeString(timeRangeData[row].end))
                tf.translatesAutoresizingMaskIntoConstraints = false
                newCell.textField = tf
                newCell.addSubview(tf)
                NSLayoutConstraint.activate([
                    tf.centerYAnchor.constraint(equalTo: newCell.centerYAnchor),
                    tf.leadingAnchor.constraint(equalTo: newCell.leadingAnchor, constant: 4),
                ])
                return newCell
            }
            if id == "remove" {
                let container = tableView.makeView(withIdentifier: col.identifier, owner: self) as? NSView
                let cell: NSView
                if let container = container {
                    cell = container
                    cell.subviews.forEach { $0.removeFromSuperview() }
                } else {
                    let newCell = NSView()
                    newCell.identifier = col.identifier
                    cell = newCell
                }
                let stack = NSStackView(views: [])
                stack.orientation = .horizontal
                stack.spacing = 8
                let editBtn = NSButton(title: "Edit", target: self, action: #selector(editTimeRange(_:)))
                editBtn.tag = row
                editBtn.bezelStyle = .rounded
                let removeBtn = NSButton(title: "Remove", target: self, action: #selector(removeTimeRange(_:)))
                removeBtn.tag = row
                removeBtn.bezelStyle = .rounded
                stack.addArrangedSubview(editBtn)
                stack.addArrangedSubview(removeBtn)
                stack.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(stack)
                NSLayoutConstraint.activate([
                    stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                ])
                return cell
            }
        }
        return nil
    }

    @objc private func gameCheckboxChanged(_ sender: NSButton) {
        let row = gamesTable.row(for: sender)
        guard row >= 0, row < gameNames.count else { return }
        let gameName = gameNames[row]
        NotificationSettingsStore.toggleGame(gameName)
        gamesTable.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 0))
        if sender.state == .on {
            appDelegate?.ensureNotificationPermissionWhenEnablingNotifications()
        }
    }

    @objc private func removeTimeRange(_ sender: NSButton) {
        let row = sender.tag
        guard row >= 0, row < timeRangeData.count else { return }
        timeRangeData.remove(at: row)
        saveTimeRanges()
        timeRangesTable.reloadData()
    }

    @objc private func editTimeRange(_ sender: NSButton) {
        let row = sender.tag
        guard row >= 0, row < timeRangeData.count else { return }
        let range = timeRangeData[row]
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        let today = calendar.startOfDay(for: Date())
        let startDate = calendar.date(byAdding: .minute, value: range.start, to: today) ?? Date()
        let endDate = calendar.date(byAdding: .minute, value: range.end, to: today) ?? Date()
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 140), styleMask: [.titled], backing: .buffered, defer: false)
        sheet.title = "Edit time range (local time)"
        let startPicker = NSDatePicker()
        startPicker.datePickerStyle = .textField
        startPicker.datePickerElements = .hourMinute
        startPicker.timeZone = TimeZone.current
        startPicker.dateValue = startDate
        let endPicker = NSDatePicker()
        endPicker.datePickerStyle = .textField
        endPicker.datePickerElements = .hourMinute
        endPicker.timeZone = TimeZone.current
        endPicker.dateValue = endDate
        let okButton = NSButton(title: "OK", target: nil, action: nil)
        let row1 = NSStackView(views: [NSTextField(labelWithString: "From:"), startPicker])
        row1.orientation = .horizontal
        row1.spacing = 8
        let row2 = NSStackView(views: [NSTextField(labelWithString: "To:"), endPicker])
        row2.orientation = .horizontal
        row2.spacing = 8
        let stack = NSStackView(views: [row1, row2, okButton])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        sheet.contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: sheet.contentView!.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: sheet.contentView!.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: sheet.contentView!.trailingAnchor, constant: -20),
        ])
        editTimeRangeSheet = sheet
        editTimeRangeStartPicker = startPicker
        editTimeRangeEndPicker = endPicker
        editTimeRangeRow = row
        okButton.target = self
        okButton.action = #selector(editTimeRangeSheetOK(_:))
        window?.beginSheet(sheet) { [weak self] _ in
            self?.editTimeRangeSheet = nil
            self?.editTimeRangeStartPicker = nil
            self?.editTimeRangeEndPicker = nil
            self?.editTimeRangeRow = -1
        }
    }

    @objc private func editTimeRangeSheetOK(_ sender: NSButton) {
        guard let sheet = editTimeRangeSheet,
              let startPicker = editTimeRangeStartPicker,
              let endPicker = editTimeRangeEndPicker,
              editTimeRangeRow >= 0,
              editTimeRangeRow < timeRangeData.count else {
            window?.endSheet(editTimeRangeSheet!)
            return
        }
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        let startComps = calendar.dateComponents([.hour, .minute], from: startPicker.dateValue)
        let endComps = calendar.dateComponents([.hour, .minute], from: endPicker.dateValue)
        let startMin = (startComps.hour ?? 0) * 60 + (startComps.minute ?? 0)
        let endMin = (endComps.hour ?? 0) * 60 + (endComps.minute ?? 0)
        timeRangeData[editTimeRangeRow] = (startMin, endMin)
        saveTimeRanges()
        timeRangesTable.reloadData()
        window?.endSheet(sheet)
    }
}

