import SwiftUI

struct GradientBackgrounds {
    func warmGradientFull(animationPhase: Binding<Double>) -> some View {
        MeshGradientView(colors: lightWarmColors, darkColors: darkWarmColors, animationPhase: animationPhase)
    }
    
    func naturalGradientFull(animationPhase: Binding<Double>) -> some View {
        MeshGradientView(colors: lightNaturalColors, darkColors: darkNaturalColors, animationPhase: animationPhase)
    }
    
    func boldGradientFull(animationPhase: Binding<Double>) -> some View {
        MeshGradientView(colors: lightBoldColors, darkColors: darkBoldColors, animationPhase: animationPhase)
    }
    
    func spiritGradientFull(animationPhase: Binding<Double>) -> some View {
        MeshGradientView(colors: lightSpiritColors, darkColors: darkSpiritColors, animationPhase: animationPhase)
    }
    
    func burningGradientFull(animationPhase: Binding<Double>) -> some View {
        MeshGradientView(colors: lightBurningColors, darkColors: darkBurningColors, animationPhase: animationPhase)
    }
    
    func natureGradientFull(animationPhase: Binding<Double>) -> some View {
        MeshGradientView(colors: lightNatureColors, darkColors: darkNatureColors, animationPhase: animationPhase)
    }

    func forestGradientFull(animationPhase: Binding<Double>) -> some View {
        MeshGradientView(colors: lightForestColors, darkColors: darkForestColors, animationPhase: animationPhase)
    }
    
    func realmGradientFull(animationPhase: Binding<Double>) -> some View {
        let phase = animationPhase.wrappedValue * 0.3
        
        let spiral = { (i: Int) -> SIMD2<Float> in
            let row = Float(i / 6) / 5.0
            let col = Float(i % 6) / 5.0
            let centerDist = sqrt(pow(row - 0.5, 2) + pow(col - 0.5, 2))
            let angle = phase + Double(i) * 0.2
            let radius = 0.2 * (1 - Float(centerDist))
            return SIMD2<Float>(
                col + radius * Float(cos(angle)),
                row + radius * Float(sin(angle))
            )
        }
        
        let vortex = { (i: Int) -> SIMD2<Float> in
            let row = Float(i / 6) / 5.0
            let col = Float(i % 6) / 5.0
            let angle = atan2(row - 0.5, col - 0.5)
            let dist = sqrt(pow(row - 0.5, 2) + pow(col - 0.5, 2))
            return SIMD2<Float>(
                col + 0.15 * Float(cos(Double(angle) + phase)) * dist,
                row + 0.15 * Float(sin(Double(angle) + phase)) * dist
            )
        }
        
        let swirl = { (i: Int) -> SIMD2<Float> in
            let row = Float(i / 6) / 5.0
            let col = Float(i % 6) / 5.0
            let angle = phase * 2 + Double(i) * 0.1
            let radius = 0.15 * Float(sin(phase * 0.5))
            return SIMD2<Float>(
                col + radius * Float(cos(angle)) * (col - 0.5),
                row + radius * Float(sin(angle)) * (row - 0.5)
            )
        }
        
        let ripple = { (i: Int) -> SIMD2<Float> in
            let row = Float(i / 6) / 5.0
            let col = Float(i % 6) / 5.0
            let centerDist = sqrt(pow(row - 0.5, 2) + pow(col - 0.5, 2))
            let angle = atan2(row - 0.5, col - 0.5) + Float(phase)
            let wave = 0.15 * Float(sin(phase - Double(centerDist) * 8))
            return SIMD2<Float>(
                col + wave * Float(cos(Double(angle))),
                row + wave * Float(sin(Double(angle)))
            )
        }
        
        return ZStack {
            MeshGradient(
                width: 6, height: 6,
                points: Array((0...35).map(spiral)),
                colors: Array(repeating: darkSpiritColors, count: 4).flatMap { $0 }
            )
            .opacity(0.5)
            
            MeshGradient(
                width: 6, height: 6,
                points: Array((0...35).map(vortex)),
                colors: Array(repeating: darkSpiritColors.reversed(), count: 4).flatMap { $0 }
            )
            .opacity(0.5)
            
            MeshGradient(
                width: 6, height: 6,
                points: Array((0...35).map(swirl)),
                colors: Array(repeating: darkSpiritColors, count: 4).flatMap { $0 }
            )
            .opacity(0.5)
            
            MeshGradient(
                width: 6, height: 6,
                points: Array((0...35).map(ripple)),
                colors: Array(repeating: darkSpiritColors, count: 4).flatMap { $0 }
            )
            .opacity(0.9)
        }
        .ignoresSafeArea()
    }
    
