import SwiftUI

struct TappableChartPreview: View {
    let data: [(Date, Double)]
    let label: String
    let unit: String
    let color: Color
    @State private var showSheet = false
    var body: some View {
        Button {
            showSheet = true
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        } label: {
            HealthLineChartPreview(data: data, label: label, unit: unit, color: color)
                .frame(height: 60)
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $showSheet) {
            HealthLineChartSheet(data: data, label: label, unit: unit, color: color)
        }
    }
}
