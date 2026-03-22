import SwiftUI
import SwiftData
import UIKit

enum AppFocus: String, CaseIterable {
    case nutrition = "Nutrition"
    case fitness = "Fitness"
    case mentalHealth = "Mental Health"
}

enum RootTabSelection: Hashable {
    case dashboard
    case insights
    case labels
    case log
    case calories
    case carbs
    case protein
    case fats
    case water
    case fiber
    case vitamins
    case minerals
    case phytochemicals
    case antioxidants
    case electrolytes
    case todaysPlan
    case trainingCalendar
    case coach
    case recoveryScore
    case readiness
    case strainRecovery
    case workoutHistory
    case activityRings
    case heartZones
    case personalRecords
    case mindfulnessRealm
    case moodTracker
    case journal
    case sleep
    case stress
    case search
    case home
    case playground
}

enum AppDestination: String, CaseIterable, Hashable, Identifiable {
    case todaysPlan
    case trainingCalendar
    case coach
    case recoveryScore
    case readiness
    case strainRecovery
    case workoutHistory
    case activityRings
    case heartZones
    case personalRecords
    case mindfulnessRealm
    case moodTracker
    case journal
    case sleep
    case stress

    var id: String { rawValue }
}

enum SearchScope: String, CaseIterable, Hashable {
    case all
    case nutrition
    case fitness
    case mentalHealth

    var title: String {
        switch self {
        case .all: return "Search"
        case .nutrition: return "Nutrivance"
        case .fitness: return "Movance"
        case .mentalHealth: return "Spirivance"
        }
    }

    var icon: String {
        switch self {
        case .all: return "magnifyingglass"
        case .nutrition: return "leaf.fill"
        case .fitness: return "figure.run"
        case .mentalHealth: return "brain.head.profile"
        }
    }
}

class NavigationState: ObservableObject {
    @Published var selectedView: String = "Dashboard"
    @Published var selectedRootTab: RootTabSelection = .dashboard
    @Published var presentedDestination: AppDestination?
    @Published var dismissAction: (() -> Void)?
    @Published var canGoBack: Bool = false
    @Published var showFocusSwitcher = false
    @Published var appFocus: AppFocus = .fitness {
        didSet {
            if oldValue != appFocus {
                guard !Self.tab(selectedRootTab, belongsTo: appFocus) else { return }

                switch self.appFocus {
                case .nutrition:
                    self.selectedView = "Insights"
                    self.selectedRootTab = Self.defaultRootTab(for: .nutrition)
                    self.presentedDestination = nil
                case .fitness:
                    self.selectedView = "Dashboard"
                    self.selectedRootTab = Self.defaultRootTab(for: .fitness)
                    self.presentedDestination = nil
                case .mentalHealth:
                    self.selectedView = "Mindfulness Realm"
                    self.selectedRootTab = Self.defaultRootTab(for: .mentalHealth)
                    self.presentedDestination = nil
                }
            }
        }
    }
    @Published var tempFocus: AppFocus = .nutrition
    @Published var navigationPath = NavigationPath()
    @Published var isSearchBarFocused = false
    
    func setDismissAction(_ action: @escaping () -> Void) {
        dismissAction = action
        canGoBack = true
    }
    
    func clearDismissAction() {
        dismissAction = nil
        canGoBack = false
    }
    
    func cycleFocus() {
        tempFocus = switch tempFocus {
        case .nutrition: .fitness
        case .fitness: .mentalHealth
        case .mentalHealth: .nutrition
        }
        isSearchBarFocused = false
    }
    
    func cycleBackwardFocus() {
        tempFocus = switch tempFocus {
        case .nutrition: .mentalHealth
        case .fitness: .nutrition
        case .mentalHealth: .fitness
        }
    }
    
    func commitFocusChange() {
        DispatchQueue.main.async {
            self.appFocus = self.tempFocus
            self.showFocusSwitcher = false
        }
    }

    static func defaultRootTab(for focus: AppFocus) -> RootTabSelection {
        if UIDevice.current.userInterfaceIdiom == .phone {
            switch focus {
            case .nutrition: return .search
            case .fitness: return .dashboard
            case .mentalHealth: return .dashboard
            }
        }

        switch focus {
        case .nutrition: return .insights
        case .fitness: return .dashboard
        case .mentalHealth: return .mindfulnessRealm
        }
    }

