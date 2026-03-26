//
//  ContentView.swift
//  Nutrivance for Apple Watch Watch App
//
//  Created by Vincent Leong on 3/25/26.
//

import Combine
import Foundation
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = WatchDashboardStore()
    @State private var selectedTab: DashboardTab = .overview

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                OverviewDashboardPage(store: store, selectedTab: $selectedTab)
                    .tag(DashboardTab.overview)

                StrainDashboardPage(store: store, selectedTab: $selectedTab)
                    .tag(DashboardTab.strain)

                RecoveryDashboardPage(store: store, selectedTab: $selectedTab)
                    .tag(DashboardTab.recovery)

                MindfulnessDashboardPage(store: store, selectedTab: $selectedTab)
                    .tag(DashboardTab.mindfulness)

                WorkoutHistoryDashboardPage(store: store)
                    .tag(DashboardTab.history)
            }
            .tabViewStyle(.verticalPage)
            .ignoresSafeArea()
            .containerBackground(.clear, for: .navigation)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: WatchDestination.self) { destination in
                destinationView(for: destination)
            }
        }
        .background(
            WatchDashboardBackground(style: selectedTab.backgroundStyle)
                .ignoresSafeArea()
        )
        .onAppear {
            store.refreshLiveData()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                store.refreshLiveData()
            }
        }
    }

    @ViewBuilder
    private func destinationView(for destination: WatchDestination) -> some View {
        switch destination {
        case .sleepManager:
            SleepManagerView(store: store)
        case .workoutLauncher:
            WorkoutLauncherView(store: store)
        case .journaling:
            JournalComposerView(store: store, title: "Journaling")
        case .hrZones:
            HRZonesView(store: store)
        case .load:
            TrainingLoadView(store: store)
        case .stats:
            StatsSnapshotView(store: store)
        case .coach:
            CoachSummaryView(store: store)
        case .vitals:
            VitalsDetailView(store: store)
        case .hrv:
            TrendMetricDetailView(
                title: "HRV",
                subtitle: "Daily average for the week",
                points: store.hrvWeek,
                unit: "ms",
                accent: .mint,
                idealRange: 52...65
            )
        case .hrr:
            TrendMetricDetailView(
                title: "HRR",
                subtitle: "Daily average for the week",
                points: store.hrrWeek,
                unit: "bpm",
                accent: .cyan,
                idealRange: 24...32
            )
        case .rhr:
            TrendMetricDetailView(
                title: "RHR",
                subtitle: "Daily average for the week",
                points: store.rhrWeek,
                unit: "bpm",
                accent: .pink,
                idealRange: 50...58
            )
        case .moodLogger:
            MoodLoggerView(store: store)
        case .stress:
            StressTrendView(store: store)
        case .sleep:
            SleepSnapshotView(store: store)
        case .journalSnippets:
            JournalComposerView(store: store, title: "Journal Snippets")
        case .workoutDetail(let workoutID):
            if let workout = store.workout(id: workoutID) {
                WorkoutDetailView(workout: workout)
            } else {
                MissingWorkoutView()
            }
        }
    }
}

private enum DashboardTab: Int, CaseIterable, Hashable {
    case overview
    case strain
    case recovery
    case mindfulness
    case history

    var backgroundStyle: WatchDashboardBackgroundStyle {
        switch self {
        case .overview, .history:
            return .neutral
        case .strain:
            return .orange
        case .recovery:
            return .green
        case .mindfulness:
            return .blue
        }
    }
}

private enum WatchDashboardBackgroundStyle {
    case neutral
    case orange
    case green
    case blue

    var topColor: Color {
        switch self {
        case .neutral:
            return Color(white: 0.20)
        case .orange:
            return Color(red: 0.38, green: 0.18, blue: 0.05)
        case .green:
            return Color(red: 0.08, green: 0.27, blue: 0.16)
        case .blue:
            return Color(red: 0.07, green: 0.18, blue: 0.30)
        }
    }

    var glowColor: Color {
        switch self {
        case .neutral:
            return Color.white.opacity(0.10)
        case .orange:
            return Color.orange.opacity(0.22)
        case .green:
            return Color.green.opacity(0.20)
        case .blue:
            return Color.cyan.opacity(0.22)
        }
    }
}

private enum WatchDestination: Hashable {
    case sleepManager
    case workoutLauncher
    case journaling
    case hrZones
    case load
    case stats
    case coach
    case vitals
    case hrv
    case hrr
    case rhr
    case moodLogger
    case stress
    case sleep
    case journalSnippets
    case workoutDetail(UUID)
}

private enum CornerPlacement {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
}

private enum MetricBand: String {
    case low = "Low"
    case optimal = "Optimal"
    case high = "High"

    var color: Color {
        switch self {
        case .low:
            return .blue
        case .optimal:
            return .green
        case .high:
            return .orange
        }
    }
}

enum CoachWindow: String, CaseIterable, Identifiable {
    case day = "1D"
    case week = "1W"
    case month = "1M"

    var id: String { rawValue }
}

private struct DashboardAction: Identifiable {
    let id = UUID()
    let title: String
    let symbol: String
    let placement: CornerPlacement
    let route: DashboardActionRoute
}

private enum DashboardActionRoute {
    case destination(WatchDestination)
    case tab(DashboardTab)
}

struct MetricPoint: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let value: Double
}

struct StressPoint: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let stress: Double
    let energy: Double
    let regulation: Double
}

struct JournalSnippet: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let text: String
}

struct WorkoutSession: Identifiable, Hashable {
    let id: UUID
    let title: String
    let subtitle: String
    let startDate: Date
    let durationMinutes: Int
    let calories: Int
    let distanceKilometers: Double?
    let averageHeartRate: Int
    let maxHeartRate: Int
    let strain: Double
    let load: Double
    let zoneMinutes: [Double]
    let note: String
}

struct VitalGauge: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let value: Double
    let displayValue: String
    let minimum: Double
    let normalRange: ClosedRange<Double>
    let maximum: Double
}

@MainActor
final class WatchDashboardStore: ObservableObject {
    @Published var wakeUpTime: Date
    @Published var latestMoodIndex: Int
    @Published var moodNote: String
    @Published var queuedWorkout: String?
    @Published var journalSnippets: [JournalSnippet]

