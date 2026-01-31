import SwiftUI

struct ComingSoonView: View {
    let feature: String
    let description: String
    @State private var animationPhase: Double = 0
    
    private var gradientBackground: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
            ],
            colors: [
                Color(red: 0.75, green: 0.0, blue: 0),  // Deep red
                Color(red: 1.0, green: 0.4, blue: 0),   // Vibrant orange
                Color(red: 0.95, green: 0.6, blue: 0),  // Warm yellow
                Color(red: 0.8, green: 0.2, blue: 0),   // Rich red-orange
                Color(red: 1.0, green: 0.5, blue: 0),   // Pure orange
                Color(red: 0.9, green: 0.3, blue: 0),   // Bright red-orange
                Color(red: 0.8, green: 0.1, blue: 0),   // Deep red
                Color(red: 1.0, green: 0.45, blue: 0),  // Bright orange
                Color(red: 0.85, green: 0.25, blue: 0)  // Rich red-orange
            ]
        )
        .ignoresSafeArea()
        .hueRotation(.degrees(animationPhase))
        .onAppear {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                animationPhase = 20  // Doubled the range
            }
        }
    }
    
    var body: some View {
        HStack {
            Spacer()
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "hammer.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.orange)
                Text(feature)
                    .font(.title)
                    .bold()
                Text(description)
                    .multilineTextAlignment(.center)
                    .padding()
                Spacer()
            }
            Spacer()
        }
        .background(
           GradientBackgrounds().burningGradientFull(animationPhase: $animationPhase)
               .onAppear {
                   withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                       animationPhase = 20
                   }
               }
       )
    }
}
