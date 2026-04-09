//
//  PresetButton.swift
//  Nutrivance
//
//  Created by Vincent Leong on 2/23/25.
//

import Foundation
import SwiftUI

struct PresetButton: View {
    let index: Int
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text("Preset \(index + 1)")
                .padding()
                .background(isSelected ? .blue : .gray)
                .foregroundColor(.white)
                .cornerRadius(8)
        }
    }
}
