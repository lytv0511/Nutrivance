import SwiftUI
import HealthKit

struct MovementAnalysisView: View {
    @State private var animationPhase: Double = 0
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    CurrentWorkoutAnalysis()
                    MovementQualityMetrics()
                    FormFeedbackCard()
                    PastWorkoutReview()
                }
                .padding()
            }
            .background(
                GradientBackgrounds().burningGradient(animationPhase: $animationPhase)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                            animationPhase = 20
                        }
                    }
            )
            .navigationTitle("Movement Analysis")
        }
    }
}

struct CurrentWorkoutAnalysis: View {
    @StateObject private var healthStore = HealthKitManager()
    @State private var currentWorkout: HKWorkout?
    @State private var heartRate: Double = 0
    @State private var isLoading = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current Session")
                .font(.title2.bold())
            
            if isLoading {
                ProgressView()
            } else if let workout = currentWorkout {
                HStack {
                    MetricItem(
                        title: "Activity",
                        value: workout.workoutActivityType.name,
                        icon: "figure.run"
                    )
                    
                    Divider()
                    
                    MetricItem(
                        title: "Heart Rate",
                        value: String(format: "%.0f bpm", heartRate),
                        icon: "heart.fill"
                    )
                }
            } else {
                Text("No active workout")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task {
            await fetchCurrentWorkout()
        }
    }
    
    private func fetchCurrentWorkout() async {
        healthStore.fetchMostRecentWorkout { workout in
            currentWorkout = workout
            isLoading = false
        }
    }
}

struct MovementQualityMetrics: View {
    @StateObject private var healthStore = HealthKitManager()
    @State private var workoutEnergy: Double = 0
    @State private var duration: TimeInterval = 0
    @State private var isLoading = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Movement Quality")
                .font(.title2.bold())
            
            if isLoading {
                ProgressView()
            } else {
                HStack {
                    MetricItem(
                        title: "Energy",
                        value: String(format: "%.0f kcal", workoutEnergy),
                        icon: "flame.fill"
                    )
                    
                    Divider()
                    
                    MetricItem(
                        title: "Duration",
                        value: formatDuration(duration),
                        icon: "clock.fill"
                    )
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task {
            await fetchMovementData()
        }
    }
    
    private func fetchMovementData() async {
        if let workout = await fetchMostRecentWorkout() {
            workoutEnergy = await healthStore.calculateWorkoutEnergy(workout: workout)
            duration = workout.duration
        }
        isLoading = false
    }
    
    private func fetchMostRecentWorkout() async -> HKWorkout? {
        await withCheckedContinuation { continuation in
            healthStore.fetchMostRecentWorkout { workout in
                continuation.resume(returning: workout)
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        return "\(minutes) min"
    }
}

struct FormFeedbackCard: View {
    @AppStorage("formTipsAutoScroll") private var autoScrollEnabled = true
    @State private var currentIndex = 0
    @State private var showingDetail = false
    @State private var selectedTip: (String, String)?
    @State private var isUserInteracting = false
    
    let formTips: [(String, String)] = [
        ("Maintain Core Engagement", "Keep your core tight throughout movements"),
        ("Control the Eccentric", "Focus on the lowering phase"),
        ("Full Range of Motion", "Complete each rep through full range"),
        ("Breathing Pattern", "Exhale during exertion")
    ]
    
    let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    let cardWidth: CGFloat = 300
    let cardHeight: CGFloat = 150
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Form Tips")
                    .font(.title2.bold())
                Spacer()
                Toggle("Auto", isOn: $autoScrollEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: .orange))
                    .labelsHidden()
            }
            
            GeometryReader { geometry in
                ZStack {
                    ForEach(formTips.indices, id: \.self) { index in
                        TipCard(title: formTips[index].0, description: formTips[index].1)
                            .frame(width: cardWidth, height: cardHeight)
                            .scaleEffect(index == currentIndex ? 1.0 : 0.8)
                            .opacity(getOpacity(for: index))
                            .offset(x: getOffset(for: index, in: geometry))
                            .zIndex(index == currentIndex ? 1 : 0)
                            .onTapGesture {
                                withAnimation(.spring()) {
                                    currentIndex = index
                                }
                                selectedTip = formTips[index]
                                showingDetail = true
                            }
                            .gesture(
                                DragGesture()
                                    .onChanged { _ in
                                        isUserInteracting = true
                                    }
                                    .onEnded { value in
                                        let threshold: CGFloat = 50
                                        if value.translation.width > threshold {
                                            withAnimation(.spring()) {
                                                currentIndex = (currentIndex - 1 + formTips.count) % formTips.count
                                            }
                                        } else if value.translation.width < -threshold {
                                            withAnimation(.spring()) {
                                                currentIndex = (currentIndex + 1) % formTips.count
                                            }
                                        }
                                        
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                                            isUserInteracting = false
                                        }
                                    }
                            )
                    }
                }
            }
            .frame(height: cardHeight + 20)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onReceive(timer) { _ in
            guard !isUserInteracting && autoScrollEnabled else { return }
            withAnimation(.spring()) {
                currentIndex = (currentIndex + 1) % formTips.count
            }
        }
        .sheet(isPresented: $showingDetail) {
                    if let tip = selectedTip {
                        TipDetailView(title: tip.0, description: tip.1)
                    }
                }
                .onChange(of: showingDetail) { _, isPresented in
                    isUserInteracting = isPresented
                    if !isPresented {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                            isUserInteracting = false
                        }
                    }
                }
    }
    
    private func getOpacity(for index: Int) -> Double {
        let distance = abs(index - currentIndex)
        return 1.0 - Double(distance) * 0.3
    }
    
    private func getOffset(for index: Int, in geometry: GeometryProxy) -> CGFloat {
        let centerOffset = (geometry.size.width - cardWidth) / 2
        let baseOffset = cardWidth * 1.2
        let distance = CGFloat(index - currentIndex)
        return centerOffset + (distance * baseOffset)
    }
}

struct TipCard: View {
    let title: String
    let description: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct TipDetailView: View {
    let title: String
    let description: String
    
    var body: some View {
        VStack(spacing: 20) {
            Text(title)
                .font(.title.bold())
            Text(description)
                .font(.body)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}


struct PastWorkoutReview: View {
    @StateObject private var healthStore = HealthKitManager()
    @State private var workouts: [HKWorkout] = []
    @State private var isLoading = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Past Workouts")
                .font(.title2.bold())
            
            if isLoading {
                ProgressView()
            } else {
                ForEach(workouts.prefix(3), id: \.uuid) { workout in
                    WorkoutReviewRow(workout: workout)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task {
            await fetchPastWorkouts()
        }
    }
    
    private func fetchPastWorkouts() async {
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -7, to: endDate)!
        
        healthStore.fetchWorkouts(from: startDate, to: endDate) { fetchedWorkouts in
            workouts = fetchedWorkouts
            isLoading = false
        }
    }
}

struct FormTipRow: View {
    let title: String
    let description: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct WorkoutReviewRow: View {
    let workout: HKWorkout
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(workout.workoutActivityType.name)
                    .font(.headline)
                Text(formatDate(workout.startDate))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text(formatDuration(workout.duration))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday().day())
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        return "\(minutes) min"
    }
}
