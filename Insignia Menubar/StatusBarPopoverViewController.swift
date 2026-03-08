//
//  StatusBarPopoverViewController.swift
//  Insignia Menubar
//
//  Popover: games list, line, Friends Online, line, Login (when logged out), line, Refresh + Settings. Logout is only on Settings page.
//

import AppKit

private enum PopoverRowAction {
    case openGame(URL)
    case login
    case notificationSettings
    case logout
}

private struct PopoverRow {
    let title: String
    let isSectionHeader: Bool
    let isSeparator: Bool
    let isPlaceholderGray: Bool  // e.g. "No Friends Online"
    let action: PopoverRowAction?

    static func separator() -> PopoverRow {
        PopoverRow(title: "", isSectionHeader: false, isSeparator: true, isPlaceholderGray: false, action: nil)
    }
}

final class StatusBarPopoverViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    weak var appDelegate: AppDelegate?
    private var tableView: NSTableView!
    private var listScrollView: NSScrollView!
    private var bottomStack: NSStackView!
    private var refreshButton: NSButton!
    private var refreshSpinner: NSProgressIndicator!
    private var rows: [PopoverRow] = []

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 400))

        listScrollView = NSScrollView(frame: .zero)
        listScrollView.hasVerticalScroller = true
        listScrollView.hasHorizontalScroller = false
        listScrollView.autohidesScrollers = true
        listScrollView.borderType = .noBorder
        listScrollView.drawsBackground = false
        listScrollView.translatesAutoresizingMaskIntoConstraints = false

        tableView = NSTableView()
        tableView.headerView = nil
        tableView.rowHeight = 22
        tableView.intercellSpacing = NSSize(width: 8, height: 2)
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.backgroundColor = .clear
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        col.width = 260
        tableView.addTableColumn(col)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(listRowDoubleClicked)
        listScrollView.documentView = tableView

        bottomStack = NSStackView(views: [])
        bottomStack.orientation = .horizontal
        bottomStack.spacing = 8
        bottomStack.alignment = .centerY
        bottomStack.distribution = .fill
        bottomStack.translatesAutoresizingMaskIntoConstraints = false

        refreshButton = NSButton(title: "Refresh", target: self, action: #selector(refresh(_:)))
        refreshButton.bezelStyle = .rounded

        refreshSpinner = NSProgressIndicator()
        refreshSpinner.style = .spinning
        refreshSpinner.controlSize = .small
        refreshSpinner.isDisplayedWhenStopped = false
        refreshSpinner.translatesAutoresizingMaskIntoConstraints = false

        let settingsBtn = NSButton(title: "Settings", target: self, action: #selector(openSettings(_:)))
        settingsBtn.bezelStyle = .rounded

        bottomStack.addArrangedSubview(refreshSpinner)
        bottomStack.addArrangedSubview(refreshButton)
        bottomStack.addArrangedSubview(settingsBtn)

        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(listScrollView)
        view.addSubview(sep)
        view.addSubview(bottomStack)

        NSLayoutConstraint.activate([
            listScrollView.topAnchor.constraint(equalTo: view.topAnchor),
            listScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            listScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            listScrollView.bottomAnchor.constraint(equalTo: sep.topAnchor),
            sep.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sep.bottomAnchor.constraint(equalTo: bottomStack.topAnchor, constant: -8),
            bottomStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 0),
            bottomStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12),
            bottomStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
        ])
    }

    func rebuildContent(games: [GameInfo], friends: [Friend], isLoggedIn: Bool) {
        guard appDelegate != nil else { return }
        _ = view
        guard tableView != nil else { return }

        var newRows: [PopoverRow] = []

        // Games
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
            // Site expects /game?titleId=... (not /game/Name)
            let urlString: String
            if let tid = game.titleId, !tid.isEmpty {
                let encoded = tid.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? tid
                urlString = "\(InsigniaStatsService.baseURL)/game?titleId=\(encoded)"
            } else {
                let gameNameEncoded = game.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? game.name
                urlString = "\(InsigniaStatsService.baseURL)/game/\(gameNameEncoded)"
            }
            if let url = URL(string: urlString) {
                newRows.append(PopoverRow(title: title, isSectionHeader: false, isSeparator: false, isPlaceholderGray: false, action: .openGame(url)))
            }
        }

        // Line after last game
        newRows.append(.separator())

        if isLoggedIn {
            // Friends Online:
            newRows.append(PopoverRow(title: "Friends Online:", isSectionHeader: true, isSeparator: false, isPlaceholderGray: false, action: nil))
            if friends.isEmpty {
                newRows.append(PopoverRow(title: "No Friends Online", isSectionHeader: false, isSeparator: false, isPlaceholderGray: true, action: nil))
            } else {
                for friend in friends {
                    let online = friend.isCurrentlyOnline
                    let status: String
                    if online {
                        let g = friend.game.map { " · \($0)" } ?? ""
                        let d = friend.duration.map { " (\($0))" } ?? ""
                        status = "Online\(g)\(d)"
                    } else {
                        let s = friend.lastSeen.map { " · Last seen: \($0)" } ?? ""
                        status = "Offline\(s)"
                    }
                    newRows.append(PopoverRow(title: "\(friend.displayName) – \(status)", isSectionHeader: false, isSeparator: false, isPlaceholderGray: false, action: nil))
                }
            }
            newRows.append(.separator())
        }

        if !isLoggedIn {
            newRows.append(PopoverRow(title: "Login to Insignia (xb.live)", isSectionHeader: false, isSeparator: false, isPlaceholderGray: false, action: .login))
        }

        rows = newRows
        tableView.reloadData()
    }

    @objc private func listRowDoubleClicked() {
        let row = tableView.selectedRow
        guard row >= 0, row < rows.count else { return }
        performAction(for: rows[row])
    }

    private func performAction(for popoverRow: PopoverRow) {
        guard let action = popoverRow.action else { return }
        switch action {
        case .openGame(let url):
            NSWorkspace.shared.open(url)
            appDelegate?.closePopover()
        case .login:
            appDelegate?.closePopover()
            appDelegate?.showLoginWindowFromPopover()
        case .notificationSettings:
            appDelegate?.closePopover()
            appDelegate?.showNotificationSettingsWindowFromPopover()
        case .logout:
            appDelegate?.logout()
            appDelegate?.closePopover()
        }
    }

    @objc private func refresh(_ sender: Any) {
        guard let appDelegate = appDelegate else { return }
        refreshButton.isEnabled = false
        refreshButton.title = "Refreshing…"
        refreshSpinner.startAnimation(nil)
        refreshSpinner.isHidden = false

        appDelegate.refreshDataWithCompletion { [weak self] in
            guard let self = self else { return }
            let (games, friends, isLoggedIn) = appDelegate.currentPopoverGamesAndFriends()
            self.rebuildContent(games: games, friends: friends, isLoggedIn: isLoggedIn)
            self.refreshSpinner.stopAnimation(nil)
            self.refreshSpinner.isHidden = true
            self.refreshButton.title = "Done"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.refreshButton.title = "Refresh"
                self?.refreshButton.isEnabled = true
            }
        }
    }

    @objc private func openSettings(_ sender: Any) {
        appDelegate?.closePopover()
        appDelegate?.showNotificationSettingsWindowFromPopover()
    }

    // MARK: - NSTableViewDataSource
    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    // MARK: - NSTableViewDelegate
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row < rows.count else { return 22 }
        return rows[row].isSeparator ? 8 : 22
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < rows.count else { return nil }
        let popoverRow = rows[row]

        if popoverRow.isSeparator {
            let cellView = NSTableCellView()
            let line = NSBox()
            line.boxType = .separator
            line.translatesAutoresizingMaskIntoConstraints = false
            cellView.addSubview(line)
            NSLayoutConstraint.activate([
                line.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
                line.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
                line.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
                line.heightAnchor.constraint(equalToConstant: 1),
            ])
            return cellView
        }

        let cellView = NSTableCellView()
        let tf = NSTextField(labelWithString: popoverRow.title)
        tf.font = popoverRow.isSectionHeader ? .boldSystemFont(ofSize: NSFont.smallSystemFontSize) : .systemFont(ofSize: NSFont.smallSystemFontSize)
        if popoverRow.isPlaceholderGray {
            tf.textColor = .tertiaryLabelColor
        } else {
            tf.textColor = popoverRow.isSectionHeader ? .secondaryLabelColor : .labelColor
        }
        tf.lineBreakMode = .byTruncatingTail
        tf.translatesAutoresizingMaskIntoConstraints = false
        cellView.addSubview(tf)
        NSLayoutConstraint.activate([
            tf.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            tf.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 6),
            tf.trailingAnchor.constraint(lessThanOrEqualTo: cellView.trailingAnchor, constant: -6),
        ])
        return cellView
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard row >= 0, row < rows.count else { return false }
        return rows[row].action != nil
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0, row < rows.count else { return }
        performAction(for: rows[row])
        tableView.deselectAll(nil)
    }
}
