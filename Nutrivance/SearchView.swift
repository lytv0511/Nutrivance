import SwiftUI
import HealthKit

struct SearchScopeBar: View {
    @EnvironmentObject var searchState: SearchState
    let placeholder: String
    @Binding var searchText: String
    let focus: FocusState<Bool>.Binding
    let onSubmitSearch: () -> Void

    private func shortcut(for scope: SearchScope) -> KeyEquivalent {
        switch scope {
        case .all:
            return "1"
        case .nutrition:
            return "2"
        case .fitness:
            return "3"
        case .mentalHealth:
            return "4"
        }
    }

    private func shortcutLabel(for scope: SearchScope) -> String {
        switch scope {
        case .all:
            return "1"
        case .nutrition:
            return "2"
        case .fitness:
            return "3"
        case .mentalHealth:
            return "4"
        }
    }

    private func scopeButtonTitle(for scope: SearchScope) -> String {
        switch scope {
        case .all:
            return "Search"
        case .nutrition:
            return "Nutrivance"
        case .fitness:
            return "Movance"
        case .mentalHealth:
            return "Spirivance"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(SearchScope.allCases, id: \.self) { scope in
                        Button {
                            searchState.selectedScope = scope
                        } label: {
                            Label(scopeButtonTitle(for: scope), systemImage: scope.icon)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(searchState.selectedScope == scope ? .white : .primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    Group {
                                        if searchState.selectedScope == scope {
                                            Capsule()
                                                .fill(Color.accentColor)
                                        } else {
                                            Capsule()
                                                .fill(.ultraThinMaterial)
                                        }
                                    }
                                )
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(shortcut(for: scope), modifiers: [.control])
                        .accessibilityHint("Control plus \(shortcutLabel(for: scope))")
                    }
                }
            }

            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)

                    TextField(placeholder, text: $searchText)
                        .textFieldStyle(.plain)
                        .focused(focus)
                        .autocorrectionDisabled(true)
                        .onSubmit(onSubmitSearch)

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )

                if focus.wrappedValue {
                    Button("Cancel") {
                        focus.wrappedValue = false
                        searchState.isSearching = false
                    }
                    .keyboardShortcut(.cancelAction)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .padding(.horizontal)
    }
}

struct SearchView: View {
    @EnvironmentObject var navigationState: NavigationState
    @EnvironmentObject var searchState: SearchState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showCamera = false
    @State private var showHome: Bool = true
    @State private var showConfirmation = false
    @State var customization = TabViewCustomization()
    @State private var capturedImage: UIImage?
    @FocusState private var searchBarFocused: Bool
    @FocusState private var sidebarFocused: Bool
    @FocusState private var contentFocused: Bool
    @State private var selectedItem: String?
    @State private var animationPhase: Double = 0
    private let gradients = GradientBackgrounds()
    
    // Update items when needed
    private let nutritionItems = ["Insights", "Labels", "Log",
                                  "Calories", "Carbs", "Protein", "Fats", "Water",
                                  "Fiber", "Vitamins", "Minerals", "Phytochemicals",
                                  "Antioxidants", "Electrolytes"]
    
    private let fitnessItems = ["Dashboard","Readiness Check", "Strain vs Recovery"]
    
    let mentalHealthItems = ["Mindfulness Realm", "Mood Tracker", "Journal", "Sleep", "Stress"]

    private var usesLegacyNavigation: Bool {
        UIDevice.current.userInterfaceIdiom == .phone || horizontalSizeClass == .compact
    }

