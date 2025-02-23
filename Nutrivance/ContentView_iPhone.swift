import SwiftUI
import SwiftData

struct ContentView_iPhone: View {
    @State private var selectedNutrient: String = "Calories"
    @State private var showNutrientDetail: Bool = false
    @State private var showCamera = false;
    @State private var showNutritionScanner = false
    @State private var isLongPressing = false
    @State private var selectedNutrientForDetail: String?
    @State private var showingNutrientDetail = false
    @State private var wheelPickerItems: [String] = []
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    @State private var choices: [String] = [
            "Calories", "Protein", "Carbs", "Fats", "Fiber", "Vitamins",
            "Minerals", "Water", "Phytochemicals", "Antioxidants", "Electrolytes"
        ]
        
        @State private var icons: [String: String] = [
            "Calories": "flame", "Protein": "fork.knife", "Carbs": "carrot",
            "Fats": "drop.fill", "Fiber": "leaf", "Vitamins": "pills",
            "Minerals": "bolt", "Water": "drop.fill",
            "Phytochemicals": "leaf.arrow.triangle.circlepath",
            "Antioxidants": "shield", "Electrolytes": "battery.100"
        ]
        
        func updateChoicesAndIcons(for focus: AppFocus) {
            switch focus {
            case .nutrition:
                choices = ["Calories", "Protein", "Carbs", "Fats", "Fiber", "Vitamins",
                          "Minerals", "Water", "Phytochemicals", "Antioxidants", "Electrolytes"]
                icons = ["Calories": "flame", "Protein": "fork.knife", "Carbs": "carrot",
                        "Fats": "drop.fill", "Fiber": "leaf", "Vitamins": "pills",
                        "Minerals": "bolt", "Water": "drop.fill",
                        "Phytochemicals": "leaf.arrow.triangle.circlepath",
                        "Antioxidants": "shield", "Electrolytes": "battery.100"]
                
            case .fitness:
                choices = ["Form Coach", "Movement Analysis", "Fuel Check",
                          "Readiness Check", "Strain vs Recovery"]
                icons = ["Form Coach": "figure.mind.and.body",
                        "Movement Analysis": "figure.walk.motion",
                        "Fuel Check": "fuelpump.fill",
                        "Readiness Check": "checkmark.seal.fill",
                        "Strain vs Recovery": "arrow.left.arrow.right"]
                
            case .mentalHealth:
                choices = ["Meditation", "Breathing", "Sleep", "Stress Management", "Focus"]
                icons = ["Meditation": "brain.head.profile",
                        "Breathing": "lungs.fill",
                        "Sleep": "moon.zzz.fill",
                        "Stress Management": "heart.text.square.fill",
                        "Focus": "scope"]
            }
        }

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color.black, Color.blue, Color(red: 0.0, green: 0.5, blue: 0.0)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack {
                ScrollViewReader { scrollViewProxy in
                    ScrollView {
                        if navigationState.appFocus == .nutrition {
                            BlankIconView()
                            BlankIconView()
                        }

                        let columns = Array(repeating: GridItem(.flexible()), count: horizontalSizeClass == .compact ? 2 : 5)

                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(choices, id: \.self) { nutrient in
                                VStack {
                                    Image(systemName: icons[nutrient] ?? "leaf.fill")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 60, height: 60)
                                        .foregroundColor(selectedNutrient == nutrient ? .blue : .white)
                                        .scaleEffect(selectedNutrient == nutrient ? 1.2 : 1.0)
                                        .animation(.easeInOut(duration: 0.1), value: selectedNutrient)

                                    Text(nutrient)
                                        .foregroundColor(.white)
                                }
                                .id(nutrient)
                                .onTapGesture {
                                    withAnimation {
                                        if selectedNutrient == nutrient {
                                            showingNutrientDetail = true
                                            let generator = UIImpactFeedbackGenerator(style: .heavy)
                                            generator.prepare()
                                            generator.impactOccurred()
                                        } else {
                                            selectedNutrient = nutrient
                                            scrollViewProxy.scrollTo(nutrient, anchor: .center)
                                            let generator = UIImpactFeedbackGenerator(style: .heavy)
                                            generator.prepare()
                                            generator.impactOccurred()
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                        .frame(maxHeight: UIScreen.main.bounds.height * 0.5)
                        if navigationState.appFocus == .nutrition {
                            BlankIconView()
                            BlankIconView()
                        }
                    }
                    .frame(maxHeight: UIScreen.main.bounds.height * 0.5)
                    .padding(.bottom, 10)
                    .onChange(of: selectedNutrient) { oldValue, newValue in
                        withAnimation {
                            scrollViewProxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                    .sheet(isPresented: $showingNutrientDetail) {
                        NutrientDetailView(nutrientName: selectedNutrient)
                    }
                }
                    WheelPicker(choices: choices, choice: $selectedNutrient) { newChoice in
                        selectedNutrient = newChoice
                    }
                    .padding(.bottom)
                }
                .padding(.top, 10)
            
            FocusModeSelectorButton(wheelPickerItems: $wheelPickerItems, updateChoicesAndIcons: updateChoicesAndIcons)
                .position(x: UIScreen.main.bounds.width - 50, y: UIScreen.main.bounds.height - 100)

//            Button(action: {}) {
//                Image(systemName: "text.viewfinder")
//                    .resizable()
//                    .scaledToFit()
//                    .frame(width: 30, height: 30)
//                    .foregroundColor(.white)
//                    .padding(10)
//                    .background(Color.blue.opacity(0.7))
//                    .clipShape(Circle())
//                    .shadow(radius: 10)
//                    .scaleEffect(isLongPressing ? 1.5 : 1.0)  // Larger scale effect
//                    .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isLongPressing)
//            }
//            .simultaneousGesture(
//                LongPressGesture(minimumDuration: 0.5)
//                    .onChanged { _ in
//                        isLongPressing = true
//                        let generator = UINotificationFeedbackGenerator()
//                        generator.notificationOccurred(.success)
//                    }
//                    .onEnded { _ in
//                        isLongPressing = false
//                        showNutritionScanner = true
//                        let generator = UIImpactFeedbackGenerator(style: .heavy)
//                        generator.impactOccurred(intensity: 1.0)
//                    }
//            )
//            .padding()
//            .position(x: UIScreen.main.bounds.width - 50, y: UIScreen.main.bounds.height - 100)
//
//            .sheet(isPresented: $showNutritionScanner) {
//                NutritionScannerView()
//            }


//            }
        }
    }
}

struct BlankIconView: View {
    var body: some View {
        VStack {
            Image(systemName: "circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .foregroundColor(.clear)
            Text("")
        }
    }
}

extension Double {
    var radiansToDegrees: Double {
        return self * 180 / .pi
    }
}

private func calculateAngle(from location: CGPoint, in geometry: GeometryProxy) -> Double {
    let dx = location.x - geometry.size.width/2
    let dy = location.y - geometry.size.height/2
    let angle = atan2(dy, dx)
    return (angle + .pi * 2).truncatingRemainder(dividingBy: .pi * 2)
}

struct WheelPicker: View {
    let choices: [String]
    @Binding var choice: String
    @State private var rotation: Double = 0
    @State private var finalAngle: Double = 0
    @State private var initialTouchAngle: Double? = nil
    let numberOfTicks = 100
    let onChange: (String) -> Void
    @State private var buttonScale: CGFloat = 1.0
    @State private var showRadialMenu = false
    @State private var showHealthInsights = false
    @State private var showNutritionScanner = false
    @State private var showLogView = false
    @State private var showHomeView = false
    @State private var showDetails = false
    @GestureState private var dragLocation: CGPoint?

    private var reversedChoices: [String] {
        choices.reversed()
    }

    private let radialMenuIcons = [
        "heart.text.square",
        "text.viewfinder",
        "square.and.pencil",
        "house"
    ]
    
    private func calculateDistance(_ location: CGPoint, in geometry: GeometryProxy) -> CGFloat {
        let dx = location.x - geometry.size.width/2
        let dy = location.y - geometry.size.height/2
        return sqrt(pow(dx, 2) + pow(dy, 2))
    }

    private func MenuItem(index: Int, geometry: GeometryProxy, menuRadius: CGFloat) -> some View {
        let angle = Double(index) * .pi / 2
        let xOffset = cos(angle) * menuRadius
        let yOffset = sin(angle) * menuRadius
        
        let isWithinCenterRange = dragLocation.map { location in
            calculateDistance(location, in: geometry) < 25
        } ?? false
        
        let currentAngle = dragLocation.map { calculateAngle(from: $0, in: geometry) } ?? 0
        
        let isSelected = !isWithinCenterRange && getSelectedIndex(for: currentAngle) == index
        
        return Image(systemName: radialMenuIcons[index])
            .font(.title)
            .foregroundColor(.white)
            .frame(width: 20, height: 20)
            .offset(x: xOffset, y: yOffset)
            .transition(.scale)
    }

    private func calculateAngleFromLocation(_ location: CGPoint, in geometry: GeometryProxy, offsetX: CGFloat, offsetY: CGFloat) -> Double {
        let dx = location.x - (geometry.size.width/2 + offsetX)
        let dy = location.y - (geometry.size.height/2 + offsetY)
        return (atan2(dy, dx) + .pi * 2).truncatingRemainder(dividingBy: .pi * 2)
    }

    private func calculateDistanceFromLocation(_ location: CGPoint, in geometry: GeometryProxy, offsetX: CGFloat, offsetY: CGFloat) -> CGFloat {
        let dx = location.x - (geometry.size.width/2 + offsetX)
        let dy = location.y - (geometry.size.height/2 + offsetY)
        return sqrt(pow(dx, 2) + pow(dy, 2))
    }
    
    private func MenuIcon(index: Int, geometry: GeometryProxy, menuRadius: CGFloat) -> some View {
        let angle = Double(index) * .pi / 2
        let xOffset = cos(angle) * menuRadius  // No centerOffset for visual position
        let yOffset = sin(angle) * menuRadius
        
        let centerOffsetX: CGFloat = 20
        let centerOffsetY: CGFloat = 30
        
        let distance = dragLocation.map { calculateDistanceFromLocation($0, in: geometry, offsetX: centerOffsetX, offsetY: centerOffsetY) } ?? 0
        let currentAngle = dragLocation.map { calculateAngleFromLocation($0, in: geometry, offsetX: centerOffsetX, offsetY: centerOffsetY) } ?? 0
        
        let isWithinCenter = distance < 20
        let highlightedAction = getHighlightedAction(angle: currentAngle, distance: distance)
        let isHighlighted = !isWithinCenter && highlightedAction == index
        
        return Image(systemName: radialMenuIcons[index])
            .font(.system(size: 32))
            .foregroundColor(.white)
            .frame(width: 80, height: 80)
//            .opacity(isWithinCenter ? 0.3 : (distance > 100 ? 1.0 : 0.5))
            .scaleEffect(isWithinCenter ? 1.0 : (isHighlighted ? 1.4 : 1.2))
            .offset(x: xOffset, y: yOffset)
            .transition(.scale)
    }

    private func DebugInfo(geometry: GeometryProxy, centerOffsetX: CGFloat, centerOffsetY: CGFloat) -> some View {
        let distance = dragLocation.map { location in
            let dx = location.x - (geometry.size.width/2 + centerOffsetX)
            let dy = location.y - (geometry.size.height/2 + centerOffsetY)
            return sqrt(pow(dx, 2) + pow(dy, 2))
        } ?? 0
        
        let currentAngle = dragLocation.map { calculateAngleFromLocation($0, in: geometry, offsetX: centerOffsetX, offsetY: centerOffsetY) } ?? 0
        
        let highlightedAction = getHighlightedAction(angle: currentAngle, distance: distance)
        let isWithinCenter = distance < 20
        
        return VStack {
            Text("Distance: \(Int(distance))")
                .foregroundColor(.white)
            Text("IsWithinCenter: \(isWithinCenter.description)")
                .foregroundColor(.white)
            Text("Angle: \(currentAngle)")
                .foregroundColor(.white)
            Text("HighlightedAction: \(highlightedAction)")
                .foregroundColor(.white)
        }
        .offset(y: 100)
    }

    func RadialMenuItems(distance: CGFloat, highlightedAction: Int) -> some View {
        GeometryReader { geometry in
            let menuRadius: CGFloat = 100
            ZStack {
                ForEach(0..<4) { index in
                    let angle = Double(index) * .pi / 2
                    let xOffset = cos(angle) * menuRadius
                    let yOffset = sin(angle) * menuRadius
                    let isWithinCenter = distance < 20
                    let isHighlighted = highlightedAction == index
                    
                    Image(systemName: radialMenuIcons[index])
                        .font(.title)
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .opacity(isWithinCenter ? 0.3 : (isHighlighted ? 1.0 : 0.5))
                        .scaleEffect(isWithinCenter ? 1.0 : (isHighlighted ? 1.6 : 1.2))
                        .offset(x: xOffset, y: yOffset)
                        .transition(.scale)
                        .onChange(of: isHighlighted) { newValue in
                            if newValue {
                                let generator = UIImpactFeedbackGenerator(style: .heavy)
                                generator.impactOccurred()
                            }
                        }
                }
            }
            .position(x: geometry.size.width/2, y: geometry.size.height/2)
        }
    }

    private func getSelectedIndex(for angle: Double) -> Int {
        switch angle {
            case (.pi * 1.75)...(2 * .pi), 0...(.pi * 0.25): return 0  // Up - Health Insights
            case (.pi * 0.25)...(.pi * 0.75): return 1      // Right - Scanner
            case (.pi * 0.75)...(.pi * 1.25): return 2      // Down - Log
            case (.pi * 1.25)...(.pi * 1.75): return 3      // Left - Home
            default: return -1
        }
    }

    private func getHighlightedAction(angle: Double, distance: CGFloat) -> Int {
        // For highlighting, require being further out (60-70 pixels)
        if distance < 100 {
            return -1
        }
        
        // Angle-based selection remains the same
        if angle >= .pi * 0.25 && angle <= .pi * 0.75 { return 1 }  // Right
        if angle >= .pi * 0.75 && angle <= .pi * 1.25 { return 2 }  // Down
        if angle >= .pi * 1.25 && angle <= .pi * 1.75 { return 3 }  // Left
        if angle >= .pi * 1.75 || angle <= .pi * 0.25 { return 0 }  // Up
        return -1
    }
    
    var body: some View {
        ZStack {
            GeometryReader { geometry in
                let wheelSize = geometry.size.width
                ZStack {
                    Circle()
                        .stroke(lineWidth: 1)
                        .foregroundColor(.gray)

                    ForEach(0..<numberOfTicks, id: \.self) { index in
                        let tickHeight = index % 5 == 0 ? 20.0 : 10.0
                        let yOffset = -wheelSize / 2 + 15 + (index % 5 == 0 ? -5 : 0)
                        let rotationAngle = 360.0 / Double(numberOfTicks) * Double(index)
                        
                        Rectangle()
                            .frame(width: 2, height: tickHeight)
                            .offset(y: yOffset)
                            .rotationEffect(Angle(degrees: rotationAngle))
                    }
                }
                .contentShape(Circle())
                .clipped()
                .frame(width: wheelSize, height: wheelSize)
                .rotationEffect(Angle(degrees: rotation))
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let centerX = wheelSize / 2
                            let centerY = wheelSize / 2
                            let vector = CGVector(
                                dx: value.location.x - centerX,
                                dy: value.location.y - centerY
                            )
                            let angle = Double(atan2(vector.dy, vector.dx)).radiansToDegrees
                            
                            if initialTouchAngle == nil {
                                initialTouchAngle = angle
                            }
                            rotation = angle - (initialTouchAngle ?? 0)
                            self.wheelSelectionUpdate()
                        }
                        .onEnded { _ in
                            finalAngle += rotation
                            rotation = 0
                            initialTouchAngle = nil
                        }
                )
            }
            .aspectRatio(1, contentMode: .fit)
            .padding(.horizontal)

            GeometryReader { geometry in
                ZStack {
                    let distance = dragLocation.map { calculateDistance($0, in: geometry) } ?? 0
                    let currentAngle = dragLocation.map { calculateAngle(from: $0, in: geometry) } ?? 0
                    let highlightedAction = getHighlightedAction(angle: currentAngle, distance: distance)

                    if showRadialMenu {
                        RadialMenuItems(distance: distance, highlightedAction: highlightedAction)
                    }
                    // Button for center control
                    Button(action: {}) {
                        let distance = dragLocation.map { calculateDistance($0, in: geometry) } ?? 0
                        
                        Image(systemName: distance < 50 ? "arrow.right.circle.fill" :
                                         (distance < 100 ? "xmark" : "info.circle.fill"))
                            .resizable()
                            .frame(width: 50, height: 50)
                            .padding(showRadialMenu ? 10 : 0)
                            .foregroundColor(.white)
                            .padding(10)
                            .clipShape(Circle())
                            .shadow(radius: 10)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
                .buttonStyle(BorderlessButtonStyle())
                .position(x: UIScreen.main.bounds.width / 2, y: geometry.size.height / 2)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .updating($dragLocation) { value, state, _ in
                            state = value.location
                        }
                        .onChanged { _ in
                            withAnimation(.spring()) {
                                showRadialMenu = true
                            }
                            let generator = UIImpactFeedbackGenerator(style: .soft)
                            generator.impactOccurred()
                        }
                        .onEnded { value in
                            let buttonCenter = CGPoint(
                                x: geometry.frame(in: .local).midX,
                                y: geometry.frame(in: .local).midY
                            )
                            self.handleMenuSelection(at: value.location, center: buttonCenter)
                            withAnimation(.spring()) {
                                showRadialMenu = false
                            }
                        }
                )
                .gesture(
                    LongPressGesture(minimumDuration: 0.3)
                        .onEnded { _ in
                            withAnimation(.spring()) {
                                showRadialMenu = true
                            }
                            let generator = UIImpactFeedbackGenerator(style: .heavy)
                            generator.impactOccurred()
                        }
                )
                .onTapGesture {
                    showDetails = true
                    let generator = UIImpactFeedbackGenerator(style: .rigid)
                    generator.impactOccurred()
                }
            }
        }
        .sheet(isPresented: $showDetails) {
            NutrientDetailView(nutrientName: choice)
        }
        .sheet(isPresented: $showHealthInsights) {
            HealthInsightsView()
        }
        .sheet(isPresented: $showNutritionScanner) {
            NutritionScannerView()
        }
        .sheet(isPresented: $showLogView) {
            LogView()
        }
        .sheet(isPresented: $showHomeView) {
            HomeView()
        }
    }

    func wheelSelectionUpdate() {
        let currentAngle = (finalAngle + rotation).truncatingRemainder(dividingBy: 360)
        let normalizedAngle = (360 - currentAngle + 360 / Double(reversedChoices.count) / 2)
            .truncatingRemainder(dividingBy: 360)
        let sensitivityFactor = 1.0
        let anglePerChoice = 360 / Double(reversedChoices.count)
        let index = Int((normalizedAngle / (anglePerChoice * sensitivityFactor))
            .truncatingRemainder(dividingBy: Double(reversedChoices.count)))
        
        let newChoice = reversedChoices[index]
        if newChoice != choice {
            choice = newChoice
            onChange(newChoice)
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()
        }
    }

    func handleMenuSelection(at location: CGPoint, center: CGPoint) {
        let dx = location.x - center.x
        let dy = location.y - center.y
        let angle = atan2(dy, dx)
        let normalizedAngle = (angle + .pi * 2).truncatingRemainder(dividingBy: .pi * 2)
        
        let distance = sqrt(pow(dx, 2) + pow(dy, 2))
        if distance < 100 && distance > 50{
            return
        } else if distance < 50 {
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.prepare()
            generator.impactOccurred()
            showDetails = true
            return
        }
        
        let highlightedAction = getHighlightedAction(angle: normalizedAngle, distance: distance)
        switch highlightedAction {
            case 0: showHealthInsights = true
            case 1: showNutritionScanner = true
            case 2: showLogView = true
            case 3: showHomeView = true
            default: break
        }
    }
}

struct FocusModeSelectorButton: View {
    @EnvironmentObject var navigationState: NavigationState
    @State private var isExpanded = false
    @State private var rotation: Double = 0
    @Binding var wheelPickerItems: [String]
    let updateChoicesAndIcons: (AppFocus) -> Void

    var body: some View {
        ZStack {
            ForEach(AppFocus.allCases.reversed(), id: \.self) { focus in
                FocusModeOption(focus: focus, onFocusChange: { _ in
                    updateChoicesAndIcons(focus)
                })
                .offset(y: isExpanded ? -CGFloat(AppFocus.allCases.firstIndex(of: focus)! + 1) * 70 : 0)
                .opacity(isExpanded ? 1 : 0)
                .scaleEffect(isExpanded ? 1 : 0.5)
            }
            
            // Main button stays fixed at bottom
            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                    rotation = isExpanded ? 45 : 0
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 70, height: 70)
                    .background(Color.blue)
                    .clipShape(Circle())
                    .rotationEffect(.degrees(rotation))
                    .shadow(radius: 5)
            }
        }
    }
}

struct FocusModeOption: View {
    @EnvironmentObject var navigationState: NavigationState
    @State private var wheelPickerItems: [String] = []
    @State private var showHomeView = false
    @State private var showHealthInsights = false
    @State private var showNutritionScanner = false
    @State private var showLogView = false
    @State private var showNutrientDetail = false
    @State private var selectedNutrient = ""
    let focus: AppFocus
    let onFocusChange: ([String]) -> Void
    
