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
        Settings {
            EmptyView() // Just needed to satisfy the 'some Scene' requirement
        }
    }
}
