import SwiftUI

struct HistoryView: View {
    @StateObject private var healthStore = HealthKitManager()
    @State private var selectedTimeFrame: TimeFrame = .daily
    @State private var entries: [HealthKitManager.NutritionEntry] = []
    @State private var selectedDate: Date = Date()
    @State private var showingFullList = false
    @State private var animationPhase: Double = 0
    
    enum TimeFrame {
        case daily, weekly, monthly, custom
    }
    
    // Break down the grouping logic
    private var groupedEntries: [Date: [HealthKitManager.NutritionEntry]] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: entries) { entry in
            calendar.startOfDay(for: entry.timestamp)
        }
        return groups
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                gradientBackground
                mainContent
            }
            .navigationTitle("Nutrition History")
            .sheet(isPresented: $showingFullList) {
                FullListView(
                    entries: groupedEntries,
                    deleteEntry: deleteEntry,
                    loadData: loadData
                )
            }
            .onAppear { loadData() }
            .onChange(of: selectedTimeFrame) { _, _ in loadData() }
            .onChange(of: selectedDate) { _, _ in loadData() }
        }
    }
    
    private var gradientBackground: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
            ],
            colors: [
                .black, Color(red: 0, green: 0.2, blue: 0), .black,
                Color(red: 0, green: 0, blue: 0.2),
                Color(red: 0, green: 0.1, blue: 0.1),
                Color(red: 0, green: 0.2, blue: 0),
                .black, Color(red: 0, green: 0, blue: 0.2), .black
            ]
        )
        .ignoresSafeArea()
        .hueRotation(.degrees(animationPhase))
        .onAppear {
            withAnimation(.linear(duration: 15).repeatForever(autoreverses: true)) {
                animationPhase = 360
            }
        }
    }
    
    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                timeFramePicker
                dateSelector
                expandButton
                entriesList
            }
            .padding(.vertical)
        }
    }
    
    private var timeFramePicker: some View {
        Picker("Time Frame", selection: $selectedTimeFrame) {
            Text("Daily").tag(TimeFrame.daily)
            Text("Weekly").tag(TimeFrame.weekly)
            Text("Monthly").tag(TimeFrame.monthly)
            Text("Custom").tag(TimeFrame.custom)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }
    
    private var dateSelector: some View {
        DatePicker("Select Date", selection: $selectedDate, displayedComponents: [.date])
            .datePickerStyle(.graphical)
            .padding(.horizontal)
    }
    
    private var expandButton: some View {
        HStack {
            Button {
                showingFullList = true
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .foregroundStyle(.blue)
            }
            .hoverEffect(.automatic)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal)
    }
    
    private var entriesList: some View {
        LazyVStack(spacing: 16) {
            let sortedDates = groupedEntries.keys.sorted(by: >)
            ForEach(sortedDates, id: \.self) { date in
                dateSection(for: date)
            }
        }
        .padding(.horizontal)
    }
    
    private func dateSection(for date: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(formatDate(date))
                .font(.headline)
                .foregroundStyle(.mint)
            
            let entries = groupedEntries[date] ?? []
            ForEach(entries) { entry in
                NutritionEntryRow(
                    entry: entry,
                    onDelete: { deleteEntry(entry) },
                    loadData: loadData
                )
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    private func deleteEntry(_ entry: HealthKitManager.NutritionEntry) {
        withAnimation {
            healthStore.deleteNutrientData(for: entry.id) { success in
                if success {
                    entries.removeAll { $0.id == entry.id }
                    loadData()
                }
            }
        }
    }
    
    private func loadData() {
        let calendar = Calendar.current
        let endDate = calendar.endOfDay(for: selectedDate)
        let startDate = getStartDate(for: selectedTimeFrame, endDate: endDate)
        
        healthStore.fetchNutrientHistory(from: startDate, to: endDate) { fetchedEntries in
            entries = fetchedEntries
        }
    }
    
    private func getStartDate(for timeFrame: TimeFrame, endDate: Date) -> Date {
        let calendar = Calendar.current
        switch timeFrame {
        case .daily:
            return calendar.startOfDay(for: selectedDate)
        case .weekly:
            return calendar.date(byAdding: .day, value: -7, to: endDate)!
        case .monthly:
            return calendar.date(byAdding: .month, value: -1, to: endDate)!
        case .custom:
            return calendar.date(byAdding: .day, value: -14, to: endDate)!
        }
    }
}

struct NutritionEntryRow: View {
    let entry: HealthKitManager.NutritionEntry
    let onDelete: () -> Void
    @StateObject private var healthStore = HealthKitManager()
    @State private var isEditing = false
    let loadData: () -> Void

    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(entry.mealType ?? "Meal")
                    .font(.headline)
                Spacer()
                Text(entry.timestamp, style: .time)
                    .foregroundColor(.secondary)
            }
            
            ForEach(Array(entry.nutrients.keys.sorted()), id: \.self) { nutrient in
                if let value = entry.nutrients[nutrient] {
                    Text("\(nutrient.capitalized): \(value, specifier: "%.1f")")
                        .font(.subheadline)
                }
            }
            
            HStack {
                Image(systemName: sourceIcon)
                Text(sourceLabel)
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .contextMenu {
            Button {
                isEditing = true
            } label: {
                Label("Edit Entry", systemImage: "pencil")
            }
            
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Entry", systemImage: "trash")
            }
        }
        .sheet(isPresented: $isEditing) {
           EditEntryView(entry: entry, onSave: onDelete, loadData: loadData)
       }
    }
    
    private var sourceIcon: String {
        switch entry.source {
        case .scanner: return "doc.text.viewfinder"
        case .search: return "text.bubble"
        case .savedMeal: return "star"
        }
    }
    
    private var sourceLabel: String {
        switch entry.source {
        case .scanner: return "Scanned"
        case .search: return "Search"
        case .savedMeal: return "Saved Meal"
        }
    }
}