    static func tab(_ tab: RootTabSelection, belongsTo focus: AppFocus) -> Bool {
        switch focus {
        case .nutrition:
            switch tab {
            case .insights, .labels, .log, .calories, .carbs, .protein, .fats, .water, .fiber, .vitamins, .minerals, .phytochemicals, .antioxidants, .electrolytes, .search:
                return true
            default:
                return false
            }
        case .fitness:
            switch tab {
            case .dashboard, .todaysPlan, .trainingCalendar, .coach, .recoveryScore, .readiness, .strainRecovery, .workoutHistory, .activityRings, .heartZones, .personalRecords:
                return true
            default:
                return false
            }
        case .mentalHealth:
            switch tab {
            case .mindfulnessRealm, .moodTracker, .journal, .sleep, .stress:
                return true
            default:
                return false
            }
        }
    }
}

class SearchState: ObservableObject {
    @Published var searchText = ""
    @Published var isSearching = false
    @Published var selectedScope: SearchScope = .all
    
    func activateSearch(proxy: ScrollViewProxy) {
        proxy.scrollTo("searchField", anchor: .top)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.isSearching = true
        }
    }
}

@main
struct NutrivanceApp: App {
    @StateObject private var navigationState = NavigationState()
    @StateObject private var searchState = SearchState()
    @Environment(\.dismiss) private var dismiss

    private func navigate(
        focus: AppFocus,
        view: String,
        tab: RootTabSelection
    ) {
        navigationState.appFocus = focus
        navigationState.selectedView = view

        if UIDevice.current.userInterfaceIdiom == .phone {
            switch tab {
            case .dashboard, .search, .playground:
                navigationState.selectedRootTab = tab
                navigationState.presentedDestination = nil
            default:
                navigationState.selectedRootTab = NavigationState.defaultRootTab(for: focus)
                navigationState.presentedDestination = destination(for: tab)
            }
            return
        }

        navigationState.selectedRootTab = tab
        navigationState.presentedDestination = nil
    }

