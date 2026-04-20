import SwiftUI

/// Reusable info badge for pro-athlete optimizations.
/// Shows a compact badge with (i) icon that opens a popover explaining the override.
struct ProAthleteInfoBadge: View {
    let title: String
    let icon: String
    let tint: Color
    let rationale: String
    let impact: String
    let isActive: Bool
    var onDisable: (() -> Void)? = nil
    
    @State private var showPopover = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button {
                    showPopover = true
                } label: {
                    Image(systemName: "info.circle.fill")
                        .font(.caption)
                        .foregroundStyle(tint.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(tint.opacity(0.1))
                    .frame(width: 4)
                
                Text(impact)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
                
                Spacer()
                
                if isActive {
                    Text("ACTIVE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(tint)
                }
            }
        }
        .padding(12)
        .background(Color(UIColor.systemBackground).opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.2), lineWidth: 1)
        )
        .popover(isPresented: $showPopover) {
            ProAthleteInfoPopover(
                title: title,
                rationale: rationale,
                impact: impact,
                onDisable: onDisable
            )
            .frame(maxWidth: 320)
        }
    }
}

// MARK: - Popover Content

struct ProAthleteInfoPopover: View {
    let title: String
    let rationale: String
    let impact: String
    var onDisable: (() -> Void)? = nil
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.bold))
                HStack {
                    Spacer()
                    Button("Close") { dismiss() }
                        .font(.caption)
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Why This Matters")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    
                    Text(rationale)
                        .font(.caption)
                        .lineLimit(nil)
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Impact on Your Score")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    
                    Text(impact)
                        .font(.caption)
                        .lineLimit(nil)
                }
            }
            
            if let onDisable = onDisable {
                Button(role: .destructive) {
                    onDisable()
                    dismiss()
                } label: {
                    Text("Disable This Optimization")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            
            Spacer()
        }
        .padding(16)
    }
}

// MARK: - Badge Definitions

enum ProAthleteBadgeType {
    case strainSensitiveHRV
    case hrvBellCurve
    case sleepQualityLow
    case acwrOptimal
    case acwrDanger
    case taperDetected
    case asymmetricStrain
    
    var title: String {
        switch self {
        case .strainSensitiveHRV:
            return "Strain-Sensitive HRV"
        case .hrvBellCurve:
            return "HRV Bell-Curve Warning"
        case .sleepQualityLow:
            return "Sleep Quality Low"
        case .acwrOptimal:
            return "ACWR Optimal"
        case .acwrDanger:
            return "ACWR Danger Zone"
        case .taperDetected:
            return "Fresh but Flat"
        case .asymmetricStrain:
            return "Asymmetric Strain"
        }
    }
    
    var icon: String {
        switch self {
        case .strainSensitiveHRV:
            return "waveform.path.ecg"
        case .hrvBellCurve:
            return "exclamationmark.circle.fill"
        case .sleepQualityLow:
            return "moon.zzz.fill"
        case .acwrOptimal:
            return "checkmark.circle.fill"
        case .acwrDanger:
            return "xmark.circle.fill"
        case .taperDetected:
            return "figure.walk"
        case .asymmetricStrain:
            return "flame.fill"
        }
    }
    
    var tint: Color {
        switch self {
        case .strainSensitiveHRV:
            return .mint
        case .hrvBellCurve:
            return .red
        case .sleepQualityLow:
            return .orange
        case .acwrOptimal:
            return .green
        case .acwrDanger:
            return .red
        case .taperDetected:
            return .yellow
        case .asymmetricStrain:
            return .orange
        }
    }
    
    var rationale: String {
        switch self {
        case .strainSensitiveHRV:
            return "When your chronic load is in the top 20%, HRV drops first as an early warning sign of overreaching. We've boosted HRV's weight from 30% to 50% during high-load periods to catch this earlier."
        case .hrvBellCurve:
            return "Your Effect HRV is abnormally high (Z-score > 2.5). In elite athletes, parasympathetic hyperactivity can signal deep fatigue or smoldering overtraining, not peak recovery. This score is capped as a warning."
        case .sleepQualityLow:
            return "Your sleep duration is adequate, but the deep/REM balance or fragmentation suggests poor architecture. Quality sleep repairs neural and cardiovascular systems more effectively than duration alone."
        case .acwrOptimal:
            return "Your acute-to-chronic workload ratio (0.8–1.3) is in the sweet spot: you're adding new stimulus without over-scaling load. Readiness receives a +5 point bonus."
        case .acwrDanger:
            return "Your ACWR exceeds the danger threshold (>1.5). Acute load is outrunning your body's ability to absorb it. Readiness is penalized heavily, not just by the linear strain effect."
        case .taperDetected:
            return "Your acute load has dropped 40% below chronic, and recovery is high. You're in a taper phase. Readiness is capped at 88 to prevent over-ambition when you should be resting strategically."
        case .asymmetricStrain:
            return "At high strain levels, your readiness is multiplied by a strain-dependent factor, not just reduced by a flat penalty. This creates an exponential cost at extreme loads."
        }
    }
    
    var impact: String {
        switch self {
        case .strainSensitiveHRV:
            return "HRV weight increased to 50% (from 30%). This means HRV contributes more strongly to your recovery score during high-load phases."
        case .hrvBellCurve:
            return "Your score is capped below 100 to warn of potential deep fatigue despite high HRV. Consider investigating sleep quality, meditation, or active recovery."
        case .sleepQualityLow:
            return "Your base recovery is multiplied by 0.85–0.92, reducing the final score by up to 15 points depending on efficiency levels."
        case .acwrOptimal:
            return "+5 points added to readiness for maintaining an optimal load progression. This supports the adaptation process."
        case .acwrDanger:
            return "Up to –40 points subtracted from readiness. Your acute load is growing faster than your body can adapt. Consider reducing volume or intensity."
        case .taperDetected:
            return "Your readiness is capped at 88/100 despite high recovery. This prevents overconfidence during a planned taper and encourages strategic rest."
        case .asymmetricStrain:
            return "At 17/21 strain, readiness is multiplied by ~0.75 instead of just subtracting 25 points. The cost grows exponentially as strain increases."
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        ProAthleteInfoBadge(
            title: "Strain-Sensitive HRV",
            icon: "waveform.path.ecg",
            tint: .mint,
            rationale: "HRV drops first when athletes overreach.",
            impact: "HRV weight boosted to 50%.",
            isActive: true
        )
        
        ProAthleteInfoBadge(
            title: "HRV Bell-Curve Warning",
            icon: "exclamationmark.circle.fill",
            tint: .red,
            rationale: "Abnormally high HRV can signal fatigue.",
            impact: "Score capped below 100.",
            isActive: true
        )
    }
    .padding()
}
