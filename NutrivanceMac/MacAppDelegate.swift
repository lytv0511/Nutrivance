import AppKit
import CloudKit
import SwiftUI

/// Enables silent CloudKit push → delta pull (Handoff-style refresh when iPhone uploads new samples).
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.registerForRemoteNotifications()
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {}

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo as [AnyHashable: Any]) != nil else { return }
        Task { @MainActor in
            await MacHealthMetricsDataController.shared.pullDeltaFromCloudKit()
        }
    }
}
