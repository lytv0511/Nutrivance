import SwiftUI

enum PlanType {
    case all
    case nutrition
    case fitness
    case mentalHealth
}

struct TodaysPlanView: View {
    @StateObject private var healthStore = HealthKitManager()
    let planType: PlanType
    @State private var selectedTime = Date()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                timelineHeader
                
                switch planType {
                case .all:
                    allActivitiesView
                case .nutrition:
                    nutritionPlanView
                case .fitness:
                    fitnessPlanView
                case .mentalHealth:
                    mentalHealthPlanView
                }
            }
            .padding()
        }
        .navigationTitle("Today's Plan")
    }
    
    private var timelineHeader: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 15) {
                ForEach(getTimeSlots(), id: \.self) { time in
                    TimeSlotButton(time: time, isSelected: Calendar.current.compare(time, to: selectedTime, toGranularity: .hour) == .orderedSame) {
                        selectedTime = time
                        Task {
                            await fetchHealthData(for: time)
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    private var allActivitiesView: some View {
        VStack(spacing: 25) {
            PlanSectionView(title: "Nutrition", systemImage: "fork.knife") {
                nutritionPlanView
            }
            
            PlanSectionView(title: "Fitness", systemImage: "figure.run") {
                fitnessPlanView
            }
            
            PlanSectionView(title: "Mental Health", systemImage: "brain.head.profile") {
                mentalHealthPlanView
            }
        }
    }
    
    private var nutritionPlanView: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(getNutritionPlans(), id: \.id) { plan in
                PlanItemView(
                    time: plan.time.formatted(.dateTime.hour().minute()),
                    title: plan.title,
                    description: plan.description,
                    isCompleted: plan.isCompleted
                )
            }
        }
    }
    
    private var fitnessPlanView: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(getFitnessPlans(), id: \.id) { plan in
                PlanItemView(
                    time: plan.time.formatted(.dateTime.hour().minute()),
                    title: plan.title,
                    description: plan.description,
                    isCompleted: plan.isCompleted
                )
            }
        }
    }
    
    private var mentalHealthPlanView: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(getMentalHealthPlans(), id: \.id) { plan in
                PlanItemView(
                    time: plan.time.formatted(.dateTime.hour().minute()),
                    title: plan.title,
                    description: plan.description,
                    isCompleted: plan.isCompleted
                )
            }
        }
    }
    
    private func fetchHealthData(for time: Date) async {
        // Implement HealthKit data fetching here
    }
}

struct TimeSlotButton: View {
    let time: Date
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(time.formatted(.dateTime.hour()))
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(isSelected ? .blue : .gray.opacity(0.2))
                .foregroundColor(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
    }
}

struct PlanSectionView<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content
    
    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
                .padding(.leading)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.gray.opacity(0.1)))
    }
}

struct PlanItem: Identifiable {
    let id = UUID()
    let time: Date
    let title: String
    let description: String
    var isCompleted: Bool
}

struct PlanItemView: View {
    let time: String
    let title: String
    let description: String
    let isCompleted: Bool
    
    var body: some View {
        HStack(alignment: .top) {
            Text(time)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Circle()
                .strokeBorder(isCompleted ? Color.green : Color.gray, lineWidth: 1.5)
                .background(Circle().fill(isCompleted ? Color.green.opacity(0.2) : Color.clear))
                .frame(width: 24, height: 24)
                .overlay {
                    if isCompleted {
                        Image(systemName: "checkmark")
                            .font(.caption2.bold())
                            .foregroundColor(.green)
                    }
                }
        }
        .padding(.vertical, 8)
    }
}

private func getTimeSlots() -> [Date] {
    let calendar = Calendar.current
    let now = Date()
    let startOfDay = calendar.startOfDay(for: now)
    
    return (0...23).map { hour in
        calendar.date(byAdding: .hour, value: hour, to: startOfDay) ?? now
    }
}

extension TodaysPlanView {
    private func getNutritionPlans() -> [PlanItem] {
        [
            PlanItem(time: selectedTime, title: "Breakfast", description: "Oatmeal with fruits and nuts", isCompleted: false),
            PlanItem(time: selectedTime.addingTimeInterval(3600 * 4), title: "Lunch", description: "Grilled chicken salad", isCompleted: false),
            PlanItem(time: selectedTime.addingTimeInterval(3600 * 8), title: "Dinner", description: "Salmon with vegetables", isCompleted: false)
        ]
    }
    
    private func getFitnessPlans() -> [PlanItem] {
        [
            PlanItem(time: selectedTime, title: "Morning Workout", description: "30 min cardio + strength training", isCompleted: false),
            PlanItem(time: selectedTime.addingTimeInterval(3600 * 6), title: "Mobility", description: "15 min stretching routine", isCompleted: false),
            PlanItem(time: selectedTime.addingTimeInterval(3600 * 10), title: "Evening Walk", description: "20 min walking", isCompleted: false)
        ]
    }
    
    private func getMentalHealthPlans() -> [PlanItem] {
        [
            PlanItem(time: selectedTime, title: "Morning Meditation", description: "10 min mindfulness practice", isCompleted: false),
            PlanItem(time: selectedTime.addingTimeInterval(3600 * 5), title: "Journaling", description: "Daily reflection and gratitude", isCompleted: false),
            PlanItem(time: selectedTime.addingTimeInterval(3600 * 9), title: "Evening Relaxation", description: "Breathing exercises", isCompleted: false)
        ]
    }
}
