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

struct WheelPicker: View {
    let choices: [String]
    @Binding var choice: String
    @State private var rotation: Double = 0
    @State private var finalAngle: Double = 0
    @State private var initialTouchAngle: Double? = nil
    let numberOfTicks = 100
    let onChange: (String) -> Void // Closure to notify about changes
    @State private var buttonScale: CGFloat = 1.0 // State to manage button scale
    @State private var showCamera: Bool = false // State for camera presentation
    @State private var showDetails: Bool = false // State for showing details view

    // Computed property to reverse the choices array
    private var reversedChoices: [String] {
        return choices.reversed()
    }

    public var body: some View {
        ZStack {
            GeometryReader { geometry in
                ZStack {
                    Circle()
                        .stroke(lineWidth: 1)
                        .foregroundColor(.gray)

                    ForEach(0..<numberOfTicks, id: \.self) { index in
                        Rectangle()
                            .frame(width: 2, height: index % 5 == 0 ? 20 : 10)
                            .offset(y: -geometry.size.width / 2 + 15 + (index % 5 == 0 ? -5 : 0))
                            .rotationEffect(Angle(degrees: 360 / Double(numberOfTicks) * Double(index)))
                    }
                }
                .contentShape(Circle())
                .clipped()
                .frame(width: geometry.size.width, height: geometry.size.width)
                .rotationEffect(Angle(degrees: self.rotation))
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let vector = CGVector(dx: value.location.x - geometry.size.width / 2,
                                                  dy: value.location.y - geometry.size.height / 2)
                            let angle = atan2(vector.dy, vector.dx).radiansToDegrees
                            if self.initialTouchAngle == nil {
                                self.initialTouchAngle = angle
                            }
                            self.rotation = angle - (self.initialTouchAngle ?? 0)

                            // Update the selection in real-time
                            updateSelection()
                        }
                        .onEnded { _ in
                            self.finalAngle += self.rotation
                            self.rotation = 0
                            self.initialTouchAngle = nil
                        }
                )
            }
            .aspectRatio(1, contentMode: .fit)
            .padding(.horizontal)

            Button(action: {
                // Open the nutrient detail view when tapped
                showDetails = true
                let generator = UIImpactFeedbackGenerator(style: .heavy)
                generator.prepare()
                generator.impactOccurred()
            }) {
                Image(systemName: "arrow.right.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50) // Frame size of the button
                    .foregroundColor(.white) // Set icon color to white
                    .padding(10) // Padding around the icon
                    .background(Color.gray.opacity(0.5)) // Translucent gray background
                    .clipShape(Circle())
                    .shadow(radius: 10)
                    .scaleEffect(buttonScale) // Scale the button
            }
            .rotationEffect(Angle(degrees: 0)) // Prevent rotation of the button

            // Full Screen Cover for Nutrient Detail View
            .sheet(isPresented: $showDetails) {
                NutrientDetailView(nutrientName: choice)
            }
        }
    }

    private func updateSelection() {
        let currentAngle = (self.finalAngle + self.rotation).truncatingRemainder(dividingBy: 360)
        let normalizedAngle = (360 - currentAngle + 360 / Double(reversedChoices.count) / 2).truncatingRemainder(dividingBy: 360)
        let sensitivityFactor = 1.0  // Lower values increase sensitivity
        let index = Int((normalizedAngle / ((360 / Double(reversedChoices.count)) * sensitivityFactor)).truncatingRemainder(dividingBy: Double(reversedChoices.count)))
        let newChoice = reversedChoices[index] // Use reversedChoices for selection
        
        if newChoice != choice {
            choice = newChoice // Update the bound choice
            onChange(newChoice) // Call the onChange closure
            let generator = UIImpactFeedbackGenerator(style: .rigid)
            generator.prepare()
            generator.impactOccurred()
        }
    }
}

extension CGFloat {
    var radiansToDegrees: Double {
        return Double(self) * 180 / .pi
    }
}
