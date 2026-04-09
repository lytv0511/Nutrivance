import SwiftUI

enum ComingSoonBackgroundStyle {
    case warm
    case natural
    case bold
    case spirit
    case burning
    case nature
    case forest
    case realm
    case sleep
}

struct ComingSoonView: View {
    let feature: String
    let description: String
    var backgroundStyle: ComingSoonBackgroundStyle = .burning
    @State private var animationPhase: Double = 0

    var body: some View {
        HStack {
            Spacer()
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "hammer.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(iconColor)
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
           backgroundView
               .onAppear {
                   withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                       animationPhase = 20
                   }
               }
       )
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch backgroundStyle {
        case .warm:
            GradientBackgrounds().warmGradientFull(animationPhase: $animationPhase)
        case .natural:
            GradientBackgrounds().naturalGradientFull(animationPhase: $animationPhase)
        case .bold:
            GradientBackgrounds().boldGradientFull(animationPhase: $animationPhase)
        case .spirit:
            GradientBackgrounds().spiritGradientFull(animationPhase: $animationPhase)
        case .burning:
            GradientBackgrounds().burningGradientFull(animationPhase: $animationPhase)
        case .nature:
            GradientBackgrounds().natureGradientFull(animationPhase: $animationPhase)
        case .forest:
            GradientBackgrounds().forestGradientFull(animationPhase: $animationPhase)
        case .realm:
            GradientBackgrounds().realmGradientFull(animationPhase: $animationPhase)
        case .sleep:
            GradientBackgrounds().sleepGradientFull(animationPhase: $animationPhase)
        }
    }

    private var iconColor: Color {
        switch backgroundStyle {
        case .nature, .natural, .forest:
            return .green
        case .spirit, .realm, .bold:
            return .purple
        case .burning, .warm, .sleep:
            return .orange
        }
    }
}
