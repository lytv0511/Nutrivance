import SwiftUI
import HealthKit

struct TrainingCalendarView: View {
    @ObservedObject private var engine = HealthStateEngine.shared
    @EnvironmentObject private var navigationState: NavigationState

    @State private var animationPhase: Double = 0
    @State private var sportFilter: String? = nil
    @State private var selectedMonth: Date
    @State private var selectedDay: Date
    @State private var selectedWorkout: CalendarWorkoutSelection? = nil
    @State private var isLoadingMonth = false
    @State private var showMonthPicker = false
    @State private var showHRZoneSettings = false
    @State private var hrZoneConfigurationMode: HRZoneConfigurationMode
    @State private var selectedHRZoneSchema: HRZoneSchema
    @State private var fixedMaxHR: Double?
    @State private var fixedRestingHR: Double?
    @State private var fixedLTHR: Double?
    @State private var customZone1Upper: Double
    @State private var customZone2Upper: Double
    @State private var customZone3Upper: Double
    @State private var customZone4Upper: Double
    @State private var customZone5Upper: Double
    @State private var hasLoadedPersistedHRZoneSettings = false

    init() {
        let persisted = HRZoneSettingsPersistence.load() ?? .fallback
        let mode = HRZoneConfigurationMode(rawValue: persisted.modeRawValue) ?? .intelligent
        let schema = HRZoneSchema(rawValue: persisted.schemaRawValue) ?? .lactatThreshold
        let bounds = persisted.customZoneUpperBounds.count == 5 ? persisted.customZoneUpperBounds : HRZonePersistedSettings.fallback.customZoneUpperBounds
        let now = Date()

        _selectedMonth = State(initialValue: Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: now)) ?? now)
        _selectedDay = State(initialValue: Calendar.current.startOfDay(for: now))
        _hrZoneConfigurationMode = State(initialValue: mode)
        _selectedHRZoneSchema = State(initialValue: schema)
        _fixedMaxHR = State(initialValue: persisted.fixedMaxHR)
        _fixedRestingHR = State(initialValue: persisted.fixedRestingHR)
        _fixedLTHR = State(initialValue: persisted.fixedLTHR)
        _customZone1Upper = State(initialValue: bounds[0])
        _customZone2Upper = State(initialValue: bounds[1])
        _customZone3Upper = State(initialValue: bounds[2])
        _customZone4Upper = State(initialValue: bounds[3])
        _customZone5Upper = State(initialValue: bounds[4])
        _hasLoadedPersistedHRZoneSettings = State(initialValue: true)
    }

    private var calendar: Calendar { .current }

    private var hrZoneSettings: HRZoneUserSettings {
        HRZoneUserSettings(
            mode: hrZoneConfigurationMode,
            customSchema: selectedHRZoneSchema,
            fixedMaxHR: fixedMaxHR,
            fixedRestingHR: fixedRestingHR,
            fixedLTHR: fixedLTHR,
            customZoneUpperBounds: [
                customZone1Upper,
                customZone2Upper,
                customZone3Upper,
                customZone4Upper,
                customZone5Upper
            ]
        )
    }

    private var persistedHRZoneSettings: HRZonePersistedSettings {
        HRZonePersistedSettings(
            modeRawValue: hrZoneConfigurationMode.rawValue,
            schemaRawValue: selectedHRZoneSchema.rawValue,
            fixedMaxHR: fixedMaxHR,
            fixedRestingHR: fixedRestingHR,
            fixedLTHR: fixedLTHR,
            customZoneUpperBounds: [
                customZone1Upper,
                customZone2Upper,
                customZone3Upper,
                customZone4Upper,
                customZone5Upper
            ]
        )
    }

    private var filteredWorkouts: [(workout: HKWorkout, analytics: WorkoutAnalytics)] {
        engine.workoutAnalytics.filter { sportFilter == nil || $0.workout.workoutActivityType.name == sportFilter }
    }

    private var uniqueSports: [String] {
        engine.workoutAnalytics.map { $0.workout.workoutActivityType.name }.unique.sorted()
    }

    private var workoutsByDay: [Date: [(workout: HKWorkout, analytics: WorkoutAnalytics)]] {
        let grouped = Dictionary(grouping: filteredWorkouts) { pair in
            calendar.startOfDay(for: pair.workout.startDate)
        }
        return grouped.mapValues { pairs in
            pairs.sorted(by: { $0.workout.startDate < $1.workout.startDate })
        }
    }

    private var workoutDaySet: Set<Date> {
        Set(workoutsByDay.keys)
    }

    private var selectedMonthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth)) ?? selectedMonth
    }

    private var monthInterval: DateInterval {
        calendar.dateInterval(of: .month, for: selectedMonthStart) ?? DateInterval(start: selectedMonthStart, duration: 31 * 24 * 60 * 60)
    }

    private var monthDays: [CalendarDaySlot] {
        guard let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
              let monthEndDay = calendar.date(byAdding: .day, value: -1, to: monthInterval.end),
              let lastWeek = calendar.dateInterval(of: .weekOfMonth, for: monthEndDay) else {
            return []
        }

        var days: [CalendarDaySlot] = []
        var cursor = firstWeek.start

        while cursor < lastWeek.end {
            let normalized = calendar.startOfDay(for: cursor)
            days.append(
                CalendarDaySlot(
                    date: normalized,
                    isInDisplayedMonth: calendar.isDate(normalized, equalTo: selectedMonthStart, toGranularity: .month),
                    workouts: workoutsByDay[normalized] ?? []
                )
            )
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return days
    }

    private var selectedDayWorkouts: [(workout: HKWorkout, analytics: WorkoutAnalytics)] {
        workoutsByDay[selectedDay] ?? []
    }

    private var activeWorkoutDaysSorted: [Date] {
        workoutDaySet.sorted()
    }

    /// Bundled so hero, summary, and grid share one streak walk per layout pass.
    private var activeStreakState: (length: Int, highlight: (lower: Date, upper: Date)?) {
        let daySet = workoutDaySet
        let length = streakLength(anchoredAtToday: true, daySet: daySet)
        guard length > 0 else { return (0, nil) }
        let today = calendar.startOfDay(for: Date())
        let anchor = workoutsByDay[today] != nil ? today : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
        guard let lowerBound = calendar.date(byAdding: .day, value: -(length - 1), to: anchor) else { return (length, nil) }
        return (length, (lowerBound, anchor))
    }

    private var longestStreak: Int {
        let daySet = workoutDaySet
        var best = 0

        for day in activeWorkoutDaysSorted {
            let previous = calendar.date(byAdding: .day, value: -1, to: day) ?? day
            guard !daySet.contains(previous) else { continue }

            var count = 0
            var cursor = day
            while daySet.contains(cursor) {
                count += 1
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
            best = max(best, count)
        }

        return best
    }

    private var monthCompletionCount: Int {
        monthDays.filter { $0.isInDisplayedMonth && !$0.workouts.isEmpty }.count
    }

    private var monthWorkoutCount: Int {
        monthDays.reduce(0) { $0 + ($1.isInDisplayedMonth ? $1.workouts.count : 0) }
    }

    private var orderedWeekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let shift = max(0, calendar.firstWeekday - 1)
        return Array(symbols[shift...]) + Array(symbols[..<shift])
    }

    private var monthTitle: String {
        selectedMonthStart.formatted(.dateTime.month(.wide).year())
    }

    /// Split out of `body` so the compiler can type-check the main view graph in reasonable time.
    @ViewBuilder
    private var trainingCalendarToolbarTrailing: some View {
        HStack(spacing: 12) {
            Button {
                refreshTrainingCalendarFromEngine()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundColor(.orange)
            }
            .catalystIconButtonSize()
            .catalystFocusablePrimaryAction { refreshTrainingCalendarFromEngine() }

            Button {
                jumpToToday()
            } label: {
                Image(systemName: "scope")
                    .foregroundColor(.orange)
            }
            .catalystIconButtonSize()
            .catalystFocusablePrimaryAction { jumpToToday() }

            Button {
                showMonthPicker = true
            } label: {
                Image(systemName: "calendar")
                    .foregroundColor(.orange)
            }
            .catalystIconButtonSize()
            .catalystFocusablePrimaryAction { showMonthPicker = true }

            Menu {
                Button("All Sports") { sportFilter = nil }
                ForEach(uniqueSports, id: \.self) { sport in
                    Button(sport.capitalized) { sportFilter = sport }
                }
            } label: {
                Image(systemName: "line.horizontal.3.decrease.circle")
                    .foregroundColor(.orange)
            }
            .catalystIconButtonSize()
            .catalystDesktopFocusable()

            Button {
                showHRZoneSettings = true
            } label: {
                Image(systemName: "gear")
                    .foregroundColor(.orange)
            }
            .catalystIconButtonSize()
            .catalystFocusablePrimaryAction { showHRZoneSettings = true }
        }
    }

    var body: some View {
        trainingCalendarMain
    }

    /// Isolated from `body` to keep SwiftUI type-checking within a reasonable bound.
    private var trainingCalendarMain: some View {
        trainingCalendarStackWithLifecycleModifiers
    }

    private var trainingCalendarStackWithLifecycleModifiers: some View {
        trainingCalendarStackWithAsyncAndValueObservers
    }

    private var trainingCalendarStackWithAsyncAndValueObservers: some View {
        trainingCalendarStackWithNotificationObservers
            .task {
                await loadMonthIfNeeded(for: selectedMonthStart, forceFetch: false)
            }
            .onChange(of: selectedMonthStart) { _, newValue in
                Task {
                    await loadMonthIfNeeded(for: newValue, forceFetch: false)
                }
            }
            .onChange(of: sportFilter) { _, _ in
                clampSelectedDayToVisibleMonth()
            }
            .onChange(of: persistedHRZoneSettings) { _, newValue in
                persistHRZoneSettingsIfReady(newValue)
            }
    }

    private var trainingCalendarStackWithNotificationObservers: some View {
        trainingCalendarStackWithPresentationModifiers
            .onReceiveViewControl(.nutrivanceViewControlTrainingCalendarToday) {
                guard navigationState.isGloballyActiveRootTab(.trainingCalendar) else { return }
                jumpToToday()
            }
            .onReceiveViewControl(.nutrivanceViewControlTrainingCalendarPreviousDay) {
                guard navigationState.isGloballyActiveRootTab(.trainingCalendar) else { return }
                stepSelectedDay(by: -1)
            }
            .onReceiveViewControl(.nutrivanceViewControlTrainingCalendarNextDay) {
                guard navigationState.isGloballyActiveRootTab(.trainingCalendar) else { return }
                stepSelectedDay(by: 1)
            }
            .onReceiveViewControl(.nutrivanceViewControlTrainingCalendarPreviousMonth) {
                guard navigationState.isGloballyActiveRootTab(.trainingCalendar) else { return }
                stepMonth(by: -1)
            }
            .onReceiveViewControl(.nutrivanceViewControlTrainingCalendarNextMonth) {
                guard navigationState.isGloballyActiveRootTab(.trainingCalendar) else { return }
                handleTrainingCalendarNextMonthShortcut()
            }
            .onReceiveViewControl(.nutrivanceViewControlTrainingCalendarRefresh) {
                guard navigationState.isGloballyActiveRootTab(.trainingCalendar) else { return }
                refreshTrainingCalendarFromEngine()
            }
            .onReceiveViewControl(.nutrivanceViewControlTrainingCalendarHRZoneSettings) {
                guard navigationState.isGloballyActiveRootTab(.trainingCalendar) else { return }
                showHRZoneSettings = true
            }
    }

    private var trainingCalendarStackWithPresentationModifiers: some View {
        trainingCalendarStackWithBurningBackground
    }

    private var trainingCalendarStackWithBurningBackground: some View {
        trainingCalendarStackWithMapCover
            .background(trainingCalendarBurningBackground)
    }

    private var trainingCalendarBurningBackground: some View {
        GradientBackgrounds().burningGradient(animationPhase: $animationPhase)
            .onAppear {
                withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                    animationPhase = 20
                }
            }
    }

    private var trainingCalendarBurningBackgroundFull: some View {
        GradientBackgrounds().burningGradientFull(animationPhase: $animationPhase)
            .onAppear {
                withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                    animationPhase = 20
                }
            }
    }

    private var trainingCalendarStackWithMapCover: some View {
        trainingCalendarStackWithHRZoneSheet
            .fullScreenCover(item: $selectedWorkout) { selection in
                MapDetailView(
                    analytics: selection.analytics,
                    hrZoneSettings: hrZoneSettings
                )
            }
    }

    private var trainingCalendarStackWithHRZoneSheet: some View {
        trainingCalendarStackWithMonthPickerSheet
            .sheet(isPresented: $showHRZoneSettings) {
                trainingCalendarHRZoneSettingsSheet
            }
    }

    private var trainingCalendarHRZoneSettingsSheet: some View {
        HRZoneSettingsSheet(
            isPresented: $showHRZoneSettings,
            configurationMode: $hrZoneConfigurationMode,
            selectedSchema: $selectedHRZoneSchema,
            fixedMaxHR: $fixedMaxHR,
            fixedRestingHR: $fixedRestingHR,
            fixedLTHR: $fixedLTHR,
            customZone1Upper: $customZone1Upper,
            customZone2Upper: $customZone2Upper,
            customZone3Upper: $customZone3Upper,
            customZone4Upper: $customZone4Upper,
            customZone5Upper: $customZone5Upper
        )
    }

    private var trainingCalendarStackWithMonthPickerSheet: some View {
        trainingCalendarNavigationStack
            .sheet(isPresented: $showMonthPicker) {
                trainingCalendarMonthPickerSheet
            }
    }

    private var trainingCalendarNavigationStack: some View {
        NavigationStack {
            trainingCalendarScrollChrome
        }
    }

    private var trainingCalendarScrollChrome: some View {
        trainingCalendarNavigationContent
            .navigationTitle("Training Calendar")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    trainingCalendarToolbarTrailing
                }
            }
    }

    private var trainingCalendarNavigationContent: some View {
        ZStack {
            ScrollView {
                let streakState = activeStreakState
                VStack(alignment: .leading, spacing: 22) {
                    calendarHero
                    streakSummaryView(currentStreak: streakState.length)
                    calendarGridView(streakHighlight: streakState.highlight)
                    selectedDayTimeline
                }
                .padding(.horizontal)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }

            if isLoadingMonth {
                ProgressView("Loading training calendar...")
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var trainingCalendarMonthPickerSheet: some View {
        NavigationStack {
            VStack(spacing: 18) {
                DatePicker(
                    "Jump to Month",
                    selection: Binding(
                        get: { selectedMonthStart },
                        set: { newValue in
                            selectedMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: newValue)) ?? newValue
                            selectedDay = calendar.startOfDay(for: newValue)
                        }
                    ),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding()
                .catalystDesktopFocusable()

                Button("Done") {
                    showMonthPicker = false
                }
                .foregroundColor(.orange)
                .catalystFocusablePrimaryAction { showMonthPicker = false }
            }
            .navigationTitle("Select Month")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private func persistHRZoneSettingsIfReady(_ settings: HRZonePersistedSettings) {
        guard hasLoadedPersistedHRZoneSettings else { return }
        HRZoneSettingsPersistence.save(settings)
    }

    private func handleTrainingCalendarNextMonthShortcut() {
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: selectedMonthStart) ?? selectedMonthStart
        guard !isFutureMonth(nextMonth) else { return }
        stepMonth(by: 1)
    }

    private func refreshTrainingCalendarFromEngine() {
        Task {
            isLoadingMonth = true
            await engine.refreshSyncedHealthDataFromICloud()
            isLoadingMonth = false
        }
    }

    private func stepSelectedDay(by days: Int) {
        let today = calendar.startOfDay(for: Date())
        guard let raw = calendar.date(byAdding: .day, value: days, to: selectedDay) else { return }
        let normalized = calendar.startOfDay(for: raw)
        if days > 0, normalized > today { return }
        selectedDay = normalized
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: normalized)) ?? normalized
        if !calendar.isDate(monthStart, equalTo: selectedMonthStart, toGranularity: .month) {
            selectedMonth = monthStart
        }
    }

    private var calendarHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Consistency compounds.")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("See streaks, session density, and every training block laid out like a real athlete's calendar.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 12) {
                Button {
                    stepMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.bold))
                        .frame(width: 42, height: 42)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .catalystFocusablePrimaryAction { stepMonth(by: -1) }

                VStack(spacing: 4) {
                    Text(monthTitle)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                    Text("\(monthWorkoutCount) workouts across \(monthCompletionCount) active days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Button {
                    stepMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.headline.weight(.bold))
                        .frame(width: 42, height: 42)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(isFutureMonth(selectedMonthStart))
                .opacity(isFutureMonth(selectedMonthStart) ? 0.35 : 1)
                .catalystFocusablePrimaryAction {
                    guard !isFutureMonth(selectedMonthStart) else { return }
                    stepMonth(by: 1)
                }
            }
        }
        .padding(22)
        .background(
            LinearGradient(
                colors: [
                    Color.orange.opacity(0.22),
                    Color.red.opacity(0.14),
                    Color.black.opacity(0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    private func streakSummaryView(currentStreak streakLen: Int) -> some View {
        HStack(spacing: 12) {
            CalendarStatCard(title: "Current Streak", value: "\(streakLen)", subtitle: streakLen == 1 ? "day" : "days", tint: .orange)
            CalendarStatCard(title: "Best Streak", value: "\(longestStreak)", subtitle: longestStreak == 1 ? "day" : "days", tint: .yellow)
            CalendarStatCard(title: "Active Days", value: "\(monthCompletionCount)", subtitle: "this month", tint: .red)
        }
    }

    private func calendarGridView(streakHighlight: (lower: Date, upper: Date)?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Training Month")
                    .font(.headline)
                Spacer()
                if let sportFilter {
                    Text(sportFilter.capitalized)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.16), in: Capsule())
                }
            }

            let columns = Self.weekdayGridColumns

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(orderedWeekdaySymbols, id: \.self) { symbol in
                    Text(symbol.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(monthDays) { slot in
                    TrainingCalendarDayCell(
                        slot: slot,
                        isToday: calendar.isDateInToday(slot.date),
                        isSelected: calendar.isDate(slot.date, inSameDayAs: selectedDay),
                        isPartOfCurrentStreak: isStreakHighlightDay(slot.date, window: streakHighlight),
                        onSelectDay: {
                            selectedDay = slot.date
                        },
                        onSelectWorkout: { pair in
                            selectedWorkout = CalendarWorkoutSelection(
                                id: workoutRowIdentifier(for: pair.workout),
                                analytics: pair.analytics
                            )
                        }
                    )
                }
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var selectedDayTimeline: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedDay.formatted(.dateTime.weekday(.wide).month().day()))
                        .font(.headline)
                    Text(selectedDayWorkouts.isEmpty ? "No workouts logged" : "\(selectedDayWorkouts.count) session\(selectedDayWorkouts.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if selectedDayWorkouts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recovery, mobility, or total rest can be part of consistency too.")
                        .font(.subheadline.weight(.semibold))
                    Text("Pick another day in the calendar to open the workout details sheet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                ForEach(selectedDayWorkouts, id: \.workout.uuid) { pair in
                    Button {
                        selectedWorkout = CalendarWorkoutSelection(
                            id: workoutRowIdentifier(for: pair.workout),
                            analytics: pair.analytics
                        )
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Circle()
                                .fill(activityTint(for: pair.workout.workoutActivityType))
                                .frame(width: 12, height: 12)
                                .padding(.top, 5)

                            VStack(alignment: .leading, spacing: 6) {
                                Text(pair.workout.workoutActivityType.name.capitalized)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)

                                Text("\(pair.workout.startDate.formatted(.dateTime.hour().minute())) • \(Int(pair.workout.duration / 60)) min")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 10) {
                                    if let kcal = pair.workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) {
                                        calendarMetricPill(title: "\(Int(kcal)) kcal", tint: .orange)
                                    }
                                    if let avgHR = pair.analytics.heartRates.map({ $0.1 }).average {
                                        calendarMetricPill(title: "\(Int(avgHR)) bpm", tint: .red)
                                    }
                                    if let distance = pair.workout.totalDistance?.doubleValue(for: .meter()) {
                                        let km = distance / 1000
                                        calendarMetricPill(title: String(format: "%.1f km", km), tint: .blue)
                                    }
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }
                        .padding(16)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(activityTint(for: pair.workout.workoutActivityType).opacity(0.18), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .catalystFocusablePrimaryAction {
                        selectedWorkout = CalendarWorkoutSelection(
                            id: workoutRowIdentifier(for: pair.workout),
                            analytics: pair.analytics
                        )
                    }
                }
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private static let weekdayGridColumns = Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 7)

    private func isStreakHighlightDay(_ date: Date, window: (lower: Date, upper: Date)?) -> Bool {
        guard let window else { return false }
        let day = calendar.startOfDay(for: date)
        return day >= window.lower && day <= window.upper && workoutsByDay[day] != nil
    }

    private func stepMonth(by value: Int) {
        guard let updated = calendar.date(byAdding: .month, value: value, to: selectedMonthStart) else { return }
        selectedMonth = updated
        selectedDay = calendar.startOfDay(for: updated)
    }

    private func jumpToToday() {
        let today = Date()
        selectedMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        selectedDay = calendar.startOfDay(for: today)
    }

    private func clampSelectedDayToVisibleMonth() {
        if !calendar.isDate(selectedDay, equalTo: selectedMonthStart, toGranularity: .month) {
            selectedDay = selectedMonthStart
        }

        if selectedDayWorkouts.isEmpty, let firstActiveDay = monthDays.first(where: { $0.isInDisplayedMonth && !$0.workouts.isEmpty })?.date {
            selectedDay = firstActiveDay
        }
    }

    @ViewBuilder
    private func calendarMetricPill(title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.14), in: Capsule())
    }

    private func activityTint(for type: HKWorkoutActivityType) -> Color {
        switch type {
        case .running: return .orange
        case .cycling: return .blue
        case .walking, .hiking: return .green
        case .swimming: return .teal
        case .functionalStrengthTraining, .traditionalStrengthTraining: return .red
        case .yoga, .pilates: return .purple
        default: return .yellow
        }
    }

    private func streakLength(anchoredAtToday: Bool, daySet: Set<Date>) -> Int {
        guard !daySet.isEmpty else { return 0 }

        var cursor = calendar.startOfDay(for: Date())
        if anchoredAtToday == false, let last = activeWorkoutDaysSorted.last {
            cursor = last
        } else if !daySet.contains(cursor),
                  let previous = calendar.date(byAdding: .day, value: -1, to: cursor),
                  daySet.contains(previous) {
            cursor = previous
        } else if !daySet.contains(cursor) {
            return 0
        }

        var count = 0
        while daySet.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    private func isFutureMonth(_ date: Date) -> Bool {
        date > (calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date())
    }

    @MainActor
    private func loadMonthIfNeeded(for month: Date, forceFetch: Bool) async {
        let interval = calendar.dateInterval(of: .month, for: month) ?? monthInterval
        guard forceFetch || engine.needsWorkoutAnalyticsCoverage(from: interval.start, to: interval.end) else {
            clampSelectedDayToVisibleMonth()
            return
        }

        isLoadingMonth = true
        await engine.ensureWorkoutAnalyticsCoverage(from: interval.start, to: interval.end, forceFetch: forceFetch)
        isLoadingMonth = false
        clampSelectedDayToVisibleMonth()
    }
}

