//
//  NutrientCharts.swift
//  Nutrivance
//
//  Created by Vincent Leong on 12/14/24.
//

import Foundation
import SwiftUI
import Charts

struct NutrientCharts: View {
    let data: [String: Double]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Nutrient Distribution")
                .font(.headline)
                .padding(.horizontal)
            
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.2))
                .frame(height: 200)
                .overlay(
                    Text("Nutrient Charts Coming Soon")
                        .foregroundColor(.gray)
                )
                .padding(.horizontal)
        }
    }
}