    func sleepGradientFull(animationPhase: Binding<Double>) -> some View {
        MeshGradientView(colors: lightSleepColors, darkColors: darkSleepColors, animationPhase: animationPhase)
    }
    
    func warmGradient(animationPhase: Binding<Double>) -> some View {
        ZStack {
            warmGradientFull(animationPhase: animationPhase)
            GradientFadeOverlay()
        }
    }
    
    func naturalGradient(animationPhase: Binding<Double>) -> some View {
        ZStack {
            naturalGradientFull(animationPhase: animationPhase)
            GradientFadeOverlay()
        }
    }
    
    func boldGradient(animationPhase: Binding<Double>) -> some View {
        ZStack {
            boldGradientFull(animationPhase: animationPhase)
            GradientFadeOverlay()
        }
    }
    
    func spiritGradient(animationPhase: Binding<Double>) -> some View {
        ZStack {
            spiritGradientFull(animationPhase: animationPhase)
            GradientFadeOverlay()
        }
    }
    
    func burningGradient(animationPhase: Binding<Double>) -> some View {
        ZStack {
            burningGradientFull(animationPhase: animationPhase)
            GradientFadeOverlay()
        }
    }
    
    func natureGradient(animationPhase: Binding<Double>) -> some View {
        ZStack {
            natureGradientFull(animationPhase: animationPhase)
            GradientFadeOverlay()
        }
    }
    
    func forestGradient(animationPhase: Binding<Double>) -> some View {
        ZStack {
            forestGradientFull(animationPhase: animationPhase)
            GradientFadeOverlay()
        }
    }
    
    func realmGradient(animationPhase: Binding<Double>) -> some View {
        ZStack {
            realmGradientFull(animationPhase: animationPhase)
            GradientFadeOverlay()
        }
    }
    
    func sleepGradient(animationPhase: Binding<Double>) -> some View {
        ZStack {
            sleepGradientFull(animationPhase: animationPhase)
            GradientFadeOverlay()
        }
    }

    func programBuilderGradientFull(animationPhase: Binding<Double>) -> some View {
        MeshGradientView(colors: lightProgramBuilderColors, darkColors: darkProgramBuilderColors, animationPhase: animationPhase)
    }

    func programBuilderGradient(animationPhase: Binding<Double>) -> some View {
        ZStack {
            programBuilderGradientFull(animationPhase: animationPhase)
            GradientFadeOverlay()
        }
    }

    func kineticPulseGradientFull(animationPhase: Binding<Double>) -> some View {
        MeshGradientView(colors: kineticPulseColors, darkColors: darkKineticPulseColors, animationPhase: animationPhase)
    }

    func kineticPulseGradient(animationPhase: Binding<Double>) -> some View {
        ZStack {
            kineticPulseGradientFull(animationPhase: animationPhase)
            GradientFadeOverlay()
        }
    }

    func oxygenFlowGradientFull(animationPhase: Binding<Double>) -> some View {
        MeshGradientView(colors: oxygenFlowColors, darkColors: darkOxygenFlowColors, animationPhase: animationPhase)
    }

    func oxygenFlowGradient(animationPhase: Binding<Double>) -> some View {
        ZStack {
            oxygenFlowGradientFull(animationPhase: animationPhase)
            GradientFadeOverlay()
        }
    }

    func solarFlareGradientFull(animationPhase: Binding<Double>) -> some View {
        MeshGradientView(colors: solarFlareColors, darkColors: darkSolarFlareColors, animationPhase: animationPhase)
    }

    func solarFlareGradient(animationPhase: Binding<Double>) -> some View {
        ZStack {
            solarFlareGradientFull(animationPhase: animationPhase)
            GradientFadeOverlay()
        }
    }

    /// Light-mode mesh stops: scaled ~14%; “rest” cells use faint theme tints — no flat white / paper gray blow-outs.
    private enum LightMesh {
        static let scale: Double = 0.86

