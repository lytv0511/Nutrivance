//import SwiftUI
//
//struct ContentView_iPad_compact: View {
//    @EnvironmentObject var navigationState: NavigationState
//    @EnvironmentObject var searchState: SearchState
//    @State var customization = TabViewCustomization()
//    @FocusState private var searchBarFocused: Bool
//    
//    var body: some View {
//        TabView {
//            Tab("Home", systemImage: "house") {
//                HomeView()
//            }
//            .customizationID("iPhone.tab.home")
//            .defaultVisibility(.visible, for: .tabBar)
//            
//            Tab(role: .search) {
//                SearchView()
//            }
//            .customizationID("iPhone.tab.search")
//            
//            TabSection {
//                Tab("Nutrivance", systemImage: "leaf") {
//                    NavigationStack {
//                        List(selection: navigationBinding) {
//                            ForEach(filteredNutritionItems, id: \.self) { item in
//                                NavigationLink(value: item) {
//                                    Label(item, systemImage: getIconName(for: item))
//                                }
//                            }
//                        }
//                        .navigationDestination(for: String.self) { view in
//                            switch view {
//                            case "Carbs":
//                                NutrientDetailView(nutrientName: "Carbs")
//                            case "Protein":
//                                NutrientDetailView(nutrientName: "Protein")
//                            case "Fats":
//                                NutrientDetailView(nutrientName: "Fats")
//                            case "Water":
//                                NutrientDetailView(nutrientName: "Water")
//                            case "Fiber":
//                                NutrientDetailView(nutrientName: "Fiber")
//                            case "Insights":
//                                HealthInsightsView()
//                            case "Labels":
//                                NutritionScannerView()
//                            case "Log":
//                                LogView()
//                            case "Saved Meals":
//                                SavedMealsView()
//                            default:
//                                HomeView()
//                            }
//                        }
//                        .navigationTitle("Nutrivance")
//                    }
//                }
//                .customizationID("iPhone.tab.nutrivance")
//                .defaultVisibility(.visible, for: .tabBar)
//                
//                Tab("Movance", systemImage: "figure.run") {
//                    MovanceView()
//                }
//                .customizationID("iPhone.tab.movance")
//                .defaultVisibility(.visible, for: .tabBar)
//                
//                Tab("Spirivance", systemImage: "brain.head.profile") {
//                    SpirivanceView()
//                }
//                .customizationID("iPhone.tab.spirivance")
//                .defaultVisibility(.visible, for: .tabBar)
//            } header: {
//                Text("Focus Modes")
//                    .font(.headline)
//                    .padding(.leading, 16)
//                    .padding(.top, 8)
//            }
//            .defaultVisibility(.visible, for: .tabBar)
//            .customizationID("iPhone.tabsection.focusModes")
//        }
//        .tabViewStyle(.sidebarAdaptable)
//        .tabViewCustomization($customization)
//    }
//    
//    private var navigationBinding: Binding<String?> {
//        Binding(
//            get: { navigationState.selectedView },
//            set: { newValue in
//                if let value = newValue {
//                    navigationState.selectedView = value
//                }
//            }
//        )
//    }
//    
//    private var filteredNutritionItems: [String] {
//        let items = ["Home", "Insights", "Labels", "Log", "Saved Meals",
//                    "Calories", "Carbs", "Protein", "Fats", "Water",
//                    "Fiber", "Vitamins", "Minerals", "Phytochemicals",
//                    "Antioxidants", "Electrolytes"]
//        return filterItems(items)
//    }
//    
//    private var filteredFitnessItems: [String] {
//        let items = ["Dashboard", "Today's Plan", "Workout History",
//                    "Training Calendar", "Coach", "Movement Analysis",
//                    "Exercise Library", "Program Builder", "Workout Generator"]
//        return filterItems(items)
//    }
//    
//    private var filteredMentalHealthItems: [String] {
//        let items = ["Mindfulness Realm", "Mood Tracker", "Journal",
//                    "Resources", "Meditation", "Breathing", "Sleep", "Stress"]
//        return filterItems(items)
//    }
//    
//    private func filterItems(_ items: [String]) -> [String] {
//        if searchState.searchText.isEmpty {
//            return items
//        }
//        return items.filter { $0.localizedCaseInsensitiveContains(searchState.searchText) }
//    }
//    
//    private func getIconName(for item: String) -> String {
//        switch item {
//        case "Home": return "house.fill"
//        case "Insights": return "chart.bar.fill"
//        case "Labels": return "barcode.viewfinder"
//        case "Log": return "square.and.pencil"
//        case "Saved Meals": return "bookmark.fill"
//        case "Calories": return "flame.fill"
//        case "Carbs": return "leaf.fill"
//        case "Protein": return "fish.fill"
//        case "Fats": return "drop.fill"
//        case "Water": return "drop.circle.fill"
//        case "Fiber": return "circle.grid.cross.fill"
//        case "Vitamins": return "pills.fill"
//        case "Minerals": return "sparkles"
//        case "Phytochemicals": return "leaf.arrow.circlepath"
//        case "Antioxidants": return "shield.fill"
//        case "Electrolytes": return "bolt.fill"
//        default: return "circle.fill"
//        }
//    }
//}
