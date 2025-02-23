import SwiftUI

struct GradientBackgrounds {
    func warmGradient(animationPhase: Binding<Double>) -> some View {
        MeshGradientView(colors: lightWarmColors, darkColors: darkWarmColors, animationPhase: animationPhase)
    }
    
    func naturalGradient(animationPhase: Binding<Double>) -> some View {
        MeshGradientView(colors: lightNaturalColors, darkColors: darkNaturalColors, animationPhase: animationPhase)
    }
    
    func boldGradient(animationPhase: Binding<Double>) -> some View {
        MeshGradientView(colors: lightBoldColors, darkColors: darkBoldColors, animationPhase: animationPhase)
    }
    
    func spiritGradient(animationPhase: Binding<Double>) -> some View {
        MeshGradientView(colors: lightSpiritColors, darkColors: darkSpiritColors, animationPhase: animationPhase)
    }
    
    func burningGradient(animationPhase: Binding<Double>) -> some View {
        MeshGradientView(colors: lightBurningColors, darkColors: darkBurningColors, animationPhase: animationPhase)
    }
    
    func natureGradient(animationPhase: Binding<Double>) -> some View {
        MeshGradientView(colors: lightNatureColors, darkColors: darkNatureColors, animationPhase: animationPhase)
    }

    func forestGradient(animationPhase: Binding<Double>) -> some View {
        MeshGradientView(colors: lightForestColors, darkColors: darkForestColors, animationPhase: animationPhase)
    }
    
    private var lightWarmColors: [Color] {
        [
//            Color(.systemBackground),
            Color(red: 1.0, green: 0.4, blue: 0.0),  // Vibrant orange
            Color(red: 0.9, green: 0.3, blue: 0.0),  // Deep orange
            Color(red: 0.8, green: 0.2, blue: 0.0),  // Orange-red
//            Color(.systemBackground),
            Color(red: 1.0, green: 0.5, blue: 0.1),  // Bright orange
            Color(red: 0.95, green: 0.6, blue: 0.2), // Golden orange
            Color(red: 0.85, green: 0.25, blue: 0.0), // Rich orange-red
//            Color(.systemBackground)
        ]
    }

    private var darkWarmColors: [Color] {
        [
//            Color(.systemBackground),
            Color(red: 0.5, green: 0.2, blue: 0.0),  // Dark orange
            Color(red: 0.45, green: 0.15, blue: 0.0), // Deep orange-red
            Color(red: 0.4, green: 0.1, blue: 0.0),   // Dark red-orange
//            Color(.systemBackground),
            Color(red: 0.5, green: 0.25, blue: 0.05), // Muted orange
            Color(red: 0.475, green: 0.3, blue: 0.1), // Dark golden
            Color(red: 0.425, green: 0.125, blue: 0.0), // Deep orange-red
//            Color(.systemBackground)
        ]
    }
    
    private var lightNaturalColors: [Color] {
        [
            .white,
            Color(red: 0.2, green: 0.8, blue: 0.2),
            Color(red: 0.0, green: 0.0, blue: 0.8),
            Color(red: 0.1, green: 0.7, blue: 0.3),
            .white,
            Color(red: 0.0, green: 0.6, blue: 0.9),
            Color(red: 0.0, green: 0.8, blue: 0.4),
            Color(red: 0.1, green: 0.9, blue: 0.2),
            .white
        ]
    }
    
    private var darkNaturalColors: [Color] {
        [
            .black,
            Color(red: 0.1, green: 0.4, blue: 0.1),
            Color(red: 0.0, green: 0.0, blue: 0.4),
            Color(red: 0.05, green: 0.35, blue: 0.15),
            .black,
            Color(red: 0.0, green: 0.3, blue: 0.45),
            Color(red: 0.0, green: 0.4, blue: 0.2),
            Color(red: 0.05, green: 0.45, blue: 0.1),
            .black
        ]
    }
    
