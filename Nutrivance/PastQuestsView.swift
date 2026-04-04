import SwiftUI
import Charts
#if canImport(FoundationModels)
import FoundationModels
#endif

private enum StageHistoryWindow: String, CaseIterable, Identifiable, Codable {
    case d7 = "7d"
    case d28 = "28d"
    case year = "Year"
    var id: String { rawValue }
    var dateComponent: Calendar.Component { self == .year ? .year : .day }
    var stepValue: Int { self == .d7 ? 7 : (self == .d28 ? 28 : 1) }
}

struct StageQuestRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let completedAt: Date
    let workoutID: String
    let goalRawValue: String
    let roleRawValue: String
    let valueMin: Double
    let valueMax: Double
    let minutes: Int
    let repeats: Int

    var goal: ProgramMicroStageGoal { ProgramMicroStageGoal(rawValue: goalRawValue) ?? .time }
    var role: ProgramMicroStageRole { ProgramMicroStageRole(storageValue: roleRawValue) ?? .work }
    var representativeValue: Double { (valueMin + valueMax) / 2 }

    private enum CodingKeys: String, CodingKey {
        case id
        case completedAt
        case workoutID
        case goalRawValue
        case roleRawValue
        case valueMin
        case valueMax
        case minutes
        case repeats
        case roundsCompleted
    }

    init(
        id: UUID,
        completedAt: Date,
        workoutID: String,
        goalRawValue: String,
        roleRawValue: String,
        valueMin: Double,
        valueMax: Double,
        minutes: Int,
        repeats: Int
    ) {
        self.id = id
        self.completedAt = completedAt
        self.workoutID = workoutID
        self.goalRawValue = goalRawValue
        self.roleRawValue = roleRawValue
        self.valueMin = valueMin
        self.valueMax = valueMax
        self.minutes = minutes
        self.repeats = repeats
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        completedAt = try container.decode(Date.self, forKey: .completedAt)
        workoutID = try container.decode(String.self, forKey: .workoutID)
        goalRawValue = try container.decode(String.self, forKey: .goalRawValue)
        roleRawValue = try container.decode(String.self, forKey: .roleRawValue)
        valueMin = try container.decode(Double.self, forKey: .valueMin)
        valueMax = try container.decode(Double.self, forKey: .valueMax)
        let legacyRounds = try container.decodeIfPresent(Int.self, forKey: .roundsCompleted) ?? 1
        minutes = try container.decodeIfPresent(Int.self, forKey: .minutes) ?? max(legacyRounds, 1)
        repeats = try container.decodeIfPresent(Int.self, forKey: .repeats) ?? max(legacyRounds, 1)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(completedAt, forKey: .completedAt)
        try container.encode(workoutID, forKey: .workoutID)
        try container.encode(goalRawValue, forKey: .goalRawValue)
        try container.encode(roleRawValue, forKey: .roleRawValue)
        try container.encode(valueMin, forKey: .valueMin)
        try container.encode(valueMax, forKey: .valueMax)
        try container.encode(minutes, forKey: .minutes)
        try container.encode(repeats, forKey: .repeats)
    }
}

private func supportedGoalsForWorkout(_ workoutID: String, role: ProgramMicroStageRole) -> [ProgramMicroStageGoal] {
    let activitySpecific: [ProgramMicroStageGoal]
    switch workoutID {
    case "running", "trail-running": activitySpecific = [.time, .distance, .energy, .heartRateZone, .power, .pace, .cadence]
    case "walking", "hiking": activitySpecific = [.time, .distance, .heartRateZone, .pace]
    case "cycling", "mountain-biking": activitySpecific = [.time, .distance, .energy, .heartRateZone, .power, .speed, .cadence]
    default: activitySpecific = [.time, .distance, .energy, .heartRateZone, .power, .cadence, .speed]
    }
    let roleMatrix: [ProgramMicroStageGoal]
    switch role {
    case .warmup: roleMatrix = [.time, .distance]
    case .goal: roleMatrix = [.time, .distance, .energy]
    case .steady, .work: roleMatrix = [.power, .heartRateZone, .cadence, .speed, .pace]
    case .recovery, .cooldown: roleMatrix = [.time, .power, .cadence, .speed, .pace, .distance]
    }
    return roleMatrix.filter { activitySpecific.contains($0) }
}

private func compatibleRolesForWorkout(_ workoutID: String, goal: ProgramMicroStageGoal) -> [ProgramMicroStageRole] {
    ProgramMicroStageRole.allCases.filter { supportedGoalsForWorkout(workoutID, role: $0).contains(goal) }
}

