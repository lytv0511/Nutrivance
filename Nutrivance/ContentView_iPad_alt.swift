//
//  ContentView_iPad_alt.swift
//  Nutrivance
//
//  Created by Vincent Leong on 11/2/24.
//

import SwiftUI

struct ContentView_iPad_alt: View {
    @State private var selectedNutrient: String?
    @State private var showCamera = false
    @State private var showHome: Bool = true
    @State private var showConfirmation = false
    @State var customization = TabViewCustomization()
    private let detector = NutritionTableDetector()
    @State private var capturedImage: UIImage?

    let nutrientDetails: [String: NutrientInfo] = [
        "Carbs": NutrientInfo(
            todayConsumption: "0 g",
            weeklyConsumption: "1.4kg",
            monthlyConsumption: "6kg",
            recommendedIntake: "45-65% of total calories",
            foodsRichInNutrient: "Bread, Pasta, Rice",
            benefits: "Provides energy, aids in digestion."
        ),
        "Protein": NutrientInfo(
            todayConsumption: "50g",
            weeklyConsumption: "350g",
            monthlyConsumption: "1.5kg",
            recommendedIntake: "10-35% of total calories",
            foodsRichInNutrient: "Meat, Beans, Nuts",
            benefits: "Essential for muscle repair and growth."
        ),
        "Fats": NutrientInfo(
            todayConsumption: "70g",
            weeklyConsumption: "490g",
            monthlyConsumption: "2.1kg",
            recommendedIntake: "20-35% of total calories",
            foodsRichInNutrient: "Oils, Nuts, Avocados",
            benefits: "Supports cell growth, provides energy."
        ),
        "Calories": NutrientInfo(
            todayConsumption: "2000 kcal",
            weeklyConsumption: "14000 kcal",
            monthlyConsumption: "60000 kcal",
            recommendedIntake: "Varies based on activity level",
            foodsRichInNutrient: "All foods contribute calories",
            benefits: "Essential for energy."
        ),
        // New categories
        "Fiber": NutrientInfo(
            todayConsumption: "25g",
            weeklyConsumption: "175g",
            monthlyConsumption: "750g",
            recommendedIntake: "25g for women, 38g for men",
            foodsRichInNutrient: "Fruits, Vegetables, Whole Grains",
            benefits: "Aids digestion, helps maintain a healthy weight."
        ),
        "Vitamins": NutrientInfo(
            todayConsumption: "A, C, D, E",
            weeklyConsumption: "Varies",
            monthlyConsumption: "Varies",
            recommendedIntake: "Varies by vitamin",
            foodsRichInNutrient: "Fruits, Vegetables, Dairy",
            benefits: "Supports immune function, promotes vision."
        ),
        "Minerals": NutrientInfo(
            todayConsumption: "Iron, Calcium",
            weeklyConsumption: "Varies",
            monthlyConsumption: "Varies",
            recommendedIntake: "Varies by mineral",
            foodsRichInNutrient: "Meat, Dairy, Leafy Greens",
            benefits: "Supports bone health, aids in oxygen transport."
        ),
        "Water": NutrientInfo(
            todayConsumption: "2L",
            weeklyConsumption: "14L",
            monthlyConsumption: "60L",
            recommendedIntake: "8 cups per day",
            foodsRichInNutrient: "Water, Fruits, Vegetables",
            benefits: "Essential for hydration, regulates body temperature."
        ),
        "Phytochemicals": NutrientInfo(
            todayConsumption: "Varies",
            weeklyConsumption: "Varies",
            monthlyConsumption: "Varies",
            recommendedIntake: "Include colorful fruits and vegetables",
            foodsRichInNutrient: "Berries, Green Tea, Nuts",
            benefits: "Antioxidant properties, may reduce disease risk."
        ),
        "Antioxidants": NutrientInfo(
            todayConsumption: "Varies",
            weeklyConsumption: "Varies",
            monthlyConsumption: "Varies",
            recommendedIntake: "Include a variety of foods",
            foodsRichInNutrient: "Berries, Dark Chocolate, Spinach",
            benefits: "Protects cells from damage, supports overall health."
        ),
        "Electrolytes": NutrientInfo(
            todayConsumption: "Sodium, Potassium",
            weeklyConsumption: "Varies",
            monthlyConsumption: "Varies",
            recommendedIntake: "Sodium: <2300 mg, Potassium: 3500 mg",
            foodsRichInNutrient: "Bananas, Salt, Coconut Water",
            benefits: "Regulates fluid balance, supports muscle function."
        )
    ]
    
