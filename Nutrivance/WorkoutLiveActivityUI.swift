import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Lock Screen Live Activity View

struct WorkoutLiveActivityView: View {
    let context: ActivityViewContext<WorkoutLiveActivityAttributes>
    
    @Environment(\.isLuminanceReduced) var isLuminanceReduced
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header with workout type and elapsed time
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: context.attributes.activityIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(context.attributes.workoutType)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
                
                Spacer()
                
                Text(context.state.formattedElapsedTime)
                    .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
            }
            
            // Metrics grid
            HStack(spacing: 12) {
                MetricBox(
                    label: "HR",
                    value: "\(context.state.currentHeartRate)",
                    unit: "bpm",
                    zone: context.state.currentHeartRateZone
                )
                
                MetricBox(
                    label: "DIST",
                    value: String(format: "%.1f", context.state.totalDistanceKilometers),
                    unit: "km"
                )
                
                MetricBox(
                    label: "KCAL",
                    value: "\(Int(context.state.totalCalories))",
                    unit: ""
                )
                
                if let pace = context.state.formattedPace {
                    MetricBox(
                        label: "PACE",
                        value: pace,
                        unit: "min/km"
                    )
                }
            }
            
            // Optional: Phase information
            if let phaseTitle = context.state.activePhaseTitle {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CURRENT")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    Text(phaseTitle)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.black.opacity(0.8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Metric Display Box

private struct MetricBox: View {
    let label: String
    let value: String
    let unit: String
    var zone: Int? = nil
    
    var zoneColor: Color {
        guard let zone = zone else { return .gray }
        switch zone {
        case 1: return .blue
        case 2: return .green
        case 3: return .yellow
        case 4: return .orange
        case 5: return .red
        default: return .gray
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                
                if zone != nil {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 4))
                        .foregroundStyle(zoneColor)
                }
            }
            
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.06))
        )
    }
}

// MARK: - Widget Bundle

struct WorkoutLiveActivityWidgets: WidgetBundle {
    var body: some Widget {
        WorkoutActivityLiveActivity()
    }
}

// MARK: - Live Activity Widget

struct WorkoutActivityLiveActivity: Widget {
    let kind: String = "WorkoutActivityLiveActivity"
    
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutLiveActivityAttributes.self) { context in
            WorkoutLiveActivityView(context: context)
                .ignoresSafeArea()
        } dynamicIsland: { context in
            DynamicIsland {
                // MARK: - Expanded View
                DynamicIslandExpandedRegion(.leading) {
                    leadingExpandedView(context)
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    trailingExpandedView(context)
                }
                
                DynamicIslandExpandedRegion(.center) {
                    centerExpandedView(context)
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    bottomExpandedView(context)
                }
            } compactLeading: {
                Image(systemName: context.attributes.activityIcon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            } compactTrailing: {
                Text(context.state.formattedElapsedTime)
                    .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
            } minimal: {
                Image(systemName: context.attributes.activityIcon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }
    
    private func leadingExpandedView(_ context: ActivityViewContext<WorkoutLiveActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(context.attributes.workoutType)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
            
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                Text("\(context.state.currentHeartRate)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }
    
    private func trailingExpandedView(_ context: ActivityViewContext<WorkoutLiveActivityAttributes>) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            Text(context.state.formattedElapsedTime)
                .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
            
            HStack(spacing: 4) {
                Text("\(Int(context.state.totalCalories))")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                Image(systemName: "flame.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
        }
    }
    
    private func centerExpandedView(_ context: ActivityViewContext<WorkoutLiveActivityAttributes>) -> some View {
        VStack(spacing: 4) {
            Text(context.state.formattedDistance)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
            
            if let pace = context.state.formattedPace {
                Text("Pace: \(pace)/km")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
    
    private func bottomExpandedView(_ context: ActivityViewContext<WorkoutLiveActivityAttributes>) -> some View {
        HStack(spacing: 12) {
            Label(context.state.formattedDistance, systemImage: "location.fill")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.8))
            
            Divider()
            
            Label("\(context.state.elevationGainMeters)m", systemImage: "mountain.2.fill")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.8))
            
            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    let attributes = WorkoutLiveActivityAttributes(
        workoutType: "Running",
        activityIcon: "figure.walk",
        startTime: Date(),
        targetMinutes: 30,
        userInitials: "VL",
        maxHeartRate: 180
    )
    
    let state = WorkoutActivityState(
        elapsedSeconds: 547,
        currentHeartRate: 158,
        totalCalories: 581,
        totalDistanceKilometers: 5.2,
        currentPaceMinutesPerKm: 1.75,
        elevationGainMeters: 42,
        currentHeartRateZone: 4,
        activePhaseTitle: "Build Phase"
    )
    
    return WorkoutActivityLiveActivity()
        .previewContext(
            .init(
                attributes: attributes,
                state: state,
                isStale: false
            )
        )
}