private struct CalendarWorkoutSelection: Identifiable {
    let id: String
    let analytics: WorkoutAnalytics
}

private struct CalendarDaySlot: Identifiable {
    let date: Date
    let isInDisplayedMonth: Bool
    let workouts: [(workout: HKWorkout, analytics: WorkoutAnalytics)]

    var id: Date { date }
}

private struct CalendarStatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(tint)
            Text(subtitle.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(tint.opacity(0.2), lineWidth: 1)
        )
        .catalystDesktopFocusable()
        .accessibilityLabel("\(title), \(value) \(subtitle)")
    }
}

private struct TrainingCalendarDayCell: View {
    let slot: CalendarDaySlot
    let isToday: Bool
    let isSelected: Bool
    let isPartOfCurrentStreak: Bool
    let onSelectDay: () -> Void
    let onSelectWorkout: ((workout: HKWorkout, analytics: WorkoutAnalytics)) -> Void

    private var visibleWorkouts: [(workout: HKWorkout, analytics: WorkoutAnalytics)] {
        Array(slot.workouts.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Calendar.current.component(.day, from: slot.date))")
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .foregroundStyle(slot.isInDisplayedMonth ? Color.primary : Color.secondary.opacity(0.45))

                Spacer()

                if isToday {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                }
            }

