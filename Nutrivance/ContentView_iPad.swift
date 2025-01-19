import SwiftUI

struct ContentView_iPad: View {
    @State private var selectedNutrient: String?
    @State private var showCamera = false
    @State private var showHome: Bool = true
    @State private var showConfirmation = false
    
    var body: some View {
        NavigationSplitView {
            SidebarView(selectedNutrient: $selectedNutrient, showCamera: $showCamera, showHome: $showHome)
        } detail: {
            if showHome {
                HomeView() // Show the home page by default
            } else if let nutrient = selectedNutrient {
//                NutrientDetailView(nutrientName: nutrient)
            } else {
                Text("Select a nutrient")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct SidebarView: View {
    @Binding var selectedNutrient: String?
    @Binding var showCamera: Bool
    @Binding var showHome: Bool
    @State private var showConfirmation = false
    
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
        List {
            // Home Button
            Button(action: {
                showHome = true
                selectedNutrient = nil
            }) {
                HStack {
                    Label("Home", systemImage: "house")
                    if showHome { // Show the green dot if Home is selected
                        Circle()
                            .fill(Color.green)
                            .frame(width: 10, height: 10)
                    }
                }
            }
            .keyboardShortcut("H", modifiers: [.control]) // ⌘H for Home
            
            // Nutrient Choices
            ForEach(nutrientChoices, id: \.self) { nutrient in
                Button(action: {
                    showHome = false
                    selectedNutrient = nutrient
                }) {
                    HStack {
                        Image(systemName: nutrientIcons[nutrient] ?? "leaf.fill")
                            .foregroundColor(.blue)
                        Text(nutrient)
                    }
                }
            }
            
            // Camera Button
            Button(action: {
                showConfirmation = true // Show the confirmation popup
            }) {
                HStack {
                    Label("Camera", systemImage: "camera")
                    if !showHome && selectedNutrient == nil { // Show the green dot if Camera is selected
                        Circle()
                            .fill(Color.green)
                            .frame(width: 10, height: 10)
                    }
                }
            }
            .keyboardShortcut("C", modifiers: [.control])
            .popover(isPresented: $showConfirmation, arrowEdge: .leading) {
                VStack {
                    Text("Are you sure you want to open the camera?")
                        .padding()
                    HStack {
                        Button("Cancel") {
                            showConfirmation = false // Dismiss the confirmation popup
                        }
                        .padding()
                        
                        Button("Open") {
                            showCamera.toggle() // Proceed to open the camera
                            showConfirmation = false // Dismiss the confirmation popup
                        }
                        .padding()
                    }
                }
                .frame(width: 250) // Set width for the popover
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraOCRView(isPresented: $showCamera)
            }
        }
        .listStyle(SidebarListStyle())
    }
}


struct ContentView_iPad_Previews: PreviewProvider {
    static var previews: some View {
        ContentView_iPad()
    }
}
