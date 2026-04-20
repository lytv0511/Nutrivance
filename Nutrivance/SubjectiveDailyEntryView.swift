import SwiftUI

/// Daily subjective data collection prompt: soreness, stress, sleep quality 1-10 ratings.
/// Optional view shown on Recovery/Readiness tabs if enabled in PerformanceProfileSettings.
struct SubjectiveDailyEntryView: View {
    @State private var sorenessRating: Int = 5
    @State private var stressRating: Int = 5
    @State private var sleepQualityRating: Int = 5
    @State private var notes: String = ""
    @State private var showConfirmation = false
    
    let onSave: (() -> Void)? = nil
    let onCancel: (() -> Void)? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("How are you feeling?")
                    .font(.headline.weight(.bold))
                Text("Your answers help personalize recovery insights.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Soreness Rating
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Soreness")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(sorenessRating)/10")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                }
                
                Slider(value: Binding(
                    get: { Double(sorenessRating) },
                    set: { sorenessRating = Int($0) }
                ), in: 1...10, step: 1)
                .tint(.orange)
                
                HStack(spacing: 12) {
                    Text("1 = Fresh")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("10 = Extremely Sore")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Stress Rating
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Stress")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(stressRating)/10")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.red)
                }
                
                Slider(value: Binding(
                    get: { Double(stressRating) },
                    set: { stressRating = Int($0) }
                ), in: 1...10, step: 1)
                .tint(.red)
                
                HStack(spacing: 12) {
                    Text("1 = Calm")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("10 = Extremely Stressed")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Sleep Quality Rating (Independent of Duration)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Sleep Quality")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(sleepQualityRating)/10")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.indigo)
                }
                
                Slider(value: Binding(
                    get: { Double(sleepQualityRating) },
                    set: { sleepQualityRating = Int($0) }
                ), in: 1...10, step: 1)
                .tint(.indigo)
                
                HStack(spacing: 12) {
                    Text("1 = Restless")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("10 = Deep & Restorative")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Optional Notes
            VStack(alignment: .leading, spacing: 6) {
                Text("Notes (Optional)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                
                TextField("Any details? Illness, travel, etc.", text: $notes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3, reservesSpace: true)
                    .font(.caption)
            }
            
            // Buttons
            HStack(spacing: 12) {
                Button(role: .cancel) {
                    onCancel?()
                } label: {
                    Text("Cancel")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                
                Button {
                    saveEntry()
                } label: {
                    Text("Save Entry")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .alert("Entry Saved", isPresented: $showConfirmation) {
            Button("OK") {
                onSave?()
            }
        } message: {
            Text("Your daily entry has been saved and will influence your recovery calculations.")
        }
    }
    
    private func saveEntry() {
        let entry = SubjectiveDailyEntry(
            date: Date(),
            sorenessRating: sorenessRating,
            stressRating: stressRating,
            sleepQualityRating: sleepQualityRating,
            notes: notes.isEmpty ? nil : notes
        )
        
        SubjectiveDailyEntryManager.shared.saveEntry(entry)
        showConfirmation = true
    }
}

// MARK: - Compact Version (for inline display)

struct SubjectiveDailyEntryCompact: View {
    @State private var sorenessRating: Int = 5
    @State private var stressRating: Int = 5
    @State private var sleepQualityRating: Int = 5
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 12) {
            if !isExpanded {
                // Collapsed state: show quick summary
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Quick Check-In")
                            .font(.subheadline.weight(.semibold))
                        Text("Soreness • Stress • Sleep")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        ForEach([(sorenessRating, Color.orange), (stressRating, Color.red), (sleepQualityRating, Color.indigo)], id: \.0) { (rating, color) in
                            VStack(spacing: 2) {
                                Text("\(rating)")
                                    .font(.caption.weight(.bold))
                                Circle()
                                    .fill(color)
                                    .frame(width: 6, height: 6)
                            }
                        }
                    }
                }
                
                Button(action: { isExpanded = true }) {
                    Text("Expand")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                }
            } else {
                // Expanded state: show full entry form
                SubjectiveDailyEntryView(
                    onSave: { isExpanded = false },
                    onCancel: { isExpanded = false }
                )
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

#Preview {
    VStack(spacing: 20) {
        SubjectiveDailyEntryView()
            .padding()
        
        Divider()
        
        SubjectiveDailyEntryCompact()
            .padding()
    }
}
