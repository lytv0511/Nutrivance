//
//  HealthKitImportView.swift
//  Nutrivance
//
//  Created by Vincent Leong on 11/20/24.
//

import SwiftUI

struct HealthKitImportView: View {
    let nutrients: [NutrientData]
    @StateObject private var healthStore = HealthKitManager()
    @Environment(\.dismiss) private var dismiss
    @State private var selectedNutrients: Set<String>
    
    init(nutrients: [NutrientData]) {
        self.nutrients = nutrients
        _selectedNutrients = State(initialValue: Set(nutrients.map { $0.name }))
    }
    
    var body: some View {
        NavigationView {
            List {
                ForEach(nutrients, id: \.name) { nutrient in
                    Toggle(isOn: Binding(
                        get: { selectedNutrients.contains(nutrient.name) },
                        set: { isSelected in
                            if isSelected {
                                selectedNutrients.insert(nutrient.name)
                            } else {
                                selectedNutrients.remove(nutrient.name)
                            }
                        }
                    )) {
                        Text("\(nutrient.name.capitalized): \(String(format: "%.1f", nutrient.value)) \(nutrient.unit)")

                    }
                }
            }
            .navigationTitle("Import to Health")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        healthStore.saveNutrients(nutrients.map { nutrient in
                            HealthKitManager.NutrientData(
                                name: nutrient.name,
                                value: nutrient.value,
                                unit: nutrient.unit
                            )
                        }) { success in
                            if success {
                                dismiss()
                            }
                        }
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                selectedNutrients = Set(nutrients.map { $0.name })
            }
        }
    }
}