    private func shouldUseLocalNavigation(for item: String) -> Bool {
        usesLegacyNavigation || target(for: item) == nil
    }
    
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
        "home": ["home", "main", "start", "welcome", "homepage"],
        "insights": ["insights", "health insights", "analysis", "trends", "statistics", "data", "reports", "overview"],
        "labels": ["labels", "scan", "camera", "photo", "nutrition facts", "food label", "scanner", "capture"],
//        "barcode": ["barcode", "scan", "upc", "product lookup", "food scan", "scanner"],
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
        "dashboard": ["dashboard", "metrics", "fitness"],
        "journal": ["journal", "write"],
        "mood": ["mood tracker", "emotion tracker", "mental health", "feeling"],
        "sleep": ["sleep", "rest", "resting", "recovery"],
        "stress": ["hrv", "stress", "anxiety", "mental health", "energy", "nervous balance"],
        "log": ["log", "record", "entry", "history"],
        "recovery score": ["recovery score", "recovery", "score"],
        "fuel": ["fuel check", "energy levels", "energy", "stamina", "food"],
        "strain": ["strain vs recovery", "strain", "hrv"],
        "readiness": ["readiness check", "readiness", "assessment", "hrv"],
        "mindfulness": ["mindfulness realm", "mindfulness", "meditation", "breathing exercises", "stress reduction", "mental health"],
        "workout history": ["workout history", "history", "workouts", "log", "record"]
    ]
    
    var filteredItems: [String] {
        let allItems = ["Dashboard", "Today's Plan", "Training Calendar", "Coach", "Recovery Score", "Readiness Check", "Strain vs Recovery", "Fuel Check", "Workout History", "Activity Rings", "Heart Zones", "Personal Records", "Mindfulness Realm", "Mood Tracker", "Journal", "Sleep", "Stress", "Insights", "Labels", "Log", "Calories", "Carbs", "Protein", "Fats", "Water", "Fiber", "Vitamins", "Minerals", "Phytochemicals", "Antioxidants", "Electrolytes"]

        let query = searchState.searchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            // No query: sort by usage
            return allItems.sorted {
                let usageA = UserDefaults.standard.integer(forKey: "usage_\($0)")
                let usageB = UserDefaults.standard.integer(forKey: "usage_\($1)")
                return usageA > usageB
            }
        }

        let words = query.split(separator: " ").map { String($0) }

        // Filter and score only items that match the query
        let scored: [(item: String, score: Int)] = allItems.compactMap { item in
            let lowerItem = item.lowercased()
            var score = 0
            var isRelevant = false

            // Exact or partial title match
            for word in words {
                if lowerItem.contains(word) {
                    score += 60
                    isRelevant = true
                }
            }

            if lowerItem == query {
                score += 100
                isRelevant = true
            }

            // Keyword scoring
            for (_, keywords) in searchKeywords {
                for keyword in keywords {
                    let k = keyword.lowercased()

                    if k == query || k.replacingOccurrences(of: " ", with: "") == query.replacingOccurrences(of: " ", with: "") {
                        score += 90
                        isRelevant = true
                    } else if k.contains(query) {
                        score += 70
                        isRelevant = true
                    } else {
                        let keywordWords = k.split(separator: " ").map { String($0) }
                        if words.allSatisfy({ keywordWords.contains($0) }) {
                            score += 80
                            isRelevant = true
                        }
                    }

                    for word in words {
                        if k.contains(word) {
                            score += 20
                            isRelevant = true
                        }
                    }
                }
            }

            return isRelevant ? (item, score) : nil
        }

        return scored.sorted { $0.score > $1.score }.map { $0.item }
    }

    // MARK: - Usage Tracking
    private func recordUsage(for item: String) {
        let key = "usage_\(item)"
        let current = UserDefaults.standard.integer(forKey: key)
        UserDefaults.standard.set(current + 1, forKey: key)
    }
    
    private func openFirstResult() {
        guard searchBarFocused, let firstResult = filteredItems.first else { return }
        openResult(firstResult)
    }

    private func target(for item: String) -> (focus: AppFocus, view: String, tab: RootTabSelection)? {
        switch item {
        case "Insights":
            return (.nutrition, "Insights", .insights)
        case "Labels":
            return (.nutrition, "Labels", .labels)
        case "Log":
            return (.nutrition, "Log", .log)
        case "Calories":
            return (.nutrition, "Calories", .calories)
        case "Carbs":
            return (.nutrition, "Carbs", .carbs)
        case "Protein":
            return (.nutrition, "Protein", .protein)
        case "Fats":
            return (.nutrition, "Fats", .fats)
        case "Water":
            return (.nutrition, "Water", .water)
        case "Fiber":
            return (.nutrition, "Fiber", .fiber)
        case "Vitamins":
            return (.nutrition, "Vitamins", .vitamins)
        case "Minerals":
            return (.nutrition, "Minerals", .minerals)
        case "Phytochemicals":
            return (.nutrition, "Phytochemicals", .phytochemicals)
        case "Antioxidants":
            return (.nutrition, "Antioxidants", .antioxidants)
        case "Electrolytes":
            return (.nutrition, "Electrolytes", .electrolytes)
        case "Dashboard":
            return (.fitness, "Dashboard", .dashboard)
        case "Today's Plan":
            return (.fitness, "Today's Plan", .todaysPlan)
        case "Training Calendar":
            return (.fitness, "Training Calendar", .trainingCalendar)
        case "Coach":
            return (.fitness, "Coach", .coach)
        case "Recovery Score":
            return (.fitness, "Recovery Score", .recoveryScore)
        case "Readiness Check":
            return (.fitness, "Readiness", .readiness)
        case "Strain vs Recovery":
            return (.fitness, "Strain vs Recovery", .strainRecovery)
        case "Workout History":
            return (.fitness, "Workout History", .workoutHistory)
        case "Activity Rings":
            return (.fitness, "Activity Rings", .activityRings)
        case "Heart Zones":
            return (.fitness, "Heart Zones", .heartZones)
        case "Personal Records":
            return (.fitness, "Personal Records", .personalRecords)
        case "Mindfulness Realm":
            return (.mentalHealth, "Mindfulness Realm", .mindfulnessRealm)
        case "Mood Tracker":
            return (.mentalHealth, "Mood Tracker", .moodTracker)
        case "Journal":
            return (.mentalHealth, "Journal", .journal)
        case "Sleep":
            return (.mentalHealth, "Sleep", .sleep)
        case "Stress":
            return (.mentalHealth, "Stress", .stress)
        default:
            return nil
        }
    }

    private func openResult(_ item: String) {
        searchBarFocused = false
        searchState.isSearching = false
        recordUsage(for: item)

        if shouldUseLocalNavigation(for: item) {
            selectedItem = item
            return
        }

        guard let target = target(for: item) else { return }
        navigationState.navigate(focus: target.focus, view: target.view, tab: target.tab)
    }

    // MARK: - Typo Tolerance (Levenshtein Distance)
    private func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        var dist = Array(
            repeating: Array(repeating: 0, count: bChars.count + 1),
            count: aChars.count + 1
        )

        for i in 0...aChars.count { dist[i][0] = i }
        for j in 0...bChars.count { dist[0][j] = j }

        for i in 1...aChars.count {
            for j in 1...bChars.count {
                if aChars[i-1] == bChars[j-1] {
                    dist[i][j] = dist[i-1][j-1]
                } else {
                    dist[i][j] = min(
                        dist[i-1][j] + 1,
                        dist[i][j-1] + 1,
                        dist[i-1][j-1] + 1
                    )
                }
            }
        }

        return dist[aChars.count][bChars.count]
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
    
    struct EquatableAnyView: Equatable {
        let view: AnyView
        
        static func == (lhs: EquatableAnyView, rhs: EquatableAnyView) -> Bool {
            withUnsafePointer(to: lhs) { lp in
                withUnsafePointer(to: rhs) { rp in
                    lp == rp
                }
            }
        }
    }

    @State private var currentGradientView: EquatableAnyView

    init() {
        _currentGradientView = State(initialValue: EquatableAnyView(view: AnyView(GradientBackgrounds().boldGradient(animationPhase: .constant(0)))))
    }
    
    private var currentGradient: AnyView {
        currentGradientView.view
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                currentGradient
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                            animationPhase = 20
                        }
                    }

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
//                            Color.clear
//                                .frame(height: 0)
//                                .id("search-top")

                            Text("Explore health, unlock the impossible")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 24)

                            SearchScopeBar(
                                placeholder: "Find in List",
                                searchText: $searchState.searchText,
                                focus: $searchBarFocused,
                                onSubmitSearch: openFirstResult
                            )

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: UIDevice.current.userInterfaceIdiom == .pad ? 200 : 140))], spacing: 40) {
                                ForEach(filteredItems, id: \.self) { item in
                                    Group {
                                        if shouldUseLocalNavigation(for: item) {
                                            NavigationLink(tag: item, selection: $selectedItem) {
                                                destinationView(for: item)
                                            } label: {
                                                resultCard(for: item)
                                            }
                                        } else {
                                            Button {
                                                openResult(item)
                                            } label: {
                                                resultCard(for: item)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                            .padding()
                        }
                    }
                    .onChange(of: searchState.searchText) { _, newValue in
                        let newGradient: EquatableAnyView

                        if !newValue.isEmpty, let firstResult = filteredItems.first {
                            if nutritionItems.contains(firstResult) {
                                newGradient = EquatableAnyView(view: AnyView(gradients.forestGradient(animationPhase: $animationPhase)))
                            } else if fitnessItems.contains(firstResult) {
                                newGradient = EquatableAnyView(view: AnyView(gradients.burningGradient(animationPhase: $animationPhase)))
                            } else if mentalHealthItems.contains(firstResult) {
                                newGradient = EquatableAnyView(view: AnyView(gradients.spiritGradient(animationPhase: $animationPhase)))
                            } else {
                                newGradient = EquatableAnyView(view: AnyView(gradients.boldGradient(animationPhase: $animationPhase)))
                            }
                        } else {
                            newGradient = EquatableAnyView(view: AnyView(gradients.boldGradient(animationPhase: $animationPhase)))
                        }

                        withAnimation(.easeInOut(duration: 1)) {
                            currentGradientView = newGradient
                        }

                        animationPhase += 0.2

                        if searchState.isSearching {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo("search-top", anchor: .top)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Search")
//            .navigationBarTitleDisplayMode(.large)
//            .toolbar {
//                ToolbarItem(placement: .principal) {
//                    Text("Search")
//                        .font(.headline)
//                }
//            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .onChange(of: searchState.isSearching) { _, isSearching in
                searchBarFocused = isSearching
            }
            .onChange(of: searchBarFocused) { _, isFocused in
                if !isFocused {
                    searchState.isSearching = false
                }
            }
            .onAppear {
                searchState.selectedScope = .all
            }
        }
    }
    
    private func destinationView(for item: String) -> some View {
        switch item {
        case "Home":
            return AnyView(HomeView())
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
        case "Mindfulness Realm":
            return AnyView(MindfulnessRealmView())
        case "Mood Tracker":
            return AnyView(MoodTrackerView())
        case "Journal":
            return AnyView(JournalView())
        case "Resources":
            return AnyView(ResourcesView())
        case "Meditation":
            return AnyView(MeditationView())
        case "Breathing":
            return AnyView(BreathingView())
        case "Sleep":
            return AnyView(SleepView())
        case "Stress":
            return AnyView(StressView())
        default:
            return AnyView(HomeView())
        }
    }

    @ViewBuilder
    private func resultCard(for item: String) -> some View {
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
        .frame(width: 120, height: 120)
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }

    
    private var nutritionSections: some View {
        Group {
            Section(header: Text("Main")) {
                ForEach(["Home", "Insights", "Labels", "Log"/*, "Barcode"*/], id: \.self) { item in
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
    case "Home": return "house"
    case "Insights": return "chart.bar.fill"
    case "Labels": return "barcode.viewfinder"
    case "Log": return "square.and.pencil"
//    case "Barcode": return "barcode.viewfinder"
    
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
        
    case "Mindfulness Realm": return "eye.fill"
    case "Mood Tracker": return "sun.max"
    case "Journal": return "book.fill"
    case "Resources": return "folder.fill"
    case "Meditation": return "sparkles"
    case "Breathing": return "wind"
    case "Sleep": return "moon.zzz.fill"
    case "Stress": return "waveform.path.ecg"
    
    default: return "circle.fill"
    }
}
