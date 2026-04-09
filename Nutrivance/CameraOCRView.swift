//
//  CameraOCRView.swift
//  Nutrivance
//
//  Created by Vincent Leong on 11/12/24.
//

import SwiftUI
import Vision
import UIKit

public struct CameraOCRView: View {
    @Binding var isPresented: Bool
    @StateObject private var healthStore = HealthKitManager()
    @State private var capturedImage: UIImage?
    @State private var recognizedText: String = ""
    
    public var body: some View {
        NavigationView {
            VStack {
                if let image = capturedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                    
                    Text(recognizedText)
                        .padding()
                    
                    Button("Process Nutrition Data") {
                        if let nutrientData = processNutritionData(from: recognizedText) {
                            healthStore.saveNutrients([nutrientData]) { success in
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("Scan Nutrition Label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }
    
    private func processNutritionData(from text: String) -> HealthKitManager.NutrientData? {
        // Extract values from OCR text
        let extractedValue = 0.0 // Replace with actual OCR parsing logic
        
        return HealthKitManager.NutrientData(
            name: "protein", // Replace with detected nutrient name
            value: extractedValue,
            unit: "g"
        )
    }
}
