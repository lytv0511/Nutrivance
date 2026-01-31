import SwiftUI
import Vision
import HealthKit
import UIKit

// ViewModel for managing nutrition scanning
class NutritionScannerViewModel: ObservableObject {
    @Published var isProcessing = false
    @Published var detectedNutrition: [NutritionDetection] = []

    struct NutritionDetection: Identifiable, Equatable {
        let id = UUID()
        let name: String
        var value: Double
        let unit: String
    }
}

// Main View for the Nutrition Scanner
public struct NutritionScannerView: View {
    @StateObject private var nutritionScanner = NutritionScannerViewModel()
    @StateObject private var healthStore = HealthKitManager() // HealthKit integration
    @State private var showingImagePicker = false
    @State private var showingSourceSelection = false  // New state for source selection dialog
    @State private var extractedNutrients: [String: Double] = [:]
    @State private var showingConfirmation = false
    @State private var selectedImage: UIImage?
    @State private var newValue: String = ""
    @State private var showEditSheet: Bool = false
    @State private var selectedNutrient: NutritionScannerViewModel.NutritionDetection?
    @State private var sourceType: UIImagePickerController.SourceType = .camera  // Default to camera
    @State private var animationPhase: Double = 0
    @State private var showingImagePreview = false
    
    public var body: some View {
        NavigationStack {
            VStack {
                ZStack {
                    if let image = selectedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(12)
                            .frame(maxHeight: 300)
                            .onTapGesture {
                                showingImagePreview = true
                            }
                            .fullScreenCover(isPresented: $showingImagePreview) {
                                NavigationStack {
                                    ZStack {
                                        Color.black.ignoresSafeArea()
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFit()
                                            .ignoresSafeArea()
                                    }
                                    .toolbar {
                                        ToolbarItem(placement: .navigationBarTrailing) {
                                            Button("Done") {
                                                 showingImagePreview = false
                                            }
                                        }
                                    }
                                    .navigationBarTitleDisplayMode(.inline)
                                }
                            }
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 200)
                            .overlay(
                                VStack {
                                    Image(systemName: "photo.on.rectangle.angled")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 50, height: 50)
                                        .foregroundColor(.gray)
                                    Text("No Image Selected")
                                        .foregroundColor(.gray)
                                }
                            )
                    }
                    
                    // Overlay progress indicator
                    if nutritionScanner.isProcessing {
                        Color.black.opacity(0.5)
                            .cornerRadius(12)
                            .overlay(
                                ProgressView("Analyzing...")
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .foregroundColor(.white)
                            )
                    }
                }
                .padding()
                
                // Scan Button with Source Selection
                Button(action: {
                    showingSourceSelection = true  // Trigger source selection dialog
                }) {
                    Label("Scan Nutrition Label", systemImage: "doc.text.viewfinder")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(LinearGradient(gradient: Gradient(colors: [Color.blue, Color.cyan]), startPoint: .leading, endPoint: .trailing))
                        .cornerRadius(12)
                        .shadow(radius: 5)
                }
                .padding(.horizontal)
                .hoverEffect(.highlight)
                .confirmationDialog("Choose Photo Source", isPresented: $showingSourceSelection) {
                    Button("Camera") {
                        sourceType = .camera
                        showingImagePicker = true
                    }
                    Button("Photo Library") {
                        sourceType = .photoLibrary
                        showingImagePicker = true
                    }
                }
                
