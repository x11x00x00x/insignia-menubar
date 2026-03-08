//
//  Insignia_MenubarApp.swift
//  Insignia Menubar
//
//  Created by Anis360 on 15/5/2025.
//

import SwiftUI

@main
struct Insignia_MenubarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        // No Settings scene — it was opening an empty window. Minimal WindowGroup so the app has
        // a scene; AppDelegate closes the empty window at launch and when opening our Settings.
        WindowGroup {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) { }
        }
    }
}
