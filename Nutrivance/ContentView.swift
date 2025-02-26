import SwiftUI
import UIKit

struct ContentView: View {
    @ObservedObject var healthKitManager = HealthKitManager()
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
//                ContentView_iPad()
                ContentView_iPad_alt()
            } else {
//                ContentView_iPhone()
//                ContentView_iPhone_alt()
                ContentView_iPad_alt()
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