    @Published var strainWeek: [MetricPoint]
    @Published var recoveryWeek: [MetricPoint]
    @Published var readinessWeek: [MetricPoint]
    @Published var mindfulnessWeek: [MetricPoint]
    @Published var trainingLoadWeek: [MetricPoint]
    @Published var hrvWeek: [MetricPoint]
    @Published var hrrWeek: [MetricPoint]
    @Published var rhrWeek: [MetricPoint]
    @Published var stressWeek: [StressPoint]
    @Published var workouts: [WorkoutSession]
    @Published var vitals: [VitalGauge]
    @Published var coachSummaries: [CoachWindow: String]
    @Published var recommendedSleepHours: Double = 8.3
    @Published var sleepDebtHours: Double = 1.4
    @Published var sleepScheduleText = "10:30 PM - 7:00 AM"
    @Published var sleepHours = 7.6
    @Published var sleepConsistency = 88.0
    @Published var sleepStages: [(name: String, hours: Double, color: Color)] = [
        ("Core", 4.2, Color.blue),
        ("REM", 1.7, Color.purple),
        ("Deep", 1.1, Color.indigo)
    ]
    let workoutTemplates = ["Outdoor Run", "Strength", "Cycle", "HIIT", "Walk"]
    @Published var stats: [(title: String, value: String, symbol: String, tint: Color)] = [
        ("Calories", "742 kcal", "flame.fill", .orange),
        ("Steps", "11,082", "figure.walk", .green),
        ("Active", "96 min", "bolt.heart.fill", .cyan),
        ("Move", "8.6 km", "location.fill", .yellow)
    ]
    @Published private(set) var lastSyncedAt: Date?

    let connectivityBridge = WatchConnectivityBridge()
    let healthBridge = WatchHealthBridge()

    init() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let wake = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: today) ?? Date()

        wakeUpTime = wake
        latestMoodIndex = 3
        moodNote = "Focused and steady."
        queuedWorkout = nil
        journalSnippets = [
            JournalSnippet(date: calendar.date(byAdding: .hour, value: -3, to: Date()) ?? Date(), text: "Morning run felt smooth."),
            JournalSnippet(date: calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date(), text: "Recovery improved after extra sleep.")
        ]

        strainWeek = Self.makeWeek(values: [11.2, 12.8, 10.7, 14.1, 13.6, 9.8, 12.4], anchoredTo: today)
        recoveryWeek = Self.makeWeek(values: [72, 76, 69, 81, 79, 74, 84], anchoredTo: today)
        readinessWeek = Self.makeWeek(values: [68, 71, 65, 78, 80, 73, 82], anchoredTo: today)
        mindfulnessWeek = Self.makeWeek(values: [55, 62, 60, 74, 70, 78, 82], anchoredTo: today)
        trainingLoadWeek = Self.makeWeek(values: [64, 72, 69, 81, 88, 76, 84], anchoredTo: today)
        hrvWeek = Self.makeWeek(values: [48, 52, 49, 57, 60, 54, 58], anchoredTo: today)
        hrrWeek = Self.makeWeek(values: [21, 24, 23, 27, 29, 25, 28], anchoredTo: today)
        rhrWeek = Self.makeWeek(values: [58, 57, 56, 55, 54, 55, 53], anchoredTo: today)
        stressWeek = Self.makeStressWeek(
            stress: [58, 49, 64, 42, 38, 46, 40],
            energy: [52, 60, 48, 66, 70, 62, 68],
            regulation: [61, 69, 58, 74, 77, 71, 79],
            anchoredTo: today
        )

        let morningRunStart = calendar.date(bySettingHour: 7, minute: 10, second: 0, of: Date()) ?? Date()
        let lunchStrengthStart = calendar.date(bySettingHour: 12, minute: 30, second: 0, of: Date()) ?? Date()
        let eveningWalkStart = calendar.date(bySettingHour: 18, minute: 5, second: 0, of: Date()) ?? Date()
        let yesterdayRideStart = calendar.date(byAdding: .day, value: -1, to: calendar.date(bySettingHour: 17, minute: 20, second: 0, of: Date()) ?? Date()) ?? Date()

        workouts = [
            WorkoutSession(
                id: UUID(),
                title: "Morning Run",
                subtitle: "Outdoor • Tempo",
                startDate: morningRunStart,
                durationMinutes: 41,
                calories: 468,
                distanceKilometers: 7.1,
                averageHeartRate: 152,
                maxHeartRate: 176,
                strain: 14.2,
                load: 82,
                zoneMinutes: [6, 9, 12, 10, 4],
                note: "Strong middle block with controlled finish."
            ),
            WorkoutSession(
                id: UUID(),
                title: "Strength",
                subtitle: "Upper body",
                startDate: lunchStrengthStart,
                durationMinutes: 34,
                calories: 244,
                distanceKilometers: nil,
                averageHeartRate: 126,
                maxHeartRate: 149,
                strain: 9.6,
                load: 68,
                zoneMinutes: [10, 12, 9, 3, 0],
                note: "Stable pacing with enough rest between sets."
            ),
            WorkoutSession(
                id: UUID(),
                title: "Evening Walk",
                subtitle: "Recovery",
                startDate: eveningWalkStart,
                durationMinutes: 28,
                calories: 118,
                distanceKilometers: 2.4,
                averageHeartRate: 101,
                maxHeartRate: 118,
                strain: 4.1,
                load: 38,
                zoneMinutes: [19, 7, 2, 0, 0],
                note: "Easy recovery walk to downshift before bed."
            ),
            WorkoutSession(
                id: UUID(),
                title: "Bike Ride",
                subtitle: "Yesterday",
                startDate: yesterdayRideStart,
                durationMinutes: 52,
                calories: 522,
                distanceKilometers: 18.6,
                averageHeartRate: 148,
                maxHeartRate: 168,
                strain: 13.4,
                load: 79,
                zoneMinutes: [5, 11, 16, 12, 8],
                note: "Progressive build with strong finish."
            )
        ]

        vitals = [
            VitalGauge(title: "Sleep HR", value: 52, displayValue: "52 bpm", minimum: 42, normalRange: 48...60, maximum: 72),
            VitalGauge(title: "Respiratory", value: 14.3, displayValue: "14.3 br/min", minimum: 10, normalRange: 12...18, maximum: 22),
            VitalGauge(title: "Wrist Temp", value: 0.2, displayValue: "+0.2 C", minimum: -1.0, normalRange: -0.3...0.3, maximum: 1.0),
            VitalGauge(title: "SpO2", value: 97, displayValue: "97%", minimum: 88, normalRange: 95...100, maximum: 100),
            VitalGauge(title: "Sleep Hours", value: 7.6, displayValue: "7.6 h", minimum: 4, normalRange: 7...9, maximum: 10),
            VitalGauge(title: "Consistency", value: 88, displayValue: "88%", minimum: 50, normalRange: 75...100, maximum: 100)
        ]

        coachSummaries = [
            .day: "Today favored controlled loading. Strain landed in range, recovery bounced back, and mindfulness improved after the evening downshift. Keep tomorrow moderate unless sleep shortens.",
            .week: "This week balanced quality work and recovery well. The best days paired moderate strain with rising readiness, while low-stress evenings kept vitals near normal. Hold the current load progression.",
            .month: "This month shows a solid aerobic base with steadier recovery patterns. Readiness is trending upward when sleep consistency stays above target, so the biggest upside is protecting bedtime regularity."
        ]

        startLiveServices()
    }

    var currentStrain: Double { strainWeek.last?.value ?? 0 }
    var currentRecovery: Double { recoveryWeek.last?.value ?? 0 }
    var currentReadiness: Double { readinessWeek.last?.value ?? 0 }
    var currentMindfulness: Double { mindfulnessWeek.last?.value ?? 0 }

    var todayWorkouts: [WorkoutSession] {
        workouts
            .filter { Calendar.current.isDateInToday($0.startDate) }
            .sorted { $0.startDate > $1.startDate }
    }

    var vitalsNormalityScore: Int {
        guard !vitals.isEmpty else { return 0 }
        let normalCount = vitals.filter { band(for: $0.value, idealRange: $0.normalRange) == .optimal }.count
        return Int((Double(normalCount) / Double(vitals.count) * 100).rounded())
    }

    var vitalsNormalityLabel: String {
        switch vitalsNormalityScore {
        case 90...100:
            return "Vitals are steady"
        case 75..<90:
            return "Vitals look good"
        default:
            return "Vitals need attention"
        }
    }

    func coachSummary(for window: CoachWindow) -> String {
        coachSummaries[window] ?? ""
    }

    func addJournalSnippet(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        journalSnippets.insert(JournalSnippet(date: Date(), text: trimmed), at: 0)
    }

    func workout(id: UUID) -> WorkoutSession? {
        workouts.first(where: { $0.id == id })
    }

    func zoneMinutes(for workoutID: UUID?) -> [Double] {
        if let workoutID, let workout = workout(id: workoutID) {
            return workout.zoneMinutes
        }

        return todayWorkouts.reduce(into: Array(repeating: 0.0, count: 5)) { partialResult, workout in
            for index in partialResult.indices {
                partialResult[index] += workout.zoneMinutes[index]
            }
        }
    }

    private static func makeWeek(values: [Double], anchoredTo date: Date) -> [MetricPoint] {
        let calendar = Calendar.current

        return values.enumerated().compactMap { index, value in
            guard let day = calendar.date(byAdding: .day, value: index - (values.count - 1), to: date) else {
                return nil
            }

            return MetricPoint(date: day, value: value)
        }
    }

    private static func makeStressWeek(stress: [Double], energy: [Double], regulation: [Double], anchoredTo date: Date) -> [StressPoint] {
        let calendar = Calendar.current

        return stress.indices.compactMap { index in
            guard let day = calendar.date(byAdding: .day, value: index - (stress.count - 1), to: date) else {
                return nil
            }

            return StressPoint(
                date: day,
                stress: stress[index],
                energy: energy[index],
                regulation: regulation[index]
            )
        }
    }

    func markSynced(at date: Date) {
        lastSyncedAt = date
    }
}