    private var lightBoldColors: [Color] {
        [
            Color(red: 0.4, green: 0.0, blue: 0.9),
            Color(red: 0.8, green: 0.0, blue: 0.0),
            .white,
            Color(red: 0.5, green: 0.0, blue: 1.0),
            .white,
            Color(red: 1.0, green: 0.0, blue: 0.0),
            .white,
            Color(red: 0.6, green: 0.0, blue: 0.8),
            Color(red: 0.9, green: 0.0, blue: 0.0)
        ]
    }
    
    private var darkBoldColors: [Color] {
        [
            Color(red: 0.2, green: 0.0, blue: 0.45),
            Color(red: 0.4, green: 0.0, blue: 0.0),
            .black,
            Color(red: 0.25, green: 0.0, blue: 0.5),
            .black,
            Color(red: 0.5, green: 0.0, blue: 0.0),
            .black,
            Color(red: 0.3, green: 0.0, blue: 0.4),
            Color(red: 0.45, green: 0.0, blue: 0.0)
        ]
    }
    
    private var lightSpiritColors: [Color] {
        [
            Color(red: 0.66, green: 0.86, blue: 0.86),  // Soft Sky Blue
            Color(red: 1.0, green: 0.78, blue: 0.64),   // Warm Peach
            Color(red: 0.80, green: 0.91, blue: 0.85),  // Pastel Mint Green
            Color(.systemBackground),
            Color(red: 0.84, green: 0.76, blue: 0.88),  // Muted Lavender
            Color(.systemBackground),
            Color(red: 0.66, green: 0.86, blue: 0.86),  // Soft Sky Blue
            Color(red: 1.0, green: 0.78, blue: 0.64),   // Warm Peach
            Color(red: 0.80, green: 0.91, blue: 0.85)   // Pastel Mint Green
        ]
    }

    private var darkSpiritColors: [Color] {
        [
            Color(red: 0.07, green: 0.12, blue: 0.18),  // Deep Midnight Blue
            Color(red: 0.56, green: 0.43, blue: 0.70),  // Soft Plum Purple
            Color(red: 0.37, green: 0.62, blue: 0.63),  // Muted Cyan Blue
            Color(.systemBackground),
            Color(red: 0.91, green: 0.61, blue: 0.43),  // Dusty Rose Orange
            Color(.systemBackground),
            Color(red: 0.07, green: 0.12, blue: 0.18),  // Deep Midnight Blue
            Color(red: 0.56, green: 0.43, blue: 0.70),  // Soft Plum Purple
            Color(red: 0.37, green: 0.62, blue: 0.63)   // Muted Cyan Blue
        ]
    }
    
    private var lightBurningColors: [Color] {
        [
            Color(red: 1.0, green: 0.55, blue: 0.0),   // Fiery Orange
            Color(red: 1.0, green: 0.27, blue: 0.0),   // Intense Red
            Color(red: 1.0, green: 0.75, blue: 0.2),   // Bright Gold
            Color(.systemBackground),
            Color(red: 0.96, green: 0.43, blue: 0.26), // Ember Coral
            Color(.systemBackground),
            Color(red: 1.0, green: 0.55, blue: 0.0),   // Fiery Orange
            Color(red: 1.0, green: 0.27, blue: 0.0),   // Intense Red
            Color(red: 1.0, green: 0.75, blue: 0.2)    // Bright Gold
        ]
    }

    private var darkBurningColors: [Color] {
        [
            Color(red: 0.2, green: 0.05, blue: 0.0),   // Deep Charcoal Ember
            Color(red: 0.85, green: 0.25, blue: 0.1),  // Burning Crimson
            Color(red: 1.0, green: 0.5, blue: 0.0),    // Molten Lava Orange
            Color(.systemBackground),
            Color(red: 0.9, green: 0.7, blue: 0.2),    // Golden Heat Glow
            Color(.systemBackground),
            Color(red: 0.2, green: 0.05, blue: 0.0),   // Deep Charcoal Ember
            Color(red: 0.85, green: 0.25, blue: 0.1),  // Burning Crimson
            Color(red: 1.0, green: 0.5, blue: 0.0)     // Molten Lava Orange
        ]
    }
    
