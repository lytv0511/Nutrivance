//
//  NutritionResultsView.swift
//  Nutrivance
//
//  Created by Vincent Leong on 11/20/24.
//

import SwiftUI

struct NutritionResultsView: View {
    let detections: [NutritionScannerViewModel.NutritionDetection]
    @State private var editMode: EditMode = .inactive
    @State private var selectedItems = Set<String>()
    @State private var showingExportOptions = false
    
    var body: some View {
        List(detections, id: \.name, selection: $selectedItems) { detection in
            HStack {
                Text(detection.name)
                Spacer()
                Text("\(detection.value, specifier: "%.1f") \(detection.unit)")
            }
        }
        .environment(\.editMode, $editMode)
        .toolbar {
            EditButton()
        }
    }
}
