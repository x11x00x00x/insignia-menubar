# Insignia Menubar

A macOS menubar app that shows **Insignia Stats** game activity, lets you **log in** to see **friends online**, and **notifies you** when friends come online or when a lobby is up for games you care about.

## Features

### Menubar & popover
- **Menubar icon** – Shows “Insignia Stats” or “X game(s) · Insignia” in the menu bar. Click to open the popover.
- **Popover** – Main UI: list of games with online counts and lobby/session info. Double‑click a game to open its page on [Insignia Stats](https://xb.live). Refresh and Settings buttons at the bottom.
- **Friends Online** – When logged in, the popover shows a “Friends Online” section with only **online** friends and the game each is playing (e.g. *Gamertag – Online · Halo 2 (15 min)*). When not logged in, this section is hidden.
- **Login** – When logged out, a “Login to Insignia (xb.live)” row appears in the popover. Log in with your Insignia Stats (Insignia Auth) email and password; session is stored in the macOS Keychain.
- **Refresh** – Manual refresh in the popover; data also refreshes when you open the popover and on a timer (interval set in Settings).

### Notifications
- **Friend came online** – Optional notification when a friend comes online (enable in Notification settings).
- **Lobby is up** – Optional notification when a lobby appears for selected games. Notification can include the **host name** when the server provides it (e.g. “Hosted by PlayerName”).
- **Events** – Optional notification about **5 minutes before** scheduled events for selected games (from Insignia Stats events).
- **Permission** – When you turn on any notification option (friend, event, or check a game for lobby), the app will prompt for notification permission if needed, or open System Settings so you can allow notifications for the app.
- **Quiet hours** – “Only notify during these hours” in Settings lets you restrict notifications to certain time ranges (e.g. 9 AM–5 PM). Leave empty for all day.

### Settings (Notification Settings…)
- **Time online** – This session and total time open.
- **Refresh interval** – How often to fetch data: 1, 3, 5, 10, or 15 minutes.
- **Notify when a friend comes online** – Checkbox to enable friend-online notifications.
- **Notify for events** – Checkbox to enable event reminders.
- **Notify when a lobby is up in these games** – Table of games; check the games you want lobby notifications for. List can be refreshed from the API.
- **Only notify during these hours** – Optional time ranges (e.g. 9:00–17:00). Add/edit/remove ranges.
- **Logout** – Log out of Insignia Stats. Logout is **only** in Settings (not in the popover or menubar menu).
- **Window** – Settings window is resizable and can be made shorter or taller.

### Dock & windows
- When you open Settings or Login, the app may appear in the dock. **Clicking the dock icon** opens the **Settings** window (instead of a blank window).
- Closing Settings or Login hides any empty window so you don’t see a blank screen.

## Requirements

- macOS 11.0 or later
- Xcode 14+ (for building)
- Swift 5

## Building

1. Open `Insignia Menubar.xcodeproj` in Xcode.
2. Choose the **Insignia Menubar** scheme and **My Mac** as the run destination.
3. Press **⌘B** to build, or **⌘R** to build and run.

The app runs as a menubar app. Look for **Insignia Stats** or **“X game(s) · Insignia”** in the menu bar. It may also appear in the dock when Settings or Login is open.

## Usage

1. **Click the menubar icon** – Opens the popover with games, friends online (if logged in), and Login (if not).
2. **Games** – Double‑click a game row to open its page on Insignia Stats.
3. **Login** – Click “Login to Insignia (xb.live)” in the popover, enter credentials, and log in. Session is saved in the Keychain.
4. **Logout** – Open **Notification Settings…** and use the **Logout** button at the bottom.
5. **Refresh** – Use **Refresh** in the popover to reload games and friends.
6. **Notification Settings…** – Configure notification toggles, games for lobby alerts, time ranges, and refresh interval. If lobby or friend notifications don’t fire, allow notifications for the app in **System Settings → Notifications**, check your “Only notify during these hours” (or leave it empty), and try a shorter refresh interval (e.g. 1–3 minutes).

## API & Auth

- **Insignia Stats API** – Base URL is `https://xb.live` by default. The app calls:
  - `GET /api/online-users` – Current online users, lobby/session counts, and when available lobby host names per game.
- **Insignia Auth** – Base URL is `https://auth.insigniastats.live/api`. The app uses:
  - `POST /api/auth/login` – Log in with email and password.
  - `GET /api/auth/friends` – Friends list (with `X-Session-Key`).

Session is stored in the Keychain under the service `com.insigniamenubar.auth`; no passwords are stored, only the session key and username.

## Project structure

- **AppDelegate.swift** – Menubar setup, popover, refresh timer, login/logout, notification logic, dock reopen (open Settings), empty-window cleanup.
- **StatusBarPopoverViewController.swift** – Popover content: games list, Friends Online (when logged in), Login (when not), Refresh, Settings.
- **NotificationSettingsWindowController.swift** – Settings window: time online, refresh interval, notification toggles, games table, time ranges, Logout, Close.
- **NotificationSettingsStore.swift** – Persists selected games, time ranges, notification toggles, refresh interval (UserDefaults).
- **InsigniaStatsModels.swift** – Types for `/api/online-users` (e.g. `GameInfo`, `OnlineUsersResponse`).
- **InsigniaStatsService.swift** – Fetches online users (and events) from the Insignia Stats API.
- **AuthModels.swift** – Types for login and friends (e.g. `Friend`, `FriendsResponse`).
- **InsigniaAuthService.swift** – Login and friends requests to the Insignia Auth API.
- **KeychainHelper.swift** – Keychain read/write for session key and username.
- **LoginWindowController.swift** – Login window (email/password) and delegate for success/cancel.
- **Insignia_MenubarApp.swift** – SwiftUI `@main` app with minimal `WindowGroup`; AppDelegate handles menubar and windows.

## License

Part of the Insignia Stats project. Use and modify as allowed by the project’s terms.