    var body: some View {
        TabView {
            
            Tab("Home", systemImage: "house.fill") {
                HomeView()
            }
            .customizationID("iPad.tab.home")
            .defaultVisibility(.visible, for: .tabBar)
            
            Tab(role: .search) {
//                SearchView()
            }
            .customizationID("iPad.tab.search")
            
            Tab("Labels", systemImage: "doc.text.viewfinder") {
                NutritionScannerView()
            }
            .customizationID("iPad.tab.camera")
            .defaultVisibility(.visible, for: .tabBar)
            
            Tab("Calories", systemImage: "flame") {
                NutrientDetailView(nutrientName: "Calories")
            }
            .customizationID("iPad.tab.calories")
            .defaultVisibility(.hidden, for: .tabBar)
            
            Tab("Carbs", systemImage: "carrot") {
                NutrientDetailView(nutrientName: "Carbs")
            }
            .customizationID("iPad.tab.carbs")
            .defaultVisibility(.hidden, for: .tabBar)
            
            Tab("Protein", systemImage: "fork.knife") {
                NutrientDetailView(nutrientName: "Protein")
            }
            .customizationID("iPad.tab.protein")
            .defaultVisibility(.hidden, for: .tabBar)
            
            Tab("Fats", systemImage: "drop") {
                NutrientDetailView(nutrientName: "Fats")
            }
            .customizationID("iPad.tab.fats")
            .defaultVisibility(.hidden, for: .tabBar)
            
            Tab("Water", systemImage: "drop.fill") {
                NutrientDetailView(nutrientName: "Water")
            }
            .customizationID("iPad.tab.water")
            .defaultVisibility(.hidden, for: .tabBar)
            
            TabSection {
                Tab("Fiber", systemImage: "leaf.fill") {
                    NutrientDetailView(nutrientName: "Fiber")
                }
                .customizationID("iPad.tab.fiber")
                
                Tab("Vitamins", systemImage: "pill") {
                    NutrientDetailView(nutrientName: "Vitamins")
                }
                .customizationID("iPad.tab.vitamins")
                
                Tab("Minerals", systemImage: "bolt") {
                    NutrientDetailView(nutrientName: "Minerals")
                }
                .customizationID("iPad.tab.minerals")
                
                Tab("Phytochemicals", systemImage: "leaf.arrow.triangle.circlepath") {
                    NutrientDetailView(nutrientName: "Phytochemicals")
                }
                .customizationID("iPad.tab.phytochemicals")
                
                Tab("Antioxidants", systemImage: "shield") {
                    NutrientDetailView(nutrientName: "Antioxidants")
                }
                .customizationID("iPad.tab.antioxidants")
                
                Tab("Electrolytes", systemImage: "battery.100") {
                    NutrientDetailView(nutrientName: "Electrolytes")
                }
                .customizationID("iPad.tab.electrolytes")
            } header: {
                Text("Micronutrients")
                    .font(.headline)
                    .padding(.leading, 16) // Add padding to the left
                    .padding(.top, 8) // Add padding to the top
            }
            .defaultVisibility(.hidden, for: .tabBar)
            .customizationID("iPad.tabsection.micronutrients") // Custom ID for Micronutrient Section
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewCustomization($customization)
    }
    private func getCapturedImage() -> UIImage? {
            // Implementation to get the captured image
            return nil // Replace with actual image retrieval logic
        }
}

//struct SearchView: View {
//    @State private var searchText = ""
//    @State private var selectedNutrient: String? // Keep track of selected nutrient
//    @FocusState private var isSearchBarFocused: Bool // Track focus state of the search bar
//    
//    // List of all nutrients
//    private let nutrients = ["Calories", "Protein", "Carbs", "Fats", "Fiber", "Vitamins", "Minerals", "Water", "Phytochemicals", "Antioxidants", "Electrolytes"]
//    
//    var body: some View {
//        VStack {
//            // Search bar
//            HStack {
//                Image(systemName: "magnifyingglass")
//                    .foregroundColor(.gray)
//                    .padding(.leading, 10)
//                
//                TextField("Search for nutrients...", text: $searchText)
//                    .focused($isSearchBarFocused)
//                    .foregroundColor(.primary)
//                    .padding(.vertical, 8)
//                    .padding(.horizontal)
//                    .background(
//                        RoundedRectangle(cornerRadius: 10)
//                            .fill(Color.gray.opacity(0.3))
//                    )
//                
//                Image(systemName: "mic.fill")
//                    .foregroundColor(.gray)
//                    .padding(.trailing, 10)
//                    .onTapGesture {
//                        startDictation()
//                    }
//            }
//            .padding(.horizontal)
//            
//            // Nutrient icons filtered by search text
//            ScrollView {
//                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 40) {
//                    ForEach(filteredNutrients(), id: \.self) { nutrient in
//                        VStack {
//                            RoundedRectangle(cornerRadius: 10)
//                                .fill(Color.gray.opacity(0.3))
//                                .frame(height: 150)
//                                .overlay(
//                                    VStack {
//                                        Image(systemName: getNutrientIcon(for: nutrient))
//                                            .resizable()
//                                            .scaledToFit()
//                                            .frame(width: 70, height: 70)
//                                            .padding()
//                                        
//                                        Text(nutrient)
//                                            .font(.headline)
//                                            .foregroundColor(.primary)
//                                    }
//                                )
//                                .onTapGesture {
//                                    selectedNutrient = nutrient
//                                }
//                        }
//                    }
//                }
//                .padding()
//            }
//        }
//        .navigationTitle("Search")
//        .background(Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all))
//    }
//    
//    private func startDictation() {
//        // Your dictation functionality here
//    }
//    
//    // Filter nutrients based on search text
//    private func filteredNutrients() -> [String] {
//        if searchText.isEmpty {
//            return nutrients
//        } else {
//            return nutrients.filter { $0.lowercased().contains(searchText.lowercased()) }
//        }
//    }
//    
//    // Get system icon name for each nutrient
//    private func getNutrientIcon(for nutrient: String) -> String {
//        switch nutrient {
//        case "Calories": return "flame"
//        case "Protein": return "fork.knife"
//        case "Carbs": return "carrot"
//        case "Fats": return "drop.fill"
//        case "Fiber": return "leaf.fill"
//        case "Vitamins": return "pill"
//        case "Minerals": return "bolt"
//        case "Water": return "drop.fill"
//        case "Phytochemicals": return "leaf.arrow.triangle.circlepath"
//        case "Antioxidants": return "shield"
//        case "Electrolytes": return "battery.100"
//        default: return "questionmark"
//        }
//    }
//}
//
//struct SidebarAdaptableTabViewStyle : View {
//    @Binding var selectedNutrient: String?
//    @Binding var showCamera: Bool
//    @Binding var showHome: Bool
//    @State private var showConfirmation = false
//    
//    private let nutrientChoices = [
//        "Calories", "Protein", "Carbs", "Fats", "Fiber", "Vitamins",
//        "Minerals", "Water", "Phytochemicals", "Antioxidants", "Electrolytes"
//    ]
//    
//    private let nutrientIcons: [String: String] = [
//        "Calories": "flame", "Protein": "fork.knife", "Carbs": "carrot",
//        "Fats": "drop.fill", "Fiber": "leaf", "Vitamins": "pills",
//        "Minerals": "bolt", "Water": "drop.fill",
//        "Phytochemicals": "leaf.arrow.triangle.circlepath",
//        "Antioxidants": "shield", "Electrolytes": "battery.100"
//    ]
//    
//    private let healthKitManager = HealthKitManager()
//    
//    var body: some View {
//        List {
//            Button(action: {
//                showHome = true
//                selectedNutrient = nil
//            }) {
//                HStack {
//                    Label("Home", systemImage: "house")
//                    if showHome { // Show the green dot if Home is selected
//                        Circle()
//                            .fill(Color.green)
//                            .frame(width: 10, height: 10)
//                    }
//                }
//            }
//            .keyboardShortcut("H", modifiers: [.control]) // ⌘H for Home
//            
//            Section(header: Text("Nutrients")) {
//                ForEach(nutrientChoices, id: \.self) { nutrient in
//                    Button(action: {
//                        showHome = false
//                        selectedNutrient = nutrient
//                    }) {
//                        HStack {
//                            Image(systemName: nutrientIcons[nutrient] ?? "leaf.fill")
//                                .foregroundColor(.blue)
//                            Text(nutrient)
//                            // Add the green dot indicator for the selected nutrient
//                            if selectedNutrient == nutrient {
//                                Circle()
//                                    .fill(Color.green)
//                                    .frame(width: 10, height: 10)
//                            }
//                        }
//                        .padding(10) // Add padding to the button for better click area
//                    }
//                }
//            }
//            
//            Section(header: Text("Utilities")) {
//                // Camera Button
//                Button(action: {
//                    showConfirmation = true // Show the confirmation popup
//                }) {
//                    HStack {
//                        Label("Camera", systemImage: "camera")
//                        if !showHome && selectedNutrient == nil { // Show the green dot if Camera is selected
//                            Circle()
//                                .fill(Color.green)
//                                .frame(width: 10, height: 10)
//                        }
//                    }
//                }
//                .padding()  /*Add padding to the button for better click area*/
//                .keyboardShortcut("C", modifiers: [.control])
//                .popover(isPresented: $showConfirmation, arrowEdge: .leading) {
//                    VStack {
//                        Text("Are you sure you want to open the camera?")
//                            .padding()
//                        HStack {
//                            Button("Cancel") {
//                                showConfirmation = false // Dismiss the confirmation popup
//                            }
//                            .padding()
//                            
//                            Button("Open") {
//                                showCamera.toggle() // Proceed to open the camera
//                                showConfirmation = false // Dismiss the confirmation popup
//                            }
//                            .padding()
//                        }
//                    }
//                    .frame(width: 250) // Set width for the popover
//                }
//                .fullScreenCover(isPresented: $showCamera) {
//                    CameraView(isPresented: $showCamera)
//                }
//            } .listStyle(SidebarListStyle())
//        }
//    }
//}

//struct SearchView: View {
//    @State private var searchText: String = ""
//    @State private var filteredNutrients: [String] = []
//    let nutrientDetails: [String: NutrientInfo]
//
//    var body: some View {
//        VStack {
//            TextField("Search for nutrients", text: $searchText, onCommit: {
//                performSearch()
//            })
//            .textFieldStyle(RoundedBorderTextFieldStyle())
//            .padding()
//            
//            List {
//                ForEach(filteredNutrients, id: \.self) { nutrientName in
//                    if let details = nutrientDetails[nutrientName] {
//                        NutrientCardView(card: details) // Ensure NutrientCardView is set up properly
//                    }
//                }
//            }
//        }
//        .onAppear {
//            filteredNutrients = Array(nutrientDetails.keys) // Initialize with all nutrient names
//        }
//    }
//    
//    private func performSearch() {
//        let (nutrientKeyword, cardKeyword) = extractKeywords(from: searchText)
//
//        filteredNutrients = nutrientDetails.keys.filter { nutrientName in
//            let matchesNutrient = nutrientKeyword == nil || nutrientName.lowercased().contains(nutrientKeyword!.lowercased())
//            let matchesCard = cardKeyword == nil || matchesCardKeyword(for: cardKeyword!, nutrientName: nutrientName)
//
//            return matchesNutrient && matchesCard
//        }
//    }
//    
//    private func extractKeywords(from searchText: String) -> (String?, String?) {
//        let components = searchText.lowercased().split(separator: " ").map { String($0) }
//        
//        guard components.count > 0 else {
//            return (nil, nil) // No keywords
//        }
//
//        var nutrientKeyword: String? = nil
//        var cardKeyword: String? = nil
//        
//        for component in components {
//            if nutrientDetails.keys.contains(component) {
//                nutrientKeyword = component
//            } else if let detectedCard = detectCardKeyword(component) {
//                cardKeyword = detectedCard
//            }
//        }
//
//        return (nutrientKeyword, cardKeyword)
//    }
//
//    private func matchesCardKeyword(for cardKeyword: String, nutrientName: String) -> Bool {
//        // Create a mapping from keywords to the actual card names
//        let cardMap: [String: String] = [
//            "daily": "Today's Consumption",
//            "weekly": "Weekly Consumption",
//            "monthly": "Monthly Consumption",
//            "recommended": "Recommended Intake",
//            "benefits": "Benefits",
//            "foods": "Foods Rich"
//        ]
//        
//        // Check if the cardKeyword matches any of the keywords
//        return cardMap.keys.contains(cardKeyword) && cardMap.values.contains(where: { $0.lowercased() == cardKeyword.lowercased() })
//    }
//    
//    private func detectCardKeyword(_ keyword: String) -> String? {
//        let cardCategories = ["daily", "weekly", "monthly", "recommended", "benefits", "foods"]
//        return cardCategories.first(where: { keyword.lowercased().contains($0) })
//    }
//}
