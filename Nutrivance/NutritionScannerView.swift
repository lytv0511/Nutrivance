import SwiftUI

/*
 Original NutritionScannerView implementation temporarily disabled.
 Replaced with a Coming Soon placeholder while preserving shared detection types.
 */

@MainActor
class NutritionScannerViewModel: ObservableObject {
    @Published var isProcessing = false
    @Published var detectedNutrition: [NutritionDetection] = []

    struct NutritionDetection: Identifiable, Equatable {
        let id = UUID()
        let name: String
        var value: Double
        let unit: String
    }
}

public struct NutritionScannerView: View {
    public init() { }

    public var body: some View {
        ComingSoonView(
            feature: "Nutrition Scanner",
            description: "Nutrition scanning is being refreshed and will be back soon.",
            backgroundStyle: .nature
        )
    }
}

#Preview {
    NutritionScannerView()
}