                // Detected Nutrients List
                if !nutritionScanner.detectedNutrition.isEmpty {
                    List {
                        ForEach(nutritionScanner.detectedNutrition) { nutrient in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(nutrient.name.capitalized)
                                        .font(.headline)
                                    Text("\(nutrient.value, specifier: "%.1f") \(nutrient.unit)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: nutrientIcon(for: nutrient.name))
                                    .foregroundColor(.blue)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteNutrient(nutrient)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                
                                Button {
                                    editNutrient(nutrient) // Trigger edit nutrient
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.yellow)
                            }
                        }
                        HStack {
                            VStack(alignment: .leading) {
                                Text("...")
                                    .font(.headline)
                                Text("...")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "camera.metering.unknown")
                                .foregroundColor(.blue)
                        }
                    }
                    
                    // Sheet for editing the nutrient value
                    .sheet(isPresented: $showEditSheet) {
                        VStack {
                            Text("Edit \(selectedNutrient?.name ?? "")")
                                .font(.title2)
                                .bold()
                                .padding()
                            
                            TextField("Enter new value", text: $newValue)
                                .keyboardType(.decimalPad) // Allow decimal input
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .padding()
                            
                            Button(action: {
                                if let newValue = Double(newValue), let nutrient = selectedNutrient {
                                    updateNutrientValue(nutrient, newValue: newValue) // Update the nutrient value
                                    showEditSheet = false // Close the sheet
                                }
                            }) {
                                Text("Save")
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(Color.blue)
                                    .cornerRadius(8)
                            }
                            
                            Button(action: {
                                showEditSheet = false // Close the sheet
                            }) {
                                Text("Cancel")
                                    .foregroundColor(.red)
                                    .padding()
                                    .background(Color.white)
                                    .cornerRadius(8)
                            }
                        }
                        .padding()
                    }
                    .listStyle(InsetGroupedListStyle())
                    
                    // Import to Health Button
                    Button(action: importToHealth) {
                        Label("Import to Health", systemImage: "heart.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .cornerRadius(12)
                            .shadow(radius: 5)
                    }
                    .padding(.horizontal)
                    .hoverEffect(.highlight)
                }
                
                Spacer()
            }
            .fullScreenCover(isPresented: $showingImagePicker) {
                ImagePicker(selectedImage: $selectedImage, sourceType: sourceType)
            }
            .onChange(of: selectedImage) { _, newValue in
                guard let image = newValue else { return }
                nutritionScanner.isProcessing = true
                processImage(image)
            }
            .navigationTitle(Text("Scan Labels"))
            .background(
               GradientBackgrounds().natureGradient(animationPhase: $animationPhase)
                   .onAppear {
                       withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                           animationPhase = 20
                       }
                   }
           )
        }
    }
    
    // Nutrient Icon Mapping
    private func nutrientIcon(for nutrient: String) -> String {
        switch nutrient.lowercased() {
        case "calories": return "flame.fill"
        case "protein": return "bolt.fill"
        case "carbs": return "leaf.fill"
        case "fats": return "drop.fill"
        case "fiber": return "tree.fill"
        case "water": return "drop.fill"
        default: return "questionmark.circle.fill"
        }
    }
    
    // Image Processing Logic
    private func processImage(_ image: UIImage) {
        let requestHandler = VNImageRequestHandler(cgImage: image.cgImage!, options: [:])
        let request = VNRecognizeTextRequest { request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            
            let recognizedText = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }.joined(separator: "\n")
            
            self.processNutritionText(recognizedText)
        }
        
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        
        try? requestHandler.perform([request])
    }
    
    private func deleteNutrient(_ nutrient: NutritionScannerViewModel.NutritionDetection) {
        if let index = nutritionScanner.detectedNutrition.firstIndex(of: nutrient) {
            nutritionScanner.detectedNutrition.remove(at: index)
        }
    }
    
    private func editNutrient(_ nutrient: NutritionScannerViewModel.NutritionDetection) {
        // Create a mutable copy of the nutrient
        if let index = nutritionScanner.detectedNutrition.firstIndex(where: { $0.id == nutrient.id }) {
            var updatedNutrient = nutritionScanner.detectedNutrition[index]
            
            // Show the alert to edit the value
            let alert = UIAlertController(title: "Edit \(updatedNutrient.name.capitalized)", message: "Enter new value for \(updatedNutrient.name.capitalized)", preferredStyle: .alert)
            
            alert.addTextField { textField in
                textField.placeholder = "New Value"
                textField.keyboardType = .decimalPad
                textField.text = "\(updatedNutrient.value)"
            }
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
            
            alert.addAction(UIAlertAction(title: "Save", style: .default, handler: { _ in
                if let newValueText = alert.textFields?.first?.text, let newValue = Double(newValueText) {
                    // Update the nutrient value
                    updatedNutrient.value = newValue
                    
                    // Replace the old nutrient with the updated one in the array
                    nutritionScanner.detectedNutrition[index] = updatedNutrient
                }
            }))
            
            // Present the alert
            // Update deprecated windows call
            let windowScene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
            _ = windowScene?.windows.first(where: { $0.isKeyWindow })

        }
    }
    
    private func updateNutrientValue(_ nutrient: NutritionScannerViewModel.NutritionDetection, newValue: Double) {
        // Find the index of the selected nutrient
        if let index = nutritionScanner.detectedNutrition.firstIndex(where: { $0.id == nutrient.id }) {
            // Create a mutable copy of the nutrient at that index
            var updatedNutrient = nutritionScanner.detectedNutrition[index]
            
            // Modify the value of the mutable copy
            updatedNutrient.value = newValue
            
            // Replace the old nutrient with the updated one in the array
            nutritionScanner.detectedNutrition[index] = updatedNutrient
        }
    }
    
    // Processing OCR Text
    private func processNutritionText(_ text: String) {
        let lines = text.components(separatedBy: .newlines)
        var detectedNutrients: [NutritionScannerViewModel.NutritionDetection] = []
        
        for line in lines {
            if let nutrient = extractNutrient(from: line) {
                detectedNutrients.append(nutrient)
            }
        }
        
        DispatchQueue.main.async {
            nutritionScanner.detectedNutrition = detectedNutrients
            nutritionScanner.isProcessing = false
        }
    }
    
    // Extract Nutrient Information from Text
    private func extractNutrient(from line: String) -> NutritionScannerViewModel.NutritionDetection? {
        let patterns = [
            #"(?i)^(Calories|Protein|Carbs|Fats|Fiber|Water)\s*:?\s*(\d+\.?\d*)\s*(g|kcal|mL)?"#,
            #"(?i)^Total\s+(Fat|Carbohydrate|Protein)\s*:?\s*(\d+\.?\d*)\s*(g|kcal|mL)?"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.utf16.count)) {
                
                let nsLine = line as NSString
                let name = nsLine.substring(with: match.range(at: 1))
                if let value = Double(nsLine.substring(with: match.range(at: 2))) {
                    let unit = match.range(at: 3).location != NSNotFound ? nsLine.substring(with: match.range(at: 3)) : "g"
                    let normalizedName = normalizeNutrientName(name)
                    return NutritionScannerViewModel.NutritionDetection(name: normalizedName, value: value, unit: unit)
                }
            }
        }
        return nil
    }
    
    // Normalize Nutrient Names
    private func normalizeNutrientName(_ name: String) -> String {
        switch name.lowercased() {
        case "carb", "carbs", "carbohydrate": return "carbs"
        case "fat", "total fat": return "fats"
        case "protein": return "protein"
        case "calorie", "calories": return "calories"
        case "fiber": return "fiber"
        case "water": return "water"
        default: return name
        }
    }

    // Import to HealthKit
    private func importToHealth() {
        let healthKitNutrients = extractedNutrients.map { nutrient in
            HealthKitManager.NutrientData(
                name: nutrient.key,
                value: nutrient.value,
                unit: NutritionUnit.getUnit(for: nutrient.key)
            )
        }

        healthStore.saveNutrients(healthKitNutrients) { success in
            if success {
                showingConfirmation = true
            }
        }
    }
}
