//
//  AddMealView.swift
//  Nutrivance
//
//  Created by Vincent Leong on 11/27/24.
//

import SwiftUI
import Vision
import VisionKit

struct AddMealView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var mealsManager: SavedMealsManager
    @State private var mealName = ""
    @State private var selectedCategory: SavedMeal.MealCategory = .breakfast
    @State private var frequency = ""
    @State private var isFavorite = false
    @State private var showingNutritionScanner = false
    @StateObject private var nutritionScanner = NutritionScannerViewModel()
    @State private var showingImagePicker = false
    @State private var showingSourceSelection = false
    @State private var selectedImage: UIImage?
    @State private var sourceType: UIImagePickerController.SourceType = .camera
    @State private var nutrients: [String: Double] = [
        "calories": 0,
        "protein": 0,
        "carbs": 0,
        "fats": 0,
        "water": 0
    ]
    
    let editingMeal: SavedMeal?
    
    init(mealsManager: SavedMealsManager, editingMeal: SavedMeal? = nil) {
        self.mealsManager = mealsManager
        self.editingMeal = editingMeal
        
        _mealName = State(initialValue: editingMeal?.name ?? "")
        _selectedCategory = State(initialValue: editingMeal?.category ?? .breakfast)
        _frequency = State(initialValue: editingMeal?.frequency ?? "")
        _isFavorite = State(initialValue: editingMeal?.isFavorite ?? false)
        _nutrients = State(initialValue: editingMeal?.nutrients ?? [
            "calories": 0,
            "protein": 0,
            "carbs": 0,
            "fats": 0,
            "water": 0
        ])
    }
    
    var body: some View {
        NavigationView {
            Form {
                mealDetailsSection
                scannerSection
                nutrientsSection
            }
            .navigationTitle(editingMeal == nil ? "Add New Meal" : "Edit Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarButtons
            }
            .sheet(isPresented: $showingNutritionScanner) {
                NutritionScannerView()
            }

        }
    }

    private var mealDetailsSection: some View {
        Section("Meal Details") {
            TextField("Meal Name", text: $mealName)
            categoryPicker
            TextField("Frequency (e.g., Every Friday)", text: $frequency)
            Toggle("Favorite", isOn: $isFavorite)
        }
    }

    private var scannerSection: some View {
        Section {
            Button(action: { showingSourceSelection = true }) {
                HStack {
                    Image(systemName: "doc.text.viewfinder")
                        .foregroundColor(.blue)
                    Text("Scan Nutrition Label")
                }
            }
            
            if let selectedImage = selectedImage {
                ZoomableImage(image: selectedImage)
            }
        }
        .confirmationDialog("Choose Photo Source", isPresented: $showingSourceSelection) {
            Button("Take Photo") {
                sourceType = .camera
                showingImagePicker = true
            }
            Button("Choose from Library") {
                sourceType = .photoLibrary
                showingImagePicker = true
            }
        }
        .fullScreenCover(isPresented: $showingImagePicker) {
            ImagePicker(selectedImage: $selectedImage, sourceType: sourceType)
        }
        .onChange(of: selectedImage) { oldValue, newImage in
            if let image = newImage {
                processNutritionLabel(image)
            }
        }
    }
    
    private var categoryPicker: some View {
        Picker("Category", selection: $selectedCategory) {
            ForEach(SavedMeal.MealCategory.allCases, id: \.self) { category in
                Text(category.rawValue).tag(category)
            }
        }
    }

    private var nutrientsSection: some View {
        Section("Nutrients") {
            ForEach(Array(nutrients.keys.sorted()), id: \.self) { nutrient in
                nutrientRow(for: nutrient)
            }
        }
    }

    private func nutrientRow(for nutrient: String) -> some View {
        HStack {
            Text(nutrient.capitalized)
            Spacer()
            TextField("Amount", value: Binding(
                get: { nutrients[nutrient] ?? 0 },
                set: { nutrients[nutrient] = $0 }
            ), format: .number)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            Text(NutritionUnit.getUnit(for: nutrient))
        }
    }

    private var toolbarButtons: some ToolbarContent {
        Group {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { saveMeal() }
                    .disabled(mealName.isEmpty)
            }
        }
    }

    private func updateNutrients(with detectedNutrients: [NutrientData]) {
        for nutrient in detectedNutrients {
            nutrients[nutrient.name.lowercased()] = nutrient.value
        }
    }

    
    private func saveMeal() {
        let meal = SavedMeal(
            id: editingMeal?.id ?? UUID(),
            name: mealName,
            category: selectedCategory,
            nutrients: nutrients,
            frequency: frequency.isEmpty ? nil : frequency,
            isFavorite: isFavorite,
            lastUsed: Date()
        )
        
        mealsManager.addMeal(meal)
        dismiss()
    }

    private func processNutritionLabel(_ image: UIImage) {
        let requestHandler = VNImageRequestHandler(cgImage: image.cgImage!, options: [:])
        let request = VNRecognizeTextRequest { request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            
            let recognizedText = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }.joined(separator: "\n")
            
            processNutritionText(recognizedText)
        }
        
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        
        try? requestHandler.perform([request])
    }

    private func processNutritionText(_ text: String) {
        let lines = text.components(separatedBy: .newlines)
        
        for line in lines {
            if let nutrient = extractNutrient(from: line) {
                DispatchQueue.main.async {
                    self.nutrients[nutrient.name.lowercased()] = nutrient.value
                }
            }
        }
    }

    private func extractNutrient(from line: String) -> NutritionScannerViewModel.NutritionDetection? {
        let patterns = [
            "^(Calories|Protein|Carbs|Carb\\.|Fats|Fiber)\\s*:?\\s*(\\d+\\.?\\d*)\\s*(g|kcal)?$",
            "^Total\\s+(Fat|Carbohydrate|Carbs|Carb\\.|Protein)\\s*:?\\s*(\\d+\\.?\\d*)\\s*(g|kcal)?$",
            "^Total\\s+Carb\\.\\s*(\\d+\\.?\\d*)\\s*(g|kcal)?$"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.count)) {
                
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

    private func normalizeNutrientName(_ name: String) -> String {
        switch name.lowercased() {
        case "carb.", "carbohydrate", "total carb.", "total carbohydrate":
            return "carbs"
        case "fat", "total fat":
            return "fats"
        case "protein", "total protein":
            return "protein"
        case "calorie", "calories", "total calories":
            return "calories"
        case "fiber", "dietary fiber", "total fiber":
            return "fiber"
        default:
            return name
        }
    }


}

struct ZoomableImage: View {
    let image: UIImage
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @GestureState private var magnifyBy = CGFloat(1.0)
    
    var body: some View {
        GeometryReader { geometry in
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                .scaleEffect(scale * magnifyBy)
                .offset(offset)
                .gesture(
                    SimultaneousGesture(
                        MagnificationGesture()
                            .updating($magnifyBy) { currentState, gestureState, _ in
                                gestureState = currentState
                            }
                            .onEnded { value in
                                scale *= value
                                scale = min(max(scale, 1), 4)
                            },
                        DragGesture()
                            .onChanged { value in
                                let newOffset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                                offset = newOffset
                            }
                            .onEnded { value in
                                lastOffset = offset
                            }
                    )
                )
                .onTapGesture(count: 2) {
                    withAnimation {
                        if scale > 1 {
                            scale = 1
                            offset = .zero
                            lastOffset = .zero
                        } else {
                            scale = 2
                        }
                    }
                }
        }
        .frame(minHeight: 400)
        .clipped()
    }
}

