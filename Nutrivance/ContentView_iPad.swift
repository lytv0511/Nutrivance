import SwiftUI
import HealthKit

struct ContentView_iPad: View {
    @EnvironmentObject var navigationState: NavigationState
    @EnvironmentObject var searchState: SearchState
    @State private var showCamera = false
    @State private var showHome: Bool = true
    @State private var showConfirmation = false
    @State var customization = TabViewCustomization()
    @State private var capturedImage: UIImage?
    @FocusState private var searchBarFocused: Bool
    @FocusState private var sidebarFocused: Bool
    @FocusState private var contentFocused: Bool
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
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
        "playground": ["playground", "sandbox", "testing", "experiment", "explore"],
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
        let allItems = [
            // Nutrition
            "Home", "Playground", "Insights", "Labels", "Log", "Saved Meals",
            
            // Macronutrients
            "Calories", "Carbs", "Protein", "Fats", "Water",
            
            // Micronutrients
            "Fiber", "Vitamins", "Minerals", "Phytochemicals", "Antioxidants", "Electrolytes",
            
            // Fitness Training
            "Dashboard", "Today's Plan", "Workout History", "Training Calendar",
            "Coach", "Movement Analysis", "Exercise Library", "Program Builder", "Workout Generator",
            
            // Recovery
            "Recovery Score", "Sleep Analysis", "Mobility Test", "Readiness", "Strain vs Recovery", "Fuel Check",
            
            // Metrics
            "Activity Rings", "Heart Zones", "Step Count", "Distance", "Calories Burned", "Personal Records",
            
            // Performance Nutrition
            "Pre-Workout Timing", "Post-Workout Window", "Performance Foods", "Hydration Status", "Macro Balance",
            
            // Social
            "Live Challenges", "Friend Activity", "Achievements", "Share Workouts", "Leaderboards",
            
            // Mental Health
            "Mindfulness Realm", "Mood Tracker", "Journal", "Resources",
            
            // Wellness
            "Meditation", "Breathing", "Sleep", "Stress"
        ]
        
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
            NavigationSplitView(columnVisibility: $columnVisibility) {
                List(selection: navigationBinding) {
                    HStack {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                                .padding(.leading, 8)
                            
                            TextField("Find in List", text: $searchState.searchText)
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
                                .keyboardShortcut(".", modifiers: [.command])
                            }
                        }
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                        
                        if searchBarFocused {
                            Button("Cancel") {
                                searchBarFocused = false
                                searchState.searchText = ""
                            }
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                            .padding(8)
                            .hoverEffect(.automatic)
                        }
                    }
                    .animation(.spring(), value: searchBarFocused)

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
                    // Nutrition Focus
                    case "Home":
                        AnyView(HomeView())
                    case "Insights":
                        AnyView(HealthInsightsView())
                    case "Labels":
                        AnyView(NutritionScannerView())
                    case "Log":
                        AnyView(LogView())
                    case "Saved Meals":
                        AnyView(SavedMealsView())
                    
                    // Detailed Nutrients
                    case "Calories":
                        AnyView(NutrientDetailView(nutrientName: "Calories", columnVisibility: columnVisibility))
                    case "Carbs":
                        AnyView(NutrientDetailView(nutrientName: "Carbs", columnVisibility: columnVisibility))
                    case "Protein":
                        AnyView(NutrientDetailView(nutrientName: "Protein", columnVisibility: columnVisibility))
                    case "Fats":
                        AnyView(NutrientDetailView(nutrientName: "Fats", columnVisibility: columnVisibility))
                    case "Water":
                        AnyView(NutrientDetailView(nutrientName: "Water", columnVisibility: columnVisibility))
                    case "Fiber":
                        AnyView(NutrientDetailView(nutrientName: "Fiber", columnVisibility: columnVisibility))
                    case "Vitamins":
                        AnyView(NutrientDetailView(nutrientName: "Vitamins", columnVisibility: columnVisibility))
                    case "Minerals":
                        AnyView(NutrientDetailView(nutrientName: "Minerals", columnVisibility: columnVisibility))
                    case "Phytochemicals":
                        AnyView(NutrientDetailView(nutrientName: "Phytochemicals", columnVisibility: columnVisibility))
                    case "Antioxidants":
                        AnyView(NutrientDetailView(nutrientName: "Antioxidants", columnVisibility: columnVisibility))
                    case "Electrolytes":
                        AnyView(NutrientDetailView(nutrientName: "Electrolytes", columnVisibility: columnVisibility))
                    
