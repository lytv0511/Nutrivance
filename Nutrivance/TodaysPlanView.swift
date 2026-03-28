import SwiftUI

/*
 Original TodaysPlanView implementation temporarily disabled.
 Replaced with a Coming Soon placeholder.
 */

enum PlanType {
    case all
    case nutrition
    case fitness
    case mentalHealth
}

struct TodaysPlanView: View {
    let planType: PlanType

    var body: some View {
        ComingSoonView(
            feature: "Today's Plan",
            description: "Your daily planning experience is being redesigned and will return soon.",
            backgroundStyle: .warm
        )
    }
}

#Preview {
    TodaysPlanView(planType: .all)
}