    private var lightNatureColors: [Color] {
        [
            Color(red: 0.18, green: 0.72, blue: 0.40),  // Rich Leaf Green
            Color(red: 0.30, green: 0.85, blue: 0.65),  // Vibrant Mint Green
            Color(red: 0.20, green: 0.68, blue: 0.78),  // Soft Ocean Teal
            Color(.systemBackground),
            Color(red: 0.12, green: 0.50, blue: 0.72),  // Deep Aqua Blue
            Color(.systemBackground),
            Color(red: 0.22, green: 0.75, blue: 0.38),  // Fresh Spinach Green
            Color(red: 0.20, green: 0.68, blue: 0.78),  // Soft Ocean Teal
            Color(red: 0.30, green: 0.85, blue: 0.65)   // Vibrant Mint Green
        ]
    }

    private var darkNatureColors: [Color] {
        [
            Color(red: 0.05, green: 0.30, blue: 0.15),  // Deep Forest Green
            Color(red: 0.10, green: 0.45, blue: 0.25),  // Herbal Green
            Color(red: 0.08, green: 0.40, blue: 0.50),  // Dark Teal Green
            Color(.systemBackground),
            Color(red: 0.06, green: 0.35, blue: 0.60),  // Muted Ocean Blue
            Color(.systemBackground),
            Color(red: 0.10, green: 0.45, blue: 0.25),  // Herbal Green
            Color(red: 0.08, green: 0.40, blue: 0.50),  // Dark Teal Green
            Color(red: 0.06, green: 0.35, blue: 0.60)   // Muted Ocean Blue
        ]
    }

    private var lightForestColors: [Color] {
        [
            Color(red: 0.22, green: 0.75, blue: 0.38),  // Fresh Spinach Green
            Color(red: 0.36, green: 0.88, blue: 0.62),  // Soft Lime Green
            Color(red: 0.92, green: 0.72, blue: 0.28),  // Gentle Golden Yellow
            Color(.systemBackground),
            Color(red: 0.16, green: 0.55, blue: 0.65),  // Muted Aqua Teal
            Color(.systemBackground),
            Color(red: 0.36, green: 0.88, blue: 0.62),  // Soft Lime Green
            Color(red: 0.92, green: 0.72, blue: 0.28),  // Gentle Golden Yellow
            Color(red: 0.16, green: 0.55, blue: 0.65)   // Muted Aqua Teal
        ]
    }

    private var darkForestColors: [Color] {
        [
            Color(red: 0.07, green: 0.35, blue: 0.18),  // Dark Jungle Green
            Color(red: 0.12, green: 0.50, blue: 0.28),  // Vibrant Herbal Green
            Color(red: 0.76, green: 0.52, blue: 0.16),  // Deep Amber Gold
            Color(.systemBackground),
            Color(red: 0.10, green: 0.42, blue: 0.50),  // Muted Blue-Green Ocean
            Color(.systemBackground),
            Color(red: 0.12, green: 0.50, blue: 0.28),  // Vibrant Herbal Green
            Color(red: 0.76, green: 0.52, blue: 0.16),  // Deep Amber Gold
            Color(red: 0.10, green: 0.42, blue: 0.50)   // Muted Blue-Green Ocean
        ]
    }

}

struct MeshGradientView: View {
    let lightColors: [Color]
    let darkColors: [Color]
    @Binding var animationPhase: Double
    @Environment(\.colorScheme) var colorScheme
    
    init(colors: [Color], darkColors: [Color], animationPhase: Binding<Double>) {
        self.lightColors = colors
        self.darkColors = darkColors
        self._animationPhase = animationPhase
    }
    
    var body: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
            ],
            colors: colorScheme == .dark ? darkColors : lightColors
        )
        .ignoresSafeArea()
        .hueRotation(.degrees(animationPhase))
    }
}
