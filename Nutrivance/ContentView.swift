import SwiftUI

struct ContentView: View {
    @ObservedObject var healthKitManager = HealthKitManager()
    
    var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .pad {
                ContentView_iPad()
            } else {
                ContentView_iPhone_alt()
            }
        }
        .onAppear {
            requestHealthDataPermissions()
        }
    }
    
    private func requestHealthDataPermissions() {
        healthKitManager.requestAuthorization { success, error in
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
