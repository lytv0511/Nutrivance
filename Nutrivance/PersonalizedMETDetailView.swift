import SwiftUI

struct PersonalizedMETDetailView: View {
    @ObservedObject private var performanceProfile = PerformanceProfileSettings.shared
    @ObservedObject private var healthEngine = HealthStateEngine.shared
    @State private var selectedTimeRange: METTimeRange = .sevenDays
    @State private var workoutSnapshots: [WorkoutPersonalizedMET] = []
    @State private var dailySnapshots: [DailyPersonalizedMETSnapshot] = []
    @State private var isLoading = false
    
    private var today: Date {
        Calendar.current.startOfDay(for: Date())
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackgrounds().forestGradient(animationPhase: .constant(0))
                    .ignoresSafeArea()
                
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        // Time Range Selector
                        Picker("Time Range", selection: $selectedTimeRange) {
                            ForEach(METTimeRange.allCases, id: \.self) { range in
                                Text(range.displayName).tag(range)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding()
                        
                        // Summary Cards
                        if let currentDaily = dailySnapshots.last {
                            VStack(spacing: 12) {
                                HStack(spacing: 12) {
                                    SummaryCard(
                                        title: "Total METs",
                                        value: String(format: "%.1f", currentDaily.totalMETs),
                                        icon: "bolt.fill",
                                        color: .blue
                                    )
                                    
                                    SummaryCard(
                                        title: "Beneficial",
                                        value: String(format: "%.1f", currentDaily.beneficialMETs),
                                        icon: "checkmark.circle.fill",
                                        color: .green
                                    )
                                    
                                    SummaryCard(
                                        title: "Avg Effort",
                                        value: String(format: "%.0f%%", currentDaily.averageEffortProportion * 100),
                                        icon: "percent",
                                        color: .orange
                                    )
                                }
                            }
                            .padding()
                        }
                        
                        // Zone Breakdown
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Zone Distribution")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            ForEach(PersonalizedMETZone.allCases, id: \.self) { zone in
                                if let minutes = dailySnapshots.last?.zoneDistribution[zone], minutes > 0 {
                                    ZoneRow(
                                        zone: zone,
                                        minutes: minutes,
                                        total: dailySnapshots.last?.totalZoneMinutes ?? 1
                                    )
                                    .padding(.horizontal)
                                }
                            }
                        }
                        .padding(.vertical)
                        
                        // Workouts List
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Workouts")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            if workoutSnapshots.isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "dumbbell.fill")
                                        .font(.title2)
                                        .foregroundColor(.secondary)
                                    Text("No workouts in this period")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                                .padding(.horizontal)
                            } else {
                                ForEach(workoutSnapshots.sorted { $0.workoutDate > $1.workoutDate }, id: \.id) { workout in
                                    WorkoutMETRow(workout: workout, profile: performanceProfile.personalizedMETProfile)
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                        
                        // Trend Chart
                        VStack(alignment: .leading, spacing: 12) {
                            Text("\(selectedTimeRange.displayName) Trend")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            ExtendedTrendChart(snapshots: dailySnapshots)
                                .frame(height: 120)
                                .padding()
                                .background(Color(.systemBackground))
                                .cornerRadius(8)
                                .padding(.horizontal)
                        }
                        
                        // Max METs Calibration Info
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Max METs: \(String(format: "%.1f", performanceProfile.personalizedMETProfile.maxMETs))")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Text("Estimation: \(performanceProfile.personalizedMETProfile.estimationMethod.description)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    if let calibrationDate = performanceProfile.personalizedMETProfile.calibrationDate {
                                        Text("Last updated: \(calibrationDate.formatted(date: .abbreviated, time: .omitted))")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                        .padding()
                        
                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle("MET Analytics")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadData()
            }
            .onChange(of: selectedTimeRange) { _, _ in
                loadData()
            }
        }
    }
    
    private func loadData() {
        isLoading = true
        let calendar = Calendar.current
        let dayCount = selectedTimeRange.dayCount
        let startDate = calendar.date(byAdding: .day, value: -dayCount, to: today) ?? today
        
        // Simulate loading workouts and snapshots
        // In real implementation, this would query from HealthEngine
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isLoading = false
        }
    }
}

// MARK: - Supporting Views

struct SummaryCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}

struct ZoneRow: View {
    let zone: PersonalizedMETZone
    let minutes: Double
    let total: Double
    
    private var percentage: Double {
        total > 0 ? (minutes / total) * 100 : 0
    }
    
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Circle()
                    .fill(Color(zone.color))
                    .frame(width: 12, height: 12)
                
                Text(zone.rawValue)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.0f min", minutes))
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text(String(format: "%.0f%%", percentage))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(zone.color).opacity(0.2))
                    .overlay(
                        HStack(spacing: 0) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(zone.color))
                                .frame(width: geometry.size.width * (percentage / 100))
                            Spacer()
                        }
                    )
            }
            .frame(height: 6)
        }
    }
}

struct WorkoutMETRow: View {
    let workout: WorkoutPersonalizedMET
    let profile: PersonalizedMETProfile
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.workoutType ?? "Workout")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(workout.workoutDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(String(format: "%.1f METs", workout.totalMETs))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                        Text(workout.zone.rawValue)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(workout.zone.color))
                            .cornerRadius(4)
                    }
                    Text(String(format: "%.0f min", workout.durationMinutes))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack(spacing: 8) {
                Image(systemName: "heart.fill")
                    .font(.caption2)
                    .foregroundColor(.red)
                Text("Avg: \(String(format: "%.0f", workout.averageHeartRate)) bpm")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Image(systemName: "bolt.fill")
                    .font(.caption2)
                    .foregroundColor(.orange)
                Text("Effort: \(String(format: "%.0f%%", workout.effortPercentage))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}

struct ExtendedTrendChart: View {
    let snapshots: [DailyPersonalizedMETSnapshot]
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            let maxBeneficial = snapshots.map { $0.beneficialMETs }.max() ?? 1
            let sortedSnapshots = snapshots.sorted { $0.date < $1.date }
            
            ForEach(sortedSnapshots, id: \.id) { snapshot in
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(snapshot.beneficialMETs > 0 ? Color.blue : Color(.systemGray4))
                        .frame(height: max(4, (snapshot.beneficialMETs / max(1, maxBeneficial)) * 80))
                    
                    Text(snapshot.date.formatted(.dateTime.day()))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Time Range Enum

enum METTimeRange: String, CaseIterable {
    case sevenDays = "7 Days"
    case thirtyDays = "30 Days"
    case ninetyDays = "90 Days"
    
    var dayCount: Int {
        switch self {
        case .sevenDays: return 7
        case .thirtyDays: return 30
        case .ninetyDays: return 90
        }
    }
    
    var displayName: String {
        self.rawValue
    }
}

#Preview {
    PersonalizedMETDetailView()
}
