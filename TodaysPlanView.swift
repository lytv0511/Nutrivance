// Add these view components after the existing code

extension TodaysPlanView {
    private var nutritionPlanView: some View {
        VStack(alignment: .leading, spacing: 15) {
            ForEach(getNutritionPlans(for: selectedTime), id: \.id) { plan in
                PlanItemView(
                    time: plan.time,
                    title: plan.title,
                    description: plan.description,
                    systemImage: "fork.knife"
                )
            }
        }
    }
    
    private var fitnessPlanView: some View {
        VStack(alignment: .leading, spacing: 15) {
            ForEach(getFitnessPlans(for: selectedTime), id: \.id) { plan in
                PlanItemView(
                    time: plan.time,
                    title: plan.title,
                    description: plan.description,
                    systemImage: "figure.run"
                )
            }
        }
    }
    
    private var mentalHealthPlanView: some View {
        VStack(alignment: .leading, spacing: 15) {
            ForEach(getMentalHealthPlans(for: selectedTime), id: \.id) { plan in
                PlanItemView(
                    time: plan.time,
                    title: plan.title,
                    description: plan.description,
                    systemImage: "brain.head.profile"
                )
            }
        }
    }
}

struct PlanItemView: View {
    let time: Date
    let title: String
    let description: String
    let systemImage: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage)
                Text(time.formatted(.dateTime.hour().minute()))
                    .fontWeight(.semibold)
                Text(title)
                    .fontWeight(.medium)
            }
            Text(description)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(.gray.opacity(0.1)))
    }
}

// Sample data structures and functions
struct PlanItem: Identifiable {
    let id = UUID()
    let time: Date
    let title: String
    let description: String
}

extension TodaysPlanView {
    private func getNutritionPlans(for time: Date) -> [PlanItem] {
        [
            PlanItem(time: time, title: "Breakfast", description: "Oatmeal with fruits and nuts"),
            PlanItem(time: time.addingTimeInterval(3600 * 4), title: "Lunch", description: "Grilled chicken salad"),
            PlanItem(time: time.addingTimeInterval(3600 * 8), title: "Dinner", description: "Salmon with vegetables")
        ]
    }
    
    private func getFitnessPlans(for time: Date) -> [PlanItem] {
        [
            PlanItem(time: time, title: "Morning Workout", description: "30 min cardio + strength training"),
            PlanItem(time: time.addingTimeInterval(3600 * 6), title: "Mobility", description: "15 min stretching routine"),
            PlanItem(time: time.addingTimeInterval(3600 * 10), title: "Evening Walk", description: "20 min walking")
        ]
    }
    
    private func getMentalHealthPlans(for time: Date) -> [PlanItem] {
        [
            PlanItem(time: time, title: "Morning Meditation", description: "10 min mindfulness practice"),
            PlanItem(time: time.addingTimeInterval(3600 * 5), title: "Journaling", description: "Daily reflection and gratitude"),
            PlanItem(time: time.addingTimeInterval(3600 * 9), title: "Evening Relaxation", description: "Breathing exercises")
        ]
    }
}
