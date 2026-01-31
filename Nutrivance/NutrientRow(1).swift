//
//  NutrientRow.swift
//  Nutrivance
//
//  Created by Vincent Leong on 11/20/24.
//

import SwiftUI

struct NutrientRow: View {
    let nutrient: String
    @State private var isEditing = false
    
    var body: some View {
        HStack {
            Text(nutrient)
                .font(.body)
            Spacer()
            Button(action: {
                isEditing.toggle()
            }) {
                Image(systemName: "pencil")
            }
        }
        .padding()
    }
}