        static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
            Color(red: r * scale, green: g * scale, blue: b * scale)
        }
    }

    private var lightWarmColors: [Color] {
        [
//            Color(.systemBackground),
            LightMesh.rgb(1.0, 0.4, 0.0),  // Vibrant orange
            LightMesh.rgb(0.9, 0.3, 0.0),  // Deep orange
            LightMesh.rgb(0.8, 0.2, 0.0),  // Orange-red
//            Color(.systemBackground),
            LightMesh.rgb(1.0, 0.5, 0.1),  // Bright orange
            LightMesh.rgb(0.95, 0.6, 0.2), // Golden orange
            LightMesh.rgb(0.85, 0.25, 0.0), // Rich orange-red
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
            LightMesh.rgb(0.86, 0.92, 0.90),  // faint sky / leaf mist
            LightMesh.rgb(0.2, 0.8, 0.2),
            LightMesh.rgb(0.0, 0.0, 0.8),
            LightMesh.rgb(0.1, 0.7, 0.3),
            LightMesh.rgb(0.84, 0.90, 0.93),  // faint blue-green haze
            LightMesh.rgb(0.0, 0.6, 0.9),
            LightMesh.rgb(0.0, 0.8, 0.4),
            LightMesh.rgb(0.1, 0.9, 0.2),
            LightMesh.rgb(0.86, 0.92, 0.90)
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
            LightMesh.rgb(0.2, 0.0, 0.45),
            LightMesh.rgb(0.4, 0.0, 0.0),
            LightMesh.rgb(0.88, 0.82, 0.90),  // faint plum / wine mist
            LightMesh.rgb(0.25, 0.0, 0.5),
            LightMesh.rgb(0.90, 0.84, 0.88),  // faint mauve
            LightMesh.rgb(0.5, 0.0, 0.0),
            LightMesh.rgb(0.86, 0.80, 0.90),
            LightMesh.rgb(0.3, 0.0, 0.4),
            LightMesh.rgb(0.45, 0.0, 0.0)
        ]
    }

    private var darkBoldColors: [Color] {
        [
            Color(red: 0.1, green: 0.0, blue: 0.225),
            Color(red: 0.2, green: 0.0, blue: 0.0),
            .black,
            Color(red: 0.125, green: 0.0, blue: 0.25),
            .black,
            Color(red: 0.25, green: 0.0, blue: 0.0),
            .black,
            Color(red: 0.15, green: 0.0, blue: 0.2),
            Color(red: 0.225, green: 0.0, blue: 0.0)
        ]
    }
    
    private var lightSpiritColors: [Color] {
        [
            LightMesh.rgb(0.66, 0.86, 0.86),  // Soft Sky Blue
            LightMesh.rgb(0.94, 0.76, 0.62),   // Warm Peach (softer peak)
            LightMesh.rgb(0.80, 0.91, 0.85),  // Pastel Mint Green
            LightMesh.rgb(0.82, 0.78, 0.88),   // faint lavender haze
            LightMesh.rgb(0.84, 0.76, 0.88),  // Muted Lavender
            LightMesh.rgb(0.80, 0.84, 0.90),   // faint sky–lavender
            LightMesh.rgb(0.66, 0.86, 0.86),  // Soft Sky Blue
            LightMesh.rgb(0.94, 0.76, 0.62),   // Warm Peach
            LightMesh.rgb(0.80, 0.91, 0.85)   // Pastel Mint Green
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
            LightMesh.rgb(1.0, 0.55, 0.0),   // Fiery Orange
            LightMesh.rgb(1.0, 0.27, 0.0),   // Intense Red
            LightMesh.rgb(1.0, 0.75, 0.2),   // Bright Gold
            LightMesh.rgb(0.92, 0.82, 0.76),   // faint ember / sand
            LightMesh.rgb(0.96, 0.43, 0.26), // Ember Coral
            LightMesh.rgb(0.90, 0.78, 0.72),   // faint coral wash
            LightMesh.rgb(1.0, 0.55, 0.0),   // Fiery Orange
            LightMesh.rgb(1.0, 0.27, 0.0),   // Intense Red
            LightMesh.rgb(1.0, 0.75, 0.2)    // Bright Gold
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
            LightMesh.rgb(0.18, 0.72, 0.40),  // Rich Leaf Green
            LightMesh.rgb(0.30, 0.85, 0.65),  // Vibrant Mint Green
            LightMesh.rgb(0.20, 0.68, 0.78),  // Soft Ocean Teal
            LightMesh.rgb(0.80, 0.90, 0.86),   // faint sage / sea glass
            LightMesh.rgb(0.12, 0.50, 0.72),  // Deep Aqua Blue
            LightMesh.rgb(0.78, 0.88, 0.90),   // faint teal mist
            LightMesh.rgb(0.22, 0.75, 0.38),  // Fresh Spinach Green
            LightMesh.rgb(0.20, 0.68, 0.78),  // Soft Ocean Teal
            LightMesh.rgb(0.30, 0.85, 0.65)   // Vibrant Mint Green
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
            LightMesh.rgb(0.22, 0.75, 0.38),  // Fresh Spinach Green
            LightMesh.rgb(0.36, 0.88, 0.62),  // Soft Lime Green
            LightMesh.rgb(0.92, 0.72, 0.28),  // Gentle Golden Yellow
            LightMesh.rgb(0.86, 0.90, 0.80),   // faint spring canopy
            LightMesh.rgb(0.16, 0.55, 0.65),  // Muted Aqua Teal
            LightMesh.rgb(0.84, 0.88, 0.82),   // faint lime–gold haze
            LightMesh.rgb(0.36, 0.88, 0.62),  // Soft Lime Green
            LightMesh.rgb(0.92, 0.72, 0.28),  // Gentle Golden Yellow
            LightMesh.rgb(0.16, 0.55, 0.65)   // Muted Aqua Teal
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

    private var lightSleepColors: [Color] {
        [
            LightMesh.rgb(0.25, 0.12, 0.40),  // Deep Purple
            LightMesh.rgb(0.15, 0.08, 0.25),  // Very Dark Purple
            LightMesh.rgb(0.05, 0.03, 0.15),  // Lighter Dark Blue
            LightMesh.rgb(0.72, 0.68, 0.82),   // faint dusk violet (not paper)
            LightMesh.rgb(0.25, 0.12, 0.40),  // Deep Purple
            LightMesh.rgb(0.15, 0.08, 0.25),  // Very Dark Purple
            LightMesh.rgb(0.05, 0.03, 0.15),  // Lighter Dark Blue
            LightMesh.rgb(0.70, 0.66, 0.80),   // faint indigo veil
            LightMesh.rgb(0.25, 0.12, 0.40),  // Deep Purple (3×3 mesh)
        ]
    }

    private var darkSleepColors: [Color] {
        [
            Color(red: 0.12, green: 0.05, blue: 0.20),  // Very Dark Purple
            Color(red: 0.08, green: 0.03, blue: 0.13),  // Almost Black Purple
            Color(red: 0.80, green: 0.75, blue: 0.40),  // Golden Pale Yellow
            Color(red: 0.95, green: 0.90, blue: 0.80),  // Faded Beige
            Color(.systemBackground),
            Color(red: 0.12, green: 0.05, blue: 0.20),  // Very Dark Purple
            Color(red: 0.08, green: 0.03, blue: 0.13),  // Almost Black Purple
            Color(red: 0.80, green: 0.75, blue: 0.40),  // Golden Pale Yellow
            Color(red: 0.95, green: 0.90, blue: 0.80),  // Faded Beige
        ]
    }
    
    // Derived from Program Builder palette:
    // Dark mode: (0.07,0.06,0.05) → (0.20,0.09,0.04) → (0.06,0.12,0.10)
    // Light mode: softly lifted versions of the same hues.
    private var lightProgramBuilderColors: [Color] {
        [
            LightMesh.rgb(0.90, 0.88, 0.86),
            LightMesh.rgb(0.92, 0.86, 0.82),
            LightMesh.rgb(0.84, 0.90, 0.88),
            LightMesh.rgb(0.82, 0.80, 0.78),   // faint warm stone (wood/tea hint)
            LightMesh.rgb(0.88, 0.86, 0.84),
            LightMesh.rgb(0.80, 0.82, 0.80),   // faint sage stone
            LightMesh.rgb(0.92, 0.86, 0.82),
            LightMesh.rgb(0.84, 0.90, 0.88),
            LightMesh.rgb(0.90, 0.88, 0.86)
        ]
    }

    private var darkProgramBuilderColors: [Color] {
        [
            Color(red: 0.07, green: 0.06, blue: 0.05),
            Color(red: 0.20, green: 0.09, blue: 0.04),
            Color(red: 0.06, green: 0.12, blue: 0.10),
            Color(.systemBackground),
            Color(red: 0.07, green: 0.06, blue: 0.05),
            Color(.systemBackground),
            Color(red: 0.20, green: 0.09, blue: 0.04),
            Color(red: 0.06, green: 0.12, blue: 0.10),
            Color(red: 0.07, green: 0.06, blue: 0.05)
        ]
    }

    /// 3×3 mesh — pads to nine stops (same hues as the seven-stop palette).
    private var kineticPulseColors: [Color] {
        [
            LightMesh.rgb(0.1, 0.02, 0.2),  // Deep Midnight Purple
            LightMesh.rgb(0.5, 0.1, 0.9),   // Electric Violet
            LightMesh.rgb(0.9, 0.2, 0.6),   // Neon Magenta
            LightMesh.rgb(0.78, 0.74, 0.90),   // faint violet–magenta mist
            LightMesh.rgb(0.2, 0.6, 1.0),   // Oxygen Blue
            LightMesh.rgb(0.76, 0.82, 0.94),   // faint periwinkle
            LightMesh.rgb(0.5, 0.1, 0.9),    // Electric Violet
            LightMesh.rgb(0.9, 0.2, 0.6),   // Neon Magenta
            LightMesh.rgb(0.2, 0.6, 1.0)   // Oxygen Blue
        ]
    }

    private var darkKineticPulseColors: [Color] {
        [
            Color(red: 0.05, green: 0.01, blue: 0.1),
            Color(red: 0.25, green: 0.05, blue: 0.45),
            Color(red: 0.45, green: 0.1, blue: 0.3),
            Color(.systemBackground),
            Color(red: 0.1, green: 0.3, blue: 0.5),
            Color(.systemBackground),
            Color(red: 0.25, green: 0.05, blue: 0.45),
            Color(red: 0.45, green: 0.1, blue: 0.3),
            Color(red: 0.1, green: 0.3, blue: 0.5)
        ]
    }

    private var oxygenFlowColors: [Color] {
        [
            LightMesh.rgb(0.0, 0.15, 0.15), // Deep Teal Abyss
            LightMesh.rgb(0.0, 0.5, 0.6),   // Oxidized Cyan
            LightMesh.rgb(0.8, 0.1, 0.2),   // Arterial Red
            LightMesh.rgb(0.76, 0.86, 0.88),   // faint teal pool
            LightMesh.rgb(0.4, 0.05, 0.1),  // Deep Venous Maroon
            LightMesh.rgb(0.82, 0.78, 0.80),   // faint maroon–teal haze
            LightMesh.rgb(0.0, 0.5, 0.6),    // Oxidized Cyan
            LightMesh.rgb(0.8, 0.1, 0.2),   // Arterial Red
            LightMesh.rgb(0.0, 0.5, 0.6)    // Oxidized Cyan
        ]
    }

    private var darkOxygenFlowColors: [Color] {
        [
            Color(red: 0.0, green: 0.08, blue: 0.08),
            Color(red: 0.0, green: 0.28, blue: 0.34),
            Color(red: 0.45, green: 0.06, blue: 0.12),
            Color(.systemBackground),
            Color(red: 0.22, green: 0.03, blue: 0.06),
            Color(.systemBackground),
            Color(red: 0.0, green: 0.28, blue: 0.34),
            Color(red: 0.45, green: 0.06, blue: 0.12),
            Color(red: 0.0, green: 0.28, blue: 0.34)
        ]
    }

    private var solarFlareColors: [Color] {
        [
            LightMesh.rgb(0.05, 0.02, 0.1), // Deep Space Indigo (Contrast)
            LightMesh.rgb(0.95, 0.2, 0.1),  // Hyper-Red
            LightMesh.rgb(1.0, 0.7, 0.0),   // Vivid Amber
            LightMesh.rgb(0.88, 0.82, 0.76),   // faint warm ash (ember)
            LightMesh.rgb(0.88, 0.78, 0.42),   // solar gold (softer than paper-white)
            LightMesh.rgb(0.90, 0.84, 0.78),   // faint amber cream
            LightMesh.rgb(0.95, 0.2, 0.1),   // Hyper-Red
            LightMesh.rgb(1.0, 0.7, 0.0),   // Vivid Amber
            LightMesh.rgb(0.88, 0.78, 0.42)   // Solar gold
        ]
    }

    private var darkSolarFlareColors: [Color] {
        [
            Color(red: 0.03, green: 0.01, blue: 0.05),
            Color(red: 0.5, green: 0.1, blue: 0.05),
            Color(red: 0.55, green: 0.38, blue: 0.0),
            Color(.systemBackground),
            Color(red: 0.55, green: 0.5, blue: 0.22),
            Color(.systemBackground),
            Color(red: 0.5, green: 0.1, blue: 0.05),
            Color(red: 0.55, green: 0.38, blue: 0.0),
            Color(red: 0.55, green: 0.5, blue: 0.22)
        ]
    }

    private var lightHealingColors: [Color] {
        [
            LightMesh.rgb(0.78, 0.90, 0.86),  // Soft Mint (no chalk white)
            LightMesh.rgb(0.70, 0.86, 0.82),  // Light Teal
            LightMesh.rgb(0.80, 0.90, 0.88),  // muted spa cyan
            LightMesh.rgb(0.76, 0.86, 0.84),   // faint eucalyptus haze
            LightMesh.rgb(0.72, 0.88, 0.86),  // Pale Blue-Green
            LightMesh.rgb(0.74, 0.84, 0.82),   // faint sea-mint veil
            LightMesh.rgb(0.78, 0.90, 0.86),  // Soft Mint
            LightMesh.rgb(0.70, 0.86, 0.82),  // Light Teal
            LightMesh.rgb(0.80, 0.90, 0.88)   // muted spa cyan
        ]
    }

    private var darkHealingColors: [Color] {
        [
            Color(red: 0.20, green: 0.50, blue: 0.45),  // Medium Teal
            Color(red: 0.15, green: 0.45, blue: 0.42),  // Muted Teal
            Color(red: 0.25, green: 0.60, blue: 0.55),  // Soft Blue-Green
            Color(.systemBackground),
            Color(red: 0.18, green: 0.52, blue: 0.48),  // Calm Teal
            Color(.systemBackground),
            Color(red: 0.20, green: 0.50, blue: 0.45),  // Medium Teal
            Color(red: 0.15, green: 0.45, blue: 0.42),  // Muted Teal
            Color(red: 0.25, green: 0.60, blue: 0.55)   // Soft Blue-Green
        ]
    }
    
    func healingGradientFull(animationPhase: Binding<Double>) -> some View {
        MeshGradientView(colors: lightHealingColors, darkColors: darkHealingColors, animationPhase: animationPhase)
    }
    
    func healingGradient(animationPhase: Binding<Double>) -> some View {
        ZStack {
            healingGradientFull(animationPhase: animationPhase)
            GradientFadeOverlay()
        }
    }
}

struct MovingProgramBuilderBackground: View {
    @State private var animationPhase: Double = 0

    var body: some View {
        GradientBackgrounds()
            .programBuilderGradient(animationPhase: $animationPhase)
            .onAppear {
                withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                    animationPhase = 20
                }
            }
    }
}

