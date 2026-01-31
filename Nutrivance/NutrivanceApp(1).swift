import SwiftUI
import SwiftData
import UIKit

enum AppFocus: String, CaseIterable {
    case nutrition = "Nutrition"
    case fitness = "Fitness"
    case mentalHealth = "Mental Health"
}

class NavigationState: ObservableObject {
    @Published var selectedView: String = "Dashboard"
    @Published var dismissAction: (() -> Void)?
    @Published var canGoBack: Bool = false
    @Published var showFocusSwitcher = false
    @Published var appFocus: AppFocus = .fitness {
        didSet {
            if oldValue != appFocus {
                DispatchQueue.main.async {
                    switch self.appFocus {
                    case .nutrition:
                        self.selectedView = "Insights"
                    case .fitness:
                        self.selectedView = "Dashboard"
                    case .mentalHealth:
                        self.selectedView = "Mindfulness Realm"
                    }
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
}

class SearchState: ObservableObject {
    @Published var searchText = ""
    @Published var isSearching = false
    
    func activateSearch(proxy: ScrollViewProxy) {
        proxy.scrollTo("searchField", anchor: .top)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.isSearching = true
        }
    }
}

class AppDelegate: UIResponder, UIApplicationDelegate {
    func applicationDidFinishLaunching(_ application: UIApplication) {
        UIMenuSystem.main.setNeedsRebuild()
    }
    
    @MainActor
    override func buildMenu(with builder: UIMenuBuilder) {
        guard builder.system == .main else { return }
        
        builder.remove(menu: .file)
        builder.remove(menu: .edit)
        builder.remove(menu: .format)
    }
}

@main
struct NutrivanceApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var navigationState = NavigationState()
    @StateObject private var searchState = SearchState()
    @Environment(\.dismiss) private var dismiss
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(navigationState)
                .environmentObject(searchState)
        }
        .commands {
            CommandMenu("Navigation") {
                Button("Home") { navigationState.selectedView = "Home" }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Insights") { navigationState.selectedView = "Insights" }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Labels") { navigationState.selectedView = "Labels" }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Log") { navigationState.selectedView = "Log" }
                    .keyboardShortcut("4", modifiers: .command)
                Button("Go Back") {
                    navigationState.dismissAction?()
                }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!navigationState.canGoBack)
                Button("Cycle Focus Right") {
                    withAnimation(.spring()) {
                        navigationState.showFocusSwitcher = true
                        navigationState.cycleFocus()
                    }
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])

                Button("Cycle Focus Left") {
                    withAnimation(.spring()) {
                        navigationState.showFocusSwitcher = true
                        navigationState.cycleBackwardFocus()
                    }
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])

                Button("Commit Focus Change") {
                    withAnimation(.spring()) {
                        navigationState.commitFocusChange()
                    }
                }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
            }
            CommandMenu("Search") {
                Button("Find in List") {
                    searchState.isSearching = true
                }
                .keyboardShortcut("F", modifiers: [.command])
                
                Divider()
                
                Button("Calories") { navigationState.selectedView = "Calories" }
                    .keyboardShortcut("1", modifiers: [.option])
                Button("Carbs") { navigationState.selectedView = "Carbs" }
                    .keyboardShortcut("2", modifiers: [.option])
                Button("Protein") { navigationState.selectedView = "Protein" }
                    .keyboardShortcut("3", modifiers: [.option])
                Button("Fats") { navigationState.selectedView = "Fats" }
                    .keyboardShortcut("4", modifiers: [.option])
                Button("Water") { navigationState.selectedView = "Water" }
                    .keyboardShortcut("5", modifiers: [.option])
                
                Divider()
                
                Button("Fiber") { navigationState.selectedView = "Fiber" }
                    .keyboardShortcut("1", modifiers: [.control])
                Button("Vitamins") { navigationState.selectedView = "Vitamins" }
                    .keyboardShortcut("2", modifiers: [.control])
                Button("Minerals") { navigationState.selectedView = "Minerals" }
                    .keyboardShortcut("3", modifiers: [.control])
                Button("Phytochemicals") { navigationState.selectedView = "Phytochemicals" }
                    .keyboardShortcut("4", modifiers: [.control])
                Button("Antioxidants") { navigationState.selectedView = "Antioxidants" }
                    .keyboardShortcut("5", modifiers: [.control])
                Button("Electrolytes") { navigationState.selectedView = "Electrolytes" }
                    .keyboardShortcut("6", modifiers: [.control])
            }
        }
    }
}
