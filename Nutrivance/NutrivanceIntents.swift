//import AppIntents
//import HealthKit
//
//@available(iOS 16.0, *)
//struct LogNutrientIntent: AppIntent {
//    static var title: LocalizedStringResource = "Log Nutrient Intake"
//    
//    @Parameter(title: "Nutrient")
//    var nutrient: String
//    
//    @Parameter(title: "Amount")
//    var amount: Double
//    
//    static var parameterSummary: some ParameterSummary {
//        Summary("Log \(\.$amount) of \(\.$nutrient)")
//    }
//    
//    func perform() async throws -> some IntentResult {
//        let healthStore = await HealthKitManager()
//        let _ = try await healthStore.fetchTodayQuantity(for: .activeEnergyBurned)
//        return .result()
//    }
//}
//
//struct QueryNutrientIntent: AppIntent {
//    static var title: LocalizedStringResource = "Check Nutrient Intake"
//    
//    @Parameter(title: "Nutrient")
//    var nutrient: String
//    
//    static var parameterSummary: some ParameterSummary {
//        Summary("Check \(\.$nutrient) intake")
//    }
//    
//    func perform() async throws -> some IntentResult {
//        let healthStore = await HealthKitManager()
//        let _ = try await healthStore.fetchTodayQuantity(for: .stepCount)
//        return .result()
//    }
//}
//
//struct NutrivanceShortcuts: AppShortcutsProvider {
//    static var appShortcuts: [AppShortcut] {
//        AppShortcut(
//            intent: LogNutrientIntent(),
//            phrases: ["Log nutrient in Nutrivance", "Track nutrition in Nutrivance"],
//            shortTitle: "Log Nutrient",
//            systemImageName: "plus.circle.fill"
//        )
//        
//        AppShortcut(
//            intent: QueryNutrientIntent(),
//            phrases: ["Check nutrient levels in Nutrivance", "Show nutrition today"],
//            shortTitle: "Check Nutrients",
//            systemImageName: "chart.bar.fill"
//        )
//    }
//}