struct MeshGradientView: View {
    let lightColors: [Color]
    let darkColors: [Color]
    @Binding var animationPhase: Double
    @Environment(\.colorScheme) var colorScheme
    
    init(colors: [Color], darkColors: [Color], animationPhase: Binding<Double>) {
        // Darken light mode colors by 20%
        self.lightColors = colors.map { color in
            color.opacity(1)
        }
        // Darken dark mode colors by 30%
        self.darkColors = darkColors.map { color in
            color.opacity(0.7)
        }
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

struct GradientFadeOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Top 10% - completely transparent
                Color(.systemBackground)
                    .opacity(0)
                    .frame(height: geometry.size.height * 0.05)
                
                // Middle 30% - gradual fade
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color(.systemBackground).opacity(0), location: 0),
                        .init(color: Color(.systemBackground).opacity(0.2), location: 0.2),
                        .init(color: Color(.systemBackground).opacity(0.4), location: 0.4),
                        .init(color: Color(.systemBackground).opacity(0.6), location: 0.6),
                        .init(color: Color(.systemBackground).opacity(0.8), location: 0.8),
                        .init(color: Color(.systemBackground), location: 1.0)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: geometry.size.height * 0.35)
                
                // Bottom 60% - full opacity
                Color(.systemBackground)
                    .frame(height: geometry.size.height * 0.60)
            }
        }
        .ignoresSafeArea()
    }
}
