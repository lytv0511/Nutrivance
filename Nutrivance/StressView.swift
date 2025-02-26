//
//  StressView.swift
//  Nutrivance
//
//  Created by Vincent Leong on 2/25/25.
//

import Foundation
import SwiftUI

struct StressView: View {
    @State private var animationPhase: Double = 0
    private let gradients = GradientBackgrounds()
    
    var body: some View {
        NavigationStack {
            ZStack {
                gradients.spiritGradient(animationPhase: $animationPhase)
            }
            .navigationTitle("Stress")
        }
    }
}
