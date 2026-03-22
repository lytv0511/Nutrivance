//
//  ContentView_iPad_alt.swift
//  Nutrivance
//
//  Created by Vincent Leong on 11/2/24.
//

import SwiftUI
import HealthKit

struct ContentView_iPad_alt: View {
    @State private var selectedNutrient: String?
    @State private var showCamera = false
    @State private var showHome: Bool = true
    @State private var showConfirmation = false
    @State var customization = TabViewCustomization()
    @State private var capturedImage: UIImage?
    @State private var showEmotionSheet = false
    
    private func displayName(for label: HKStateOfMind.Label) -> String {
        let raw = String(describing: label)
        return raw
            .replacingOccurrences(of: "([a-z])([A-Z])",
                                  with: "$1 $2",
                                  options: .regularExpression)
            .capitalized
    }

    private func displayName(for association: HKStateOfMind.Association) -> String {
        let raw = String(describing: association)
        return raw
            .replacingOccurrences(of: "([a-z])([A-Z])",
                                  with: "$1 $2",
                                  options: .regularExpression)
            .capitalized
    }

    var body: some View {
        TabView {
            TabSection ("Fitness") {
                Tab("Dashboard", systemImage: "gauge.medium") {
                    DashboardView()
                }
//                .customizationID( "iPad.tab.dashboard")
                .defaultVisibility(.visible, for: .tabBar)
                .customizationBehavior(.disabled, for: .sidebar)
                Tab("Recovery Score", systemImage: "chart.bar.fill") {
                    RecoveryScoreView()
                }
                .customizationID( "iPad.tab.recoveryScore")
                .defaultVisibility(.hidden, for: .tabBar)
                Tab("Readiness", systemImage: "heart.fill") {
                    ReadinessCheckView()
                }
                .customizationID("iPad.tab.readiness")
                .defaultVisibility(.hidden, for: .tabBar)
                Tab("Strain vs Recovery", systemImage: "gauge.with.dots.needle.bottom.50percent") {
                    StrainRecoveryView()
                }
                .customizationID("iPad.tab.strainVsRecovery")
                .defaultVisibility(.hidden, for: .tabBar)
                Tab("Workout History", systemImage: "clock.arrow.circlepath") {
                    WorkoutHistoryView()
                }
                .customizationID( "iPad.tab.workoutHistory")
                .defaultVisibility(.hidden, for: .tabBar)
            }
            TabSection("Mental Health") {
                Tab("Mindfulness Realm", systemImage: "eye.fill") {
                    MindfulnessRealmView()
                }
//                .customizationID( "iPad.tab.mindfulnessRealm")
                .defaultVisibility(.visible, for: .tabBar)
                .customizationBehavior(.disabled, for: .sidebar)
                Tab("Mood Tracker", systemImage: "sun.max") {
                    MoodTrackerView()
                }
                .customizationID("iPad.tab.moodTracker")
                .defaultVisibility(.hidden, for: .tabBar)
                Tab("Journal", systemImage: "book.fill") {
                    JournalView()
                }
                .customizationID("iPad.tab.journal")
                .defaultVisibility(.hidden, for: .tabBar)
                Tab("Sleep", systemImage: "moon.zzz.fill") {
                    SleepView()
                }
                .customizationID("iPad.tab.sleep")
                .defaultVisibility(.hidden, for: .tabBar)
                Tab("Stress", systemImage: "waveform.path.ecg") {
                    StressView()
                }
                .customizationID("iPad.tab.stress")
                .defaultVisibility(.hidden, for: .tabBar)
            }
            .sectionActions {
                Button {
                    showEmotionSheet = true
                } label: {
                    Text("Log Emotion")
                    Image(systemName: "apple.meditate.square.stack.fill")
                }
            }
            Tab(role: .search) {
                SearchView_iPhone()
            }
            .customizationID("iPad.tab.search")
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewCustomization($customization)
        .sheet(isPresented: $showEmotionSheet) {
            EmotionLogSheet()
        }
    }
    private func getCapturedImage() -> UIImage? {
            // Implementation to get the captured image
            return nil // Replace with actual image retrieval logic
        }
}

struct EmotionLogSheet: View {

    @Environment(\.dismiss) private var dismiss

    @State private var kind: HKStateOfMind.Kind = .momentaryEmotion
    @State private var valence: Double = 0

    @State private var selectedLabel: HKStateOfMind.Label = .calm
    @State private var selectedAssociation: HKStateOfMind.Association = .selfCare

    @State private var notes: String = ""

