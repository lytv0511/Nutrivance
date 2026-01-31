//import SwiftUI
//import SwiftData
//
//struct ContentView_iPhone: View {
//    @EnvironmentObject var navigationState: NavigationState
//    @State private var selectedView: String = "Home"
//    @State private var choices: [String] = []
//    @State private var icons: [String: String] = [:]
//    @Environment(\.horizontalSizeClass) var horizontalSizeClass
//    @State private var navigationPath = NavigationPath()
//    @State var choice: String = "Home"
//    @State var selectedNutrient: String = "Calories"
//    @State private var showDetails = false
//    
//    var currentViewChoices: [String] {
//        switch navigationState.appFocus {
//        case .nutrition:
//            return ["Home", "Insights", "Labels", "Log",
//                   "Calories", "Carbs", "Protein", "Fats", "Water",
//                   "Fiber", "Vitamins", "Minerals", "Phytochemicals",
//                   "Antioxidants", "Electrolytes"]
//        case .fitness:
//            return ["Dashboard", "Today's Plan", "Workout History", "Training Calendar",
//                   "Coach", "Movement Analysis", "Exercise Library",
//                   "Program Builder", "Workout Generator", "Recovery Score",
//                   "Sleep Analysis", "Mobility Test", "Readiness Check",
//                   "Strain vs Recovery", "Activity Rings", "Heart Zones",
//                   "Step Count", "Distance", "Calories Burned", "Personal Records",
//                   "Pre-Workout Timing", "Post-Workout Window", "Performance Foods",
//                   "Hydration Status", "Macro Balance"]
//        case .mentalHealth:
//            return ["Live Challenges", "Friend Activity", "Achievements",
//                   "Share Workouts", "Leaderboards"]
//        }
//    }
//    
//    var body: some View {
//        NavigationStack {
//            ZStack {
//                LinearGradient(
//                    gradient: Gradient(colors: [Color.black, Color.blue, Color(red: 0.0, green: 0.5, blue: 0.0)]),
//                    startPoint: .top,
//                    endPoint: .bottom
//                )
//                .ignoresSafeArea()
//                
//                VStack {
//                    ScrollViewReader { proxy in
//                        ScrollView {
//                            let columns = Array(repeating: GridItem(.flexible()), count: horizontalSizeClass == .compact ? 2 : 5)
//                            
//                            LazyVGrid(columns: columns, spacing: 20) {
//                                ForEach(currentViewChoices, id: \.self) { view in
//                                    ViewGridItem(viewName: view, isSelected: selectedView == view)
//                                        .onTapGesture {
//                                            navigationState.selectedView = view
//                                        }
//                                }
//                            }
//                            .padding()
//                        }
//                        .onChange(of: selectedView) { _, newValue in
//                            withAnimation {
//                                proxy.scrollTo(newValue, anchor: .center)
//                            }
//                        }
//                    }
//                    
//                    WheelPicker(
//                        choices: currentViewChoices,
//                        choice: $selectedNutrient,
//                        onChange: { newChoice in
//                            selectedNutrient = newChoice
//                        },
//                        selectedNutrient: $selectedNutrient
//                    )
//                    .padding(.bottom)
//                }
//            }
//            .navigationDestination(for: String.self) { view in
//                switch view {
//                case "Home": HomeView()
//                case "Insights": HealthInsightsView()
//                case "Labels": NutritionScannerView()
//                case "Log": LogView()
//                case "Calories": NutrientDetailView(nutrientName: "Calories")
//                case "Carbs": NutrientDetailView(nutrientName: "Carbs")
//                case "Protein": NutrientDetailView(nutrientName: "Protein")
//                case "Fats": NutrientDetailView(nutrientName: "Fats")
//                case "Water": NutrientDetailView(nutrientName: "Water")
//                case "Fiber": NutrientDetailView(nutrientName: "Fiber")
//                case "Vitamins": NutrientDetailView(nutrientName: "Vitamins")
//                case "Minerals": NutrientDetailView(nutrientName: "Minerals")
//                case "Phytochemicals": NutrientDetailView(nutrientName: "Phytochemicals")
//                case "Antioxidants": NutrientDetailView(nutrientName: "Antioxidants")
//                case "Electrolytes": NutrientDetailView(nutrientName: "Electrolytes")
//                case "Dashboard": DashboardView()
//                case "Today's Plan": TodaysPlanView()
//                case "Workout History": WorkoutHistoryView()
//                case "Training Calendar": TrainingCalendarView()
//                case "Coach": CoachView()
//                case "Movement Analysis": MovementAnalysisView()
//                case "Fuel Check": FuelCheckView()
//                case "Exercise Library": ExerciseLibraryView()
//                case "Program Builder": ProgramBuilderView()
//                case "Workout Generator": WorkoutGeneratorView()
//                case "Recovery Score": RecoveryScoreView()
//                case "Sleep Analysis": SleepAnalysisView()
//                case "Mobility Test": MobilityTestView()
//                case "Readiness Check": ReadinessCheckView()
//                case "Strain vs Recovery": StrainRecoveryView()
//                case "Activity Rings": ActivityRingsView()
//                case "Heart Zones": HeartZonesView()
//                case "Step Count": StepCountView()
//                case "Distance": DistanceView()
//                case "Calories Burned": CaloriesBurnedView()
//                case "Personal Records": PersonalRecordsView()
//                case "Pre-Workout Timing": PreWorkoutTimingView()
//                case "Post-Workout Window": PostWorkoutWindowView()
//                case "Performance Foods": PerformanceFoodsView()
//                case "Hydration Status": HydrationStatusView()
//                case "Macro Balance": MacroBalanceView()
//                case "Live Challenges": LiveChallengesView()
//                case "Friend Activity": FriendActivityView()
//                case "Achievements": AchievementsView()
//                case "Share Workouts": ShareWorkoutsView()
//                case "Leaderboards": LeaderboardsView()
//                default: HomeView()
//                }
//            }
//            .overlay(alignment: .bottomTrailing) {
//                FocusModeSelectorButton(wheelPickerItems: $choices, updateChoicesAndIcons: updateChoicesAndIcons)
//                    .padding()
//            }
//        }
//    }
//
//        
//    private func getFocusIcon(_ focus: AppFocus) -> String {
//        switch focus {
//        case .nutrition: return "leaf.fill"
//        case .fitness: return "figure.run"
//        case .mentalHealth: return "brain.head.profile"
//        }
//    }
//    
//    private func updateChoicesAndIcons(for focus: AppFocus) {
//        switch focus {
//        case .nutrition:
//            choices = ["Calories", "Protein", "Carbs", "Fats", "Fiber", "Vitamins",
//                       "Minerals", "Water", "Phytochemicals", "Antioxidants", "Electrolytes"]
//            icons = ["Calories": "flame", "Protein": "fork.knife", "Carbs": "carrot",
//                     "Fats": "drop.fill", "Fiber": "leaf", "Vitamins": "pills",
//                     "Minerals": "bolt", "Water": "drop.fill",
//                     "Phytochemicals": "leaf.arrow.triangle.circlepath",
//                     "Antioxidants": "shield", "Electrolytes": "battery.100"]
//        case .fitness:
//            choices = ["Coach", "Movement Analysis", "Fuel Check",
//                       "Readiness Check", "Strain vs Recovery"]
//            icons = ["Coach": "figure.mind.and.body",
//                     "Movement Analysis": "figure.walk.motion",
//                     "Fuel Check": "fuelpump.fill",
//                     "Readiness Check": "checkmark.seal.fill",
//                     "Strain vs Recovery": "arrow.left.arrow.right"]
//        case .mentalHealth:
//            choices = ["Meditation", "Breathing", "Sleep", "Stress Management", "Focus"]
//            icons = ["Meditation": "brain.head.profile",
//                     "Breathing": "lungs.fill",
//                     "Sleep": "moon.zzz.fill",
//                     "Stress Management": "heart.text.square.fill",
//                     "Focus": "scope"]
//        }
//    }
//    
//    private func isNutrientView(_ view: String) -> Bool {
//        ["Calories", "Protein", "Carbs", "Fats", "Water", "Fiber",
//         "Vitamins", "Minerals", "Phytochemicals", "Antioxidants", "Electrolytes"].contains(view)
//    }
//}
//    
//struct ViewGridItem: View {
//    let viewName: String
//    let isSelected: Bool
//    
//    var icon: String {
//        switch viewName {
//            // Nutrition
//        case "Home": return "house.fill"
//        case "Insights": return "chart.bar.fill"
//        case "Labels": return "text.viewfinder"
//        case "Log": return "square.and.pencil"
//        case "Calories": return "flame"
//        case "Protein": return "fork.knife"
//        case "Carbs": return "carrot"
//        case "Fats": return "drop.fill"
//        case "Fiber": return "leaf"
//        case "Vitamins": return "pills"
//        case "Minerals": return "bolt"
//        case "Water": return "drop.fill"
//        case "Phytochemicals": return "leaf.arrow.triangle.circlepath"
//        case "Antioxidants": return "shield"
//        case "Electrolytes": return "battery.100"
//            
//            // Fitness
//        case "Dashboard": return "gauge"
//        case "Today's Plan": return "calendar"
//        case "Workout History": return "clock.arrow.circlepath"
//        case "Training Calendar": return "calendar.badge.clock"
//        case "Coach": return "figure.mixed.cardio"
//        case "Movement Analysis": return "figure.walk.motion"
//        case "Exercise Library": return "books.vertical"
//        case "Program Builder": return "building.2"
//        case "Workout Generator": return "gear"
//        case "Recovery Score": return "heart.text.square"
//        case "Sleep Analysis": return "bed.double"
//        case "Mobility Test": return "figure.walk"
//        case "Readiness Check": return "checkmark.circle"
//        case "Strain vs Recovery": return "chart.xyaxis.line"
//        case "Activity Rings": return "circle.circle"
//        case "Heart Zones": return "heart.circle"
//        case "Step Count": return "figure.walk"
//        case "Distance": return "location.north"
//        case "Calories Burned": return "flame"
//        case "Personal Records": return "trophy"
//        case "Pre-Workout Timing": return "timer"
//        case "Post-Workout Window": return "clock.badge"
//        case "Performance Foods": return "leaf"
//        case "Hydration Status": return "drop"
//        case "Macro Balance": return "scale.3d"
//            
//            // Community
//        case "Live Challenges": return "flame"
//        case "Friend Activity": return "person.2"
//        case "Achievements": return "star"
//        case "Share Workouts": return "square.and.arrow.up"
//        case "Leaderboards": return "list.number"
//            
//        default: return "questionmark"
//        }
//    }
//    
//    var body: some View {
//        VStack {
//            Image(systemName: icon)
//                .resizable()
//                .scaledToFit()
//                .frame(width: 60, height: 60)
//                .foregroundColor(isSelected ? .blue : .white)
//                .scaleEffect(isSelected ? 1.2 : 1.0)
//                .animation(.easeInOut(duration: 0.1), value: isSelected)
//            
//            Text(viewName)
//                .foregroundColor(.white)
//                .multilineTextAlignment(.center)
//                .lineLimit(2)
//                .minimumScaleFactor(0.5)
//        }
//    }
//}
//
//struct BlankIconView: View {
//    var body: some View {
//        VStack {
//            Image(systemName: "circle.fill")
//                .resizable()
//                .scaledToFit()
//                .frame(width: 60, height: 60)
//                .foregroundColor(.clear)
//            Text("")
//        }
//    }
//}
//
//extension Double {
//    var radiansToDegrees: Double {
//        return self * 180 / .pi
//    }
//}
//
//private func calculateAngle(from location: CGPoint, in geometry: GeometryProxy) -> Double {
//    let dx = location.x - geometry.size.width/2
//    let dy = location.y - geometry.size.height/2
//    let angle = atan2(dy, dx)
//    return (angle + .pi * 2).truncatingRemainder(dividingBy: .pi * 2)
//}
//
//struct WheelPicker: View {
//    let choices: [String]
//    @Binding var choice: String
//    @State private var rotation: Double = 0
//    @State private var finalAngle: Double = 0
//    @State private var initialTouchAngle: Double? = nil
//    let numberOfTicks = 100
//    let onChange: (String) -> Void
//    @State private var buttonScale: CGFloat = 1.0
//    @State private var showRadialMenu = false
//    @State private var showHealthInsights = false
//    @State private var showNutritionScanner = false
//    @State private var showLogView = false
//    @State private var showHomeView = false
//    @State private var showDetails = false
//    @GestureState private var dragLocation: CGPoint?
//    @EnvironmentObject var navigationState: NavigationState
//    @Binding var selectedNutrient: String
//
//    private var reversedChoices: [String] {
//        choices.reversed()
//    }
//
//    private let radialMenuIcons = [
//        "heart.text.square",
//        "text.viewfinder",
//        "square.and.pencil",
//        "house"
//    ]
//    
//    private func calculateDistance(_ location: CGPoint, in geometry: GeometryProxy) -> CGFloat {
//        let dx = location.x - geometry.size.width/2
//        let dy = location.y - geometry.size.height/2
//        return sqrt(pow(dx, 2) + pow(dy, 2))
//    }
//
//    private func MenuItem(index: Int, geometry: GeometryProxy, menuRadius: CGFloat) -> some View {
//        let angle = Double(index) * .pi / 2
//        let xOffset = cos(angle) * menuRadius
//        let yOffset = sin(angle) * menuRadius
//        
//        return Image(systemName: radialMenuIcons[index])
//            .font(.title)
//            .foregroundColor(.white)
//            .frame(width: 20, height: 20)
//            .offset(x: xOffset, y: yOffset)
//            .transition(.scale)
//    }
//
//    private func calculateAngleFromLocation(_ location: CGPoint, in geometry: GeometryProxy, offsetX: CGFloat, offsetY: CGFloat) -> Double {
//        let dx = location.x - (geometry.size.width/2 + offsetX)
//        let dy = location.y - (geometry.size.height/2 + offsetY)
//        return (atan2(dy, dx) + .pi * 2).truncatingRemainder(dividingBy: .pi * 2)
//    }
//
//    private func calculateDistanceFromLocation(_ location: CGPoint, in geometry: GeometryProxy, offsetX: CGFloat, offsetY: CGFloat) -> CGFloat {
//        let dx = location.x - (geometry.size.width/2 + offsetX)
//        let dy = location.y - (geometry.size.height/2 + offsetY)
//        return sqrt(pow(dx, 2) + pow(dy, 2))
//    }
//    
//    private func MenuIcon(index: Int, geometry: GeometryProxy, menuRadius: CGFloat) -> some View {
//        let angle = Double(index) * .pi / 2
//        let xOffset = cos(angle) * menuRadius  // No centerOffset for visual position
//        let yOffset = sin(angle) * menuRadius
//        
//        let centerOffsetX: CGFloat = 20
//        let centerOffsetY: CGFloat = 30
//        
//        let distance = dragLocation.map { calculateDistanceFromLocation($0, in: geometry, offsetX: centerOffsetX, offsetY: centerOffsetY) } ?? 0
//        let currentAngle = dragLocation.map { calculateAngleFromLocation($0, in: geometry, offsetX: centerOffsetX, offsetY: centerOffsetY) } ?? 0
//        
//        let isWithinCenter = distance < 20
//        let highlightedAction = getHighlightedAction(angle: currentAngle, distance: distance)
//        let isHighlighted = !isWithinCenter && highlightedAction == index
//        
//        return Image(systemName: radialMenuIcons[index])
//            .font(.system(size: 32))
//            .foregroundColor(.white)
//            .frame(width: 80, height: 80)
////            .opacity(isWithinCenter ? 0.3 : (distance > 100 ? 1.0 : 0.5))
//            .scaleEffect(isWithinCenter ? 1.0 : (isHighlighted ? 1.4 : 1.2))
//            .offset(x: xOffset, y: yOffset)
//            .transition(.scale)
//    }
//
//    private func DebugInfo(geometry: GeometryProxy, centerOffsetX: CGFloat, centerOffsetY: CGFloat) -> some View {
//        let distance = dragLocation.map { location in
//            let dx = location.x - (geometry.size.width/2 + centerOffsetX)
//            let dy = location.y - (geometry.size.height/2 + centerOffsetY)
//            return sqrt(pow(dx, 2) + pow(dy, 2))
//        } ?? 0
//        
//        let currentAngle = dragLocation.map { calculateAngleFromLocation($0, in: geometry, offsetX: centerOffsetX, offsetY: centerOffsetY) } ?? 0
//        
//        let highlightedAction = getHighlightedAction(angle: currentAngle, distance: distance)
//        let isWithinCenter = distance < 20
//        
//        return VStack {
//            Text("Distance: \(Int(distance))")
//                .foregroundColor(.white)
//            Text("IsWithinCenter: \(isWithinCenter.description)")
//                .foregroundColor(.white)
//            Text("Angle: \(currentAngle)")
//                .foregroundColor(.white)
//            Text("HighlightedAction: \(highlightedAction)")
//                .foregroundColor(.white)
//        }
//        .offset(y: 100)
//    }
//
//    func RadialMenuItems(distance: CGFloat, highlightedAction: Int) -> some View {
//        GeometryReader { geometry in
//            let menuRadius: CGFloat = 100
//            ZStack {
//                ForEach(0..<4) { index in
//                    let angle = Double(index) * .pi / 2
//                    let xOffset = cos(angle) * menuRadius
//                    let yOffset = sin(angle) * menuRadius
//                    let isWithinCenter = distance < 20
//                    let isHighlighted = highlightedAction == index
//                    
//                    Image(systemName: radialMenuIcons[index])
//                        .font(.title)
//                        .foregroundColor(.white)
//                        .frame(width: 20, height: 20)
//                        .opacity(isWithinCenter ? 0.3 : (isHighlighted ? 1.0 : 0.5))
//                        .scaleEffect(isWithinCenter ? 1.0 : (isHighlighted ? 1.6 : 1.2))
//                        .offset(x: xOffset, y: yOffset)
//                        .transition(.scale)
//                        .onChange(of: isHighlighted) { oldValue, newValue in
//                            if newValue {
//                                let generator = UIImpactFeedbackGenerator(style: .heavy)
//                                generator.impactOccurred()
//                            }
//                        }
//                }
//            }
//            .position(x: geometry.size.width/2, y: geometry.size.height/2)
//        }
//    }
//
//    private func getSelectedIndex(for angle: Double) -> Int {
//        switch angle {
//            case (.pi * 1.75)...(2 * .pi), 0...(.pi * 0.25): return 0  // Up - Health Insights
//            case (.pi * 0.25)...(.pi * 0.75): return 1      // Right - Scanner
//            case (.pi * 0.75)...(.pi * 1.25): return 2      // Down - Log
//            case (.pi * 1.25)...(.pi * 1.75): return 3      // Left - Home
//            default: return -1
//        }
//    }
//
//    private func getHighlightedAction(angle: Double, distance: CGFloat) -> Int {
//        // For highlighting, require being further out (60-70 pixels)
//        if distance < 100 {
//            return -1
//        }
//        
//        // Angle-based selection remains the same
//        if angle >= .pi * 0.25 && angle <= .pi * 0.75 { return 1 }  // Right
//        if angle >= .pi * 0.75 && angle <= .pi * 1.25 { return 2 }  // Down
//        if angle >= .pi * 1.25 && angle <= .pi * 1.75 { return 3 }  // Left
//        if angle >= .pi * 1.75 || angle <= .pi * 0.25 { return 0 }  // Up
//        return -1
//    }
//    
//    var body: some View {
//        ZStack {
//            GeometryReader { geometry in
//                let wheelSize = geometry.size.width
//                ZStack {
//                    Circle()
//                        .stroke(lineWidth: 1)
//                        .foregroundColor(.gray)
//                    
//                    ForEach(0..<numberOfTicks, id: \.self) { index in
//                        let tickHeight = index % 5 == 0 ? 20.0 : 10.0
//                        let yOffset = -wheelSize / 2 + 15 + (index % 5 == 0 ? -5 : 0)
//                        let rotationAngle = 360.0 / Double(numberOfTicks) * Double(index)
//                        
//                        Rectangle()
//                            .frame(width: 2, height: tickHeight)
//                            .offset(y: yOffset)
//                            .rotationEffect(Angle(degrees: rotationAngle))
//                    }
//                }
//                .contentShape(Circle())
//                .clipped()
//                .frame(width: wheelSize, height: wheelSize)
//                .rotationEffect(Angle(degrees: rotation))
//                .gesture(
//                    DragGesture()
//                        .onChanged { value in
//                            let centerX = wheelSize / 2
//                            let centerY = wheelSize / 2
//                            let vector = CGVector(
//                                dx: value.location.x - centerX,
//                                dy: value.location.y - centerY
//                            )
//                            let angle = Double(atan2(vector.dy, vector.dx)).radiansToDegrees
//                            
//                            if initialTouchAngle == nil {
//                                initialTouchAngle = angle
//                            }
//                            rotation = angle - (initialTouchAngle ?? 0)
//                            self.wheelSelectionUpdate()
//                        }
//                        .onEnded { _ in
//                            finalAngle += rotation
//                            rotation = 0
//                            initialTouchAngle = nil
//                        }
//                )
//            }
//            .aspectRatio(1, contentMode: .fit)
//            .padding(.horizontal)
//            
//            GeometryReader { geometry in
//                ZStack {
//                    let distance = dragLocation.map { calculateDistance($0, in: geometry) } ?? 0
//                    let currentAngle = dragLocation.map { calculateAngle(from: $0, in: geometry) } ?? 0
//                    let highlightedAction = getHighlightedAction(angle: currentAngle, distance: distance)
//                    
//                    if showRadialMenu {
//                        RadialMenuItems(distance: distance, highlightedAction: highlightedAction)
//                    }
//                    // Button for center control
//                    Button(action: {}) {
//                        let distance = dragLocation.map { calculateDistance($0, in: geometry) } ?? 0
//                        
//                        Image(systemName: distance < 50 ? "arrow.right.circle.fill" :
//                                (distance < 100 ? "xmark" : "info.circle.fill"))
//                        .resizable()
//                        .frame(width: 50, height: 50)
//                        .padding(showRadialMenu ? 10 : 0)
//                        .foregroundColor(.white)
//                        .padding(10)
//                        .clipShape(Circle())
//                        .shadow(radius: 10)
//                    }
//                    .buttonStyle(BorderlessButtonStyle())
//                }
//                .buttonStyle(BorderlessButtonStyle())
//                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
//                .simultaneousGesture(
//                    DragGesture(minimumDistance: 0)
//                        .updating($dragLocation) { value, state, _ in
//                            state = value.location
//                        }
//                        .onChanged { _ in
//                            withAnimation(.spring()) {
//                                showRadialMenu = true
//                            }
////                            let generator = UIImpactFeedbackGenerator(style: .soft)
////                            generator.impactOccurred()
//                        }
//                        .onEnded { value in
//                            let buttonCenter = CGPoint(
//                                x: geometry.frame(in: .local).midX,
//                                y: geometry.frame(in: .local).midY
//                            )
//                            self.handleMenuSelection(at: value.location, center: buttonCenter)
//                            withAnimation(.spring()) {
//                                showRadialMenu = false
//                            }
//                        }
//                )
//                .gesture(
//                    LongPressGesture(minimumDuration: 0.3)
//                        .onEnded { _ in
//                            withAnimation(.spring()) {
//                                showRadialMenu = true
//                            }
//                            let generator = UIImpactFeedbackGenerator(style: .heavy)
//                            generator.impactOccurred()
//                        }
//                )
//                .onTapGesture {
//                    if choice == selectedNutrient {
//                        showDetails = true
//                        let generator = UIImpactFeedbackGenerator(style: .rigid)
//                        generator.impactOccurred()
//                    } else {
//                        selectedNutrient = choice
//                    }
//                }
//            }
//        }
//    }
//
//    func wheelSelectionUpdate() {
//        let currentAngle = (finalAngle + rotation).truncatingRemainder(dividingBy: 360)
//        let normalizedAngle = (360 - currentAngle + 360 / Double(reversedChoices.count) / 2)
//            .truncatingRemainder(dividingBy: 360)
//        let anglePerChoice = 360 / Double(reversedChoices.count)
//        let index = Int((normalizedAngle / anglePerChoice).truncatingRemainder(dividingBy: Double(reversedChoices.count)))
//        
//        let newChoice = reversedChoices[index]
//        if newChoice != choice {
//            choice = newChoice
//            onChange(newChoice)
//            let generator = UIImpactFeedbackGenerator(style: .heavy)
//            generator.impactOccurred()
//        }
//    }
//
//    func handleMenuSelection(at location: CGPoint, center: CGPoint) {
//        let dx = location.x - center.x
//        let dy = location.y - center.y
//        let angle = atan2(dy, dx)
//        let normalizedAngle = (angle + .pi * 2).truncatingRemainder(dividingBy: .pi * 2)
//        
//        let distance = sqrt(pow(dx, 2) + pow(dy, 2))
//        if distance < 100 && distance > 50{
//            return
//        } else if distance < 50 {
//            print(navigationState.selectedView)
//            navigationState.selectedView = choice
//            print(navigationState.selectedView)
//            let generator = UIImpactFeedbackGenerator(style: .rigid)
//            generator.impactOccurred()
//        }
//        
//        let highlightedAction = getHighlightedAction(angle: normalizedAngle, distance: distance)
//        switch highlightedAction {
//            case 0: showHealthInsights = true
//            case 1: showNutritionScanner = true
//            case 2: showLogView = true
//            case 3: showHomeView = true
//            default: break
//        }
//    }
//}
//
//struct FocusModeSelectorButton: View {
//    @EnvironmentObject var navigationState: NavigationState
//    @State private var isExpanded = false
//    @State private var rotation: Double = 0
//    @Binding var wheelPickerItems: [String]
//    let updateChoicesAndIcons: (AppFocus) -> Void
//
//    var body: some View {
//        ZStack {
//            ForEach(AppFocus.allCases.reversed(), id: \.self) { focus in
//                FocusModeOption(focus: focus, onFocusChange: { _ in
//                    updateChoicesAndIcons(focus)
//                })
//                .offset(y: isExpanded ? -CGFloat(AppFocus.allCases.firstIndex(of: focus)! + 1) * 70 : 0)
//                .opacity(isExpanded ? 1 : 0)
//                .scaleEffect(isExpanded ? 1 : 0.5)
//            }
//            
//            // Main button stays fixed at bottom
//            Button {
//                let generator = UIImpactFeedbackGenerator(style: .light)
//                generator.impactOccurred()
//                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
//                    isExpanded.toggle()
//                    rotation = isExpanded ? 45 : 0
//                }
//            } label: {
//                Image(systemName: "plus")
//                    .font(.system(size: 30, weight: .semibold))
//                    .foregroundColor(.white)
//                    .frame(width: 70, height: 70)
//                    .background(Color.blue)
//                    .clipShape(Circle())
//                    .rotationEffect(.degrees(rotation))
//                    .shadow(radius: 5)
//            }
//        }
//    }
//}
//
//struct FocusModeOption: View {
//    @EnvironmentObject var navigationState: NavigationState
//    @State private var wheelPickerItems: [String] = []
//    @State private var showHomeView = false
//    @State private var showHealthInsights = false
//    @State private var showNutritionScanner = false
//    @State private var showLogView = false
//    @State private var showNutrientDetail = false
//    @State private var selectedNutrient = ""
//    let focus: AppFocus
//    let onFocusChange: ([String]) -> Void
//    
//    var icon: String {
//        switch focus {
//        case .nutrition: return "leaf.fill"
//        case .fitness: return "figure.run"
//        case .mentalHealth: return "brain.head.profile"
//        }
//    }
//    
//    var body: some View {
//        Button {
//            let generator = UIImpactFeedbackGenerator(style: .medium)
//            generator.impactOccurred()
//            
//            withAnimation(.spring()) {
//                navigationState.appFocus = focus
//                onFocusChange([])  // This calls the passed function
//            }
//        } label: {
//            Image(systemName: icon)
//                .font(.title2)
//                .foregroundColor(.white)
//                .frame(width: 50, height: 50)
//                .background(focus == navigationState.appFocus ? Color.blue : Color.blue.opacity(0.8))
//                .clipShape(Circle())
//        }
//        .sheet(isPresented: $showHomeView) { HomeView() }
//        .sheet(isPresented: $showHealthInsights) { HealthInsightsView() }
//        .sheet(isPresented: $showNutritionScanner) { NutritionScannerView() }
//        .sheet(isPresented: $showLogView) { LogView() }
//        .sheet(isPresented: $showNutrientDetail) {
//            NutrientDetailView(nutrientName: selectedNutrient)
//        }
//    }
//    
//    private func updateWheelPickerItems(for focus: AppFocus) {
//        switch focus {
//        case .nutrition:
//            wheelPickerItems = ["Home", "Insights", "Labels", "Log",
//                              "Calories", "Protein", "Carbs", "Fats", "Fiber", "Vitamins",
//                              "Minerals", "Water", "Phytochemicals", "Antioxidants", "Electrolytes"]
//        case .fitness:
//            wheelPickerItems = ["Coach", "Movement Analysis", "Fuel Check",
//                              "Readiness Check", "Strain vs Recovery", "Dashboard",
//                              "Today's Plan", "Workout History", "Training Calendar"]
//        case .mentalHealth:
//            wheelPickerItems = ["Pre-Workout Timing", "Post-Workout Window",
//                              "Performance Foods", "Hydration Status", "Macro Balance"]
//        }
//    }
//    
//    func getItemsForFocus(_ focus: AppFocus) -> [String] {
//        switch focus {
//        case .nutrition:
//            return ["Home", "Insights", "Labels", "Log",
//                   "Calories", "Protein", "Carbs", "Fats", "Fiber", "Vitamins",
//                   "Minerals", "Water", "Phytochemicals", "Antioxidants", "Electrolytes"]
//        case .fitness:
//            return ["Coach", "Movement Analysis", "Fuel Check",
//                   "Readiness Check", "Strain vs Recovery", "Dashboard",
//                   "Today's Plan", "Workout History", "Training Calendar"]
//        case .mentalHealth:
//            return ["Pre-Workout Timing", "Post-Workout Window",
//                   "Performance Foods", "Hydration Status", "Macro Balance"]
//        }
//    }
//    
//    private func handleWheelSelection(for item: String) {
//        switch navigationState.appFocus {
//        case .nutrition:
//            switch item {
//            case "Home": showHomeView = true
//            case "Insights": showHealthInsights = true
//            case "Labels": showNutritionScanner = true
//            case "Log": showLogView = true
//            case "Calories", "Carbs", "Protein", "Fats", "Water", "Fiber",
//                 "Vitamins", "Minerals", "Phytochemicals", "Antioxidants", "Electrolytes":
//                selectedNutrient = item
//                showNutrientDetail = true
//            default: break
//            }
//            
//        case .fitness:
//            switch item {
//            case "Coach": showView("Coach")
//            case "Movement Analysis": showView("Movement Analysis")
//            case "Fuel Check": showView("Fuel Check")
//            case "Readiness Check": showView("Readiness Check")
//            case "Strain vs Recovery": showView("Strain vs Recovery")
//            default:
//                showComingSoon(feature: item)
//            }
//            
//        case .mentalHealth:
//            showComingSoon(feature: item)
//        }
//    }
//    
//    private func showView(_ viewName: String) {
//        navigationState.selectedView = viewName
//    }
//
//    private func showComingSoon(feature: String) {
//        navigationState.selectedView = feature
//    }
//}
