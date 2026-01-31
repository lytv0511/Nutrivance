//
//  BreathingView.swift
//  Nutrivance
//
//  Created by Vincent Leong on 2/25/25.
//

import Foundation
import SwiftUI

struct BreathingView: View {
    @State private var animationPhase: Double = 0
    private let gradients = GradientBackgrounds()
    
    var body: some View {
        NavigationStack {
            HStack {
                Spacer()
                VStack {
                    Spacer()
                    Text("Breathing")
                    Spacer()
                }
                Spacer()
            }
            .background(
                GradientBackgrounds().spiritGradient(animationPhase: $animationPhase)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                            animationPhase = 20
                        }
                    }
            )
            .navigationTitle(Text("Breathing"))
        }
    }
}