    private func destination(for tab: RootTabSelection) -> AppDestination? {
        switch tab {
        case .insights, .labels, .log, .calories, .carbs, .protein, .fats, .water, .fiber, .vitamins, .minerals, .phytochemicals, .antioxidants, .electrolytes:
            return nil
        case .todaysPlan: return .todaysPlan
        case .trainingCalendar: return .trainingCalendar
        case .coach: return .coach
        case .recoveryScore: return .recoveryScore
        case .readiness: return .readiness
        case .strainRecovery: return .strainRecovery
        case .workoutHistory: return .workoutHistory
        case .activityRings: return .activityRings
        case .heartZones: return .heartZones
        case .personalRecords: return .personalRecords
        case .mindfulnessRealm: return .mindfulnessRealm
        case .moodTracker: return .moodTracker
        case .journal: return .journal
        case .sleep: return .sleep
        case .stress: return .stress
        case .dashboard, .search, .home, .playground: return nil
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(navigationState)
                .environmentObject(searchState)
        }
        .commands {
            CommandMenu("Navigation") {
                Button("Insights") {
                    navigate(focus: .nutrition, view: "Insights", tab: .insights)
                }
                .keyboardShortcut("I", modifiers: [.command, .shift])

                Button("Labels") {
                    navigate(focus: .nutrition, view: "Labels", tab: .labels)
                }
                .keyboardShortcut("B", modifiers: [.command, .shift])

                Button("Log") {
                    navigate(focus: .nutrition, view: "Log", tab: .log)
                }
                .keyboardShortcut("G", modifiers: [.command, .shift])

                Button("Calories") {
                    navigate(focus: .nutrition, view: "Calories", tab: .calories)
                }
                .keyboardShortcut("1", modifiers: [.command, .option])

                Button("Carbs") {
                    navigate(focus: .nutrition, view: "Carbs", tab: .carbs)
                }
                .keyboardShortcut("2", modifiers: [.command, .option])

                Button("Protein") {
                    navigate(focus: .nutrition, view: "Protein", tab: .protein)
                }
                .keyboardShortcut("3", modifiers: [.command, .option])

                Button("Fats") {
                    navigate(focus: .nutrition, view: "Fats", tab: .fats)
                }
                .keyboardShortcut("4", modifiers: [.command, .option])

                Button("Water") {
                    navigate(focus: .nutrition, view: "Water", tab: .water)
                }
                .keyboardShortcut("5", modifiers: [.command, .option])

                Button("Fiber") {
                    navigate(focus: .nutrition, view: "Fiber", tab: .fiber)
                }
                .keyboardShortcut("6", modifiers: [.command, .option])

                Button("Vitamins") {
                    navigate(focus: .nutrition, view: "Vitamins", tab: .vitamins)
                }
                .keyboardShortcut("7", modifiers: [.command, .option])

                Button("Minerals") {
                    navigate(focus: .nutrition, view: "Minerals", tab: .minerals)
                }
                .keyboardShortcut("8", modifiers: [.command, .option])

                Button("Phytochemicals") {
                    navigate(focus: .nutrition, view: "Phytochemicals", tab: .phytochemicals)
                }
                .keyboardShortcut("9", modifiers: [.command, .option])

                Button("Antioxidants") {
                    navigate(focus: .nutrition, view: "Antioxidants", tab: .antioxidants)
                }
                .keyboardShortcut("0", modifiers: [.command, .option])

                Button("Electrolytes") {
                    navigate(focus: .nutrition, view: "Electrolytes", tab: .electrolytes)
                }
                .keyboardShortcut("-", modifiers: [.command, .option])

                Button("Dashboard") {
                    navigate(focus: .fitness, view: "Dashboard", tab: .dashboard)
                }
                .keyboardShortcut("D", modifiers: [.command, .shift])

                Button("Today's Plan") {
                    navigate(focus: .fitness, view: "Today's Plan", tab: .todaysPlan)
                }
                .keyboardShortcut("T", modifiers: [.command, .shift])

                Button("Training Calendar") {
                    navigate(focus: .fitness, view: "Training Calendar", tab: .trainingCalendar)
                }
                .keyboardShortcut("R", modifiers: [.command, .shift])

                Button("Coach") {
                    navigate(focus: .fitness, view: "Coach", tab: .coach)
                }
                .keyboardShortcut("C", modifiers: [.command, .shift])

                Button("Recovery Score") {
                    navigate(focus: .fitness, view: "Recovery Score", tab: .recoveryScore)
                }
                .keyboardShortcut("Y", modifiers: [.command, .shift])

                Button("Readiness") {
                    navigate(focus: .fitness, view: "Readiness", tab: .readiness)
                }
                .keyboardShortcut("N", modifiers: [.command, .shift])

                Button("Strain vs Recovery") {
                    navigate(focus: .fitness, view: "Strain vs Recovery", tab: .strainRecovery)
                }
                .keyboardShortcut("V", modifiers: [.command, .shift])

                Button("Workout History") {
                    navigate(focus: .fitness, view: "Workout History", tab: .workoutHistory)
                }
                .keyboardShortcut("W", modifiers: [.command, .option])

                Button("Activity Rings") {
                    navigate(focus: .fitness, view: "Activity Rings", tab: .activityRings)
                }
                .keyboardShortcut("A", modifiers: [.command, .shift])

                Button("Heart Zones") {
                    navigate(focus: .fitness, view: "Heart Zones", tab: .heartZones)
                }
                .keyboardShortcut("H", modifiers: [.command, .shift])

                Button("Personal Records") {
                    navigate(focus: .fitness, view: "Personal Records", tab: .personalRecords)
                }
                .keyboardShortcut("P", modifiers: [.command, .shift])

                Button("Mindfulness Realm") {
                    navigate(focus: .mentalHealth, view: "Mindfulness Realm", tab: .mindfulnessRealm)
                }
                .keyboardShortcut("M", modifiers: [.command, .shift])

                Button("Mood Tracker") {
                    navigate(focus: .mentalHealth, view: "Mood Tracker", tab: .moodTracker)
                }
                .keyboardShortcut("O", modifiers: [.command, .shift])

                Button("Journal") {
                    navigate(focus: .mentalHealth, view: "Journal", tab: .journal)
                }
                .keyboardShortcut("J", modifiers: [.command, .shift])

                Button("Sleep") {
                    navigate(focus: .mentalHealth, view: "Sleep", tab: .sleep)
                }
                .keyboardShortcut("L", modifiers: [.command, .shift])

                Button("Stress") {
                    navigate(focus: .mentalHealth, view: "Stress", tab: .stress)
                }
                .keyboardShortcut("X", modifiers: [.command, .shift])
            }
            CommandMenu("Search") {
                Button("Find") {
                    navigationState.presentedDestination = nil
                    navigationState.selectedRootTab = .search
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        searchState.isSearching = true
                    }
                }
                .keyboardShortcut("F", modifiers: [.command])
            }
        }
    }
}
