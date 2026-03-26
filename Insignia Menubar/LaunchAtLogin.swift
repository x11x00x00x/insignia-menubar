//
//  LaunchAtLogin.swift
//  Insignia Menubar
//
//  Register/unregister app as a login item (open at startup). Uses SMAppService on macOS 13+,
//  and LSSharedFileList on older macOS so the checkbox works on the app’s minimum deployment target.
//

import Foundation
import CoreServices
import ServiceManagement

enum LaunchAtLogin {
    /// Whether the app is currently registered as a login item (read from system).
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return legacyIsInLoginItems
    }

    /// Add or remove the app from login items. Returns true if the change succeeded.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                return true
            } catch {
                return false
            }
        }
        return legacySetLoginItem(enabled)
    }

    // MARK: - Legacy (macOS 11–12)

    private static var legacyLoginItemsList: LSSharedFileList? {
        guard let list = LSSharedFileListCreate(
            nil,
            kLSSharedFileListSessionLoginItems.takeUnretainedValue(),
            nil
        )?.takeRetainedValue() else { return nil }
        return (list as LSSharedFileList)
    }

    private static var legacyIsInLoginItems: Bool {
        guard let listRef = legacyLoginItemsList else { return false }
        let snapshot = LSSharedFileListCopySnapshot(listRef, nil)?.takeRetainedValue() as? [LSSharedFileListItem]
        guard let items = snapshot else { return false }
        let bundleURL = Bundle.main.bundleURL as CFURL
        for item in items {
            if let itemURL = LSSharedFileListItemCopyResolvedURL(item, 0, nil)?.takeRetainedValue() {
                if CFEqual(itemURL, bundleURL) { return true }
            }
        }
        return false
    }

    private static func legacySetLoginItem(_ enabled: Bool) -> Bool {
        guard let listRef = legacyLoginItemsList else { return false }
        let bundleURL = Bundle.main.bundleURL as CFURL
        if enabled {
            LSSharedFileListInsertItemURL(listRef, kLSSharedFileListItemLast.takeUnretainedValue(), nil, nil, bundleURL, nil, nil)
            return true
        }
        let snapshot = LSSharedFileListCopySnapshot(listRef, nil)?.takeRetainedValue() as? [LSSharedFileListItem]
        guard let items = snapshot else { return false }
        for item in items {
            if let itemURL = LSSharedFileListItemCopyResolvedURL(item, 0, nil)?.takeRetainedValue() {
                if CFEqual(itemURL, bundleURL) {
                    LSSharedFileListItemRemove(listRef, item)
                    return true
                }
            }
        }
        return true
    }
}
