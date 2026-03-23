import SwiftUI

struct RecoveryScoreView: View {
    @StateObject private var engine = HealthStateEngine.shared
    var body: some View {
        NavigationStack{
            VStack(spacing: 20){
                HealthCard(
                    symbol: "heart.circle.fill",
                    title: "Recovery Score",
                    value: String(Int(engine.recoveryScore)),
                    unit: "/100",
                    trend: "7d avg: \(String(format: "%0.f", engine.recoveryScore))",
                    color: .green,
                    chartData: [],
                    chartLabel: "Recovery",
                    chartUnit: "pts",
                    expandedContent: {
                        EmptyView()
                    }
                )
                HealthCard(
                    symbol: "bolt.heart.fill",
                    title: "Readiness Score",
                    value: String(Int(engine.readinessScore)),
                    unit: "/100",
                    trend: "7d avg: \(String(format: "%0.f", engine.readinessScore))",
                    color: .blue,
                    chartData: [],
                    chartLabel: "Readiness",
                    chartUnit: "pts",
                    expandedContent: {
                        EmptyView()
                    }
                )
            }
            .padding()
        }
    }
}

#Preview {
    RecoveryScoreView()
}