import SwiftUI
import Vision
import HealthKit
import UIKit

class NutritionScannerViewModel: ObservableObject {
    @Published var isProcessing = false
    @Published var detectedNutrition: [NutritionDetection] = []
    
    struct NutritionDetection: Equatable {
        let name: String
        let value: Double
        let unit: String
    }
}

public struct NutritionScannerView: View {
    @StateObject private var nutritionScanner = NutritionScannerViewModel()
    @StateObject private var healthStore = HealthKitManager()
    @State private var showingImportOptions = false
    @State private var showingImagePicker = false
    @State private var showingSourceSelection = false
    @State private var selectedImage: UIImage?
    @State private var sourceType: UIImagePickerController.SourceType = .camera
    
    public var body: some View {
        VStack {
            Button(action: {
                showingSourceSelection = true
            }) {
                Label("Scan Nutrition Label", systemImage: "doc.text.viewfinder")
                    .font(.title2)
            }
            .disabled(nutritionScanner.isProcessing)
            .scaleEffect(nutritionScanner.isProcessing ? 0.9 : 1.0)
            .padding(100)
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
            
            if nutritionScanner.isProcessing {
                ProgressView("Analyzing nutrition label...")
                    .transition(.scale.combined(with: .opacity))
            } else if !nutritionScanner.detectedNutrition.isEmpty {
                detectedNutrientsView
            }
        }
        .animation(.spring(), value: nutritionScanner.isProcessing)
        .animation(.spring(), value: nutritionScanner.detectedNutrition)
        .fullScreenCover(isPresented: $showingImagePicker) {
            ImagePicker(selectedImage: $selectedImage, sourceType: sourceType)
        }
        .onChange(of: selectedImage) { oldValue, newValue in
            guard let image = newValue else { return }
            nutritionScanner.isProcessing = true
            processImage(image)
        }
    }
    
    private var detectedNutrientsView: some View {
        VStack {
            NutritionResultsView(detections: nutritionScanner.detectedNutrition)
            
            Button(action: {
                showingImportOptions = true
            }) {
                Label("Import to Health", systemImage: "heart.fill")
                    .foregroundColor(.green)
            }
            .sheet(isPresented: $showingImportOptions) {
                HealthKitImportView(nutrients: convertToNutrientData(nutritionScanner.detectedNutrition))
            }
            .padding(100)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    private func convertToNutrientData(_ detections: [NutritionScannerViewModel.NutritionDetection]) -> [NutrientData] {
        detections.map { detection in
            NutrientData(
                name: detection.name,
                value: detection.value,
                unit: detection.unit
            )
        }
    }
    private func processResults(_ results: [Any]) -> [NutritionScannerViewModel.NutritionDetection] {
        // Convert the detector results to NutritionDetection objects
        // Implementation depends on the format of your detector results
        return []
    }
    private func processNutritionText(_ text: String) {
        let lines = text.components(separatedBy: .newlines)
        var detectedNutrients: [NutritionScannerViewModel.NutritionDetection] = []
        
        for line in lines {
            // Match patterns like "Protein 12g" or "Calories 240"
            if let nutrient = extractNutrient(from: line) {
                detectedNutrients.append(nutrient)
            }
        }
        
        DispatchQueue.main.async {
            nutritionScanner.detectedNutrition = detectedNutrients
            nutritionScanner.isProcessing = false
        }
    }
    private func extractNutrient(from line: String) -> NutritionScannerViewModel.NutritionDetection? {
        let patterns = [
            // Matches "Protein 12g" or "Protein: 12g"
            "^(Calories|Protein|Carbs|Fats|Fiber)\\s*:?\\s*(\\d+\\.?\\d*)\\s*(g|kcal)?$",
            // Matches "Total Fat 12g" or "Total Fat: 12g"
            "^Total\\s+(Fat|Carbohydrate|Protein)\\s*:?\\s*(\\d+\\.?\\d*)\\s*(g|kcal)?$"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.count)) {
                
                let nsLine = line as NSString
                let name = nsLine.substring(with: match.range(at: 1))
                if let value = Double(nsLine.substring(with: match.range(at: 2))) {
                    let unit = switch name.lowercased() {
                        case "calories": "kcal"
                        case "water": "ml"
                        default: match.range(at: 3).location != NSNotFound ? nsLine.substring(with: match.range(at: 3)) : "g"
                    }
                    return NutritionScannerViewModel.NutritionDetection(name: name, value: value, unit: unit)
                }
            }
        }
        return nil
    }
    
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



}
