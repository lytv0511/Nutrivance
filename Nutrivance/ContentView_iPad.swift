import SwiftUI

struct ContentView_iPad: View {
    @State private var selectedNutrient: String? = "Home"
    @State private var showCamera = false
    @State private var showHome: Bool = true
    @State private var showConfirmation = false
    @State var customization = TabViewCustomization()
    @State private var searchText = ""
    @FocusState private var isSearchBarFocused: Bool
    private let detector = NutritionTableDetector()
    @State private var capturedImage: UIImage?
    @FocusState private var sidebarFocused: Bool
    
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
        let allItems = ["Home", "Insights", "Labels", "Search",
                       "Calories", "Carbs", "Protein", "Fats", "Water",
                       "Fiber", "Vitamins", "Minerals", "Phytochemicals", "Antioxidants", "Electrolytes"]
        
        if searchText.isEmpty {
            return allItems
        }
        
        return allItems.filter { item in
            let lowercasedItem = item.lowercased()
            if let keywords = searchKeywords[lowercasedItem] {
                return keywords.contains { keyword in
                    keyword.localizedCaseInsensitiveContains(searchText)
                } || lowercasedItem.localizedCaseInsensitiveContains(searchText)
            }
            return lowercasedItem.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedNutrient) {
                SearchBar(text: $searchText)
                    .listRowInsets(EdgeInsets())
                
                if filteredItems.contains("Home") {
//                    Section(header: Text("Main")) {
                        if filteredItems.contains("Home") {
                            NavigationLink("Home", destination: HomeView())
                                .keyboardShortcut("h", modifiers: .control)
                                .focused($sidebarFocused)
                        }
                        if filteredItems.contains("Insights") {
                            NavigationLink("Insights", destination: HealthInsightsView())
                                .keyboardShortcut("i", modifiers: .control)
                        }
                        if filteredItems.contains("Labels") {
                            NavigationLink("Labels", destination: NutritionScannerView())
                                .keyboardShortcut("l", modifiers: .control)
                        }
                        if filteredItems.contains("Search") {
                            NavigationLink("Search", destination: SearchView())
                                .keyboardShortcut("s", modifiers: .control)
                        }
//                    }
                }
                
                if filteredItems.contains(where: { ["Calories", "Carbs", "Protein", "Fats", "Water"].contains($0) }) {
                    Section(header: Text("Macronutrients")) {
                        if filteredItems.contains("Calories") {
                            NavigationLink("Calories", destination: NutrientDetailView(nutrientName: "Calories"))
                                .keyboardShortcut("c", modifiers: .control)
                        }
                        if filteredItems.contains("Carbs") {
                            NavigationLink("Carbs", destination: NutrientDetailView(nutrientName: "Carbs"))
                                .keyboardShortcut("a", modifiers: .control)
                        }
                        if filteredItems.contains("Protein") {
                            NavigationLink("Protein", destination: NutrientDetailView(nutrientName: "Protein"))
                                .keyboardShortcut("p", modifiers: .control)
                        }
                        if filteredItems.contains("Fats") {
                            NavigationLink("Fats", destination: NutrientDetailView(nutrientName: "Fats"))
                                .keyboardShortcut("f", modifiers: .control)
                        }
                        if filteredItems.contains("Water") {
                            NavigationLink("Water", destination: NutrientDetailView(nutrientName: "Water"))
                                .keyboardShortcut("w", modifiers: .control)
                        }
                    }
                }
                
                if filteredItems.contains(where: { ["Fiber", "Vitamins", "Minerals", "Phytochemicals", "Antioxidants", "Electrolytes"].contains($0) }) {
                    Section(header: Text("Micronutrients")) {
                        if filteredItems.contains("Fiber") {
                            NavigationLink("Fiber", destination: NutrientDetailView(nutrientName: "Fiber"))
                                .keyboardShortcut("b", modifiers: .control)
                        }
                        if filteredItems.contains("Vitamins") {
                            NavigationLink("Vitamins", destination: NutrientDetailView(nutrientName: "Vitamins"))
                                .keyboardShortcut("v", modifiers: .control)
                        }
                        if filteredItems.contains("Minerals") {
                            NavigationLink("Minerals", destination: NutrientDetailView(nutrientName: "Minerals"))
                                .keyboardShortcut("m", modifiers: .control)
                        }
                        if filteredItems.contains("Phytochemicals") {
                            NavigationLink("Phytochemicals", destination: NutrientDetailView(nutrientName: "Phytochemicals"))
                                .keyboardShortcut("y", modifiers: .control)
                        }
                        if filteredItems.contains("Antioxidants") {
                            NavigationLink("Antioxidants", destination: NutrientDetailView(nutrientName: "Antioxidants"))
                                .keyboardShortcut("x", modifiers: .control)
                        }
                        if filteredItems.contains("Electrolytes") {
                            NavigationLink("Electrolytes", destination: NutrientDetailView(nutrientName: "Electrolytes"))
                                .keyboardShortcut("e", modifiers: .control)
                        }
                    }
                }
            }
            .onAppear {
                sidebarFocused = true
            }
            .navigationTitle("Nutrivance")
        } detail: {
            HomeView()
        }
        .ignoresSafeArea(.keyboard)
    }
    
}

struct SearchBar: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool
    
    var body: some View {
        ZStack {
            // "Find in list" Button
            Button("Find in list") {
                isFocused = true
            }
            .hidden()
            .font(.system(size: 13))
            .foregroundColor(.gray)
            .buttonStyle(.plain)
            .keyboardShortcut("f", modifiers: [.command, .option])
                
            HStack {
                // Search Bar with Magnifying Glass
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(Color(.systemGray2))
                        .font(.system(size: 16))
                        .padding(.leading)
                    
                    TextField("Search", text: $text)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 16))
                        .autocorrectionDisabled()
                        .focused($isFocused)
                }
                .frame(height: 35)
                .background(Color(.systemGray).opacity(0.15))
                .cornerRadius(10)
                
                Spacer()
                
                // "Cancel" Button
                if isFocused /*|| !text.isEmpty*/ {
                    Button("Cancel") {
                        text = ""
                        isFocused = false
                    }
                    .font(.system(size: 13))
                    .foregroundColor(Color(.systemGray))
                    .keyboardShortcut(.escape, modifiers: [])
                    .padding(8)
                    .hoverEffect(.automatic)
                }
            }
        }
    }
}