    var icon: String {
        switch focus {
        case .nutrition: return "leaf.fill"
        case .fitness: return "figure.run"
        case .mentalHealth: return "brain.head.profile"
        }
    }
    
    var body: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            
            withAnimation(.spring()) {
                navigationState.appFocus = focus
                onFocusChange([])  // This calls the passed function
            }
        } label: {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(focus == navigationState.appFocus ? Color.blue : Color.blue.opacity(0.8))
                .clipShape(Circle())
        }
        .sheet(isPresented: $showHomeView) { HomeView() }
        .sheet(isPresented: $showHealthInsights) { HealthInsightsView() }
        .sheet(isPresented: $showNutritionScanner) { NutritionScannerView() }
        .sheet(isPresented: $showLogView) { LogView() }
        .sheet(isPresented: $showNutrientDetail) {
            NutrientDetailView(nutrientName: selectedNutrient)
        }
    }
    
    private func updateWheelPickerItems(for focus: AppFocus) {
        switch focus {
        case .nutrition:
            wheelPickerItems = ["Home", "Insights", "Labels", "Log",
                              "Calories", "Protein", "Carbs", "Fats", "Fiber", "Vitamins",
                              "Minerals", "Water", "Phytochemicals", "Antioxidants", "Electrolytes"]
        case .fitness:
            wheelPickerItems = ["Form Coach", "Movement Analysis", "Fuel Check",
                              "Readiness Check", "Strain vs Recovery", "Dashboard",
                              "Today's Plan", "Workout History", "Training Calendar"]
        case .mentalHealth:
            wheelPickerItems = ["Pre-Workout Timing", "Post-Workout Window",
                              "Performance Foods", "Hydration Status", "Macro Balance"]
        }
    }
    
    func getItemsForFocus(_ focus: AppFocus) -> [String] {
        switch focus {
        case .nutrition:
            return ["Home", "Insights", "Labels", "Log",
                   "Calories", "Protein", "Carbs", "Fats", "Fiber", "Vitamins",
                   "Minerals", "Water", "Phytochemicals", "Antioxidants", "Electrolytes"]
        case .fitness:
            return ["Form Coach", "Movement Analysis", "Fuel Check",
                   "Readiness Check", "Strain vs Recovery", "Dashboard",
                   "Today's Plan", "Workout History", "Training Calendar"]
        case .mentalHealth:
            return ["Pre-Workout Timing", "Post-Workout Window",
                   "Performance Foods", "Hydration Status", "Macro Balance"]
        }
    }
    
    private func handleWheelSelection(for item: String) {
        switch navigationState.appFocus {
        case .nutrition:
            switch item {
            case "Home": showHomeView = true
            case "Insights": showHealthInsights = true
            case "Labels": showNutritionScanner = true
            case "Log": showLogView = true
            case "Calories", "Carbs", "Protein", "Fats", "Water", "Fiber",
                 "Vitamins", "Minerals", "Phytochemicals", "Antioxidants", "Electrolytes":
                selectedNutrient = item
                showNutrientDetail = true
            default: break
            }
            
        case .fitness:
            switch item {
            case "Form Coach": showView("Form Coach")
            case "Movement Analysis": showView("Movement Analysis")
            case "Fuel Check": showView("Fuel Check")
            case "Readiness Check": showView("Readiness Check")
            case "Strain vs Recovery": showView("Strain vs Recovery")
            default:
                showComingSoon(feature: item)
            }
            
        case .mentalHealth:
            showComingSoon(feature: item)
        }
    }
    
    private func showView(_ viewName: String) {
        navigationState.selectedView = viewName
    }

    private func showComingSoon(feature: String) {
        navigationState.selectedView = feature
    }
}
