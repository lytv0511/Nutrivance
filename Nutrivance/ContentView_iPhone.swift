import SwiftUI
import SwiftData

// ContentView
import SwiftUI

struct ContentView_iPhone: View {
    @State private var selectedNutrient: String = "Calories"
    @State private var showNutrientDetail: Bool = false
    @State private var showCamera = false;
    @State private var showNutritionScanner = false
    @State private var isLongPressing = false
    @Environment(\.horizontalSizeClass) var horizontalSizeClass // Detects the device size class

    private let nutrientChoices = [
        "Calories", "Protein", "Carbs", "Fats", "Fiber", "Vitamins",
        "Minerals", "Water", "Phytochemicals", "Antioxidants", "Electrolytes"
    ]

    private let nutrientIcons: [String: String] = [
        "Calories": "flame", "Protein": "fork.knife", "Carbs": "carrot",
        "Fats": "drop.fill", "Fiber": "leaf", "Vitamins": "pills",
        "Minerals": "bolt", "Water": "drop.fill",
        "Phytochemicals": "leaf.arrow.triangle.circlepath",
        "Antioxidants": "shield", "Electrolytes": "battery.100"
    ]

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
                        // Add blank icons based on the device type
//                        if horizontalSizeClass == .compact {
                            BlankIconView()
                            BlankIconView() // 2 blank views for compact (iOS)
//                        } else {
//                        }

                        // Determine the number of columns based on device type
                        let columns = Array(repeating: GridItem(.flexible()), count: horizontalSizeClass == .compact ? 2 : 5)

                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(nutrientChoices, id: \.self) { nutrient in
                                VStack {
                                    Image(systemName: nutrientIcons[nutrient] ?? "leaf.fill")
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
                                            showNutrientDetail = true
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

                        // Add blank icons based on the device type
//                        if horizontalSizeClass == .compact {
                            BlankIconView()
                            BlankIconView() // 2 blank views for compact (iOS)
//                        } else {
//                            BlankIconView() // 1 blank view for regular (iPadOS)
//                        }
                    }
                    .frame(maxHeight: UIScreen.main.bounds.height * 0.5)
                    .padding(.bottom, 10)
                    .onChange(of: selectedNutrient) { oldValue, newValue in
                        withAnimation {
                            scrollViewProxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }

                    // WheelPicker at the bottom half of the screen
//                    if horizontalSizeClass == .compact {
                        WheelPicker(choices: nutrientChoices, choice: $selectedNutrient) { newChoice in
                            selectedNutrient = newChoice // Update the selected nutrient
                        }
                        .padding(.bottom)
//                    } else {
                        
//                    }
                }
                .padding(.top, 10) // Optional: Add some padding at the top to give space from the top of the screen

                // Camera button in bottom right corner
            // Update the camera button section with this code

            Button(action: {}) {
                Image(systemName: "text.viewfinder")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.blue.opacity(0.7))
                    .clipShape(Circle())
                    .shadow(radius: 10)
                    .scaleEffect(isLongPressing ? 1.5 : 1.0)  // Larger scale effect
                    .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isLongPressing)
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5)
                    .onChanged { _ in
                        isLongPressing = true
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                    }
                    .onEnded { _ in
                        isLongPressing = false
                        showNutritionScanner = true
                        let generator = UIImpactFeedbackGenerator(style: .heavy)
                        generator.impactOccurred(intensity: 1.0)
                    }
            )
            .padding()
            .position(x: UIScreen.main.bounds.width - 50, y: UIScreen.main.bounds.height - 100)

            .sheet(isPresented: $showNutritionScanner) {
                NutritionScannerView()
            }


            }
//        }
    }
}

// BlankIconView to represent empty icons
struct BlankIconView: View {
    var body: some View {
        VStack {
            Image(systemName: "circle.fill") // Use a circle or any other placeholder icon
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .foregroundColor(.clear) // Make it transparent
            Text("") // Empty text for spacing
        }
    }
}

extension Double {
    var radiansToDegrees: Double {
        return self * 180 / .pi
    }
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
    
    @ViewBuilder
    func RadialMenuItems() -> some View {
        let menuRadius = 80.0
        ZStack {
            ForEach(0..<4) { index in
                let angle = Double(index) * .pi / 2
                let xOffset = cos(angle) * menuRadius
                let yOffset = sin(angle) * menuRadius
                
                Image(systemName: radialMenuIcons[index])
                    .font(.title)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .opacity(dragLocation != nil ? 1.0 : 0.5)
                    .offset(x: xOffset, y: yOffset)
                    .transition(.scale)
            }
        }
        .animation(.spring(), value: showRadialMenu)
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
                Button(action: {}) {
                    Image(systemName: "arrow.right.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 50, height: 50)
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.gray.opacity(0.5))
                        .clipShape(Circle())
                        .shadow(radius: 10)
                        .scaleEffect(buttonScale)
                        .overlay(
                            Group {
                                if showRadialMenu {
                                    RadialMenuItems()
                                }
                            }
                        )
                }
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .updating($dragLocation) { value, state, _ in
                            state = value.location
                        }
                        .onChanged { _ in
                            withAnimation(.spring()) {
                                showRadialMenu = true
                            }
                            let generator = UIImpactFeedbackGenerator(style: .medium)
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
            let generator = UIImpactFeedbackGenerator(style: .rigid)
            generator.impactOccurred()
        }
    }

    func handleMenuSelection(at location: CGPoint, center: CGPoint) {
        let dx = location.x - center.x
        let dy = location.y - center.y
        let angle = atan2(dy, dx)
        let normalizedAngle = (angle + .pi * 2).truncatingRemainder(dividingBy: .pi * 2)
        
        let distanceFromCenter = sqrt(pow(dx, 2) + pow(dy, 2))
        if distanceFromCenter < 25 {
            showDetails = true
            return
        }
        
        // Rest of the angle checks remain the same
        switch normalizedAngle {
            case (.pi * 1.75)...(2 * .pi), 0...(.pi * 0.25):  // Up
                showHealthInsights = true
            case (.pi * 0.25)...(.pi * 0.75):  // Right
                showNutritionScanner = true
            case (.pi * 0.75)...(.pi * 1.25):  // Down
                showLogView = true
            case (.pi * 1.25)...(.pi * 1.75):  // Left
                showHomeView = true
            default:
                showDetails = true
        }
    }
}