private struct OverviewDashboardPage: View {
    @ObservedObject var store: WatchDashboardStore
    @Binding var selectedTab: DashboardTab

    private var actions: [DashboardAction] {
        [
            DashboardAction(title: "Sleep Manager", symbol: "bed.double.fill", placement: .topLeading, route: .destination(.sleepManager)),
            DashboardAction(title: "Workouts", symbol: "list.bullet", placement: .topTrailing, route: .tab(.history)),
            DashboardAction(title: "Workout", symbol: "figure.run.circle.fill", placement: .bottomLeading, route: .destination(.workoutLauncher)),
            DashboardAction(title: "Journaling", symbol: "square.and.pencil", placement: .bottomTrailing, route: .destination(.journaling))
        ]
    }

    var body: some View {
        DashboardPageContainer(
            title: nil,
            subtitle: nil,
            actions: actions,
            selectedTab: $selectedTab
        ) {
            TripleMetricRing(
                strain: store.currentStrain / 21,
                recovery: store.currentRecovery / 100,
                readiness: store.currentReadiness / 100
            )
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct StrainDashboardPage: View {
    @ObservedObject var store: WatchDashboardStore
    @Binding var selectedTab: DashboardTab

    private var actions: [DashboardAction] {
        [
            DashboardAction(title: "HR Zones", symbol: "heart.text.square.fill", placement: .topLeading, route: .destination(.hrZones)),
            DashboardAction(title: "Load", symbol: "chart.line.uptrend.xyaxis", placement: .topTrailing, route: .destination(.load)),
            DashboardAction(title: "Stats", symbol: "figure.walk", placement: .bottomLeading, route: .destination(.stats)),
            DashboardAction(title: "Coach", symbol: "sparkles", placement: .bottomTrailing, route: .destination(.coach))
        ]
    }

    var body: some View {
        DashboardPageContainer(
            title: "Strain",
            subtitle: "Weekly load",
            actions: actions,
            selectedTab: $selectedTab
        ) {
            VStack(spacing: 6) {
                HStack {
                    Text("Weekly Load")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text(String(format: "%.1f", store.currentStrain))
                        .font(.caption.weight(.bold))
                }
                .frame(maxWidth: .infinity)

                WeeklyBarChart(
                    points: store.strainWeek,
                    accent: .orange,
                    highlightedIndex: store.strainWeek.count - 1
                )
                .frame(height: 58)
            }
        }
    }
}

private struct RecoveryDashboardPage: View {
    @ObservedObject var store: WatchDashboardStore
    @Binding var selectedTab: DashboardTab

    private var actions: [DashboardAction] {
        [
            DashboardAction(title: "Vitals", symbol: "waveform.path.ecg", placement: .topLeading, route: .destination(.vitals)),
            DashboardAction(title: "HRV", symbol: "heart.fill", placement: .topTrailing, route: .destination(.hrv)),
            DashboardAction(title: "HRR", symbol: "bolt.heart.fill", placement: .bottomLeading, route: .destination(.hrr)),
            DashboardAction(title: "RHR", symbol: "moon.zzz.fill", placement: .bottomTrailing, route: .destination(.rhr))
        ]
    }

    var body: some View {
        DashboardPageContainer(
            title: "Recovery",
            subtitle: "Recovery + readiness",
            actions: actions,
            selectedTab: $selectedTab
        ) {
            WeeklyDualBarChart(
                primaryPoints: store.recoveryWeek,
                primaryColor: .cyan,
                secondaryPoints: store.readinessWeek,
                secondaryColor: .mint
            )
            .frame(height: 62)
        }
    }
}

private struct MindfulnessDashboardPage: View {
    @ObservedObject var store: WatchDashboardStore
    @Binding var selectedTab: DashboardTab

    private var actions: [DashboardAction] {
        [
            DashboardAction(title: "Mood Logger", symbol: "face.smiling.inverse", placement: .topLeading, route: .destination(.moodLogger)),
            DashboardAction(title: "Stress", symbol: "waveform.badge.exclamationmark", placement: .topTrailing, route: .destination(.stress)),
            DashboardAction(title: "Sleep", symbol: "bed.double.circle.fill", placement: .bottomLeading, route: .destination(.sleep)),
            DashboardAction(title: "Journal Snippets", symbol: "text.book.closed.fill", placement: .bottomTrailing, route: .destination(.journalSnippets))
        ]
    }

    var body: some View {
        DashboardPageContainer(
            title: nil,
            subtitle: nil,
            actions: actions,
            selectedTab: $selectedTab
        ) {
            MindfulnessRing(score: store.currentMindfulness)
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct WorkoutHistoryDashboardPage: View {
    @ObservedObject var store: WatchDashboardStore

    var body: some View {
        ZStack {
            WatchDashboardBackground(style: .neutral)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Today")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.72))

                    Text("Workout History")
                        .font(.headline.weight(.semibold))

                    if store.todayWorkouts.isEmpty {
                        SectionCard(title: "No workouts today") {
                            Text("Start a workout from the launcher to populate this list.")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.72))
                        }
                    } else {
                        ForEach(store.todayWorkouts) { workout in
                            NavigationLink(value: WatchDestination.workoutDetail(workout.id)) {
                                WorkoutRowCard(workout: workout)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(12)
            }
        }
    }
}

private struct DashboardPageContainer<Content: View>: View {
    let title: String?
    let subtitle: String?
    let actions: [DashboardAction]
    @Binding var selectedTab: DashboardTab
    let content: Content

    init(
        title: String?,
        subtitle: String?,
        actions: [DashboardAction],
        selectedTab: Binding<DashboardTab>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.actions = actions
        _selectedTab = selectedTab
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .containerBackground(.clear, for: .navigation)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                if let topLeading = action(for: .topLeading) {
                    ToolbarItem(placement: .topBarLeading) {
                        dashboardActionView(for: topLeading)
                    }
                }

                if let topTrailing = action(for: .topTrailing) {
                    ToolbarItem(placement: .topBarTrailing) {
                        dashboardActionView(for: topTrailing)
                    }
                }

                if action(for: .bottomLeading) != nil || action(for: .bottomTrailing) != nil {
                    ToolbarItemGroup(placement: .bottomBar) {
                        if let bottomLeading = action(for: .bottomLeading) {
                            dashboardActionView(for: bottomLeading)
                        }

                        Spacer(minLength: 0)

                        if let bottomTrailing = action(for: .bottomTrailing) {
                            dashboardActionView(for: bottomTrailing)
                        }
                    }
                }
            }
    }

    private func action(for placement: CornerPlacement) -> DashboardAction? {
        actions.first(where: { $0.placement == placement })
    }

    @ViewBuilder
    private func dashboardActionView(for action: DashboardAction) -> some View {
        switch action.route {
        case .destination(let destination):
            NavigationLink(value: destination) {
                actionLabel(for: action)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(action.title)
        case .tab(let tab):
            Button {
                selectedTab = tab
            } label: {
                actionLabel(for: action)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(action.title)
        }
    }

    private func actionLabel(for action: DashboardAction) -> some View {
        UniformToolbarBubble(symbol: action.symbol)
    }
}

private struct UniformToolbarBubble: View {
    let symbol: String

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.22))

            Circle()
                .stroke(Color.white.opacity(0.16), lineWidth: 1)

            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 36, height: 36)
    }
}

private struct ActionBubble: View {
    let symbol: String
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.24))

            Circle()
                .stroke(tint.opacity(0.55), lineWidth: 1)

            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 32, height: 32)
        .shadow(color: tint.opacity(0.25), radius: 5, y: 2)
    }
}

