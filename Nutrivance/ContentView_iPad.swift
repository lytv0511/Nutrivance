import SwiftUI

struct ContentView_iPad: View {
    @EnvironmentObject var navigationState: NavigationState
    @EnvironmentObject var searchState: SearchState
    @State private var showCamera = false
    @State private var showHome: Bool = true
    @State private var showConfirmation = false
    @State var customization = TabViewCustomization()
    private let detector = NutritionTableDetector()
    @State private var capturedImage: UIImage?
    @FocusState private var searchBarFocused: Bool
    @FocusState private var sidebarFocused: Bool
    @FocusState private var contentFocused: Bool
    
    private var navigationBinding: Binding<String?> {
        Binding(
            get: { navigationState.selectedView },
            set: { newValue in
                if let value = newValue {
                    navigationState.selectedView = value
                }
            }
        )
    }
    
    private let searchKeywords = [
        "home": ["home", "main", "dashboard", "start", "welcome", "homepage"],
        "insights": ["insights", "health insights", "analysis", "trends", "statistics", "data", "reports", "overview"],
        "labels": ["labels", "scan", "camera", "photo", "nutrition facts", "food label", "scanner", "capture"],
        "search": ["search", "find", "lookup", "nutrients", "add nutrients", "input", "track"],
        "calories": ["calories", "calorie", "kcal", "cal", "energy", "dietary energy"],
        "protein": ["protein", "proteins", "whey", "casein", "amino acid", "amino acids"],
        "carbs": ["carbs", "carbohydrates", "carbohydrate", "sugars", "starches", "glucose"],
        "fats": ["fat", "fats", "lipids", "oil", "oils", "triglycerides"],
        "water": ["water", "h2o", "fluid", "hydration"],
        "fiber": ["fiber", "fibre", "dietary fiber", "roughage", "cellulose", "pectin"],
        "vitamins": ["vitamin", "vitamins", "vitamin a", "vitamin c", "vitamin d", "vitamin e", "vitamin k"],
        "minerals": ["minerals", "calcium", "iron", "magnesium", "zinc", "selenium"],
        "phytochemicals": ["phytochemicals", "plant compounds", "bioactive compounds"],
        "antioxidants": ["antioxidants", "antioxidant", "free radicals"],
        "electrolytes": ["electrolytes", "sodium", "potassium", "chloride"]
    ]
    
    var filteredItems: [String] {
        let allItems = ["Home", "Insights", "Labels", "Log",
                       "Calories", "Carbs", "Protein", "Fats", "Water",
                       "Fiber", "Vitamins", "Minerals", "Phytochemicals", "Antioxidants", "Electrolytes"]
        
        if searchState.searchText.isEmpty {
            return allItems
        }
        
        return allItems.filter { item in
            let lowercasedItem = item.lowercased()
            if let keywords = searchKeywords[lowercasedItem] {
                return keywords.contains { keyword in
                    keyword.localizedCaseInsensitiveContains(searchState.searchText)
                } || lowercasedItem.localizedCaseInsensitiveContains(searchState.searchText)
            }
            return lowercasedItem.localizedCaseInsensitiveContains(searchState.searchText)
        }
    }
    
    var body: some View {
        NavigationSplitView {
            List(selection: navigationBinding) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .padding(.leading, 8)
                    
                    TextField("Find in List", text: $searchState.searchText)
                        .textFieldStyle(.plain)
                        .focused($searchBarFocused)
                        .autocorrectionDisabled(true)
                }
                .padding(8)
                .background(Color(.systemGray5))
                .cornerRadius(8)
                .listRowBackground(Color.clear)
                .onChange(of: searchBarFocused) { _, isFocused in
                    searchState.isSearching = isFocused
                }
                .onChange(of: searchState.isSearching) { _, isSearching in
                    searchBarFocused = isSearching
                }

                
                Section(header: Text("Main")) {
                    ForEach(["Home", "Insights", "Labels", "Log"], id: \.self) { item in
                        if filteredItems.contains(item) {
                            Text(item)
                                .tag(item)
                        }
                    }
                }
                
                Section(header: Text("Macronutrients")) {
                    ForEach(["Calories", "Carbs", "Protein", "Fats", "Water"], id: \.self) { item in
                        if filteredItems.contains(item) {
                            Text(item)
                                .tag(item)
                        }
                    }
                }
                
                Section(header: Text("Micronutrients")) {
                    ForEach(["Fiber", "Vitamins", "Minerals", "Phytochemicals", "Antioxidants", "Electrolytes"], id: \.self) { item in
                        if filteredItems.contains(item) {
                            Text(item)
                                .tag(item)
                        }
                    }
                }
            }
            .onChange(of: searchState.isSearching) { _, isSearching in
                if isSearching {
                    searchBarFocused = true
                } else {
                    searchBarFocused = false
                    sidebarFocused = true
                }
            }
            .focused($sidebarFocused)
            .navigationTitle("Nutrivance")
        } detail: {
            Group {
                switch navigationState.selectedView {
                case "Home":
                    HomeView()
                case "Insights":
                    HealthInsightsView()
                case "Labels":
                    NutritionScannerView()
                case "Log":
                    LogView()
                case "Calories":
                    NutrientDetailView(nutrientName: "Calories")
                case "Carbs":
                    NutrientDetailView(nutrientName: "Carbs")
                case "Protein":
                    NutrientDetailView(nutrientName: "Protein")
                case "Fats":
                    NutrientDetailView(nutrientName: "Fats")
                case "Water":
                    NutrientDetailView(nutrientName: "Water")
                case "Fiber":
                    NutrientDetailView(nutrientName: "Fiber")
                case "Vitamins":
                    NutrientDetailView(nutrientName: "Vitamins")
                case "Minerals":
                    NutrientDetailView(nutrientName: "Minerals")
                case "Phytochemicals":
                    NutrientDetailView(nutrientName: "Phytochemicals")
                case "Antioxidants":
                    NutrientDetailView(nutrientName: "Antioxidants")
                case "Electrolytes":
                    NutrientDetailView(nutrientName: "Electrolytes")
                default:
                    HomeView()
                }
            }
            .focused($contentFocused)
        }
    }

    
    
    private func cycleFocus() {
        if searchBarFocused {
            searchBarFocused = false
            sidebarFocused = true
        } else if sidebarFocused {
            sidebarFocused = false
            contentFocused = true
        } else {
            contentFocused = false
            searchBarFocused = true
        }
    }
}
