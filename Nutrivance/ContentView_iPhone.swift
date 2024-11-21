import SwiftUI
import SwiftData

// ContentView
import SwiftUI

struct ContentView_iPhone: View {
    @State private var selectedNutrient: String = "Calories"
    @State private var showNutrientDetail: Bool = false
    @State private var showCamera = false;
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
                Button(action: {
                    // Do nothing on tap; handled in long press
                }) {
                    Image(systemName: "camera.fill") // Use camera icon
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.gray.opacity(0.5)) // Translucent background
                        .clipShape(Circle())
                        .shadow(radius: 10)
                }
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .onChanged { _ in
                            // Handle button grow effect if desired
                            let generator = UIImpactFeedbackGenerator(style: .heavy)
                            generator.prepare()
                            generator.impactOccurred()
                        }
                        .onEnded { _ in
                            // Open the camera
                            showCamera = true
                            let generator = UIImpactFeedbackGenerator(style: .heavy)
                            generator.prepare()
                            generator.impactOccurred()
                        }
                )
                .padding()
                .position(x: UIScreen.main.bounds.width - 50, y: UIScreen.main.bounds.height - 100) // Position it at the bottom right
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraOCRView(isPresented: $showCamera) // Use your CameraView here
            }
            .fullScreenCover(isPresented: $showNutrientDetail) {
                NutrientDetailView(nutrientName: selectedNutrient) // Present the nutrient detail view
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