private func supportedGoalsForWorkout(_ workoutID: String) -> [ProgramMicroStageGoal] {
    let all = Set(ProgramMicroStageRole.allCases.flatMap { supportedGoalsForWorkout(workoutID, role: $0) })
    return ProgramMicroStageGoal.allCases.filter { all.contains($0) && $0 != .open }
}

struct StageRangeRecommendation: Codable, Hashable {
    let comfortableRange: String
    let pushingRange: String
    let createdAt: Date
}

private struct StageHistoryFilterState: Codable {
    let workoutID: String
    let windowRawValue: String
    let anchorDate: Date
}

@MainActor
final class StageQuestStore: ObservableObject {
    static let shared = StageQuestStore()
    @Published private(set) var records: [StageQuestRecord] = []
    @Published private(set) var recommendations: [String: StageRangeRecommendation] = [:]

    private let defaults = UserDefaults.standard
    private let cloud = NSUbiquitousKeyValueStore.default
    private let recordsKey = "stage_quest_records_v1"
    private let recommendationsKey = "stage_quest_recommendations_v1"

    private init() { load() }

    func load() {
        cloud.synchronize()
        let cloudRecords = decodeFromCloud([StageQuestRecord].self, key: recordsKey) ?? []
        let localRecords = decodeFromLocal([StageQuestRecord].self, key: recordsKey) ?? []
        records = mergeRecords(cloudRecords, localRecords)
        recommendations = decode([String: StageRangeRecommendation].self, key: recommendationsKey) ?? [:]
    }

    func append(record: StageQuestRecord) {
        let cloudRecords = decodeFromCloud([StageQuestRecord].self, key: recordsKey) ?? []
        let localRecords = decodeFromLocal([StageQuestRecord].self, key: recordsKey) ?? []
        records = mergeRecords(records, cloudRecords, localRecords, [record])
        save()
    }

    func save() {
        encode(records, key: recordsKey)
        encode(recommendations, key: recommendationsKey)
    }

    func quests(forSport sport: String, from startDate: Date, to endDate: Date) -> [StageQuestRecord] {
        let normalizedSport = sport.lowercased().replacingOccurrences(of: " ", with: "-")
        return records.filter { record in
            let recordSport = record.workoutID.lowercased().replacingOccurrences(of: " ", with: "-")
            return recordSport == normalizedSport
                && record.completedAt >= startDate
                && record.completedAt <= endDate
        }
    }

    func questSummary(forSport sport: String, from startDate: Date, to endDate: Date) -> String {
        let matching = quests(forSport: sport, from: startDate, to: endDate)
        guard !matching.isEmpty else { return "" }

        let grouped = Dictionary(grouping: matching, by: \.goalRawValue)
        var parts: [String] = []
        for (goal, recs) in grouped.sorted(by: { $0.value.count > $1.value.count }) {
            let totalMin = recs.reduce(0) { $0 + $1.minutes }
            let count = recs.count
            parts.append("\(count)x \(goal) for \(totalMin)min")
        }
        return parts.joined(separator: ", ")
    }

    func recommendation(key: String, role: ProgramMicroStageRole, goal: ProgramMicroStageGoal, values: [Double]) async -> StageRangeRecommendation {
        if let cached = recommendations[key] { return cached }
        let generated = await generateRecommendation(role: role, goal: goal, values: values)
        recommendations[key] = generated
        save()
        return generated
    }

    private func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        if let cloudData = cloud.data(forKey: key), let decoded = try? JSONDecoder().decode(T.self, from: cloudData) { return decoded }
        if let localData = defaults.data(forKey: key), let decoded = try? JSONDecoder().decode(T.self, from: localData) { return decoded }
        return nil
    }

    private func decodeFromCloud<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let cloudData = cloud.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: cloudData)
    }

    private func decodeFromLocal<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let localData = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: localData)
    }

    private func encode<T: Encodable>(_ value: T, key: String) {
        guard let encoded = try? JSONEncoder().encode(value) else { return }
        defaults.set(encoded, forKey: key)
        cloud.set(encoded, forKey: key)
        cloud.synchronize()
    }

    private func mergeRecords(_ inputs: [StageQuestRecord]...) -> [StageQuestRecord] {
        var map: [UUID: StageQuestRecord] = [:]
        for source in inputs {
            for record in source {
                map[record.id] = record
            }
        }
        return map.values.sorted { $0.completedAt < $1.completedAt }
    }

    private func generateRecommendation(role: ProgramMicroStageRole, goal: ProgramMicroStageGoal, values: [Double]) async -> StageRangeRecommendation {
        let sorted = values.sorted()
        let median = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
        let p25 = sorted.isEmpty ? 0 : sorted[max(0, Int(Double(sorted.count - 1) * 0.25))]
        let p75 = sorted.isEmpty ? 0 : sorted[max(0, Int(Double(sorted.count - 1) * 0.75))]
        let fallback = StageRangeRecommendation(comfortableRange: "\(Int(p25.rounded()))-\(Int(median.rounded()))", pushingRange: "\(Int(median.rounded()))-\(Int(p75.rounded()))", createdAt: .now)
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel(useCase: .general)
            if model.isAvailable {
                do {
                    let session = LanguageModelSession(model: model)
                    let prompt = "Role \(role.title), Goal \(goal.title), values: \(sorted). Return exactly: comfortable=<range>; pushing=<range>"
                    let response = try await session.respond(to: prompt).content
                    let parts = response.components(separatedBy: ";")
                    if parts.count == 2 {
                        let comfortable = parts[0].replacingOccurrences(of: "comfortable=", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let pushing = parts[1].replacingOccurrences(of: "pushing=", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                        if !comfortable.isEmpty, !pushing.isEmpty {
                            return StageRangeRecommendation(comfortableRange: comfortable, pushingRange: pushing, createdAt: .now)
                        }
                    }
                } catch {}
            }
        }
        #endif
        return fallback
    }
}