                    // Fitness Focus - Training
                    case "Dashboard":
                        AnyView(DashboardView())
                    case "Today's Plan":
                        AnyView(TodaysPlanView(planType: .all))
                    case "Workout History":
                        AnyView(WorkoutHistoryView())
                    case "Training Calendar":
                        AnyView(TrainingCalendarView())
                    case "Coach":
                        AnyView(CoachView())
                    case "Movement Analysis":
                        AnyView(MovementAnalysisView())
                    case "Exercise Library":
                        AnyView(ExerciseLibraryView())
                    case "Program Builder":
                        AnyView(ProgramBuilderView())
                    case "Workout Generator":
                        AnyView(WorkoutGeneratorView())
                    
                    // Fitness Focus - Recovery
                    case "Recovery Score":
                        AnyView(RecoveryScoreView())
                    case "Sleep Analysis":
                        AnyView(SleepAnalysisView())
                    case "Mobility Test":
                        AnyView(MobilityTestView())
                    case "Readiness":
                        AnyView(ReadinessCheckView())
                    case "Strain vs Recovery":
                        AnyView(StrainRecoveryView())
                    case "Fuel Check":
                        AnyView(FuelCheckView())
                    
                    // Fitness Focus - Metrics
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
                    
                    // Fitness Focus - Nutrition
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
                    
                    // Fitness Focus - Social
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
                    
                    // Mental Health Focus
                    case "Mindfulness Realm":
                        AnyView(MindfulnessRealmView())
                    case "Mood Tracker":
                        AnyView(MoodTrackerView())
                    case "Journal":
                        AnyView(JournalView())
                    case "Resources":
                        AnyView(ResourcesView())
                    case "Meditation":
                        AnyView(MeditationView())
                    case "Breathing":
                        AnyView(BreathingView())
                    case "Sleep":
                        AnyView(SleepView())
                    case "Stress":
                        AnyView(StressView())
                    case "Playground":
                        AnyView(PlaygroundView())
                    
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
                ForEach(["Home", "Playground"], id: \.self) { item in
                    if filteredItems.contains(item) {
                        Label(item, systemImage: getIconName(for: item))
                            .tag(item)
                    }
                }
            }
            Section(header: Text("Nutrivance Tools")) {
                ForEach(["Insights", "Labels", "Log", "Saved Meals"], id: \.self) { item in
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
                ForEach(["Home", "Playground"], id: \.self) { item in
                    if filteredItems.contains(item) {
                        Label(item, systemImage: getIconName(for: item))
                            .tag(item)
                    }
                }
            }
            Section(header: Text("Training")) {
                ForEach(["Dashboard", "Today's Plan", "Workout History", "Training Calendar", "Coach", "Movement Analysis", "Exercise Library", "Program Builder", "Workout Generator"], id: \.self) { item in
                    if filteredItems.contains(item) {
                        Label(item, systemImage: getIconName(for: item))
                            .tag(item)
                    }
                }
            }
            
            Section(header: Text("Recovery")) {
                ForEach(["Recovery Score", "Sleep Analysis", "Mobility Test", "Readiness", "Strain vs Recovery", "Fuel Check"], id: \.self) { item in
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
            
            Section(header: Text("Performance Nutrition")) {
                ForEach(["Pre-Workout Timing", "Post-Workout Window", "Performance Foods", "Hydration Status", "Macro Balance"], id: \.self) { item in
                    if filteredItems.contains(item) {
                        Label(item, systemImage: getIconName(for: item))
                            .tag(item)
                    }
                }
            }
            
            Section(header: Text("Social")) {
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
                ForEach(["Home", "Playground"], id: \.self) { item in
                    if filteredItems.contains(item) {
                        Label(item, systemImage: getIconName(for: item))
                            .tag(item)
                    }
                }
            }
            Section(header: Text("Mental Health")) {
                ForEach(["Mindfulness Realm", "Mood Tracker", "Journal", "Resources"], id: \.self) { item in
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

private func getIconName(for item: String) -> String {
    switch item {
    // Main section
    case "Home": return "house.fill"
    case "Insights": return "chart.bar.fill"
    case "Labels": return "barcode.viewfinder"
    case "Log": return "square.and.pencil"
    case "Playground": return "arrow.triangle.2.circlepath"
    
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
        
    // Update
    case "Mindfulness Realm": return "eye.fill"
    case "Mood Tracker": return "sun.max"
    case "Journal": return "book.fill"
    case "Resources": return "folder.fill"
    case "Meditation": return "sparkles"
    case "Breathing": return "wind"
    case "Sleep": return "moon.zzz.fill"
    case "Stress": return "waveform.path.ecg"
    case "Saved Meals": return "bookmark.fill"

    default: return "circle.fill"
    }
}
