import SwiftData
import SwiftUI

@main
struct NutrivanceMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            MacRootContentView()
                .environmentObject(MacHealthMetricsDataController.shared)
        }
        .modelContainer(MacHealthMetricsDataController.shared.modelContainer)
    }
}
