import SwiftUI
import HealthKit

struct NutrivanceView: View {
    @State private var animationPhase: Double = 0
    @EnvironmentObject var navigationState: NavigationState
    @EnvironmentObject var searchState: SearchState
    @State private var showCamera = false
    @State private var showConfirmation = false
    @State var customization = TabViewCustomization()
    @State private var capturedImage: UIImage?
    @FocusState private var searchBarFocused: Bool
    @FocusState private var sidebarFocused: Bool
    @FocusState private var contentFocused: Bool
//    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
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
        "electrolytes": ["electrolytes", "sodium", "potassium", "chloride"],
        "barcode": ["barcode", "code 128", "upc", "ean"]
    ]
    var filteredItems: [String] {
           let nutritionItems = ["Insights", "Labels", "Log",
                                 "Calories", "Carbs", "Protein", "Fats", "Water", "Barcode",
                              "Fiber", "Vitamins", "Minerals", "Phytochemicals",
                              "Antioxidants", "Electrolytes"]
        
        if searchState.searchText.isEmpty {
            return nutritionItems
        }
        
        return nutritionItems.filter { item in
            let lowercasedItem = item.lowercased()
            if let keywords = searchKeywords[lowercasedItem] {
                return keywords.contains { keyword in
                    keyword.localizedCaseInsensitiveContains(searchState.searchText)
                } || lowercasedItem.localizedCaseInsensitiveContains(searchState.searchText)
            }
            return lowercasedItem.localizedCaseInsensitiveContains(searchState.searchText)
        }
    }
    
    private func getAppTitle(_ focus: AppFocus) -> String {
        switch focus {
        case .nutrition:
            return "Nutrivance"
        case .fitness:
            return "Movance"
        case .mentalHealth:
            return "Spirivance"
        }
    }
    
    private func getFocusIcon(_ focus: AppFocus) -> String {
        switch focus {
        case .nutrition:
            return "leaf.fill"
        case .fitness:
            return "figure.run"
        case .mentalHealth:
            return "brain.head.profile"
        }
    }
        
    var body: some View {
        NavigationStack {
                VStack {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Fuel vitality with nature's essence")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 24)
                        HStack {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 8)
                                
                                TextField("Nature's bounty...", text: $searchState.searchText)
                                    .textFieldStyle(.plain)
                                    .focused($searchBarFocused)
                                    .autocorrectionDisabled(true)
                                
                                if !searchState.searchText.isEmpty {
                                    Button(action: {
                                        searchState.searchText = ""
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                            .frame(width: 16, height: 16)
                                    }
                                    .hoverEffect(.automatic)
                                    .padding(.trailing, 8)
                                }
                            }
                            .padding(8)
                            .background(Color(.systemGray5))
                            .cornerRadius(8)
                            
                            if searchBarFocused {
                                Button("Cancel") {
                                    searchBarFocused = false
                                }
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                                .padding(8)
                                .hoverEffect(.automatic)
                            }
                        }
                        .padding(.horizontal)
                        .animation(.spring(), value: searchBarFocused)
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: UIDevice.current.userInterfaceIdiom == .pad ? 200 : 140))], spacing: 40) {
                                ForEach(filteredItems, id: \.self) { item in
                                    NavigationLink {
                                        switch item {
                                        case "Insights":
                                            HealthInsightsView()
                                        case "Labels":
                                            NutritionScannerView()
                                        case "Log":
                                            UnifiedLogView()
//                                        case "Barcode":
//                                            BarcodeScannerView()
                                        case "Calories", "Carbs", "Protein", "Fats", "Water", "Fiber", "Vitamins", "Minerals", "Phytochemicals", "Antioxidants", "Electrolytes":
                                            NutrientDetailView(nutrientName: item)
                                        case "Dashboard":
                                            DashboardView()
                                        case "Today's Plan":
                                            TodaysPlanView(planType: .all)
                                        case "Workout History":
                                            WorkoutHistoryView()
                                        case "Training Calendar":
                                            TrainingCalendarView()
                                        case "Coach":
                                            CoachView()
                                        case "Movement Analysis":
                                            MovementAnalysisView()
                                        case "Exercise Library":
                                            ExerciseLibraryView()
                                        case "Program Builder":
                                            ProgramBuilderView()
                                        case "Workout Generator":
                                            WorkoutGeneratorView()
                                        case "Recovery Score":
                                            RecoveryScoreView()
                                        case "Sleep Analysis":
                                            SleepAnalysisView()
                                        case "Mobility Test":
                                            MobilityTestView()
                                        case "Readiness Check":
                                            ReadinessCheckView()
                                        case "Strain vs Recovery":
                                            StrainRecoveryView()
                                        case "Activity Rings":
                                            ActivityRingsView()
                                        case "Heart Zones":
                                            HeartZonesView()
                                        case "Step Count":
                                            StepCountView()
                                        case "Distance":
                                            DistanceView()
                                        case "Calories Burned":
                                            CaloriesBurnedView()
                                        case "Personal Records":
                                            PersonalRecordsView()
                                        case "Pre-Workout Timing":
                                            PreWorkoutTimingView()
                                        case "Post-Workout Window":
                                            PostWorkoutWindowView()
                                        case "Performance Foods":
                                            PerformanceFoodsView()
                                        case "Hydration Status":
                                            HydrationStatusView()
                                        case "Macro Balance":
                                            MacroBalanceView()
                                        case "Live Challenges":
                                            LiveChallengesView()
                                        case "Friend Activity":
                                            FriendActivityView()
                                        case "Achievements":
                                            AchievementsView()
                                        case "Share Workouts":
                                            ShareWorkoutsView()
                                        case "Leaderboards":
                                            LeaderboardsView()
                                        case "Fuel Check":
                                            FuelCheckView()
                                        default:
                                            HealthInsightsView()
                                        }
                                    } label: {
                                        VStack {
                                            Image(systemName: getIconName(for: item))
                                                .font(.system(size: 40))
                                                .foregroundColor(.primary)
                                                .frame(width: 80, height: 80)
                                                .background(.ultraThinMaterial)
                                                .clipShape(Circle())
                                            
                                            Text(item)
                                                .font(.caption)
                                                .multilineTextAlignment(.center)
                                                .frame(width: 80, height: 40)
                                        }
                                        .frame(width: 120, height: 120) // Makes container square
                                        .padding()
                                        .background(.ultraThinMaterial)
                                        .cornerRadius(12)
                                    }
                                }
                                
                            }
                            .padding()
                        }
                        .navigationTitle("Nutrivance")
                        .navigationBarTitleDisplayMode(.large)
                    }
                }
                .background(
                   GradientBackgrounds().forestGradient(animationPhase: $animationPhase)
                       .onAppear {
                           withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                               animationPhase = 20
                           }
                       }
               )
        }
    }
    
    private func destinationView(for item: String) -> some View {
        switch item {
        case "Insights":
            return AnyView(HealthInsightsView())
        case "Labels":
            return AnyView(NutritionScannerView())
        case "Log":
            return AnyView(UnifiedLogView())
        case "Calories", "Carbs", "Protein", "Fats", "Water", "Fiber", "Vitamins", "Minerals", "Phytochemicals", "Antioxidants", "Electrolytes":
            return AnyView(NutrientDetailView(nutrientName: item))
//        case "Barcode":
//            return AnyView(BarcodeScannerView())
        case "Dashboard":
            return AnyView(DashboardView())
        case "Today's Plan":
            return AnyView(TodaysPlanView(planType: .all))
        case "Workout History":
            return AnyView(WorkoutHistoryView())
        case "Training Calendar":
            return AnyView(TrainingCalendarView())
        case "Coach":
            return AnyView(CoachView())
        case "Movement Analysis":
            return AnyView(MovementAnalysisView())
        case "Exercise Library":
            return AnyView(ExerciseLibraryView())
        case "Program Builder":
            return AnyView(ProgramBuilderView())
        case "Workout Generator":
            return AnyView(WorkoutGeneratorView())
        case "Recovery Score":
            return AnyView(RecoveryScoreView())
        case "Sleep Analysis":
            return AnyView(SleepAnalysisView())
        case "Mobility Test":
            return AnyView(MobilityTestView())
        case "Readiness Check":
            return AnyView(ReadinessCheckView())
        case "Strain vs Recovery":
            return AnyView(StrainRecoveryView())
        case "Activity Rings":
            return AnyView(ActivityRingsView())
        case "Heart Zones":
            return AnyView(HeartZonesView())
        case "Step Count":
            return AnyView(StepCountView())
        case "Distance":
            return AnyView(DistanceView())
        case "Calories Burned":
            return AnyView(CaloriesBurnedView())
        case "Personal Records":
            return AnyView(PersonalRecordsView())
        case "Pre-Workout Timing":
            return AnyView(PreWorkoutTimingView())
        case "Post-Workout Window":
            return AnyView(PostWorkoutWindowView())
        case "Performance Foods":
            return AnyView(PerformanceFoodsView())
        case "Hydration Status":
            return AnyView(HydrationStatusView())
        case "Macro Balance":
            return AnyView(MacroBalanceView())
        case "Live Challenges":
            return AnyView(LiveChallengesView())
        case "Friend Activity":
            return AnyView(FriendActivityView())
        case "Achievements":
            return AnyView(AchievementsView())
        case "Share Workouts":
            return AnyView(ShareWorkoutsView())
        case "Leaderboards":
            return AnyView(LeaderboardsView())
        case "Fuel Check":
            return AnyView(FuelCheckView())
        default:
            return AnyView(HealthInsightsView())
        }
    }

    
    private var nutritionSections: some View {
        Group {
            Section(header: Text("Main")) {
                ForEach(["Insights", "Labels", "Log", "Barcode"], id: \.self) { item in
                    if filteredItems.contains(item) {
                        Label(item, systemImage: getIconName(for: item))
                            .tag(item)
                    }
                }
            }
            
            Section(header: Text("Macronutrients")) {
                ForEach(["Calories", "Carbs", "Protein", "Fats", "Water"], id: \.self) { item in
                    if filteredItems.contains(item) {
                        Label(item, systemImage: getIconName(for: item))
                            .tag(item)
                    }
                }
            }
            
            Section(header: Text("Micronutrients")) {
                ForEach(["Fiber", "Vitamins", "Minerals", "Phytochemicals", "Antioxidants", "Electrolytes"], id: \.self) { item in
                    if filteredItems.contains(item) {
                        Label(item, systemImage: getIconName(for: item))
                            .tag(item)
                    }
                }
            }
        }
    }
    private var fitnessSections: some View {
        Group {
            Section(header: Text("Main")) {
                ForEach(["Dashboard", "Today's Plan", "Workout History", "Training Calendar"], id: \.self) { item in
                    if filteredItems.contains(item) {
                        Label(item, systemImage: getIconName(for: item))
                            .tag(item)
                    }
                }
            }
            
            Section(header: Text("Smart Training")) {
                ForEach(["Coach", "Movement Analysis", "Exercise Library", "Program Builder", "Workout Generator"], id: \.self) { item in
                    if filteredItems.contains(item) {
                        Label(item, systemImage: getIconName(for: item))
                            .tag(item)
                    }
                }
            }
            
            Section(header: Text("Recovery")) {
                ForEach(["Recovery Score", "Sleep Analysis", "Mobility Test", "Readiness Check", "Strain vs Recovery"], id: \.self) { item in
                    if filteredItems.contains(item) {
                        Label(item, systemImage: getIconName(for: item))
                            .tag(item)
                    }
                }
            }
            
            Section(header: Text("Metrics")) {
                ForEach(["Activity Rings", "Heart Zones", "Step Count", "Distance", "Calories Burned", "Personal Records"], id: \.self) { item in
                    if filteredItems.contains(item) {
                        Label(item, systemImage: getIconName(for: item))
                            .tag(item)
                    }
                }
            }
            
            Section(header: Text("Nutrition Impact")) {
                ForEach(["Pre-Workout Timing", "Post-Workout Window", "Fuel Check", "Hydration Status", "Macro Balance"], id: \.self) { item in
                    if filteredItems.contains(item) {
                        Label(item, systemImage: getIconName(for: item))
                            .tag(item)
                    }
                }
            }
            
            Section(header: Text("Community")) {
                ForEach(["Live Challenges", "Friend Activity", "Achievements", "Share Workouts", "Leaderboards"], id: \.self) { item in
                    if filteredItems.contains(item) {
                        Label(item, systemImage: getIconName(for: item))
                            .tag(item)
                    }
                }
            }
        }
    }
    private var mentalHealthSections: some View {
        Group {
            Section(header: Text("Main")) {
                ForEach(["Dashboard", "Mood Tracker", "Journal", "Resources"], id: \.self) { item in
                    if filteredItems.contains(item) {
                        Label(item, systemImage: getIconName(for: item))
                            .tag(item)
                    }
                }
            }
            
            Section(header: Text("Wellness")) {
                ForEach(["Meditation", "Breathing", "Sleep", "Stress"], id: \.self) { item in
                    if filteredItems.contains(item) {
                        Label(item, systemImage: getIconName(for: item))
                            .tag(item)
                    }
                }
            }
            
            Section(header: Text("Support")) {
                ForEach(["Community", "Professional Help", "Crisis Resources"], id: \.self) { item in
                    if filteredItems.contains(item) {
                        Label(item, systemImage: getIconName(for: item))
                            .tag(item)
                    }
                }
            }
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
    
    private func cycleFocusForward() {
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
    
    private func cycleFocusBackward() {
        if searchBarFocused {
            searchBarFocused = false
            contentFocused = true
        } else if contentFocused {
            contentFocused = false
            sidebarFocused = true
        } else {
            sidebarFocused = false
            searchBarFocused = true
        }
    }
}

private func getIconName(for item: String) -> String {
    switch item {
    // Main section
    case "Insights": return "chart.bar.fill"
    case "Labels": return "barcode.viewfinder"
    case "Log": return "square.and.pencil"
    case "Barcode": return "barcode.viewfinder"
    
    // Nutrition
    case "Calories": return "flame.fill"
    case "Carbs": return "leaf.fill"
    case "Protein": return "fish.fill"
    case "Fats": return "drop.fill"
    case "Water": return "drop.circle.fill"
    case "Fiber": return "circle.grid.cross.fill"
    case "Vitamins": return "pills.fill"
    case "Minerals": return "sparkles"
    case "Phytochemicals": return "leaf.arrow.circlepath"
    case "Antioxidants": return "shield.fill"
    case "Electrolytes": return "bolt.fill"
    
    // Fitness
    case "Dashboard": return "gauge.medium"
    case "Today's Plan": return "calendar.badge.clock"
    case "Workout History": return "clock.arrow.circlepath"
    case "Training Calendar": return "calendar.badge.plus"
    case "Coach": return "figure.mind.and.body"
    case "Movement Analysis": return "figure.walk.motion"
    case "Fuel Check": return "fuelpump.fill"
    case "Exercise Library": return "books.vertical.fill"
    case "Program Builder": return "hammer.fill"
    case "Workout Generator": return "wand.and.stars"
    
    // Recovery & Analysis
    case "Recovery Score": return "heart.text.square.fill"
    case "Sleep Analysis": return "moon.zzz.fill"
    case "Mobility Test": return "figure.walk.arrival"
    case "Readiness Check": return "checkmark.seal.fill"
    case "Strain vs Recovery": return "arrow.left.arrow.right"
    
    // Metrics
    case "Activity Rings": return "circle.circle.fill"
    case "Heart Zones": return "heart.circle.fill"
    case "Step Count": return "figure.walk"
    case "Distance": return "location.fill"
    case "Calories Burned": return "flame.circle.fill"
    case "Personal Records": return "trophy.fill"
    
    // Nutrition Timing
    case "Pre-Workout Timing": return "timer"
    case "Post-Workout Window": return "clock.badge.checkmark"
    case "Performance Foods": return "leaf.circle.fill"
    case "Hydration Status": return "drop.triangle.fill"
    case "Macro Balance": return "scale.3d"
    
    // Social
    case "Live Challenges": return "flag.fill"
    case "Friend Activity": return "person.2.fill"
    case "Achievements": return "medal.fill"
    case "Share Workouts": return "square.and.arrow.up.fill"
    case "Leaderboards": return "list.number"
    
    default: return "circle.fill"
    }
}
