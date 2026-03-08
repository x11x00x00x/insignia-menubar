//
//  AppDelegate.swift
//  Insignia Menubar
//
//  Created by Anis360 on 15/5/2025.
//

import Foundation
import Cocoa
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem?
    var statusMenu: NSMenu!
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "Xbox Insignia"
        
        statusMenu = NSMenu()
        statusMenu.delegate = self
        statusItem?.menu = statusMenu
        
        fetchAndUpdateMenu()
    }
    @objc func openGameURL(_ sender: NSMenuItem) {
        if let urlString = sender.representedObject as? String,
           let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
    @objc func refreshData() {
        fetchAndUpdateMenu()
    }
    
    func fetchAndUpdateMenu() {
        guard let url = URL(string: "https://insignia-notify-job-app.fly.dev/api/games") else { return }
        
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let data = data {
                do {
                    let gameResponse = try JSONDecoder().decode(GameResponse.self, from: data)
                    print("Received \(gameResponse.games.count) sessions")
                    
                    DispatchQueue.main.async {
                        self.updateMenu(with: gameResponse.games)
                    }
                } catch {
                    print("Decode error:", error)
                }
            } else {
                print("No data or error:", error?.localizedDescription ?? "Unknown error")
            }
        }
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            self.fetchAndUpdateMenu()
        }
        task.resume()
    }
    
    func updateMenu(with sessions: [GameSession]) {
        let activeCount = sessions.filter { $0.active_users > 0 }.count
        self.statusItem?.button?.title = "\(activeCount) Active XBL Games"
        statusMenu.removeAllItems()
        
        for session in sessions.sorted(by: { $0.online_users > $1.online_users }) {
            if session.active_sessions > 0 && session.active_users > 0
            {
                let title = "\(session.name): \(session.active_users) in \(session.active_sessions) session(s) / \(session.online_users) online"
                let item = NSMenuItem(title: title, action: #selector(openGameURL), keyEquivalent: "")
                item.target = self
                item.representedObject = "https://insignia.live/games/\(session.code)"
                self.statusMenu.addItem(item)
            }
        }
            statusMenu.addItem(NSMenuItem.separator())
            statusMenu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApp.terminate), keyEquivalent: "Q"))
            
        
        func menuWillOpen(_ menu: NSMenu) {
            fetchAndUpdateMenu()
        }
    }
    
}