private struct WatchScoreRow: View {
    let title: String
    let value: String
    let progress: Double
    let band: MetricBand

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(value)
                    .font(.caption.weight(.bold))
                StatusPill(band: band)
            }

            ProgressView(value: progress.clamped(to: 0...1))
                .tint(band.color)
                .scaleEffect(x: 1, y: 0.85, anchor: .center)
        }
    }
}

private struct TripleMetricRing: View {
    let strain: Double
    let recovery: Double
    let readiness: Double

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height) * 0.78
            let lineWidth = max(12, size * 0.115)

            ZStack {
                ring(progress: readiness, lineWidth: lineWidth, diameter: size, color: Color(red: 0.20, green: 0.78, blue: 0.35))
                ring(progress: recovery, lineWidth: lineWidth, diameter: size * 0.72, color: Color(red: 0.45, green: 0.80, blue: 1.0))
                ring(progress: strain, lineWidth: lineWidth, diameter: size * 0.45, color: .orange)

                HStack(spacing: size * 0.06) {
                    symbolBadge(symbol: "flame.fill", color: .orange, size: size)
                    symbolBadge(symbol: "heart.fill", color: Color(red: 0.45, green: 0.80, blue: 1.0), size: size)
                    symbolBadge(symbol: "checkmark", color: Color(red: 0.20, green: 0.78, blue: 0.35), size: size)
                }
                .offset(y: -size * 0.23)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func ring(progress: Double, lineWidth: CGFloat, diameter: CGFloat, color: Color) -> some View {
        Circle()
            .stroke(Color.white.opacity(0.10), lineWidth: lineWidth)
            .overlay {
                Circle()
                    .trim(from: 0, to: progress.clamped(to: 0...1))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: diameter, height: diameter)
    }

    private func symbolBadge(symbol: String, color: Color, size: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: max(9, size * 0.075), weight: .bold))
            .foregroundStyle(color)
            .frame(width: max(16, size * 0.13), height: max(16, size * 0.13))
            .background(Color.black.opacity(0.28))
            .clipShape(Circle())
    }
}

private struct StatusPill: View {
    let band: MetricBand

    var body: some View {
        Text(band.rawValue)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(band.color.opacity(0.22))
            .clipShape(Capsule())
            .foregroundStyle(.white)
    }
}

