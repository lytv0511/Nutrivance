import SwiftUI
import HealthKit

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
                       "Fiber", "Vitamins", "Minerals", "Phytochemicals", "Antioxidants", "Electrolytes",
                       "Dashboard", "Today's Plan", "Workout History", "Training Calendar",
                       "Form Coach", "Movement Analysis", "Exercise Library", "Program Builder", "Workout Generator",
                       "Recovery Score", "Sleep Analysis", "Mobility Test", "Readiness Check", "Strain vs Recovery",
                       "Activity Rings", "Heart Zones", "Step Count", "Distance", "Calories Burned", "Personal Records",
                       "Pre-Workout Timing", "Post-Workout Window", "Performance Foods", "Hydration Status", "Macro Balance",
                       "Live Challenges", "Friend Activity", "Achievements", "Share Workouts", "Leaderboards"]
        
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
        ZStack {
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
                    
                    switch navigationState.appFocus {
                    case .nutrition:
                        nutritionSections
                    case .fitness:
                        fitnessSections
                    case .mentalHealth:
                        mentalHealthSections
                    }
                }
                .toolbar(id: "mainToolbar") {
                    ToolbarItem(id: "focusSelector", placement: .automatic) {
                        Menu {
                            ForEach(AppFocus.allCases, id: \.self) { focus in
                                Button {
                                    withAnimation(.spring()) {
                                        navigationState.appFocus = focus
                                    }
                                } label: {
                                    Label(focus.rawValue, systemImage: getFocusIcon(focus))
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: getFocusIcon(navigationState.appFocus))
                                Text(navigationState.appFocus.rawValue)
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(FocusPickerButtonStyle())
                    }
                }
                .navigationTitle(getAppTitle(navigationState.appFocus))
                .onChange(of: searchState.isSearching) { _, isSearching in
                    if isSearching {
                        searchBarFocused = true
                    } else {
                        searchBarFocused = false
                        sidebarFocused = true
                    }
                }
                .focused($sidebarFocused)
            } detail: {
                Group {
                    switch navigationState.selectedView {
                    case "Home":
                        AnyView(HomeView())
                    case "Insights":
                        AnyView(HealthInsightsView())
                    case "Labels":
                        AnyView(NutritionScannerView())
                    case "Log":
                        AnyView(LogView())
                    case "Calories":
                        AnyView(NutrientDetailView(nutrientName: "Calories"))
                    case "Carbs":
                        AnyView(NutrientDetailView(nutrientName: "Carbs"))
                    case "Protein":
                        AnyView(NutrientDetailView(nutrientName: "Protein"))
                    case "Fats":
                        AnyView(NutrientDetailView(nutrientName: "Fats"))
                    case "Water":
                        AnyView(NutrientDetailView(nutrientName: "Water"))
                    case "Fiber":
                        AnyView(NutrientDetailView(nutrientName: "Fiber"))
                    case "Vitamins":
                        AnyView(NutrientDetailView(nutrientName: "Vitamins"))
                    case "Minerals":
                        AnyView(NutrientDetailView(nutrientName: "Minerals"))
                    case "Phytochemicals":
                        AnyView(NutrientDetailView(nutrientName: "Phytochemicals"))
                    case "Antioxidants":
                        AnyView(NutrientDetailView(nutrientName: "Antioxidants"))
                    case "Electrolytes":
                        AnyView(NutrientDetailView(nutrientName: "Electrolytes"))
                    case "Dashboard":
                        AnyView(DashboardView())
                    case "Today's Plan":
                        AnyView(TodaysPlanView())
                    case "Workout History":
                        AnyView(WorkoutHistoryView())
                    case "Training Calendar":
                        AnyView(TrainingCalendarView())
                    case "Form Coach":
                        AnyView(FormCoachView())
                    case "Movement Analysis":
                        AnyView(MovementAnalysisView())
                    case "Exercise Library":
                        AnyView(ExerciseLibraryView())
                    case "Program Builder":
                        AnyView(ProgramBuilderView())
                    case "Workout Generator":
                        AnyView(WorkoutGeneratorView())
                    case "Recovery Score":
                        AnyView(RecoveryScoreView())
                    case "Sleep Analysis":
                        AnyView(SleepAnalysisView())
                    case "Mobility Test":
                        AnyView(MobilityTestView())
                    case "Readiness Check":
                        AnyView(ReadinessCheckView())
                    case "Strain vs Recovery":
                        AnyView(StrainRecoveryView())
                    case "Activity Rings":
                        AnyView(ActivityRingsView())
                    case "Heart Zones":
                        AnyView(HeartZonesView())
                    case "Step Count":
                        AnyView(StepCountView())
                    case "Distance":
                        AnyView(DistanceView())
                    case "Calories Burned":
                        AnyView(CaloriesBurnedView())
                    case "Personal Records":
                        AnyView(PersonalRecordsView())
                    case "Pre-Workout Timing":
                        AnyView(PreWorkoutTimingView())
                    case "Post-Workout Window":
                        AnyView(PostWorkoutWindowView())
                    case "Performance Foods":
                        AnyView(PerformanceFoodsView())
                    case "Hydration Status":
                        AnyView(HydrationStatusView())
                    case "Macro Balance":
                        AnyView(MacroBalanceView())
                    case "Live Challenges":
                        AnyView(LiveChallengesView())
                    case "Friend Activity":
                        AnyView(FriendActivityView())
                    case "Achievements":
                        AnyView(AchievementsView())
                    case "Share Workouts":
                        AnyView(ShareWorkoutsView())
                    case "Leaderboards":
                        AnyView(LeaderboardsView())
                    default:
                        AnyView(HomeView())
                    }
                }
                .focused($contentFocused)
            }
            
            if navigationState.showFocusSwitcher {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .overlay {
                        HStack(spacing: 20) {
                            ForEach(AppFocus.allCases, id: \.self) { focus in
                                VStack {
                                    Image(systemName: getFocusIcon(focus))
                                        .font(.system(size: 40))
                                        .foregroundStyle(navigationState.tempFocus == focus ? .blue : .secondary)
                                    Text(getAppTitle(focus))
                                        .font(.caption)
                                        .foregroundStyle(navigationState.tempFocus == focus ? .primary : .secondary)
                                }
                                .padding()
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .scaleEffect(navigationState.tempFocus == focus ? 1.1 : 0.9)
                                .animation(.spring(response: 0.3), value: navigationState.tempFocus)
                            }
                        }
                        .padding(40)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                    .transition(.opacity)
            }
        }
    }
    private var nutritionSections: some View {
        Group {
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
    }
    private var fitnessSections: some View {
        Group {
            Section(header: Text("Main")) {
                ForEach(["Dashboard", "Today's Plan", "Workout History", "Training Calendar"], id: \.self) { item in
                    if filteredItems.contains(item) {
                        Text(item)
                            .tag(item)
                    }
                }
            }
            
            Section(header: Text("Smart Training")) {
                ForEach(["Form Coach", "Movement Analysis", "Exercise Library", "Program Builder", "Workout Generator"], id: \.self) { item in
                    if filteredItems.contains(item) {
                        Text(item)
                            .tag(item)
                    }
                }
            }
            
            Section(header: Text("Recovery")) {
                ForEach(["Recovery Score", "Sleep Analysis", "Mobility Test", "Readiness Check", "Strain vs Recovery"], id: \.self) { item in
                    if filteredItems.contains(item) {
                        Text(item)
                            .tag(item)
                    }
                }
            }
            
            Section(header: Text("Metrics")) {
                ForEach(["Activity Rings", "Heart Zones", "Step Count", "Distance", "Calories Burned", "Personal Records"], id: \.self) { item in
                    if filteredItems.contains(item) {
                        Text(item)
                            .tag(item)
                    }
                }
            }
            
            Section(header: Text("Nutrition Impact")) {
                ForEach(["Pre-Workout Timing", "Post-Workout Window", "Performance Foods", "Hydration Status", "Macro Balance"], id: \.self) { item in
                    if filteredItems.contains(item) {
                        Text(item)
                            .tag(item)
                    }
                }
            }
            
            Section(header: Text("Community")) {
                ForEach(["Live Challenges", "Friend Activity", "Achievements", "Share Workouts", "Leaderboards"], id: \.self) { item in
                    if filteredItems.contains(item) {
                        Text(item)
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
                        Text(item)
                            .tag(item)
                    }
                }
            }
            
            Section(header: Text("Wellness")) {
                ForEach(["Meditation", "Breathing", "Sleep", "Stress"], id: \.self) { item in
                    if filteredItems.contains(item) {
                        Text(item)
                            .tag(item)
                    }
                }
            }
            
            Section(header: Text("Support")) {
                ForEach(["Community", "Professional Help", "Crisis Resources"], id: \.self) { item in
                    if filteredItems.contains(item) {
                        Text(item)
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

struct FocusPickerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(8)
            .background(.ultraThinMaterial.opacity(configuration.isPressed ? 0.7 : 1))
            .clipShape(Capsule())
            .contentShape(Capsule())
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }
}
