import SwiftUI
import HealthKit
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Tap that respects drag-to-cancel (no action / haptic if finger moves too far before lift)

private struct DragCancellableTap<Label: View>: View {
    var cancelThreshold: CGFloat = 14
    let action: () -> Void
    @ViewBuilder var label: () -> Label

    @State private var dragExceeded = false

    var body: some View {
        label()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let d = hypot(value.translation.width, value.translation.height)
                        if d > cancelThreshold {
                            dragExceeded = true
                        }
                    }
                    .onEnded { _ in
                        let shouldFire = !dragExceeded
                        dragExceeded = false
                        guard shouldFire else { return }
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        #endif
                        action()
                    }
            )
    }
}

// MARK: - Scrollable tap that allows parent ScrollView to scroll while still being tappable

private struct ScrollableTapRow<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var hasDragged = false

    var body: some View {
        content()
            .contentShape(Rectangle())
            .opacity(hasDragged ? 0.7 : 1.0)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        hasDragged = true
                    }
                    .onEnded { value in
                        hasDragged = false
                        let d = hypot(value.translation.width, value.translation.height)
                        if d < 10 {
                            #if canImport(UIKit)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            action()
                        }
                    }
            )
    }
}

// MARK: - MindfulnessRealmView

struct MindfulnessRealmView: View {
    @State private var animationPhase: Double = 0
    @State private var isLoading = true
    @State private var score: Int = 0
    @State private var mindfulMinutesToday: Double = 0
    @State private var mindfulSessionCount: Int = 0
    @State private var stateOfMindCount: Int = 0
    @State private var scoreCaption: String = ""

    @State private var showJournal = false
    @State private var showPathfinder = false

    @State private var sessionStart: Date?
    @State private var sessionTick = Date()
    private let sessionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var calendar: Calendar { Calendar.current }

    private var todayInterval: (start: Date, end: Date) {
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? Date()
        return (start, end)
    }

    private var activeMindfulSession: Bool { sessionStart != nil }

    private var sessionElapsedSeconds: Int {
        guard let start = sessionStart else { return 0 }
        return max(0, Int(sessionTick.timeIntervalSince(start)))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackgrounds().realmGradientFull(animationPhase: $animationPhase)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        scoreSection
                        statsRow
                        actionsSection
                        if activeMindfulSession {
                            sessionSection
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                }
            }
            .navigationTitle("Mindfulness Realm")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .refreshable {
                await loadData()
            }
            .onReceive(sessionTimer) { sessionTick = $0 }
            .sheet(isPresented: $showJournal) {
                JournalView()
            }
            .sheet(isPresented: $showPathfinder) {
                PathfinderView()
            }
        }
        .onAppear {
            Task { await loadData() }
            withAnimation(.linear(duration: 24).repeatForever(autoreverses: false)) {
                animationPhase = 1
            }
        }
    }

    private var scoreSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if isLoading {
                    ProgressView()
                        .tint(.primary)
                } else {
                    Text("\(score)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("Mindfulness")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            Text(scoreCaption)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            statPill(title: "Mindful min", value: mindfulMinutesToday == 0 ? "—" : String(format: "%.0f", mindfulMinutesToday))
            statPill(title: "Sessions", value: "\(mindfulSessionCount)")
            statPill(title: "Mood logs", value: "\(stateOfMindCount)")
        }
    }

    private func statPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick actions")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                realmActionRow(
                    icon: "book.fill",
                    title: "Journal",
                    subtitle: "Reflect and capture context"
                ) {
                    showJournal = true
                }

                realmActionRow(
                    icon: "point.3.connected.trianglepath.dotted",
                    title: "Pathfinder",
                    subtitle: "Patterns from mood and life areas"
                ) {
                    showPathfinder = true
                }

                if !activeMindfulSession {
                    realmActionRow(
                        icon: "timer",
                        title: "Start mindful minute",
                        subtitle: "Counts toward Mindful Minutes when you end the session"
                    ) {
                        sessionStart = Date()
                    }
                }
            }
        }
    }

    private func realmActionRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        ScrollableTapRow(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 40, height: 40)
                    .background(Color.primary.opacity(0.08), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active session")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack {
                Text(formatElapsed(sessionElapsedSeconds))
                    .font(.system(.title2, design: .monospaced).weight(.semibold))
                Spacer()
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            DragCancellableTap(action: { endMindfulSession(save: true) }) {
                Text("End & save to Health")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor.opacity(0.25), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            DragCancellableTap(action: { endMindfulSession(save: false) }) {
                Text("Cancel session")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
        }
    }

    private func formatElapsed(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private func endMindfulSession(save: Bool) {
        guard let start = sessionStart else { return }
        sessionStart = nil
        let end = Date()
        guard save, end.timeIntervalSince(start) >= 5 else { return }
        let duration = end.timeIntervalSince(start)
        HealthKitManager().saveMindfulSession(start: start, end: end) { success, _ in
            if success {
                let minutes = duration / 60.0
                NotificationCenter.default.post(
                    name: .nutrivanceViewControlPathfinderMindfulnessLogged,
                    object: minutes
                )
            }
        }
        Task { await loadData() }
    }

    @MainActor
    private func loadData() async {
        isLoading = true
        let range = todayInterval
        let hkm = HealthKitManager()

        async let samplesTask = hkm.fetchMindfulSessionSamples(from: range.start, to: range.end)
        async let statesTask = hkm.fetchStateOfMindSamples(from: range.start, to: range.end)

        let samples = await samplesTask
        let states = await statesTask

        let minutes = samples.reduce(0.0) { partial, sample in
            partial + sample.endDate.timeIntervalSince(sample.startDate) / 60.0
        }

        mindfulMinutesToday = minutes
        mindfulSessionCount = samples.count
        stateOfMindCount = states.count

        let computed = Self.computeMindfulnessScore(mindfulMinutes: minutes, states: states)
        score = computed.value
        scoreCaption = computed.caption
        isLoading = false
    }

    /// Blends logged **Mindful Minutes** (HealthKit mindful sessions) with **State of Mind** valence for today.
    private static func computeMindfulnessScore(mindfulMinutes: Double, states: [HKStateOfMind]) -> (value: Int, caption: String) {
        let practiceProgress = min(1, mindfulMinutes / 25)

        let moodNormalized: Double
        if states.isEmpty {
            moodNormalized = 0.42
        } else {
            let avg = states.reduce(0.0) { $0 + $1.valence } / Double(states.count)
            moodNormalized = (avg + 1) / 2
        }

        let blend = 0.55 * practiceProgress + 0.45 * moodNormalized
        let value = Int((blend * 100).rounded())
        let clamped = min(100, max(0, value))

        let cap = "About 25 mindful minutes today contributes fully to the practice side of this score."
        if states.isEmpty {
            return (clamped, "Practice from Mindful Minutes plus a neutral mood baseline. Log State of Mind in Health or Pathfinder to reflect your emotional tone. \(cap)")
        }
        return (clamped, "Weighted toward mindful practice and today’s average mood valence from Health. \(cap)")
    }
}

#Preview {
    MindfulnessRealmView()
}
