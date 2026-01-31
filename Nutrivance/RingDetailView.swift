import SwiftUI

struct RingDetailView: View {
    let ring: DashboardViewModel.RingMetric
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Main ring visualization
                if let outerRing = ring.layers.first {
                    ActivityRing(
                        progress: outerRing.value / outerRing.goal,
                        gradient: Gradient(colors: [outerRing.color, outerRing.color]),
                        backgroundGradient: Gradient(colors: [outerRing.color.opacity(0.2)])
                    )
                    .frame(width: 250, height: 250)
                    .padding()
                }
                
                // Ring details
                VStack(alignment: .leading, spacing: 16) {
                    Text(ring.name)
                        .font(.title)
                        .bold()
                    
                    ForEach(ring.layers) { layer in
                        HStack {
                            Circle()
                                .fill(layer.color)
                                .frame(width: 12, height: 12)
                            Text(layer.title)
                            Spacer()
                            Text("\(Int(layer.value))/\(Int(layer.goal)) \(layer.unit)")
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(15)
                .padding()
            }
        }
        .navigationTitle(ring.name)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemBackground))
    }
}
