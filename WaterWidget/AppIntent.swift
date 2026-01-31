// AppIntent.swift

import AppIntents
import WidgetKit

struct AddCupIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Water Cup"

    // You could adjust the amount added per cup if needed
    func perform() async throws -> some IntentResult {
        // Update the water intake in UserDefaults
        let currentIntake = UserDefaults.standard.integer(forKey: "dailyWaterIntake")
        UserDefaults.standard.set(currentIntake + 1, forKey: "dailyWaterIntake")
        
        // Signal that the widget needs to refresh
        WidgetCenter.shared.reloadAllTimelines()
        
        return .result()
    }
}
