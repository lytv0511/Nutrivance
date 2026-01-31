// WaterWidget.swift

import WidgetKit
import SwiftUI

struct WaterWidgetEntryView : View {
    var entry: Provider.Entry

    var body: some View {
        VStack {
            Text("Water Intake Today")
                .font(.headline)
            
            // Display current water intake
            Text("\(entry.waterIntake) cups")
                .font(.largeTitle)
                .bold()
            
            // Button to add water cup, linked to AddCupIntent
            Button(intent: AddCupIntent()) {
                Label("Add Cup", systemImage: "plus.circle.fill")
                    .font(.body)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
    }
}

struct WaterWidget: Widget {
    let kind: String = "WaterWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            WaterWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Water Intake Widget")
        .description("Tracks your daily water intake and lets you add more cups.")
        .supportedFamilies([.systemSmall, .systemMedium]) // Adjust sizes as needed
    }
}

// WaterWidget.swift continued

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), waterIntake: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        let entry = SimpleEntry(date: Date(), waterIntake: UserDefaults.standard.integer(forKey: "dailyWaterIntake"))
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let waterIntake = UserDefaults.standard.integer(forKey: "dailyWaterIntake")
        let entry = SimpleEntry(date: Date(), waterIntake: waterIntake)
        
        // Refresh every 15 minutes
        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60)))
        completion(timeline)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let waterIntake: Int
}