struct PastQuestsView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var store = StageQuestStore.shared
    @StateObject private var engine = HealthStateEngine.shared
    @State private var selectedWorkoutID = "cycling"
    @State private var selectedWindow: StageHistoryWindow = .d28
    @State private var anchorDate = Date()
    @State private var isManualLoggerPresented = false
    private let filterStateKey = "personal_records_filter_state_v1"

    private var availableWorkouts: [String] {
        let fromRecords = Set(store.records.map(\.workoutID))
        let fromAnalytics = Set(engine.workoutAnalytics.map { normalizedWorkoutID(from: $0.workout.workoutActivityType.name) })
        return Array(fromRecords.union(fromAnalytics)).sorted()
    }

    private var periodStart: Date {
        let day = Calendar.current.startOfDay(for: anchorDate)
        switch selectedWindow {
        case .d7: return Calendar.current.date(byAdding: .day, value: -6, to: day) ?? day
        case .d28: return Calendar.current.date(byAdding: .day, value: -27, to: day) ?? day
        case .year: return Calendar.current.date(byAdding: .year, value: -1, to: day) ?? day
        }
    }
    private var periodEnd: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: anchorDate)) ?? anchorDate
    }

    /// Single pass over quest records for the selected sport and date window; cards read by O(1) key instead of filtering each time.
    private var indexedQuestRecordsInPeriod: [String: [StageQuestRecord]] {
        Dictionary(
            grouping: store.records.filter { record in
                record.workoutID == selectedWorkoutID
                    && record.completedAt >= periodStart
                    && record.completedAt < periodEnd
            },
            by: { "\($0.goal.rawValue)|\($0.role.rawValue)" }
        )
    }

    var body: some View {
        ZStack {
            MovingProgramBuilderBackground()

            ScrollView {
                let questIndex = indexedQuestRecordsInPeriod
                LazyVStack(alignment: .leading, spacing: 16) {
                    Menu {
                        ForEach(availableWorkouts, id: \.self) { workout in
                            Button(workout.capitalized) { selectedWorkoutID = workout }
                        }
                    } label: {
                        HStack {
                            Label(selectedWorkoutID.capitalized, systemImage: "figure.run")
                            Spacer()
                            Image(systemName: "chevron.down")
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(12)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    ForEach(supportedGoals(for: selectedWorkoutID), id: \.self) { goal in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(goal.title).font(.title3.weight(.bold))
                            let roles = compatibleRoles(for: selectedWorkoutID, goal: goal)
                            LazyVGrid(columns: gridColumns, spacing: 12) {
                                ForEach(roles, id: \.self) { role in
                                    StageQuestCard(
                                        workoutID: selectedWorkoutID,
                                        goal: goal,
                                        role: role,
                                        records: questRecordsForCard(in: questIndex, goal: goal, role: role)
                                    )
                                    .environmentObject(store)
                                }
                            }
                        }
                        .padding(14)
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Past Quests")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { isManualLoggerPresented = true } label: { Image(systemName: "plus") }
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { stepWindow(-1) } label: { Image(systemName: "chevron.left") }
                Menu(selectedWindow.rawValue) {
                    ForEach(StageHistoryWindow.allCases) { window in
                        Button(window.rawValue) { selectedWindow = window }
                    }
                }
                Button { stepWindow(1) } label: { Image(systemName: "chevron.right") }.disabled(!canStepForward)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nutrivanceViewControlFilter1)) { _ in selectedWindow = .d7 }
        .onReceive(NotificationCenter.default.publisher(for: .nutrivanceViewControlFilter2)) { _ in selectedWindow = .d28 }
        .onReceive(NotificationCenter.default.publisher(for: .nutrivanceViewControlFilter3)) { _ in selectedWindow = .year }
        .onReceive(NotificationCenter.default.publisher(for: .nutrivanceViewControlLogNewQuest)) { _ in isManualLoggerPresented = true }
        .onReceive(NotificationCenter.default.publisher(for: .nutrivanceViewControlToday)) { _ in jumpToToday() }
        .sheet(isPresented: $isManualLoggerPresented) {
            ManualQuestLoggerSheet(defaultWorkoutID: selectedWorkoutID, workouts: availableWorkouts) { record in
                store.append(record: record)
            }
        }
        .onAppear(perform: restoreFilterState)
        .onChange(of: selectedWorkoutID) { _, _ in persistFilterState() }
        .onChange(of: selectedWindow) { _, _ in persistFilterState() }
        .onChange(of: anchorDate) { _, _ in persistFilterState() }
        .onReceive(NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)) { _ in
            restoreFilterState()
            store.load()
        }
    }

    private var gridColumns: [GridItem] {
        if horizontalSizeClass == .regular {
            return [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        }
        return [GridItem(.flexible(), spacing: 12)]
    }
    private var canStepForward: Bool {
        let today = Calendar.current.startOfDay(for: .now)
        let next = Calendar.current.date(byAdding: selectedWindow.dateComponent, value: selectedWindow.stepValue, to: Calendar.current.startOfDay(for: anchorDate)) ?? today
        return next <= today
    }
    private func stepWindow(_ direction: Int) {
        let delta = selectedWindow.stepValue * direction
        if let date = Calendar.current.date(byAdding: selectedWindow.dateComponent, value: delta, to: anchorDate) {
            anchorDate = min(date, .now)
        }
    }

    private func jumpToToday() {
        anchorDate = Date()
    }

    private func questRecordsForCard(in index: [String: [StageQuestRecord]], goal: ProgramMicroStageGoal, role: ProgramMicroStageRole) -> [StageQuestRecord] {
        index["\(goal.rawValue)|\(role.rawValue)"] ?? []
    }

    private func supportedGoals(for workoutID: String) -> [ProgramMicroStageGoal] {
        supportedGoalsForWorkout(workoutID)
    }
    private func compatibleRoles(for workoutID: String, goal: ProgramMicroStageGoal) -> [ProgramMicroStageRole] {
        compatibleRolesForWorkout(workoutID, goal: goal)
    }
    private func supportedGoals(for workoutID: String, role: ProgramMicroStageRole) -> [ProgramMicroStageGoal] {
        supportedGoalsForWorkout(workoutID, role: role)
    }

    private func normalizedWorkoutID(from name: String) -> String { name.lowercased().replacingOccurrences(of: " ", with: "-") }
    private func restoreFilterState() {
        let cloud = NSUbiquitousKeyValueStore.default
        cloud.synchronize()
        let data = cloud.data(forKey: filterStateKey) ?? UserDefaults.standard.data(forKey: filterStateKey)
        guard let data, let decoded = try? JSONDecoder().decode(StageHistoryFilterState.self, from: data) else {
            selectedWorkoutID = availableWorkouts.contains("cycling") ? "cycling" : (availableWorkouts.first ?? "cycling")
            return
        }
        selectedWorkoutID = availableWorkouts.contains(decoded.workoutID) ? decoded.workoutID : (availableWorkouts.first ?? "cycling")
        selectedWindow = StageHistoryWindow(rawValue: decoded.windowRawValue) ?? .d28
        anchorDate = min(decoded.anchorDate, Date())
    }
    private func persistFilterState() {
        let state = StageHistoryFilterState(workoutID: selectedWorkoutID, windowRawValue: selectedWindow.rawValue, anchorDate: anchorDate)
        guard let encoded = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(encoded, forKey: filterStateKey)
        let cloud = NSUbiquitousKeyValueStore.default
        cloud.set(encoded, forKey: filterStateKey)
        cloud.synchronize()
    }
}

private struct StageQuestChartPoint: Identifiable {
    let id = UUID()
    let date: Date
    let valueMin: Double
    let valueMax: Double
    let totalMinutes: Int
    let totalRepeats: Int
    let count: Int
}

private struct StageQuestCard: View {
    @EnvironmentObject private var store: StageQuestStore
    let workoutID: String
    let goal: ProgramMicroStageGoal
    let role: ProgramMicroStageRole
    let records: [StageQuestRecord]
    @State private var highlightedDay: Date?
    @State private var recommendationText = "Calculating suggested ranges..."

    /// Stable, order-independent fingerprint so `.task` does not rebuild huge UUID arrays on every layout.
    private var recommendationTaskIdentity: String {
        let prefix = "\(workoutID)|\(goal.rawValue)|\(role.rawValue)"
        guard !records.isEmpty else { return "\(prefix)|0" }
        var h = Hasher()
        h.combine(records.count)
        for id in records.map(\.id).sorted(by: { $0.uuidString < $1.uuidString }) {
            h.combine(id)
        }
        return "\(prefix)|\(h.finalize())"
    }

    private func chartAvailableDays(from points: [StageQuestChartPoint]) -> [Date] {
        let cal = Calendar.current
        let days = points.map { cal.startOfDay(for: $0.date) }
        return Array(Set(days)).sorted()
    }

    var body: some View {
        let points = groupedPoints
        let availableDays = chartAvailableDays(from: points)
        VStack(alignment: .leading, spacing: 8) {
            Label(role.title, systemImage: symbol).font(.headline).foregroundStyle(themeColor)
            Text("\(records.count)").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(themeColor)
            chartView(points: points, availableDays: availableDays).frame(height: 180)
            Text(statsSummary(for: points)).font(.caption).foregroundStyle(.secondary)
            Text(recommendationText).font(.caption).foregroundStyle(themeColor)
        }
        .padding(12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .task(id: recommendationTaskIdentity) {
            let key = "\(workoutID)|\(goal.rawValue)|\(role.rawValue)"
            let recommendation = await store.recommendation(key: key, role: role, goal: goal, values: points.map(\.valueMax))
            recommendationText = "Comfortable: \(recommendation.comfortableRange) | Pushing: \(recommendation.pushingRange)"
        }
    }

    private var groupedPoints: [StageQuestChartPoint] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: records) { record in
            let day = calendar.startOfDay(for: record.completedAt)
            return "\(day.timeIntervalSinceReferenceDate)|\(record.valueMin)|\(record.valueMax)"
        }
        return grouped.compactMap { key, items in
            let parts = key.split(separator: "|")
            guard parts.count == 3, let daySeconds = Double(parts[0]), let minValue = Double(parts[1]), let maxValue = Double(parts[2]) else { return nil }
            return StageQuestChartPoint(
                date: Date(timeIntervalSinceReferenceDate: daySeconds),
                valueMin: minValue,
                valueMax: maxValue,
                totalMinutes: items.reduce(0) { $0 + max($1.minutes, 0) * max($1.repeats, 1) },
                totalRepeats: items.reduce(0) { $0 + max($1.repeats, 1) },
                count: items.count
            )
        }
        .sorted { $0.date < $1.date }
    }

    private var symbol: String {
        switch role {
        case .warmup: return "sunrise.fill"
        case .goal: return "target"
        case .steady: return "gauge.medium"
        case .work: return "flame.fill"
        case .recovery: return "leaf.fill"
        case .cooldown: return "snowflake"
        }
    }
    private var themeColor: Color {
        switch goal {
        case .cadence: return .blue
        case .power: return .purple
        case .heartRateZone: return .red
        case .speed, .pace: return .green
        case .distance: return .mint
        case .energy: return .orange
        case .time: return .cyan
        case .open: return .gray
        }
    }
    private func format(_ value: Double) -> String { String(format: "%.1f", value) }
    private func normalizedSize(for minutes: Int, minSize: CGFloat, maxSize: CGFloat) -> CGFloat {
        let clamped = min(max(minutes, 5), 120)
        let ratio = Double(clamped - 5) / 115.0
        return minSize + CGFloat(ratio) * (maxSize - minSize)
    }

    private func chartView(points: [StageQuestChartPoint], availableDays: [Date]) -> some View {
        Chart(points) { point in
            if role == .steady {
                BarMark(
                    x: .value("Date", point.date),
                    yStart: .value("Min", point.valueMin),
                    yEnd: .value("Max", point.valueMax),
                    width: .fixed(normalizedSize(for: point.totalMinutes, minSize: 4, maxSize: 18))
                )
                .foregroundStyle(themeColor.opacity(0.45))
            }
            LineMark(
                x: .value("Date", point.date),
                y: .value("Value", role == .work ? point.valueMin : (role == .recovery ? point.valueMax : point.valueMax))
            )
            .foregroundStyle(themeColor.opacity(0.7))
            .interpolationMethod(.catmullRom)
            PointMark(
                x: .value("Date", point.date),
                y: .value("Value", (point.valueMin + point.valueMax) / 2)
            )
            .symbolSize(normalizedSize(for: point.totalMinutes, minSize: 30, maxSize: 140))
            .foregroundStyle(themeColor)
            if let highlightedDay {
                RuleMark(x: .value("Selected", highlightedDay))
                    .foregroundStyle(themeColor.opacity(0.9))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .center) {
                        indicatorPane(for: highlightedDay, points: points)
                    }
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartOverlay { proxy in
            GeometryReader { geo in
                pastQuestsHorizontalScrubOverlay { location in
                    let origin = geo[proxy.plotAreaFrame].origin
                    let plotFrame = geo[proxy.plotAreaFrame]
                    let plotWidth = max(plotFrame.size.width, 0.0001)
                    let xRaw = location.x - origin.x
                    let xClamped = min(max(xRaw, 0), plotWidth)

                    guard !availableDays.isEmpty else {
                        highlightedDay = nil
                        return
                    }

                    if let date: Date = proxy.value(atX: xClamped) {
                        let day = Calendar.current.startOfDay(for: date)
                        highlightedDay = nearestDay(from: availableDays, to: day) ?? availableDays.first
                    }
                }
            }
        }
    }

    private func nearestDay(from days: [Date], to target: Date) -> Date? {
        guard !days.isEmpty else { return nil }
        return days.min(by: { abs($0.timeIntervalSinceReferenceDate - target.timeIntervalSinceReferenceDate) < abs($1.timeIntervalSinceReferenceDate - target.timeIntervalSinceReferenceDate) })
    }

    private func indicatorPane(for day: Date, points: [StageQuestChartPoint]) -> some View {
        let dayPoints = points.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }

        let low = dayPoints.map(\.valueMin).min() ?? 0
        let high = dayPoints.map(\.valueMax).max() ?? 0
        let totalMinutes = dayPoints.reduce(0) { $0 + $1.totalMinutes }

        return VStack(spacing: 4) {
            Text(day.formatted(.dateTime.month(.abbreviated).day()))
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            rangeRow(low: low, high: high)

            Text("\(totalMinutes) minutes")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(themeColor.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 2)
        .padding(.top, 2)
    }

    @ViewBuilder
    private func rangeRow(low: Double, high: Double) -> some View {
        let isSingle = abs(low - high) < 0.0001
        let roundedLow = roundedDisplayValue(low)
        let roundedHigh = roundedDisplayValue(high)

        switch goal {
        case .heartRateZone:
            let z1 = Int(roundedLow.rounded())
            let z2 = Int(roundedHigh.rounded())
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(isSingle ? "\(z1)" : "\(min(z1, z2))-\(max(z1, z2))")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                Text("Zone")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        case .cadence:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(isSingle ? displayNumberString(roundedLow) : "\(displayNumberString(roundedLow))-\(displayNumberString(roundedHigh))")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                Text("rpm")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        case .power:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(isSingle ? displayNumberString(roundedLow) : "\(displayNumberString(roundedLow))-\(displayNumberString(roundedHigh))")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                Text("W")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        case .speed:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(isSingle ? displayNumberString(roundedLow) : "\(displayNumberString(roundedLow))-\(displayNumberString(roundedHigh))")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                Text("mph")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        case .pace:
            // Pace values are seconds; display as m:ss - m:ss /mi
            let start = formatPaceSeconds(roundedLow)
            let end = formatPaceSeconds(roundedHigh)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(isSingle ? start : "\(start)-\(end)")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                Text("/mi")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        case .distance:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(isSingle ? "\(Int(roundedLow.rounded()))" : "\(Int(min(roundedLow, roundedHigh).rounded()))-\(Int(max(roundedLow, roundedHigh).rounded()))")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                Text("km")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        case .energy:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(isSingle ? "\(Int(roundedLow.rounded()))" : "\(Int(min(roundedLow, roundedHigh).rounded()))-\(Int(max(roundedLow, roundedHigh).rounded()))")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                Text("kcal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        case .time:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(isSingle ? "\(Int(roundedLow.rounded()))" : "\(Int(min(roundedLow, roundedHigh).rounded()))-\(Int(max(roundedLow, roundedHigh).rounded()))")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                Text("min")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        case .open:
            EmptyView()
        }
    }

    private func roundedDisplayValue(_ value: Double) -> Double {
        let roundedInt = value.rounded()
        if abs(value - roundedInt) < 0.001 {
            return roundedInt
        }
        return (value * 10).rounded() / 10
    }

    private func displayNumberString(_ value: Double) -> String {
        let rounded = roundedDisplayValue(value)
        let roundedInt = rounded.rounded()
        if abs(rounded - roundedInt) < 0.001 {
            return "\(Int(roundedInt))"
        }
        return String(format: "%.1f", rounded)
    }

    private func formatPaceSeconds(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let minutes = total / 60
        let secs = total % 60
        return "\(minutes):" + String(format: "%02d", secs)
    }

    private func statsSummary(for points: [StageQuestChartPoint]) -> String {
        let values = points.map { ($0.valueMin + $0.valueMax) / 2 }.sorted()
        guard !values.isEmpty else { return "No completed quests in this period." }
        let mean = values.reduce(0, +) / Double(values.count)
        let median = values[values.count / 2]
        let maxValue = values.max() ?? 0
        let q1 = values[max(0, Int(Double(values.count - 1) * 0.25))]
        let q3 = values[max(0, Int(Double(values.count - 1) * 0.75))]
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        return "Mean \(format(mean)) | Median \(format(median)) | SD \(format(sqrt(variance))) | Max \(format(maxValue)) | Q1 \(format(q1)) | Q3 \(format(q3))"
    }
}

private struct pastQuestsHorizontalScrubOverlay: UIViewRepresentable {
    let onChanged: (CGPoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChanged: onChanged)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        panGesture.delegate = context.coordinator
        panGesture.cancelsTouchesInView = true
        panGesture.delaysTouchesBegan = false
        panGesture.delaysTouchesEnded = false
        view.addGestureRecognizer(panGesture)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onChanged = onChanged
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onChanged: (CGPoint) -> Void

        init(onChanged: @escaping (CGPoint) -> Void) {
            self.onChanged = onChanged
        }

        @objc
        func handlePan(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began, .changed, .ended:
                onChanged(gesture.location(in: gesture.view))
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let view = pan.view else { return false }
            let velocity = pan.velocity(in: view)
            return abs(velocity.x) > abs(velocity.y)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            false
        }
    }
}

private struct ManualQuestLoggerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var workoutID: String
    let workouts: [String]
    @State private var role: ProgramMicroStageRole = .steady
    @State private var goal: ProgramMicroStageGoal = .cadence
    @State private var minSelection = "90"
    @State private var maxSelection = "110"
    @State private var valueSelection = "90"
    @State private var minutes = 10
    @State private var repeats = 1
    let onSave: (StageQuestRecord) -> Void

    init(defaultWorkoutID: String, workouts: [String], onSave: @escaping (StageQuestRecord) -> Void) {
        _workoutID = State(initialValue: defaultWorkoutID)
        self.workouts = workouts
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Picker("Workout", selection: $workoutID) {
                    ForEach(workouts, id: \.self) { workout in
                        Text(workout.capitalized).tag(workout)
                    }
                }
                Picker("Role", selection: $role) {
                    ForEach(compatibleRolesForWorkout(workoutID, goal: goal)) { Text($0.title).tag($0) }
                }
                Picker("Goal", selection: $goal) {
                    ForEach(supportedGoalsForWorkout(workoutID, role: role)) { Text($0.title).tag($0) }
                }
                if valueMode == .range || valueMode == .minOnly {
                    wheelPickerField(title: "Min", selection: $minSelection, options: wheelOptions(for: goal))
                }
                if valueMode == .range || valueMode == .maxOnly {
                    wheelPickerField(title: "Max", selection: $maxSelection, options: wheelOptions(for: goal))
                }
                if valueMode == .single {
                    wheelPickerField(title: "Value", selection: $valueSelection, options: wheelOptions(for: goal))
                }
                Stepper("Minutes: \(minutes)", value: $minutes, in: 1...240)
                Stepper("Repeats: \(repeats)", value: $repeats, in: 1...20)
            }
            .onAppear {
                normalizeSelections()
            }
            .onChange(of: workoutID) { _, _ in
                normalizeSelections()
            }
            .onChange(of: role) { _, _ in
                let allowed = supportedGoalsForWorkout(workoutID, role: role)
                if !allowed.contains(goal), let first = allowed.first {
                    goal = first
                }
                normalizeWheelSelections()
            }
            .onChange(of: goal) { _, _ in
                let roles = compatibleRolesForWorkout(workoutID, goal: goal)
                if !roles.contains(role), let first = roles.first {
                    role = first
                }
                normalizeWheelSelections()
            }
            .onChange(of: minSelection) { _, _ in
                enforceRangeOrdering()
            }
            .onChange(of: maxSelection) { _, _ in
                enforceRangeOrdering()
            }
            .navigationTitle("Log Quest")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        let parsedMin = wheelComparableValue(for: minSelection) ?? 0
                        let parsedMax = wheelComparableValue(for: maxSelection) ?? parsedMin
                        let parsedValue = wheelComparableValue(for: valueSelection) ?? parsedMin
                        let minValue: Double
                        let maxValue: Double
                        switch valueMode {
                        case .range:
                            minValue = min(parsedMin, parsedMax)
                            maxValue = max(parsedMin, parsedMax)
                        case .minOnly:
                            minValue = parsedMin
                            maxValue = parsedMin
                        case .maxOnly:
                            minValue = parsedMax
                            maxValue = parsedMax
                        case .single:
                            minValue = parsedValue
                            maxValue = parsedValue
                        }
                        let record = StageQuestRecord(
                            id: UUID(),
                            completedAt: date,
                            workoutID: workoutID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                            goalRawValue: goal.rawValue,
                            roleRawValue: role.rawValue,
                            valueMin: min(minValue, maxValue),
                            valueMax: max(minValue, maxValue),
                            minutes: minutes,
                            repeats: repeats
                        )
                        onSave(record)
                        dismiss()
                    }
                }
            }
        }
    }

    private enum ValueMode {
        case minOnly
        case maxOnly
        case range
        case single
    }

    private var valueMode: ValueMode {
        switch role {
        case .work:
            return .minOnly
        case .recovery:
            return .maxOnly
        case .steady:
            return .range
        case .warmup, .goal, .cooldown:
            return goal == .heartRateZone ? .single : .range
        }
    }

    private func normalizeSelections() {
        if !workouts.contains(workoutID), let first = workouts.first {
            workoutID = first
        }
        let goals = supportedGoalsForWorkout(workoutID, role: role)
        if !goals.contains(goal), let first = goals.first {
            goal = first
        }
        let roles = compatibleRolesForWorkout(workoutID, goal: goal)
        if !roles.contains(role), let first = roles.first {
            role = first
        }
        normalizeWheelSelections()
    }

    private func wheelPickerField(title: String, selection: Binding<String>, options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 92)
            .clipped()
        }
    }

    private func wheelOptions(for goal: ProgramMicroStageGoal) -> [String] {
        switch goal {
        case .power:
            return stride(from: 50, through: 600, by: 5).map(String.init)
        case .cadence:
            return stride(from: 50, through: 220, by: 5).map(String.init)
        case .speed:
            return stride(from: 1, through: 40, by: 1).map { "\($0) mph" }
        case .distance:
            return stride(from: 1, through: 50, by: 1).map { "\($0) km" }
        case .energy:
            return stride(from: 25, through: 2000, by: 25).map { "\($0) kcal" }
        case .pace:
            return (180...900).filter { $0 % 5 == 0 }.map { String(format: "%d:%02d /mi", $0 / 60, $0 % 60) }
        case .heartRateZone:
            return (1...5).map { "Zone \($0)" }
        case .open, .time:
            return stride(from: 1, through: 240, by: 1).map { "\($0) min" }
        }
    }

    private func wheelComparableValue(for value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("zone ") {
            return Double(trimmed.replacingOccurrences(of: "zone ", with: ""))
        }
        if trimmed.contains(":") {
            let base = trimmed.components(separatedBy: " ").first ?? trimmed
            let parts = base.split(separator: ":")
            guard parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]) else { return nil }
            return minutes * 60 + seconds
        }
        let numeric = trimmed
            .replacingOccurrences(of: ",", with: "")
            .components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted)
            .joined()
        return Double(numeric)
    }

    private func nearestWheelOption(for current: String, options: [String]) -> String {
        guard !options.isEmpty else { return current }
        if options.contains(current) { return current }
        guard let currentValue = wheelComparableValue(for: current) else { return options[0] }
        return options.min(by: {
            abs((wheelComparableValue(for: $0) ?? currentValue) - currentValue) <
            abs((wheelComparableValue(for: $1) ?? currentValue) - currentValue)
        }) ?? options[0]
    }

    private func normalizeWheelSelections() {
        let options = wheelOptions(for: goal)
        guard !options.isEmpty else { return }
        minSelection = nearestWheelOption(for: minSelection, options: options)
        maxSelection = nearestWheelOption(for: maxSelection, options: options)
        valueSelection = nearestWheelOption(for: valueSelection, options: options)
        enforceRangeOrdering()
    }

    private func enforceRangeOrdering() {
        guard valueMode == .range else { return }
        guard let minValue = wheelComparableValue(for: minSelection),
              let maxValue = wheelComparableValue(for: maxSelection),
              minValue > maxValue else { return }
        maxSelection = minSelection
    }
}