private struct VitalsNormalityCard: View {
    let score: Int
    let caption: String

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Vitals Normality")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(score)%")
                    .font(.caption.weight(.bold))
            }

            ProgressView(value: Double(score), total: 100)
                .tint(score >= 80 ? .green : .orange)

            Text(caption)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.72))
        }
        .padding(10)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct LegendTag: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text(label)
                .foregroundStyle(.white.opacity(0.82))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
    }
}

private struct MiniTrendChart: View {
    let points: [MetricPoint]
    let accent: Color
    let secondaryPoints: [MetricPoint]?
    let highlightedIndex: Int?

    var body: some View {
        GeometryReader { proxy in
            let rect = proxy.frame(in: .local)
            let minValue = minimumValue()
            let maxValue = maximumValue()

            ZStack {
                VStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.white.opacity(0.05))
                            .frame(height: 1)
                        Spacer()
                    }
                }
                .padding(.vertical, 10)

                LineChartPath(
                    points: points.map(\.value),
                    minValue: minValue,
                    maxValue: maxValue
                )
                .stroke(accent, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))

                if let secondaryPoints {
                    LineChartPath(
                        points: secondaryPoints.map(\.value),
                        minValue: minValue,
                        maxValue: maxValue
                    )
                    .stroke(Color.white.opacity(0.32), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
                }

                if let highlightedIndex,
                   points.indices.contains(highlightedIndex),
                   points.count > 1 {
                    let x = rect.minX + rect.width * CGFloat(highlightedIndex) / CGFloat(points.count - 1)
                    let y = yPosition(for: points[highlightedIndex].value, in: rect, minValue: minValue, maxValue: maxValue)

                    Circle()
                        .fill(accent)
                        .frame(width: 9, height: 9)
                        .position(x: x, y: y)
                        .shadow(color: accent.opacity(0.45), radius: 4)
                }
            }
        }
    }

    private func minimumValue() -> Double {
        let primary = points.map(\.value)
        let secondary = secondaryPoints?.map(\.value) ?? []
        return min(primary.min() ?? 0, secondary.min() ?? primary.min() ?? 0)
    }

    private func maximumValue() -> Double {
        let primary = points.map(\.value)
        let secondary = secondaryPoints?.map(\.value) ?? []
        return max(primary.max() ?? 1, secondary.max() ?? primary.max() ?? 1)
    }

    private func yPosition(for value: Double, in rect: CGRect, minValue: Double, maxValue: Double) -> CGFloat {
        let inset: CGFloat = 10
        guard maxValue > minValue else { return rect.midY }
        let ratio = (value - minValue) / (maxValue - minValue)
        return rect.maxY - inset - (rect.height - inset * 2) * CGFloat(ratio)
    }
}

private struct WeeklyBarChart: View {
    let points: [MetricPoint]
    let accent: Color
    let highlightedIndex: Int?

    var body: some View {
        GeometryReader { proxy in
            let maxValue = max(points.map(\.value).max() ?? 1, 1)
            let yLabelWidth: CGFloat = 18
            let xLabelHeight: CGFloat = 12
            let chartHeight = max(proxy.size.height - xLabelHeight - 4, 26)
            let plotWidth = max(proxy.size.width - yLabelWidth - 4, 40)
            let barWidth = min(14, max(6, (plotWidth - CGFloat(max(points.count - 1, 0)) * 4) / CGFloat(max(points.count, 1))))

            VStack(spacing: 4) {
                HStack(alignment: .bottom, spacing: 4) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(String(format: "%.0f", maxValue))
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.white.opacity(0.58))
                        Spacer()
                        Text("0")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.white.opacity(0.58))
                    }
                    .frame(width: yLabelWidth, height: chartHeight)

                    ZStack(alignment: .bottomLeading) {
                        Rectangle()
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 1, height: chartHeight)

                        Rectangle()
                            .fill(Color.white.opacity(0.18))
                            .frame(height: 1)

                        HStack(alignment: .bottom, spacing: 4) {
                            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                                let isHighlighted = highlightedIndex == index
                                let ratio = point.value / maxValue

                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(isHighlighted ? accent : accent.opacity(0.72))
                                    .frame(width: barWidth, height: max(10, (chartHeight - 2) * CGFloat(ratio.clamped(to: 0...1))))
                            }
                        }
                        .padding(.leading, 4)
                    }
                    .frame(width: plotWidth, height: chartHeight, alignment: .bottomLeading)
                }

                HStack(spacing: 4) {
                    Spacer()
                        .frame(width: yLabelWidth)

                    HStack(spacing: 4) {
                        ForEach(points) { point in
                            Text(weekdayLetter(point.date))
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.white.opacity(0.62))
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

private struct WeeklyDualBarChart: View {
    let primaryPoints: [MetricPoint]
    let primaryColor: Color
    let secondaryPoints: [MetricPoint]
    let secondaryColor: Color

    var body: some View {
        GeometryReader { proxy in
            let maxValue = max(
                primaryPoints.map(\.value).max() ?? 1,
                secondaryPoints.map(\.value).max() ?? 1,
                1
            )
            let yLabelWidth: CGFloat = 18
            let xLabelHeight: CGFloat = 12
            let chartHeight = max(proxy.size.height - xLabelHeight - 4, 26)
            let plotWidth = max(proxy.size.width - yLabelWidth - 4, 40)
            let dayWidth = min(18, max(10, (plotWidth - CGFloat(max(primaryPoints.count - 1, 0)) * 4) / CGFloat(max(primaryPoints.count, 1))))
            let barWidth = max(4, (dayWidth - 3) / 2)

            VStack(spacing: 4) {
                HStack(alignment: .bottom, spacing: 4) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(String(format: "%.0f", maxValue))
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.white.opacity(0.58))
                        Spacer()
                        Text("0")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.white.opacity(0.58))
                    }
                    .frame(width: yLabelWidth, height: chartHeight)

                    ZStack(alignment: .bottomLeading) {
                        Rectangle()
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 1, height: chartHeight)

                        Rectangle()
                            .fill(Color.white.opacity(0.18))
                            .frame(height: 1)

                        HStack(alignment: .bottom, spacing: 4) {
                            ForEach(primaryPoints.indices, id: \.self) { index in
                                let primaryRatio = primaryPoints[index].value / maxValue
                                let secondaryValue = secondaryPoints[safe: index]?.value ?? 0
                                let secondaryRatio = secondaryValue / maxValue

                                HStack(alignment: .bottom, spacing: 3) {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(primaryColor)
                                        .frame(width: barWidth, height: max(10, (chartHeight - 2) * CGFloat(primaryRatio.clamped(to: 0...1))))

                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(secondaryColor)
                                        .frame(width: barWidth, height: max(10, (chartHeight - 2) * CGFloat(secondaryRatio.clamped(to: 0...1))))
                                }
                                .frame(width: dayWidth, alignment: .center)
                            }
                        }
                        .padding(.leading, 4)
                    }
                    .frame(width: plotWidth, height: chartHeight, alignment: .bottomLeading)
                }

                HStack(spacing: 4) {
                    Spacer()
                        .frame(width: yLabelWidth)

                    HStack(spacing: 4) {
                        ForEach(primaryPoints) { point in
                            Text(weekdayLetter(point.date))
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.white.opacity(0.62))
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

private struct MindfulnessRing: View {
    let score: Double

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height) * 0.78
            let lineWidth = max(13, size * 0.125)

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: lineWidth)

                Circle()
                    .trim(from: 0, to: score.clamped(to: 0...100) / 100)
                    .stroke(
                        AngularGradient(
                            colors: [.mint, .teal, .blue, .pink],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Text(String(format: "%.0f", score))
                    .font(.system(size: max(26, size * 0.22), weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct SectionCard<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))

            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct WatchDashboardBackground: View {
    let style: WatchDashboardBackgroundStyle

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [style.topColor, .black],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [style.glowColor, .clear],
                center: .top,
                startRadius: 10,
                endRadius: 180
            )
            .blendMode(.screen)
        }
    }
}

private struct MetricLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
        }
    }
}

