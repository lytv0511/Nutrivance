import SwiftUI

@MainActor
class AppState: ObservableObject {
    @Published var healthKitManager = HealthKitManager()
    @Published var selectedNutrient: String?
    @Published var navigationPath = NavigationPath()
}

struct ContentView: View {
    @StateObject private var appState = AppState()
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .pad {
//                if horizontalSizeClass == .regular {
                    ContentView_iPad_alt()
                        .environmentObject(appState)
//                } else {
//                    ContentView_iPad()
//                        .environmentObject(appState)
//                }
            } else if UIDevice.current.userInterfaceIdiom == .phone {
                ContentView_iPhone_alt()
            }
        }
        .task {
            requestHealthDataPermissions()
        }
    }
    private func requestHealthDataPermissions() {
        appState.healthKitManager.requestAuthorization { success, error in
            if let error = error {
                print("Error requesting health data permissions: \(error.localizedDescription)")
            } else if success {
                print("Health data permissions granted.")
            } else {
                print("Health data permissions not granted.")
            }
        }
    }
}
