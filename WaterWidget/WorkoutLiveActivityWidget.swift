
import ActivityKit
import WidgetKit
import SwiftUI

struct WorkoutLiveActivityView: View {
    let context: ActivityViewContext<WorkoutLiveActivityAttributes>
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Label(context.attributes.workoutType, systemImage: context.attributes.activityIcon)
                    .font(.headline)
                
                Spacer()
                
                Text(context.state.formattedElapsedTime)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            
            HStack(spacing: 20) {
                metricView(value: "\(context.state.currentHeartRate)", unit: "BPM", color: .red)
                metricView(value: context.state.formattedDistance, unit: "", color: .green)
                metricView(value: "\(Int(context.state.totalCalories))", unit: "CAL", color: .orange)
            }
            
            if let phase = context.state.activePhaseTitle {
                Text(phase)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

private func metricView(value: String, unit: String, color: Color) -> some View {
    VStack(spacing: 2) {
        Text(value)
            .font(.system(size: 20, weight: .bold, design: .rounded))
        
        if !unit.isEmpty {
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
    .frame(maxWidth: .infinity)
}

struct WorkoutActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutLiveActivityAttributes.self) { context in
            WorkoutLiveActivityView(context: context)
                .widgetURL(URL(string: "nutrivance://liveworkout"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading) {
                        Text("HR")
                            .font(.caption2)
                        Text("\(context.state.currentHeartRate)")
                            .font(.title2.bold())
                            .foregroundStyle(.red)
                    }
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing) {
                        Text("TIME")
                            .font(.caption2)
                        Text(context.state.formattedElapsedTime)
                            .font(.headline.monospacedDigit())
                    }
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.formattedDistance)
                        Spacer()
                        Text("\(Int(context.state.totalCalories)) CAL")
                    }
                    .font(.subheadline)
                }
                
            } compactLeading: {
                Text("❤️")
            } compactTrailing: {
                Text("\(context.state.currentHeartRate)")
                    .font(.caption2)
            } minimal: {
                Text("🏃")
            }
        }
    }
}