private struct WorkoutRowCard: View {
    let workout: WorkoutSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.title)
                        .font(.caption.weight(.semibold))
                    Text(workout.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.72))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.45))
            }

            HStack(spacing: 8) {
                WorkoutTag(text: shortTime(workout.startDate), symbol: "clock.fill")
                WorkoutTag(text: "\(workout.durationMinutes)m", symbol: "timer")
                WorkoutTag(text: "\(workout.calories)", symbol: "flame.fill")
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct WorkoutTag: View {
    let text: String
    let symbol: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
            Text(text)
                .font(.system(size: 9, weight: .semibold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
    }
}

private struct SleepManagerView: View {
    @ObservedObject var store: WatchDashboardStore

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                SectionCard(title: "Tonight") {
                    MetricLine(label: "Recommended", value: hoursString(store.recommendedSleepHours))
                    MetricLine(label: "Sleep debt", value: hoursString(store.sleepDebtHours))
                    MetricLine(label: "Schedule", value: store.sleepScheduleText)
                }

                SectionCard(title: "Wake-Up Timer") {
                    DatePicker("Wake Time", selection: $store.wakeUpTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }

                SectionCard(title: "Suggestion") {
                    Text("Aim to start your wind-down by 10:05 PM to clear the current sleep debt inside the next two nights.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.78))
                }
            }
            .padding(10)
        }
        .navigationTitle("Sleep Manager")
    }
}

private struct WorkoutLauncherView: View {
    @ObservedObject var store: WatchDashboardStore

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if let queuedWorkout = store.queuedWorkout {
                    SectionCard(title: "Ready") {
                        Text("\(queuedWorkout) is queued for start.")
                            .font(.caption2)
                    }
                }

                ForEach(store.workoutTemplates, id: \.self) { workout in
                    Button {
                        store.queuedWorkout = workout
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(workout)
                                    .font(.caption.weight(.semibold))
                                Text("Tap to stage")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.68))
                            }
                            Spacer()
                            Image(systemName: "play.fill")
                                .font(.caption.weight(.bold))
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
        }
        .navigationTitle("Workout")
    }
}

private struct JournalComposerView: View {
    @ObservedObject var store: WatchDashboardStore
    let title: String
    @State private var draft = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                SectionCard(title: "New Entry") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Add a short note", text: $draft)
                            .padding(8)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        Button("Save") {
                            store.addJournalSnippet(draft)
                            draft = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.pink)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                if !store.journalSnippets.isEmpty {
                    SectionCard(title: "Recent") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(store.journalSnippets.prefix(4)) { snippet in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(snippet.text)
                                        .font(.caption2)
                                    Text(relativeDate(snippet.date))
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.55))
                                }
                            }
                        }
                    }
                }
            }
            .padding(10)
        }
        .navigationTitle(title)
    }
}

private struct HRZonesView: View {
    @ObservedObject var store: WatchDashboardStore
    @State private var selectedWorkoutID: UUID?

    var body: some View {
        let zoneMinutes = store.zoneMinutes(for: selectedWorkoutID)
        let maxValue = zoneMinutes.max() ?? 1

        ScrollView {
            VStack(spacing: 10) {
                SectionCard(title: "Time in Zone") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(selectedWorkoutID == nil ? "All workouts today" : "Specific workout")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.72))
                            Spacer()
                            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.pink)
                        }

                        Picker("Workout Filter", selection: $selectedWorkoutID) {
                            Text("All workouts today")
                                .tag(UUID?.none)
                            ForEach(store.todayWorkouts) { workout in
                                Text(workout.title)
                                    .tag(UUID?.some(workout.id))
                            }
                        }
                        .labelsHidden()

                        ForEach(zoneMinutes.indices, id: \.self) { index in
                            ZoneBarRow(
                                label: "Zone \(index + 1)",
                                minutes: zoneMinutes[index],
                                maxValue: maxValue,
                                color: zoneColor(index)
                            )
                        }
                    }
                }
            }
            .padding(10)
        }
        .navigationTitle("HR Zones")
    }
}

private struct ZoneBarRow: View {
    let label: String
    let minutes: Double
    let maxValue: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(Int(minutes.rounded())) min")
                    .font(.caption2)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(color)
                        .frame(width: proxy.size.width * CGFloat(minutes / max(maxValue, 1)))
                }
            }
            .frame(height: 8)
        }
    }
}

private struct TrainingLoadView: View {
    @ObservedObject var store: WatchDashboardStore

    var body: some View {
        CrownControlledMetricView(
            title: "Load",
            subtitle: "Scroll the Digital Crown through the week",
            points: store.trainingLoadWeek,
            unit: "TL",
            accent: .orange,
            idealRange: 70...90
        )
    }
}

private struct StatsSnapshotView: View {
    @ObservedObject var store: WatchDashboardStore

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(store.stats, id: \.title) { stat in
                    SectionCard(title: stat.title) {
                        HStack {
                            Image(systemName: stat.symbol)
                                .foregroundStyle(stat.tint)
                            Text(stat.value)
                                .font(.headline.weight(.semibold))
                        }
                    }
                }
            }
            .padding(10)
        }
        .navigationTitle("Stats")
    }
}

