//
//  MoodTrackerView.swift
//  Nutrivance
//
//  Created by Vincent Leong on 2/25/25.
//

import Foundation
import SwiftUI

struct MoodTrackerView: View {
    @State private var animationPhase: Double = 0
    private let gradients = GradientBackgrounds()
    
    var body: some View {
        NavigationStack {
            HStack {
                Spacer()
                VStack {
                    Spacer()
                    Text("Mood Tracker")
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
            .navigationTitle("Mood Tracker")
        }
    }
}