    private func displayName(for label: HKStateOfMind.Label) -> String {
        switch label {
        case .amazed: return "Amazed"
        case .amused: return "Amused"
        case .angry: return "Angry"
        case .annoyed: return "Annoyed"
        case .anxious: return "Anxious"
        case .ashamed: return "Ashamed"
        case .brave: return "Brave"
        case .calm: return "Calm"
        case .confident: return "Confident"
        case .content: return "Content"
        case .disappointed: return "Disappointed"
        case .discouraged: return "Discouraged"
        case .disgusted: return "Disgusted"
        case .drained: return "Drained"
        case .embarrassed: return "Embarrassed"
        case .excited: return "Excited"
        case .frustrated: return "Frustrated"
        case .grateful: return "Grateful"
        case .guilty: return "Guilty"
        case .happy: return "Happy"
        case .hopeful: return "Hopeful"
        case .hopeless: return "Hopeless"
        case .indifferent: return "Indifferent"
        case .irritated: return "Irritated"
        case .jealous: return "Jealous"
        case .joyful: return "Joyful"
        case .lonely: return "Lonely"
        case .overwhelmed: return "Overwhelmed"
        case .passionate: return "Passionate"
        case .peaceful: return "Peaceful"
        case .proud: return "Proud"
        case .relieved: return "Relieved"
        case .sad: return "Sad"
        case .satisfied: return "Satisfied"
        case .scared: return "Scared"
        case .stressed: return "Stressed"
        case .surprised: return "Surprised"
        case .worried: return "Worried"
        @unknown default: return "Emotion"
        }
    }

    private func displayName(for association: HKStateOfMind.Association) -> String {
        switch association {
        case .health: return "Health"
        case .fitness: return "Fitness"
        case .selfCare: return "Self‑Care"
        case .hobbies: return "Hobbies"
        case .identity: return "Identity"
        case .spirituality: return "Spirituality"
        case .community: return "Community"
        case .family: return "Family"
        case .friends: return "Friends"
        case .partner: return "Partner"
        case .dating: return "Dating"
        case .tasks: return "Tasks"
        case .work: return "Work"
        case .education: return "Education"
        case .travel: return "Travel"
        case .weather: return "Weather"
        case .currentEvents: return "Current Events"
        case .money: return "Money"
        @unknown default: return "Other"
        }
    }

    let emotions: [HKStateOfMind.Label] = [
        .amazed,.amused,.angry,.annoyed,.anxious,.ashamed,.brave,.calm,.confident,.content,
        .disappointed,.discouraged,.disgusted,.drained,.embarrassed,.excited,.frustrated,
        .grateful,.guilty,.happy,.hopeful,.hopeless,.indifferent,.irritated,.jealous,.joyful,
        .lonely,.overwhelmed,.passionate,.peaceful,.proud,.relieved,.sad,.satisfied,.scared,
        .stressed,.surprised,.worried
    ]

    let associations: [HKStateOfMind.Association] = [
        .health,.fitness,.selfCare,.hobbies,.identity,.spirituality,.community,.family,
        .friends,.partner,.dating,.tasks,.work,.education,.travel,.weather,.currentEvents,.money
    ]

    var body: some View {

        NavigationStack {
            Form {

                Section("Emotion Type") {
                    Picker("Type", selection: $kind) {
                        Text("Momentary").tag(HKStateOfMind.Kind.momentaryEmotion)
                        Text("Day Summary").tag(HKStateOfMind.Kind.dailyMood)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Valence") {
                    Slider(value: $valence, in: -1...1)
                    Text(String(format: "%.2f", valence))
                }

                Section("Emotion") {
                    Picker("Emotion", selection: $selectedLabel) {
                        ForEach(emotions, id: \.self) { emotion in
                            Text(displayName(for: emotion))
                                .tag(emotion)
                        }
                    }
                }

                Section("Association") {
                    Picker("Association", selection: $selectedAssociation) {
                        ForEach(associations, id: \.self) { association in
                            Text(displayName(for: association))
                                .tag(association)
                        }
                    }
                }

                Section("Notes (Optional)") {
                    TextField("Notes", text: $notes)
                }

            }
            .navigationTitle("Log Emotion")
            .toolbar {

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        saveStateOfMind()
                        dismiss()
                    }
                }
            }
        }
    }

    func saveStateOfMind() {

        let healthStore = HKHealthStore()

        let state = HKStateOfMind(
            date: Date(),
            kind: kind,
            valence: valence,
            labels: [selectedLabel],
            associations: [selectedAssociation]
        )

        Task {
            try? await healthStore.save(state)
        }
    }
}