private struct CoachSummaryView: View {
    @ObservedObject var store: WatchDashboardStore
    @State private var selectedWindow: CoachWindow = .day

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                SectionCard(title: "Report Window") {
                    Picker("Window", selection: $selectedWindow) {
                        ForEach(CoachWindow.allCases) { window in
                            Text(window.rawValue)
                                .tag(window)
                        }
                    }
                    .labelsHidden()
                }

                SectionCard(title: "Coach Summary") {
                    Text(store.coachSummary(for: selectedWindow))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.82))
                }
            }
            .padding(10)
        }
        .navigationTitle("Coach")
    }
}

private struct VitalsDetailView: View {
    @ObservedObject var store: WatchDashboardStore

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(store.vitals) { vital in
                    SectionCard(title: vital.title) {
                        VitalGaugeRow(gauge: vital)
                    }
                }
            }
            .padding(10)
        }
        .navigationTitle("Vitals")
    }
}

private struct VitalGaugeRow: View {
    let gauge: VitalGauge

    var body: some View {
        let span = max(gauge.maximum - gauge.minimum, 0.01)
        let lowRatio = (gauge.normalRange.lowerBound - gauge.minimum) / span
        let normalRatio = (gauge.normalRange.upperBound - gauge.normalRange.lowerBound) / span
        let valueRatio = (gauge.value - gauge.minimum) / span
        let currentBand = band(for: gauge.value, idealRange: gauge.normalRange)

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(gauge.displayValue)
                    .font(.headline.weight(.semibold))
                Spacer()
                StatusPill(band: currentBand)
            }

            GeometryReader { proxy in
                let fullWidth = proxy.size.width
                let lowWidth = fullWidth * CGFloat(lowRatio.clamped(to: 0...1))
                let normalWidth = fullWidth * CGFloat(normalRatio.clamped(to: 0...1))
                let highWidth = max(fullWidth - lowWidth - normalWidth, 0)
                let markerX = fullWidth * CGFloat(valueRatio.clamped(to: 0...1))

                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.blue.opacity(0.55))
                            .frame(width: lowWidth)
                        Rectangle()
                            .fill(Color.green.opacity(0.75))
                            .frame(width: normalWidth)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.orange.opacity(0.55))
                            .frame(width: highWidth)
                    }

                    Circle()
                        .fill(.white)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(currentBand.color, lineWidth: 2))
                        .offset(x: markerX - 5)
                }
            }
            .frame(height: 12)
        }
    }
}

private struct TrendMetricDetailView: View {
    let title: String
    let subtitle: String
    let points: [MetricPoint]
    let unit: String
    let accent: Color
    let idealRange: ClosedRange<Double>

    var body: some View {
        CrownControlledMetricView(
            title: title,
            subtitle: subtitle,
            points: points,
            unit: unit,
            accent: accent,
            idealRange: idealRange
        )
    }
}

private struct CrownControlledMetricView: View {
    let title: String
    let subtitle: String
    let points: [MetricPoint]
    let unit: String
    let accent: Color
    let idealRange: ClosedRange<Double>

    @State private var crownSelection: Double = 0

    private var selectedIndex: Int {
        guard !points.isEmpty else { return 0 }
        return Int(crownSelection.rounded()).clamped(to: 0...(points.count - 1))
    }

    var body: some View {
        GeometryReader { proxy in
            let compactHeight = proxy.size.height < 220
            let chartHeight = min(max(proxy.size.height * 0.22, 62), 82)
            let point = points[safe: selectedIndex]
            let selectedValue = point?.value ?? 0
            let selectedBand = band(for: selectedValue, idealRange: idealRange)

            VStack(spacing: compactHeight ? 8 : 10) {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)

                MiniTrendChart(
                    points: points,
                    accent: accent,
                    secondaryPoints: nil,
                    highlightedIndex: selectedIndex
                )
                .frame(height: chartHeight)

                SectionCard(title: point.map { shortDay($0.date) } ?? "No Data") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(formattedMetricValue(selectedValue, unit: unit))
                                .font(.headline.weight(.semibold))
                            Spacer()
                            StatusPill(band: selectedBand)
                        }

                        Text(detailMessage(for: selectedValue, title: title, band: selectedBand))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.78))
                    }
                }

                Text("Use the Digital Crown to change the selected day.")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .scenePadding(.horizontal)
            .padding(.vertical, compactHeight ? 8 : 10)
        }
        .navigationTitle(title)
        .focusable(true)
        .digitalCrownRotation(
            $crownSelection,
            from: 0,
            through: Double(max(points.count - 1, 0)),
            by: 1,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onAppear {
            crownSelection = Double(max(points.count - 1, 0))
        }
    }
}

private struct MoodLoggerView: View {
    @ObservedObject var store: WatchDashboardStore

