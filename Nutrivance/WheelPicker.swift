import SwiftUI

public struct WheelPicker: View {
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
            .fullScreenCover(isPresented: $showDetails) {
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

struct WheelPicker_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
