import SwiftUI

struct HomeView: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    private let titles = Array(repeating: "Win 50% of Your Day in the First Few Hours", count: 12)
    private let contents = Array(repeating: "Have you ever woken up feeling frustrated, irritated, or even rushed? Reflecting on the ensuing events of a bad morning, it’s likely that your tasks felt more draining than usual. This isn’t to say you should let a rough start dictate the whole day, but it highlights the power of those early moments. Our bodies follow circadian rhythms, which regulate sleep-wake cycles and alertness levels. Upon waking, your brain is still transitioning from rest to wake, like warming up a car engine. This is the perfect time to do something productive—something small but meaningful, like brushing your teeth or making your bed.", count: 12)
    @State private var animationPhase: Double = 0

    var body: some View {
        let columns: Int = (horizontalSizeClass == .compact) ? 1 : 3 // 4 columns on compact, 3 on regular
        let gridItems = Array(repeating: GridItem(.flexible()), count: columns)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(timeBasedGreeting() + ", learn more about your health")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("Featured Articles")
                        .font(.title)
                        .foregroundColor(.primary)
                        .bold()
                    
                    LazyVGrid(columns: gridItems, spacing: 20) {
                        ForEach(0..<titles.count, id: \.self) { index in
                            VStack {
                                Text(titles[index])
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text(contents[index])
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color(UIColor.systemGray6)))
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            .background(
                GradientBackgrounds().forestGradient(animationPhase: $animationPhase)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                            animationPhase = 20
                        }
                    }
            )
            .navigationTitle(Text("Home"))
        }
    }
    
    private func timeBasedGreeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return "Good Morning"
        case 12..<17:
            return "Good Afternoon"
        case 17..<21:
            return "Good Evening"
        default:
            return "Good Night"
        }
    }
}