    private let moods: [(label: String, symbol: String)] = [
        ("Low", "cloud.drizzle.fill"),
        ("Flat", "cloud.fill"),
        ("Good", "sun.haze.fill"),
        ("Great", "sun.max.fill"),
        ("Peak", "sparkles")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                SectionCard(title: "Today") {
                    HStack(spacing: 6) {
                        ForEach(moods.indices, id: \.self) { index in
                            Button {
                                store.latestMoodIndex = index
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: moods[index].symbol)
                                        .font(.caption.weight(.bold))
                                    Text("\(index + 1)")
                                        .font(.system(size: 9, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(index == store.latestMoodIndex ? Color.yellow.opacity(0.28) : Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                SectionCard(title: "Current Mood") {
                    Text(moods[store.latestMoodIndex].label)
                        .font(.headline.weight(.semibold))
                    Text(store.moodNote)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .padding(10)
        }
        .navigationTitle("Mood Logger")
    }
}

private struct StressTrendView: View {
    @ObservedObject var store: WatchDashboardStore
    @State private var crownSelection: Double = 0

    private var selectedIndex: Int {
        guard !store.stressWeek.isEmpty else { return 0 }
        return Int(crownSelection.rounded()).clamped(to: 0...(store.stressWeek.count - 1))
    }

    var body: some View {
        GeometryReader { proxy in
            let compactHeight = proxy.size.height < 220
            let chartHeight = min(max(proxy.size.height * 0.22, 62), 82)
            let point = store.stressWeek[safe: selectedIndex]

            VStack(spacing: compactHeight ? 8 : 10) {
                Text("Stress, energy, and regulation from the weekly trend")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)

                MiniTrendChart(
                    points: store.stressWeek.map { MetricPoint(date: $0.date, value: $0.stress) },
                    accent: .red,
                    secondaryPoints: nil,
                    highlightedIndex: selectedIndex
                )
                .frame(height: chartHeight)

                if let point {
                    SectionCard(title: shortDay(point.date)) {
                        VStack(alignment: .leading, spacing: 8) {
                            MetricLine(label: "Stress", value: "\(Int(point.stress.rounded()))")
                            MetricLine(label: "Energy", value: "\(Int(point.energy.rounded()))")
                            MetricLine(label: "Regulation", value: "\(Int(point.regulation.rounded()))")
                        }
                    }
                }

                Text("Use the Digital Crown to move through the week.")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .scenePadding(.horizontal)
            .padding(.vertical, compactHeight ? 8 : 10)
        }
        .navigationTitle("Stress")
        .focusable(true)
        .digitalCrownRotation(
            $crownSelection,
            from: 0,
            through: Double(max(store.stressWeek.count - 1, 0)),
            by: 1,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onAppear {
            crownSelection = Double(max(store.stressWeek.count - 1, 0))
        }
    }
}

private struct SleepSnapshotView: View {
    @ObservedObject var store: WatchDashboardStore

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                SectionCard(title: "Sleep Snapshot") {
                    MetricLine(label: "Hours", value: String(format: "%.1f h", store.sleepHours))
                    MetricLine(label: "Consistency", value: "\(Int(store.sleepConsistency.rounded()))%")
                }

                SectionCard(title: "Stages") {
                    VStack(spacing: 10) {
                        ForEach(store.sleepStages, id: \.name) { stage in
                            StageBarRow(name: stage.name, hours: stage.hours, total: store.sleepHours, color: stage.color)
                        }
                    }
                }
            }
            .padding(10)
        }
        .navigationTitle("Sleep")
    }
}

private struct StageBarRow: View {
    let name: String
    let hours: Double
    let total: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(String(format: "%.1f h", hours))
                    .font(.caption2)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(color)
                        .frame(width: proxy.size.width * CGFloat((hours / max(total, 0.1)).clamped(to: 0...1)))
                }
            }
            .frame(height: 8)
        }
    }
}

private struct WorkoutDetailView: View {
    let workout: WorkoutSession

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                SectionCard(title: workout.title) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(workout.subtitle)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.72))
                        MetricLine(label: "Start", value: shortTime(workout.startDate))
                        MetricLine(label: "Duration", value: "\(workout.durationMinutes) min")
                        MetricLine(label: "Calories", value: "\(workout.calories) kcal")
                        if let distance = workout.distanceKilometers {
                            MetricLine(label: "Distance", value: String(format: "%.1f km", distance))
                        }
                    }
                }

                SectionCard(title: "Performance") {
                    if workout.averageHeartRate > 0 {
                        MetricLine(label: "Avg HR", value: "\(workout.averageHeartRate) bpm")
                    }
                    if workout.maxHeartRate > 0 {
                        MetricLine(label: "Max HR", value: "\(workout.maxHeartRate) bpm")
                    }
                    if workout.strain > 0 {
                        MetricLine(label: "Strain", value: String(format: "%.1f / 21", workout.strain))
                    }
                    if workout.load > 0 {
                        MetricLine(label: "Load", value: String(format: "%.0f", workout.load))
                    }
                    if workout.averageHeartRate <= 0 && workout.maxHeartRate <= 0 && workout.strain <= 0 && workout.load <= 0 {
                        Text("Detailed performance analytics are syncing from your iPhone.")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }

                if workout.zoneMinutes.contains(where: { $0 > 0 }) {
                    SectionCard(title: "HR Zones") {
                        let maxValue = workout.zoneMinutes.max() ?? 1
                        VStack(spacing: 10) {
                            ForEach(workout.zoneMinutes.indices, id: \.self) { index in
                                ZoneBarRow(
                                    label: "Zone \(index + 1)",
                                    minutes: workout.zoneMinutes[index],
                                    maxValue: maxValue,
                                    color: zoneColor(index)
                                )
                            }
                        }
                    }
                }

                SectionCard(title: "Coach Note") {
                    Text(workout.note)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.82))
                }
            }
            .padding(10)
        }
        .navigationTitle("Workout Details")
    }
}

private struct MissingWorkoutView: View {
    var body: some View {
        Text("Workout details are unavailable.")
            .font(.caption)
            .padding()
            .navigationTitle("Workout")
    }
}

private struct LineChartPath: Shape {
    let points: [Double]
    let minValue: Double
    let maxValue: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }

        let inset: CGFloat = 10
        let height = rect.height - inset * 2
        let width = rect.width
        let span = max(maxValue - minValue, 0.0001)

        for index in points.indices {
            let x = width * CGFloat(index) / CGFloat(points.count - 1)
            let ratio = (points[index] - minValue) / span
            let y = rect.height - inset - height * CGFloat(ratio)

            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        return path
    }
}

private func band(for value: Double, idealRange: ClosedRange<Double>) -> MetricBand {
    if value < idealRange.lowerBound {
        return .low
    }

    if value > idealRange.upperBound {
        return .high
    }

    return .optimal
}

private func zoneColor(_ index: Int) -> Color {
    switch index {
    case 0:
        return .blue
    case 1:
        return .cyan
    case 2:
        return .green
    case 3:
        return .orange
    default:
        return .red
    }
}

private func detailMessage(for value: Double, title: String, band: MetricBand) -> String {
    switch band {
    case .low:
        return "\(title) is below its current target range. Keep recovery habits tight and avoid forcing intensity."
    case .optimal:
        return "\(title) is sitting in its target range. This is a good point to preserve the current rhythm."
    case .high:
        return "\(title) is above its current target range. Great trend, but make sure it is supported by recovery."
    }
}

private func formattedMetricValue(_ value: Double, unit: String) -> String {
    if unit == "TL" {
        return String(format: "%.0f %@", value, unit)
    }

    return String(format: "%.1f %@", value, unit)
}

private func shortDay(_ date: Date) -> String {
    date.formatted(.dateTime.weekday(.abbreviated).day())
}

private func weekdayLetter(_ date: Date) -> String {
    String(date.formatted(.dateTime.weekday(.narrow)))
}

private func shortTime(_ date: Date) -> String {
    date.formatted(.dateTime.hour().minute())
}

private func relativeDate(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: Date())
}

private func hoursString(_ hours: Double) -> String {
    let wholeHours = Int(hours)
    let minutes = Int(((hours - Double(wholeHours)) * 60).rounded())
    return "\(wholeHours)h \(minutes)m"
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