            if visibleWorkouts.isEmpty {
                Spacer(minLength: 0)
            } else {
                ForEach(visibleWorkouts, id: \.workout.uuid) { pair in
                    Button {
                        onSelectDay()
                        onSelectWorkout(pair)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pair.workout.startDate.formatted(.dateTime.hour().minute()))
                                .font(.caption2.weight(.bold))
                            Text("\(pair.workout.workoutActivityType.name.capitalized) • \(Int(pair.workout.duration / 60))m")
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 6)
                        .background(
                            activityTint(for: pair.workout.workoutActivityType).opacity(0.18),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        "\(pair.workout.workoutActivityType.name.capitalized), \(pair.workout.startDate.formatted(date: .omitted, time: .shortened))"
                    )
                    .catalystFocusablePrimaryAction {
                        onSelectDay()
                        onSelectWorkout(pair)
                    }
                }

                if slot.workouts.count > visibleWorkouts.count {
                    Button(action: onSelectDay) {
                        Text("+\(slot.workouts.count - visibleWorkouts.count) more")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(slot.workouts.count - visibleWorkouts.count) additional workouts this day")
                    .catalystFocusablePrimaryAction(onSelectDay)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .background(backgroundFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(borderColor, lineWidth: isSelected ? 1.6 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture(perform: onSelectDay)
        .catalystFocusablePrimaryAction(onSelectDay)
        .accessibilityLabel(
            "Day \(Calendar.current.component(.day, from: slot.date)), \(slot.workouts.count) workout\(slot.workouts.count == 1 ? "" : "s")"
        )
    }

    private var backgroundFill: LinearGradient {
        if isSelected {
            return LinearGradient(
                colors: [Color.orange.opacity(0.24), Color.red.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        if isPartOfCurrentStreak {
            return LinearGradient(
                colors: [Color.yellow.opacity(0.14), Color.orange.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [Color.white.opacity(slot.isInDisplayedMonth ? 0.09 : 0.04), Color.black.opacity(0.04)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderColor: Color {
        if isSelected {
            return .orange.opacity(0.75)
        }
        if isPartOfCurrentStreak {
            return .yellow.opacity(0.3)
        }
        return Color.white.opacity(slot.isInDisplayedMonth ? 0.08 : 0.04)
    }

    private func activityTint(for type: HKWorkoutActivityType) -> Color {
        switch type {
        case .running: return .orange
        case .cycling: return .blue
        case .walking, .hiking: return .green
        case .swimming: return .teal
        case .functionalStrengthTraining, .traditionalStrengthTraining: return .red
        case .yoga, .pilates: return .purple
        default: return .yellow
        }
    }
}