struct EditEntryView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var healthStore = HealthKitManager()
    let entry: HealthKitManager.NutritionEntry
    @State private var mealType: String
    @State private var nutrients: [String: Double]
    let onSave: () -> Void
    
    let loadData: () -> Void  // Add this

    init(entry: HealthKitManager.NutritionEntry, onSave: @escaping () -> Void, loadData: @escaping () -> Void) {
        self.entry = entry
        self.onSave = onSave
        self.loadData = loadData
        _mealType = State(initialValue: entry.mealType ?? "")
        _nutrients = State(initialValue: entry.nutrients)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Meal Type") {
                    TextField("Meal Type", text: $mealType)
                }
                
                Section("Nutrients") {
                    ForEach(Array(nutrients.keys.sorted()), id: \.self) { nutrient in
                        HStack {
                            Text(nutrient.capitalized)
                            Spacer()
                            TextField("Amount", value: Binding(
                                get: { nutrients[nutrient] ?? 0 },
                                set: { nutrients[nutrient] = $0 }
                            ), format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
            .navigationTitle("Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let nutrientDataArray = nutrients.map { (name, value) in
                            NutrientData(name: name, value: value, unit: "g")
                        }
                        onSave() // Delete old entry
                        healthStore.saveNutrients(nutrientDataArray) { success in
                            if success {
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    loadData() // Refresh view after a slight delay to ensure deletion is processed
                                }
                            }
                        }
                    }

                }
            }
        }
    }
}

struct FullListView: View {
    let entries: [Date: [HealthKitManager.NutritionEntry]]
        let deleteEntry: (HealthKitManager.NutritionEntry) -> Void
        let loadData: () -> Void
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    let sortedDates = entries.keys.sorted(by: >)
                    ForEach(sortedDates, id: \.self) { date in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(formatDate(date))
                                .font(.headline)
                                .foregroundStyle(.mint)
                            
                            let entries = entries[date] ?? []
                            ForEach(entries) { entry in
                                NutritionEntryRow(
                                    entry: entry,
                                    onDelete: { deleteEntry(entry) },
                                    loadData: { loadData() }
                                )
                            }
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                    }
                }
                .padding()
            }
            .navigationTitle("All Entries")
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

extension Calendar {
    func endOfDay(for date: Date) -> Date {
        var components = DateComponents()
        components.day = 1
        components.second = -1
        return self.date(byAdding: components, to: startOfDay(for: date))!
    }
}
