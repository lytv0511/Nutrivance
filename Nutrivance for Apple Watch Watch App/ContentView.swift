//
//  ContentView.swift
//  Nutrivance for Apple Watch Watch App
//
//  Created by Vincent Leong on 3/25/26.
//

import Combine
import CoreLocation
import Foundation
import HealthKit
import MapKit
import SwiftUI
import WatchKit
import WorkoutKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = WatchDashboardStore()
    @StateObject private var workoutManager = WatchWorkoutManager.shared
    @State private var selectedTab: DashboardTab = .overview

    var body: some View {
        Group {
            if workoutManager.isSessionActive {
                ActiveWorkoutCardsView(manager: workoutManager)
            } else if workoutManager.postWorkoutDestination == .effortPrompt {
                WorkoutEffortPromptView(manager: workoutManager)
            } else if workoutManager.postWorkoutDestination == .nextWorkoutPicker {
                WorkoutLauncherView(store: store)
            } else {
                NavigationStack {
                    TabView(selection: $selectedTab) {
                        OverviewDashboardPage(store: store, selectedTab: $selectedTab)
                            .tag(DashboardTab.overview)

                        StrainDashboardPage(store: store, selectedTab: $selectedTab)
                            .tag(DashboardTab.strain)

                        RecoveryDashboardPage(store: store, selectedTab: $selectedTab)
                            .tag(DashboardTab.recovery)

                        MindfulnessDashboardPage(store: store, selectedTab: $selectedTab)
                            .tag(DashboardTab.mindfulness)

                        WorkoutHistoryDashboardPage(store: store)
                            .tag(DashboardTab.history)
                    }
                    .tabViewStyle(.verticalPage)
                    .ignoresSafeArea()
                    .containerBackground(.clear, for: .navigation)
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationDestination(for: WatchDestination.self) { destination in
                        destinationView(for: destination)
                    }
                }
            }
        }
        .background(
            WatchDashboardBackground(style: selectedTab.backgroundStyle)
                .ignoresSafeArea()
        )
        .onAppear {
            store.refreshLiveData()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                store.refreshLiveData()
            }
        }
    }

    @ViewBuilder
    private func destinationView(for destination: WatchDestination) -> some View {
        switch destination {
        case .sleepManager:
            SleepManagerView(store: store)
        case .workoutLauncher:
            WorkoutLauncherView(store: store)
        case .journaling:
            JournalComposerView(store: store, title: "Journaling")
        case .hrZones:
            HRZonesView(store: store)
        case .load:
            TrainingLoadView(store: store)
        case .stats:
            StatsSnapshotView(store: store)
        case .coach:
            CoachSummaryView(store: store)
        case .vitals:
            VitalsDetailView(store: store)
        case .hrv:
            TrendMetricDetailView(
                title: "HRV",
                subtitle: "",
                points: store.hrvWeek,
                unit: "ms",
                accent: .mint,
                idealRange: 52...65
            )
        case .hrr:
            TrendMetricDetailView(
                title: "HRR",
                subtitle: "",
                points: store.hrrWeek,
                unit: "bpm",
                accent: .cyan,
                idealRange: 24...32
            )
        case .rhr:
            TrendMetricDetailView(
                title: "RHR",
                subtitle: "",
                points: store.rhrWeek,
                unit: "bpm",
                accent: .pink,
                idealRange: 50...58
            )
        case .moodLogger:
            MoodLoggerView(store: store)
        case .stress:
            StressTrendView(store: store)
        case .sleep:
            SleepSnapshotView(store: store)
        case .journalSnippets:
            JournalComposerView(store: store, title: "Journal Snippets")
        case .workoutDetail(let workoutID):
            if let workout = store.workout(id: workoutID) {
                WorkoutDetailView(workout: workout)
            } else {
                MissingWorkoutView()
            }
        }
    }
}

private enum ActiveWorkoutSidePane: Int {
    case controls
    case main
    case media
}

private enum WorkoutMetricsVariant {
    case primary
    case secondary
}

private struct ActiveWorkoutCardsView: View {
    @ObservedObject var manager: WatchWorkoutManager
    @StateObject private var mapTracker = WatchWorkoutMapTracker()
    @State private var verticalSelection: WatchWorkoutPageKind = .metricsPrimary
    @State private var horizontalSelection: ActiveWorkoutSidePane = .main
    @State private var shouldPrewarmMap = true
    @State private var shouldActivateMapTracker = false

    private var verticalPages: [WatchWorkoutPageKind] {
        manager.orderedWorkoutPages
    }

    private var supportsMapPage: Bool {
        verticalPages.contains(.map)
    }

    var body: some View {
        TabView(selection: $horizontalSelection) {
            WorkoutControlsCard(
                manager: manager,
                onWaterLock: {
                    verticalSelection = verticalPages.first ?? .metricsPrimary
                    horizontalSelection = .main
                    mapTracker.setActive(false)
                    manager.enableWaterLock()
                }
            )
                .tag(ActiveWorkoutSidePane.controls)

            TabView(selection: $verticalSelection) {
                ForEach(verticalPages) { page in
                    WorkoutLivePageView(
                        manager: manager,
                        mapTracker: mapTracker,
                        page: page
                    )
                    .tag(page)
                }
            }
            .tabViewStyle(.verticalPage(transitionStyle: .automatic))
            .tag(ActiveWorkoutSidePane.main)

            WorkoutMediaCard()
                .tag(ActiveWorkoutSidePane.media)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Color.black.ignoresSafeArea())
        .overlay {
            if shouldActivateMapTracker && shouldPrewarmMap && supportsMapPage {
                WorkoutMapPrewarmView(mapTracker: mapTracker)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .onAppear {
            verticalSelection = verticalPages.first ?? .metricsPrimary
            mapTracker.setActive(false)
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard !Task.isCancelled else { return }
                guard supportsMapPage else {
                    shouldPrewarmMap = false
                    return
                }
                shouldActivateMapTracker = true
                mapTracker.activate()
                mapTracker.setActive(verticalSelection == .map)
            }
            Task {
                try? await Task.sleep(nanoseconds: 3_200_000_000)
                guard !Task.isCancelled else { return }
                shouldPrewarmMap = false
            }
        }
        .onChange(of: manager.orderedWorkoutPages) { _, newPages in
            guard let firstPage = newPages.first else { return }
            if !newPages.contains(verticalSelection) {
                verticalSelection = firstPage
            }
        }
        .onChange(of: verticalSelection) { _, newValue in
            if newValue == .map && !shouldActivateMapTracker {
                shouldActivateMapTracker = true
                mapTracker.activate()
            }
            mapTracker.setActive(newValue == .map)
            if newValue == .map {
                shouldPrewarmMap = false
            }
        }
    }
}

private struct WorkoutLivePageView: View {
    @ObservedObject var manager: WatchWorkoutManager
    @ObservedObject var mapTracker: WatchWorkoutMapTracker
    let page: WatchWorkoutPageKind

    var body: some View {
        Group {
            switch page {
            case .metricsPrimary:
                WorkoutMetricsCard(manager: manager, variant: .primary)
            case .metricsSecondary:
                WorkoutMetricsCard(manager: manager, variant: .secondary)
            case .heartRateZones:
                WorkoutZonesCard(manager: manager)
            case .segments:
                WorkoutSegmentsCard(manager: manager)
            case .splits:
                WorkoutSplitsCard(manager: manager)
            case .elevationGraph:
                WorkoutMetricGraphCard(manager: manager, metric: .elevation)
            case .powerGraph:
                WorkoutMetricGraphCard(manager: manager, metric: .power)
            case .powerZones:
                WorkoutPowerZonesCard(manager: manager)
            case .pacer:
                WorkoutPacerCard(manager: manager)
            case .map:
                WorkoutMapCard(mapTracker: mapTracker)
            }
        }
        .padding(.horizontal, page == .map ? 0 : 2)
        .padding(.vertical, page == .map ? 0 : 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct WorkoutMetricsCard: View {
    @ObservedObject var manager: WatchWorkoutManager
    let variant: WorkoutMetricsVariant
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: watchWorkoutSymbol(manager.activeActivity))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.green)
                    .frame(width: 34, height: 34)
                    .background(Color.green.opacity(0.18))
                    .clipShape(Circle())

                Text(workoutElapsedDisplayString(manager.elapsedTime, reducedLuminance: isLuminanceReduced))
                    .font(.system(size: 28, weight: .black, design: .rounded).monospacedDigit())
                    .fontWidth(.condensed)
                    .foregroundStyle(.yellow)
                    .privacySensitive()

                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(manager.currentHeartRate.map { "\(Int($0.rounded()))" } ?? "--")
                        .font(.system(size: 25, weight: .black, design: .rounded).monospacedDigit())
                        .fontWidth(.condensed)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(.red)
                }
                .padding(.bottom, 2)

                ForEach(metricLines(for: manager, variant: variant)) { line in
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(line.value)
                            .font(.system(size: 24, weight: .black, design: .rounded).monospacedDigit())
                            .fontWidth(.condensed)
                        if !line.label.isEmpty {
                            Text(line.label)
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .fontWidth(.compressed)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 4)
        }
    }
}

private struct WorkoutZonesCard: View {
    @ObservedObject var manager: WatchWorkoutManager
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        GeometryReader { geometry in
            let currentZone = manager.currentZoneIndex ?? 0
            let timeInZone = manager.liveZoneDurations[safe: currentZone] ?? 0

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Image(systemName: watchWorkoutSymbol(manager.activeActivity))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.green)
                        .frame(width: 34, height: 34)
                        .background(Color.green.opacity(0.18))
                        .clipShape(Circle())
                    Spacer(minLength: 0)
                }

                Text(workoutElapsedDisplayString(manager.elapsedTime, reducedLuminance: isLuminanceReduced))
                    .font(.system(size: 27, weight: .black, design: .rounded).monospacedDigit())
                    .fontWidth(.condensed)
                    .foregroundStyle(.yellow)

                WorkoutZoneStrip(currentZone: currentZone)
                    .padding(.vertical, 2)

                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(manager.currentHeartRate.map { "\(Int($0.rounded()))" } ?? "--")
                        .font(.system(size: 26, weight: .black, design: .rounded).monospacedDigit())
                        .fontWidth(.condensed)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(.red)
                }

                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(shortElapsedString(timeInZone))
                        .font(.system(size: 24, weight: .black, design: .rounded).monospacedDigit())
                        .fontWidth(.condensed)
                    Text("TIME\nIN ZONE")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .fontWidth(.compressed)
                        .foregroundStyle(.white.opacity(0.82))
                }

                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(manager.averageHeartRate.map { "\(Int($0.rounded()))BPM" } ?? "--")
                        .font(.system(size: 24, weight: .black, design: .rounded).monospacedDigit())
                        .fontWidth(.condensed)
                    Text("AVERAGE\nHR")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .fontWidth(.condensed)
                        .foregroundStyle(.white.opacity(0.82))
                }

                Spacer(minLength: 0)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 4)
        }
    }
}

private enum WorkoutGraphMetric {
    case elevation
    case power

    var accent: Color {
        switch self {
        case .elevation:
            return .green
        case .power:
            return .yellow
        }
    }

    var title: String {
        switch self {
        case .elevation:
            return "ELEVATION"
        case .power:
            return "POWER"
        }
    }

    var symbol: String {
        switch self {
        case .elevation:
            return "mountain.2.fill"
        case .power:
            return "bolt.fill"
        }
    }
}

private struct WorkoutSegmentsCard: View {
    @ObservedObject var manager: WatchWorkoutManager
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        WorkoutMetricGraphScaffold(
            elapsedTime: manager.elapsedTime,
            isLuminanceReduced: isLuminanceReduced,
            accent: .cyan,
            symbol: "chart.bar.xaxis",
            activitySymbol: watchWorkoutSymbol(manager.activeActivity),
            points: segmentGraphPoints(for: manager),
            topValue: segmentPrimaryValue(for: manager),
            topLabel: segmentPrimaryLabel(for: manager),
            bottomValue: segmentSecondaryValue(for: manager),
            bottomLabel: segmentSecondaryLabel(for: manager)
        )
    }
}

private struct WorkoutSplitsCard: View {
    @ObservedObject var manager: WatchWorkoutManager
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private var currentSplitDuration: TimeInterval {
        max(manager.elapsedTime - latestSplitElapsedTime, 0)
    }

    private var latestSplitElapsedTime: TimeInterval {
        manager.splits.last?.elapsedTime ?? 0
    }

    private var currentSplitDistanceMeters: Double {
        max(manager.totalDistanceMeters - latestSplitDistanceMeters, 0)
    }

    private var latestSplitDistanceMeters: Double {
        manager.splits.reduce(0) { $0 + $1.splitDistanceMeters }
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 8) {
                Text(workoutElapsedDisplayString(manager.elapsedTime, reducedLuminance: isLuminanceReduced))
                    .font(.system(size: 27, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(.yellow)

                Text(shortElapsedString(currentSplitDuration))
                    .font(.system(size: 28, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                Text("CURRENT SPLIT")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))

                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(splitSpeedValue(for: manager, splitDistanceMeters: currentSplitDistanceMeters, splitDuration: currentSplitDuration))
                            .font(.system(size: 24, weight: .black, design: .rounded).monospacedDigit())
                        Text(splitSpeedLabel(for: manager))
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .foregroundStyle(.white.opacity(0.62))
                    }
                    Spacer(minLength: 12)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(splitDistanceValue(for: manager, splitDistanceMeters: currentSplitDistanceMeters))
                            .font(.system(size: 24, weight: .black, design: .rounded).monospacedDigit())
                        Text("SPLIT DIST")
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .foregroundStyle(.white.opacity(0.62))
                    }
                }

                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(manager.currentHeartRate.map { "\(Int($0.rounded()))" } ?? "--")
                        .font(.system(size: 23, weight: .black, design: .rounded).monospacedDigit())
                    Text("BPM")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(.red.opacity(0.9))
                }
                .foregroundStyle(.white)

                if let latest = manager.splits.last {
                    Divider()
                        .overlay(Color.white.opacity(0.12))
                        .padding(.vertical, 2)

                    Text("LAST \(latest.index)")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                    Text(shortElapsedString(latest.splitDuration))
                        .font(.system(size: 20, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(.cyan)
                }

                Spacer(minLength: 0)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .padding(.horizontal, 10)
            .padding(.top, 6)
        }
    }
}

private struct WorkoutMetricGraphCard: View {
    @ObservedObject var manager: WatchWorkoutManager
    let metric: WorkoutGraphMetric
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        WorkoutMetricGraphScaffold(
            elapsedTime: manager.elapsedTime,
            isLuminanceReduced: isLuminanceReduced,
            accent: metric.accent,
            symbol: metric.symbol,
            activitySymbol: watchWorkoutSymbol(manager.activeActivity),
            points: metric == .elevation ? manager.elevationHistory : manager.powerHistory,
            topValue: metricPrimaryValue(metric, manager: manager),
            topLabel: metricPrimaryLabel(metric),
            bottomValue: metricSecondaryValue(metric, manager: manager),
            bottomLabel: metricSecondaryLabel(metric, manager: manager)
        )
    }
}

private struct WorkoutPowerZonesCard: View {
    @ObservedObject var manager: WatchWorkoutManager
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private var currentZone: Int {
        manager.currentPowerWatts.map(powerZoneIndex) ?? 0
    }

    var body: some View {
        GeometryReader { geometry in
            let timeInZone = manager.powerZoneDurations[safe: currentZone] ?? 0
            VStack(alignment: .leading, spacing: 10) {
                Text(workoutElapsedDisplayString(manager.elapsedTime, reducedLuminance: isLuminanceReduced))
                    .font(.system(size: 27, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(.yellow)

                WorkoutPowerZoneStrip(currentZone: currentZone)
                    .padding(.vertical, 6)

                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(manager.currentPowerWatts.map { "\(Int($0.rounded()))" } ?? "--")
                        .font(.system(size: 30, weight: .black, design: .rounded).monospacedDigit())
                    Text("W")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.yellow.opacity(0.9))
                }

                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(shortElapsedString(timeInZone))
                        .font(.system(size: 24, weight: .black, design: .rounded).monospacedDigit())
                    Text("TIME\nIN ZONE")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                }

                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(manager.currentCadence.map { "\(Int($0.rounded()))" } ?? "--")
                        .font(.system(size: 24, weight: .black, design: .rounded).monospacedDigit())
                    Text("CADENCE")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                }

                Spacer(minLength: 0)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .padding(.horizontal, 10)
            .padding(.top, 6)
        }
    }
}

private struct WorkoutPacerCard: View {
    @ObservedObject var manager: WatchWorkoutManager
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 10) {
                Text(workoutElapsedDisplayString(manager.elapsedTime, reducedLuminance: isLuminanceReduced))
                    .font(.system(size: 27, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(.yellow)

                if let pacerTarget = manager.pacerTarget {
                    WorkoutPacerBar(
                        progress: pacerProgress(for: manager, target: pacerTarget),
                        inTarget: pacerInRange(for: manager, target: pacerTarget)
                    )
                    .frame(height: 38)

                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(pacerAverageValue(for: manager))
                            .font(.system(size: 28, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundStyle(.mint)
                        Text("AVERAGE")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundStyle(.mint.opacity(0.85))
                    }

                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(pacerCurrentValue(for: manager))
                            .font(.system(size: 28, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                        Text("CURRENT")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                } else {
                    Text("Pacer is available for moving workouts.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.68))
                }

                Text(distanceSummaryValue(for: manager))
                    .font(.system(size: 30, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)

                Spacer(minLength: 0)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .padding(.horizontal, 10)
            .padding(.top, 6)
        }
    }
}

private struct WorkoutMetricGraphScaffold: View {
    let elapsedTime: TimeInterval
    let isLuminanceReduced: Bool
    let accent: Color
    let symbol: String
    let activitySymbol: String
    let points: [WatchWorkoutSeriesPoint]
    let topValue: String
    let topLabel: String
    let bottomValue: String
    let bottomLabel: String

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    Image(systemName: activitySymbol)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(accent)
                        .frame(width: 34, height: 34)
                        .background(accent.opacity(0.18))
                        .clipShape(Circle())
                    Spacer(minLength: 0)
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(accent.opacity(0.85))
                }

                HStack(alignment: .top) {
                    Text(workoutElapsedDisplayString(elapsedTime, reducedLuminance: isLuminanceReduced))
                        .font(.system(size: 27, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(.yellow)
                    Spacer(minLength: 0)
                }

                WorkoutHistorySparkline(points: points, accent: accent)
                    .frame(height: max(72, geometry.size.height * 0.34))

                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(topValue)
                            .font(.system(size: 26, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundStyle(accent)
                        Text(topLabel)
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundStyle(accent.opacity(0.78))
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(topValue)
                            .hidden()
                        Text(bottomValue)
                            .font(.system(size: 26, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                        Text(bottomLabel)
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .padding(.horizontal, 10)
            .padding(.top, 6)
        }
    }
}

private struct WorkoutHistorySparkline: View {
    let points: [WatchWorkoutSeriesPoint]
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            let values = points.map(\.value)
            let minValue = values.min() ?? 0
            let maxValue = max(values.max() ?? 1, minValue + 1)
            let chartHeight = proxy.size.height
            let barCount = max(32, Int(proxy.size.width / 3.6))
            let sampledValues = denseGraphSamples(from: points, count: barCount)

            ZStack(alignment: .bottomTrailing) {
                HStack(alignment: .bottom, spacing: 1.5) {
                    ForEach(Array(sampledValues.enumerated()), id: \.offset) { _, value in
                        let ratio = (value - minValue) / max(maxValue - minValue, 0.001)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [accent.opacity(0.45), accent],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(maxWidth: .infinity, maxHeight: max(8, chartHeight * CGFloat(ratio.clamped(to: 0...1))), alignment: .bottom)
                    }
                }

                VStack(alignment: .trailing, spacing: 0) {
                    Text(shortMetricAxisLabel(maxValue))
                    Spacer()
                    Text(shortMetricAxisLabel(minValue))
                }
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.white.opacity(0.46))
            }
            .overlay(alignment: .bottomLeading) {
                HStack {
                    Text("30 MIN AGO")
                    Spacer()
                    Text("NOW")
                }
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .offset(y: 14)
            }
        }
        .padding(.trailing, 18)
        .padding(.bottom, 16)
    }
}

private struct WorkoutPowerZoneStrip: View {
    let currentZone: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(index == currentZone ? powerZoneColor(index) : powerZoneColor(index).opacity(0.26))
                    .frame(width: index == currentZone ? 62 : 24, height: index == currentZone ? 28 : 24)
                    .overlay {
                        if index == currentZone {
                            Text("P\(index + 1)")
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .foregroundStyle(.black)
                        }
                    }
            }
        }
    }
}

private struct WorkoutPacerBar: View {
    let progress: Double
    let inTarget: Bool

    var body: some View {
        GeometryReader { proxy in
            let clampedProgress = progress.clamped(to: 0...1)
            let width = proxy.size.width
            let markerX = width * CGFloat(clampedProgress)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.red.opacity(0.58))
                    .frame(height: 30)

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.green.opacity(0.68))
                    .frame(width: width * 0.52, height: 30)
                    .offset(x: width * 0.24)

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(inTarget ? Color.green : Color.mint)
                    .frame(width: 54, height: 38)
                    .offset(x: max(0, min(width - 54, markerX - 27)))
                    .overlay {
                        Text(inTarget ? "ON" : "OFF")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundStyle(.black)
                    }
            }
        }
    }
}

private struct WorkoutMapCard: View {
    @ObservedObject var mapTracker: WatchWorkoutMapTracker

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if mapTracker.hasRenderableMap {
                WorkoutMapSurface(mapTracker: mapTracker)
                    .ignoresSafeArea()
                    .clipped()
            } else {
                ZStack {
                    Color.black.ignoresSafeArea()
                    VStack(spacing: 8) {
                        ProgressView()
                            .tint(.white)
                        Text(mapTracker.statusText)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .fontWidth(.compressed)
                            .foregroundStyle(.white.opacity(0.72))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 14)
                }
            }

            Text("MAP")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .fontWidth(.compressed)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(8)
        }
        .ignoresSafeArea()
    }
}

private struct WorkoutMapSurface: View {
    @ObservedObject var mapTracker: WatchWorkoutMapTracker

    var body: some View {
        Map(position: $mapTracker.position, interactionModes: []) {
            if let coordinate = mapTracker.userCoordinate {
                Annotation("", coordinate: coordinate, anchor: .center) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.22))
                            .frame(width: 28, height: 28)
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 12, height: 12)
                        Image(systemName: "location.north.fill")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(.white)
                            .offset(y: -13)
                    }
                }
            }
        }
        .mapStyle(.standard)
    }
}

private struct WorkoutMapPrewarmView: View {
    @ObservedObject var mapTracker: WatchWorkoutMapTracker

    var body: some View {
        Group {
            if mapTracker.hasRenderableMap {
                WorkoutMapSurface(mapTracker: mapTracker)
                    .frame(width: 2, height: 2)
                    .opacity(0.01)
                    .clipped()
            }
        }
    }
}

private struct WorkoutMediaCard: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
            Color.black.ignoresSafeArea()
            NowPlayingView()
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

private struct WorkoutControlsCard: View {
    @ObservedObject var manager: WatchWorkoutManager
    let onWaterLock: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let gridWidth = max(geometry.size.width - 10, 160.0)

            VStack(spacing: 6) {
                let columns = [GridItem(.fixed((gridWidth - 4) / 2), spacing: 4), GridItem(.fixed((gridWidth - 4) / 2), spacing: 4)]

                LazyVGrid(columns: columns, spacing: 4) {
                    if manager.displayState == .running {
                        WorkoutControlPill(symbol: "pause.fill", title: "Pause", tint: Color(red: 0.58, green: 0.52, blue: 0.22)) {
                            manager.pause()
                        }
                    } else if manager.displayState == .paused {
                        WorkoutControlPill(symbol: "play.fill", title: "Resume", tint: Color(red: 0.22, green: 0.55, blue: 0.36)) {
                            manager.resume()
                        }
                    } else {
                        Color.clear
                            .frame(height: 38)
                    }

                    WorkoutControlPill(symbol: "flag.checkered", title: "Split", tint: Color(red: 0.27, green: 0.42, blue: 0.58)) {
                        manager.markSplit()
                    }

                    WorkoutControlPill(symbol: "drop.fill", title: "Lock", tint: Color(red: 0.24, green: 0.47, blue: 0.52)) {
                        onWaterLock()
                    }

                    WorkoutControlPill(symbol: "iphone", title: "Phone", tint: Color(red: 0.31, green: 0.51, blue: 0.49)) {
                        manager.showOnPhone()
                    }

                    WorkoutControlPill(symbol: "plus.circle.fill", title: "New", tint: Color(red: 0.52, green: 0.38, blue: 0.23)) {
                        manager.newWorkout()
                    }

                    WorkoutControlPill(symbol: "stop.fill", title: "Stop", tint: Color(red: 0.56, green: 0.24, blue: 0.24)) {
                        manager.end()
                    }
                }
                .frame(width: gridWidth)

                Text(manager.statusMessage)
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .fontWidth(.compressed)
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .frame(width: gridWidth)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 0)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .padding(.top, 4)
            .padding(.bottom, 0)
        }
    }
}

private struct WorkoutZoneStrip: View {
    let currentZone: Int

    var body: some View {
        HStack(spacing: 4) {
            zoneItem(0)
            zoneItem(1)
            zoneItem(2)
            zoneItem(3)
            zoneItem(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func zoneItem(_ index: Int) -> some View {
        let isCurrent = index == currentZone

        if isCurrent {
            VStack(spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 9, weight: .black))
                    Text("ZONE \(index + 1)")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .fontWidth(.compressed)
                }
                .foregroundStyle(.black)
                .frame(width: 94, height: 28)
                .background(zoneColor(index).opacity(0.98))
                .clipShape(Capsule())

                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(.white)
            }
        } else {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(zoneColor(index).opacity(0.45))
                .frame(width: 20, height: 28)
                .padding(.bottom, 9)
        }
    }
}

private struct WorkoutControlPill: View {
    let symbol: String
    let title: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .fontWidth(.compressed)
                    .foregroundStyle(.white.opacity(0.88))
            }
            .frame(width: 78, height: 48)
            .background(
                LinearGradient(
                    colors: [Color(white: 0.19), Color(white: 0.11)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                Capsule()
                    .stroke(tint.opacity(0.45), lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            TapGesture().onEnded {
                WKInterfaceDevice.current().play(.click)
            }
        )
    }
}

@MainActor
private final class WatchWorkoutMapTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var position: MapCameraPosition = .automatic
    @Published var userCoordinate: CLLocationCoordinate2D?
    @Published var statusText = "Locating..."

    private let locationManager = CLLocationManager()
    private var hasActivated = false
    private var isActive = false
    private var isPrewarming = false
    private var lastLocation: CLLocation?
    private var lastHeading: CLLocationDirection?
    private var lastCameraUpdate = Date.distantPast

    var hasRenderableMap: Bool {
        userCoordinate != nil
    }

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.activityType = .fitness
        locationManager.distanceFilter = 10
        locationManager.headingFilter = 10
    }

    func activate() {
        guard !hasActivated else { return }
        hasActivated = true
        locationManager.requestWhenInUseAuthorization()
        if let currentLocation = locationManager.location {
            lastLocation = currentLocation
            userCoordinate = currentLocation.coordinate
            statusText = "Following your route"
            updateCamera(force: true)
        }
        beginPrewarm()
        setActive(isActive)
    }

    func setActive(_ active: Bool) {
        isActive = active
        guard hasActivated else { return }

        if active {
            isPrewarming = false
            statusText = userCoordinate == nil ? "Locating..." : "Following your route"
            locationManager.startUpdatingLocation()
            locationManager.startUpdatingHeading()
            locationManager.requestLocation()
            if let currentLocation = locationManager.location {
                lastLocation = currentLocation
                userCoordinate = currentLocation.coordinate
                statusText = "Following your route"
            }
            updateCamera(force: true)
        } else {
            locationManager.stopUpdatingHeading()
            if !isPrewarming {
                locationManager.stopUpdatingLocation()
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            statusText = "Locating..."
            setActive(isActive)
        case .denied, .restricted:
            statusText = "Location access needed"
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let previousLocation = lastLocation
        lastLocation = location
        userCoordinate = location.coordinate
        statusText = "Following your route"
        updateCamera(previousLocation: previousLocation)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        guard heading >= 0 else { return }
        lastHeading = heading
        updateCamera(previousLocation: lastLocation)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if userCoordinate == nil {
            statusText = "Waiting for GPS"
        }
    }

    private func updateCamera(previousLocation: CLLocation? = nil, force: Bool = false) {
        guard (isActive || isPrewarming), let location = lastLocation else { return }

        let now = Date()
        let movedEnough = previousLocation.map { previous in
            location.distance(from: previous) >= 10
        } ?? true
        let headingChangedEnough = lastHeading.map { heading in
            let prior = (positionHeading ?? heading)
            return abs(heading - prior) >= 8
        } ?? false

        guard force || movedEnough || headingChangedEnough || now.timeIntervalSince(lastCameraUpdate) > 1.0 else {
            return
        }

        let heading = lastHeading ?? location.course.clamped(to: 0...359)
        let camera = MapCamera(
            centerCoordinate: location.coordinate,
            distance: 243.84,
            heading: heading.isFinite ? heading : 0,
            pitch: 0
        )
        position = .camera(camera)
        positionHeading = heading
        lastCameraUpdate = now
    }

    private func beginPrewarm() {
        guard !isActive else { return }
        isPrewarming = true
        locationManager.startUpdatingLocation()
        locationManager.requestLocation()

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self else { return }
            self.isPrewarming = false
            if !self.isActive {
                self.locationManager.stopUpdatingLocation()
                self.locationManager.stopUpdatingHeading()
            }
        }
    }

    private var positionHeading: CLLocationDirection?
}

private enum DashboardTab: Int, CaseIterable, Hashable {
    case overview
    case strain
    case recovery
    case mindfulness
    case history

    var backgroundStyle: WatchDashboardBackgroundStyle {
        switch self {
        case .overview, .history:
            return .neutral
        case .strain:
            return .orange
        case .recovery:
            return .green
        case .mindfulness:
            return .blue
        }
    }
}

private enum WatchDashboardBackgroundStyle {
    case neutral
    case orange
    case green
    case blue

    var topColor: Color {
        switch self {
        case .neutral:
            return Color(white: 0.20)
        case .orange:
            return Color(red: 0.38, green: 0.18, blue: 0.05)
        case .green:
            return Color(red: 0.08, green: 0.27, blue: 0.16)
        case .blue:
            return Color(red: 0.07, green: 0.18, blue: 0.30)
        }
    }

    var glowColor: Color {
        switch self {
        case .neutral:
            return Color.white.opacity(0.10)
        case .orange:
            return Color.orange.opacity(0.22)
        case .green:
            return Color.green.opacity(0.20)
        case .blue:
            return Color.cyan.opacity(0.22)
        }
    }
}

private enum WatchDestination: Hashable {
    case sleepManager
    case workoutLauncher
    case journaling
    case hrZones
    case load
    case stats
    case coach
    case vitals
    case hrv
    case hrr
    case rhr
    case moodLogger
    case stress
    case sleep
    case journalSnippets
    case workoutDetail(UUID)
}

private enum CornerPlacement {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
}

private enum MetricBand: String {
    case low = "Low"
    case optimal = "Optimal"
    case high = "High"

    var color: Color {
        switch self {
        case .low:
            return .blue
        case .optimal:
            return .green
        case .high:
            return .orange
        }
    }
}

enum CoachWindow: String, CaseIterable, Identifiable {
    case day = "1D"
    case week = "1W"
    case month = "1M"

    var id: String { rawValue }
}

private struct DashboardAction: Identifiable {
    let id = UUID()
    let title: String
    let symbol: String
    let placement: CornerPlacement
    let route: DashboardActionRoute
}

private enum DashboardActionRoute {
    case destination(WatchDestination)
    case tab(DashboardTab)
}

struct MetricPoint: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let value: Double
}

struct StressPoint: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let stress: Double
    let energy: Double
    let regulation: Double
}

struct JournalSnippet: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let text: String
}

struct WorkoutSession: Identifiable, Hashable {
    let id: UUID
    let title: String
    let subtitle: String
    let startDate: Date
    let durationMinutes: Int
    let calories: Int
    let distanceKilometers: Double?
    let averageHeartRate: Int
    let maxHeartRate: Int
    let strain: Double
    let load: Double
    let zoneMinutes: [Double]
    let note: String
}

struct VitalGauge: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let value: Double
    let displayValue: String
    let minimum: Double
    let normalRange: ClosedRange<Double>
    let maximum: Double
}

@MainActor
final class WatchDashboardStore: ObservableObject {
    @Published var wakeUpTime: Date
    @Published var latestMoodIndex: Int
    @Published var moodNote: String
    @Published var queuedWorkout: String?
    @Published var journalSnippets: [JournalSnippet]

    @Published var strainWeek: [MetricPoint]
    @Published var recoveryWeek: [MetricPoint]
    @Published var readinessWeek: [MetricPoint]
    @Published var mindfulnessWeek: [MetricPoint]
    @Published var trainingLoadWeek: [MetricPoint]
    @Published var hrvWeek: [MetricPoint]
    @Published var hrrWeek: [MetricPoint]
    @Published var rhrWeek: [MetricPoint]
    @Published var stressWeek: [StressPoint]
    @Published var workouts: [WorkoutSession]
    @Published var vitals: [VitalGauge]
    @Published var coachSummaries: [CoachWindow: String]
    @Published var recommendedSleepHours: Double = 8.3
    @Published var sleepDebtHours: Double = 1.4
    @Published var sleepScheduleText = "10:30 PM - 7:00 AM"
    @Published var sleepHours = 7.6
    @Published var sleepConsistency = 88.0
    @Published var sleepStages: [(name: String, hours: Double, color: Color)] = [
        ("Core", 4.2, Color.blue),
        ("REM", 1.7, Color.purple),
        ("Deep", 1.1, Color.indigo)
    ]
    let workoutTemplates = WatchWorkoutTemplate.defaults
    let wakeScheduler = WatchWakeScheduler()
    let workoutManager = WatchWorkoutManager.shared
    @Published var stats: [(title: String, value: String, symbol: String, tint: Color)] = [
        ("Calories", "742 kcal", "flame.fill", .orange),
        ("Steps", "11,082", "figure.walk", .green),
        ("Active", "96 min", "bolt.heart.fill", .cyan),
        ("Move", "8.6 km", "location.fill", .yellow)
    ]
    @Published private(set) var lastSyncedAt: Date?

    let connectivityBridge = WatchConnectivityBridge()
    let healthBridge = WatchHealthBridge()

    init() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let wake = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: today) ?? Date()

        wakeUpTime = wake
        latestMoodIndex = 3
        moodNote = "Focused and steady."
        queuedWorkout = nil
        journalSnippets = [
            JournalSnippet(date: calendar.date(byAdding: .hour, value: -3, to: Date()) ?? Date(), text: "Morning run felt smooth."),
            JournalSnippet(date: calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date(), text: "Recovery improved after extra sleep.")
        ]

        strainWeek = Self.makeWeek(values: [11.2, 12.8, 10.7, 14.1, 13.6, 9.8, 12.4], anchoredTo: today)
        recoveryWeek = Self.makeWeek(values: [72, 76, 69, 81, 79, 74, 84], anchoredTo: today)
        readinessWeek = Self.makeWeek(values: [68, 71, 65, 78, 80, 73, 82], anchoredTo: today)
        mindfulnessWeek = Self.makeWeek(values: [55, 62, 60, 74, 70, 78, 82], anchoredTo: today)
        trainingLoadWeek = Self.makeWeek(values: [64, 72, 69, 81, 88, 76, 84], anchoredTo: today)
        hrvWeek = Self.makeWeek(values: [48, 52, 49, 57, 60, 54, 58], anchoredTo: today)
        hrrWeek = Self.makeWeek(values: [21, 24, 23, 27, 29, 25, 28], anchoredTo: today)
        rhrWeek = Self.makeWeek(values: [58, 57, 56, 55, 54, 55, 53], anchoredTo: today)
        stressWeek = Self.makeStressWeek(
            stress: [58, 49, 64, 42, 38, 46, 40],
            energy: [52, 60, 48, 66, 70, 62, 68],
            regulation: [61, 69, 58, 74, 77, 71, 79],
            anchoredTo: today
        )

        let morningRunStart = calendar.date(bySettingHour: 7, minute: 10, second: 0, of: Date()) ?? Date()
        let lunchStrengthStart = calendar.date(bySettingHour: 12, minute: 30, second: 0, of: Date()) ?? Date()
        let eveningWalkStart = calendar.date(bySettingHour: 18, minute: 5, second: 0, of: Date()) ?? Date()
        let yesterdayRideStart = calendar.date(byAdding: .day, value: -1, to: calendar.date(bySettingHour: 17, minute: 20, second: 0, of: Date()) ?? Date()) ?? Date()

        workouts = [
            WorkoutSession(
                id: UUID(),
                title: "Morning Run",
                subtitle: "Outdoor • Tempo",
                startDate: morningRunStart,
                durationMinutes: 41,
                calories: 468,
                distanceKilometers: 7.1,
                averageHeartRate: 152,
                maxHeartRate: 176,
                strain: 14.2,
                load: 82,
                zoneMinutes: [6, 9, 12, 10, 4],
                note: "Strong middle block with controlled finish."
            ),
            WorkoutSession(
                id: UUID(),
                title: "Strength",
                subtitle: "Upper body",
                startDate: lunchStrengthStart,
                durationMinutes: 34,
                calories: 244,
                distanceKilometers: nil,
                averageHeartRate: 126,
                maxHeartRate: 149,
                strain: 9.6,
                load: 68,
                zoneMinutes: [10, 12, 9, 3, 0],
                note: "Stable pacing with enough rest between sets."
            ),
            WorkoutSession(
                id: UUID(),
                title: "Evening Walk",
                subtitle: "Recovery",
                startDate: eveningWalkStart,
                durationMinutes: 28,
                calories: 118,
                distanceKilometers: 2.4,
                averageHeartRate: 101,
                maxHeartRate: 118,
                strain: 4.1,
                load: 38,
                zoneMinutes: [19, 7, 2, 0, 0],
                note: "Easy recovery walk to downshift before bed."
            ),
            WorkoutSession(
                id: UUID(),
                title: "Bike Ride",
                subtitle: "Yesterday",
                startDate: yesterdayRideStart,
                durationMinutes: 52,
                calories: 522,
                distanceKilometers: 18.6,
                averageHeartRate: 148,
                maxHeartRate: 168,
                strain: 13.4,
                load: 79,
                zoneMinutes: [5, 11, 16, 12, 8],
                note: "Progressive build with strong finish."
            )
        ]

        vitals = [
            VitalGauge(title: "Sleep HR", value: 52, displayValue: "52 bpm", minimum: 42, normalRange: 48...60, maximum: 72),
            VitalGauge(title: "Respiratory", value: 14.3, displayValue: "14.3 br/min", minimum: 10, normalRange: 12...18, maximum: 22),
            VitalGauge(title: "Wrist Temp", value: 0.2, displayValue: "+0.2 C", minimum: -1.0, normalRange: -0.3...0.3, maximum: 1.0),
            VitalGauge(title: "SpO2", value: 97, displayValue: "97%", minimum: 88, normalRange: 95...100, maximum: 100),
            VitalGauge(title: "Sleep Hours", value: 7.6, displayValue: "7.6 h", minimum: 4, normalRange: 7...9, maximum: 10),
            VitalGauge(title: "Consistency", value: 88, displayValue: "88%", minimum: 50, normalRange: 75...100, maximum: 100)
        ]

        coachSummaries = [
            .day: "Today favored controlled loading. Strain landed in range, recovery bounced back, and mindfulness improved after the evening downshift. Keep tomorrow moderate unless sleep shortens.",
            .week: "This week balanced quality work and recovery well. The best days paired moderate strain with rising readiness, while low-stress evenings kept vitals near normal. Hold the current load progression.",
            .month: "This month shows a solid aerobic base with steadier recovery patterns. Readiness is trending upward when sleep consistency stays above target, so the biggest upside is protecting bedtime regularity."
        ]

        startLiveServices()
    }

    var currentStrain: Double { strainWeek.last?.value ?? 0 }
    var currentRecovery: Double { recoveryWeek.last?.value ?? 0 }
    var currentReadiness: Double { readinessWeek.last?.value ?? 0 }
    var currentMindfulness: Double { mindfulnessWeek.last?.value ?? 0 }

    var todayWorkouts: [WorkoutSession] {
        workouts
            .filter { Calendar.current.isDateInToday($0.startDate) }
            .sorted { $0.startDate > $1.startDate }
    }

    var yesterdayWorkouts: [WorkoutSession] {
        workouts
            .filter { Calendar.current.isDateInYesterday($0.startDate) }
            .sorted { $0.startDate > $1.startDate }
    }

    var vitalsNormalityScore: Int {
        guard !vitals.isEmpty else { return 0 }
        let normalCount = vitals.filter { band(for: $0.value, idealRange: $0.normalRange) == .optimal }.count
        return Int((Double(normalCount) / Double(vitals.count) * 100).rounded())
    }

    var vitalsNormalityLabel: String {
        switch vitalsNormalityScore {
        case 90...100:
            return "Vitals are steady"
        case 75..<90:
            return "Vitals look good"
        default:
            return "Vitals need attention"
        }
    }

    func coachSummary(for window: CoachWindow) -> String {
        coachSummaries[window] ?? ""
    }

    func addJournalSnippet(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        journalSnippets.insert(JournalSnippet(date: Date(), text: trimmed), at: 0)
    }

    func workout(id: UUID) -> WorkoutSession? {
        workouts.first(where: { $0.id == id })
    }

    func zoneMinutes(for workoutID: UUID?) -> [Double] {
        if let workoutID, let workout = workout(id: workoutID) {
            return workout.zoneMinutes
        }

        return todayWorkouts.reduce(into: Array(repeating: 0.0, count: 5)) { partialResult, workout in
            for index in partialResult.indices {
                partialResult[index] += workout.zoneMinutes[index]
            }
        }
    }

    private static func makeWeek(values: [Double], anchoredTo date: Date) -> [MetricPoint] {
        let calendar = Calendar.current

        return values.enumerated().compactMap { index, value in
            guard let day = calendar.date(byAdding: .day, value: index - (values.count - 1), to: date) else {
                return nil
            }

            return MetricPoint(date: day, value: value)
        }
    }

    private static func makeStressWeek(stress: [Double], energy: [Double], regulation: [Double], anchoredTo date: Date) -> [StressPoint] {
        let calendar = Calendar.current

        return stress.indices.compactMap { index in
            guard let day = calendar.date(byAdding: .day, value: index - (stress.count - 1), to: date) else {
                return nil
            }

            return StressPoint(
                date: day,
                stress: stress[index],
                energy: energy[index],
                regulation: regulation[index]
            )
        }
    }

    func markSynced(at date: Date) {
        lastSyncedAt = date
    }
}

private struct OverviewDashboardPage: View {
    @ObservedObject var store: WatchDashboardStore
    @Binding var selectedTab: DashboardTab

    private var actions: [DashboardAction] {
        [
            DashboardAction(title: "Sleep Manager", symbol: "bed.double.fill", placement: .topLeading, route: .destination(.sleepManager)),
            DashboardAction(title: "Workouts", symbol: "list.bullet", placement: .topTrailing, route: .tab(.history)),
            DashboardAction(title: "Workout", symbol: "figure.run", placement: .bottomLeading, route: .destination(.workoutLauncher)),
            DashboardAction(title: "Journaling", symbol: "square.and.pencil", placement: .bottomTrailing, route: .destination(.journaling))
        ]
    }

    var body: some View {
        DashboardPageContainer(
            title: nil,
            subtitle: nil,
            actions: actions,
            selectedTab: $selectedTab
        ) {
            TripleMetricRing(
                strain: store.currentStrain / 21,
                recovery: store.currentRecovery / 100,
                readiness: store.currentReadiness / 100
            )
            .padding(0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(y: -12)
        }
    }
}

private struct StrainDashboardPage: View {
    @ObservedObject var store: WatchDashboardStore
    @Binding var selectedTab: DashboardTab

    private var actions: [DashboardAction] {
        [
            DashboardAction(title: "HR Zones", symbol: "heart.text.square.fill", placement: .topLeading, route: .destination(.hrZones)),
            DashboardAction(title: "Load", symbol: "chart.line.uptrend.xyaxis", placement: .topTrailing, route: .destination(.load)),
            DashboardAction(title: "Stats", symbol: "figure.walk", placement: .bottomLeading, route: .destination(.stats)),
            DashboardAction(title: "Coach", symbol: "sparkles", placement: .bottomTrailing, route: .destination(.coach))
        ]
    }

    var body: some View {
        DashboardPageContainer(
            title: "Strain",
            subtitle: "Weekly load",
            actions: actions,
            selectedTab: $selectedTab
        ) {
            GeometryReader { proxy in
                let chartHeight = min(max(proxy.size.height * 0.64, 88), 126)

                VStack(spacing: 8) {
                    WeeklyBarChart(
                        points: store.strainWeek,
                        accent: .orange,
                        highlightedIndex: store.strainWeek.count - 1
                    )
                    .frame(height: chartHeight)

                    VStack(spacing: 2) {
                        HStack(alignment: .lastTextBaseline, spacing: 6) {
                            Text(String(format: "%.1f", store.currentStrain))
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.orange)
                            Text(watchStrainClassificationTitle(for: store.currentStrain))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(watchStrainClassificationColor(for: store.currentStrain))
                        }
                        Text("Today • \(todayLabel())")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity, alignment: .center)
            }
        }
    }
}

private struct RecoveryDashboardPage: View {
    @ObservedObject var store: WatchDashboardStore
    @Binding var selectedTab: DashboardTab

    private var actions: [DashboardAction] {
        [
            DashboardAction(title: "Vitals", symbol: "waveform.path.ecg", placement: .topLeading, route: .destination(.vitals)),
            DashboardAction(title: "HRV", symbol: "heart.fill", placement: .topTrailing, route: .destination(.hrv)),
            DashboardAction(title: "HRR", symbol: "bolt.heart.fill", placement: .bottomLeading, route: .destination(.hrr)),
            DashboardAction(title: "RHR", symbol: "moon.zzz.fill", placement: .bottomTrailing, route: .destination(.rhr))
        ]
    }

    var body: some View {
        DashboardPageContainer(
            title: "Recovery",
            subtitle: "Recovery + readiness",
            actions: actions,
            selectedTab: $selectedTab
        ) {
            GeometryReader { proxy in
                let chartHeight = min(max(proxy.size.height * 0.42, 60), 84)

                VStack(spacing: 12) {
                    WeeklyDualBarChart(
                        primaryPoints: store.recoveryWeek,
                        primaryColor: .cyan,
                        secondaryPoints: store.readinessWeek,
                        secondaryColor: .mint
                    )
                    .frame(height: chartHeight)

                    HStack(spacing: 18) {
                        VStack(spacing: 2) {
                            Text(String(format: "%.0f", store.currentRecovery))
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.cyan)
                            Text("Recovery")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.white.opacity(0.62))
                            Text(watchRecoveryClassificationTitle(for: store.currentRecovery))
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(watchRecoveryClassificationColor(for: store.currentRecovery))
                        }
                        .frame(maxWidth: .infinity)

                        VStack(spacing: 2) {
                            Text(String(format: "%.0f", store.currentReadiness))
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.mint)
                            Text("Readiness")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.white.opacity(0.62))
                            Text(watchRecoveryClassificationTitle(for: store.currentReadiness))
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(watchRecoveryClassificationColor(for: store.currentReadiness))
                        }
                        .frame(maxWidth: .infinity)
                    }

                    Text("Today • \(todayLabel())")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }
}

private struct MindfulnessDashboardPage: View {
    @ObservedObject var store: WatchDashboardStore
    @Binding var selectedTab: DashboardTab

    private var actions: [DashboardAction] {
        [
            DashboardAction(title: "Mood Logger", symbol: "face.smiling.inverse", placement: .topLeading, route: .destination(.moodLogger)),
            DashboardAction(title: "Stress", symbol: "waveform.badge.exclamationmark", placement: .topTrailing, route: .destination(.stress)),
            DashboardAction(title: "Sleep", symbol: "bed.double.circle.fill", placement: .bottomLeading, route: .destination(.sleep)),
            DashboardAction(title: "Journal Snippets", symbol: "text.book.closed.fill", placement: .bottomTrailing, route: .destination(.journalSnippets))
        ]
    }

    var body: some View {
        DashboardPageContainer(
            title: nil,
            subtitle: nil,
            actions: actions,
            selectedTab: $selectedTab
        ) {
            MindfulnessRing(score: store.currentMindfulness)
                .padding(0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: -12)
        }
    }
}

private struct WorkoutHistoryDashboardPage: View {
    @ObservedObject var store: WatchDashboardStore

    var body: some View {
        ZStack {
            WatchDashboardBackground(style: .neutral)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Workout History")
                        .font(.headline.weight(.semibold))

                    workoutSection(title: "Today", workouts: store.todayWorkouts)
                    workoutSection(title: "Yesterday", workouts: store.yesterdayWorkouts)
                }
                .padding(12)
            }
        }
    }

    @ViewBuilder
    private func workoutSection(title: String, workouts: [WorkoutSession]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.72))

            if workouts.isEmpty {
                SectionCard(title: "No workouts \(title.lowercased())") {
                    Text(title == "Today" ? "Start a workout from the launcher to populate this list." : "No workouts were recorded yesterday.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.72))
                }
            } else {
                ForEach(workouts) { workout in
                    NavigationLink(value: WatchDestination.workoutDetail(workout.id)) {
                        WorkoutRowCard(workout: workout)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct DashboardPageContainer<Content: View>: View {
    let title: String?
    let subtitle: String?
    let actions: [DashboardAction]
    @Binding var selectedTab: DashboardTab
    let content: Content

    init(
        title: String?,
        subtitle: String?,
        actions: [DashboardAction],
        selectedTab: Binding<DashboardTab>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.actions = actions
        _selectedTab = selectedTab
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .containerBackground(.clear, for: .navigation)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                if let topLeading = action(for: .topLeading) {
                    ToolbarItem(placement: .topBarLeading) {
                        dashboardActionView(for: topLeading)
                    }
                }

                if let topTrailing = action(for: .topTrailing) {
                    ToolbarItem(placement: .topBarTrailing) {
                        dashboardActionView(for: topTrailing)
                    }
                }

                if action(for: .bottomLeading) != nil || action(for: .bottomTrailing) != nil {
                    ToolbarItemGroup(placement: .bottomBar) {
                        if let bottomLeading = action(for: .bottomLeading) {
                            dashboardActionView(for: bottomLeading)
                        }

                        Spacer(minLength: 0)

                        if let bottomTrailing = action(for: .bottomTrailing) {
                            dashboardActionView(for: bottomTrailing)
                        }
                    }
                }
            }
    }

    private func action(for placement: CornerPlacement) -> DashboardAction? {
        actions.first(where: { $0.placement == placement })
    }

    @ViewBuilder
    private func dashboardActionView(for action: DashboardAction) -> some View {
        switch action.route {
        case .destination(let destination):
            NavigationLink(value: destination) {
                actionLabel(for: action)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(action.title)
        case .tab(let tab):
            Button {
                selectedTab = tab
            } label: {
                actionLabel(for: action)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(action.title)
        }
    }

    private func actionLabel(for action: DashboardAction) -> some View {
        UniformToolbarBubble(symbol: action.symbol)
    }
}

private struct UniformToolbarBubble: View {
    let symbol: String

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.22))

            Circle()
                .stroke(Color.white.opacity(0.16), lineWidth: 1)

            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 36, height: 36)
    }
}

private struct ActionBubble: View {
    let symbol: String
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.24))

            Circle()
                .stroke(tint.opacity(0.55), lineWidth: 1)

            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 32, height: 32)
        .shadow(color: tint.opacity(0.25), radius: 5, y: 2)
    }
}

private struct WatchScoreRow: View {
    let title: String
    let value: String
    let progress: Double
    let band: MetricBand

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(value)
                    .font(.caption.weight(.bold))
                StatusPill(band: band)
            }

            ProgressView(value: progress.clamped(to: 0...1))
                .tint(band.color)
                .scaleEffect(x: 1, y: 0.85, anchor: .center)
        }
    }
}

private struct TripleMetricRing: View {
    let strain: Double
    let recovery: Double
    let readiness: Double

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height) * 1.16
            let lineWidth = max(12, size * 0.115)
            let outerDiameter = size
            let middleDiameter = size * 0.72
            let innerDiameter = size * 0.45
            let outerY = -(outerDiameter / 2) + (lineWidth / 2)
            let middleY = -(middleDiameter / 2) + (lineWidth / 2)
            let innerY = -(innerDiameter / 2) + (lineWidth / 2)

            ZStack {
                ring(progress: readiness, lineWidth: lineWidth, diameter: outerDiameter, color: Color(red: 0.20, green: 0.78, blue: 0.35))
                ring(progress: recovery, lineWidth: lineWidth, diameter: middleDiameter, color: Color(red: 0.45, green: 0.80, blue: 1.0))
                ring(progress: strain, lineWidth: lineWidth, diameter: innerDiameter, color: .orange)

                symbolBadge(symbol: "checkmark", color: .black, size: size * 0.66)
                    .offset(y: outerY)

                symbolBadge(symbol: "heart.fill", color: .black, size: size * 0.56)
                    .offset(y: middleY)

                symbolBadge(symbol: "flame.fill", color: .black, size: size * 0.42)
                    .offset(y: innerY)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func ring(progress: Double, lineWidth: CGFloat, diameter: CGFloat, color: Color) -> some View {
        Circle()
            .stroke(Color.white.opacity(0.10), lineWidth: lineWidth)
            .overlay {
                Circle()
                    .trim(from: 0, to: progress.clamped(to: 0...1))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: diameter, height: diameter)
    }

    private func symbolBadge(symbol: String, color: Color, size: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: max(9, size * 0.075), weight: .bold))
            .foregroundStyle(color)
            .frame(width: max(16, size * 0.13), height: max(16, size * 0.13))
            .background(Color.black.opacity(0.28))
            .clipShape(Circle())
    }
}

private struct StatusPill: View {
    let band: MetricBand

    var body: some View {
        Text(band.rawValue)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(band.color.opacity(0.22))
            .clipShape(Capsule())
            .foregroundStyle(.white)
    }
}

private struct VitalsNormalityCard: View {
    let score: Int
    let caption: String

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Vitals Normality")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(score)%")
                    .font(.caption.weight(.bold))
            }

            ProgressView(value: Double(score), total: 100)
                .tint(score >= 80 ? .green : .orange)

            Text(caption)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.72))
        }
        .padding(10)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct LegendTag: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text(label)
                .foregroundStyle(.white.opacity(0.82))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
    }
}

private enum MetricTrendDirection {
    case up
    case down
    case steady

    var symbol: String {
        switch self {
        case .up:
            return "arrow.up.right"
        case .down:
            return "arrow.down.right"
        case .steady:
            return "equal"
        }
    }

    var color: Color {
        switch self {
        case .up:
            return .mint
        case .down:
            return .orange
        case .steady:
            return .cyan
        }
    }

    var label: String {
        switch self {
        case .up:
            return "Rising"
        case .down:
            return "Falling"
        case .steady:
            return "Steady"
        }
    }
}

private struct MiniTrendChart: View {
    let points: [MetricPoint]
    let accent: Color
    let secondaryPoints: [MetricPoint]?
    let highlightedIndex: Int?
    let idealRange: ClosedRange<Double>?

    var body: some View {
        GeometryReader { proxy in
            let minValue = minimumValue()
            let maxValue = maximumValue()
            let xAxisHeight: CGFloat = 18
            let chartHeight = max(proxy.size.height - xAxisHeight - 4, 46)
            let plotWidth = max(proxy.size.width, 30)
            let rect = CGRect(x: 0, y: 0, width: plotWidth, height: chartHeight)

            VStack(spacing: 4) {
                HStack(alignment: .bottom, spacing: 0) {
                    ZStack(alignment: .bottomLeading) {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [accent.opacity(0.18), Color.white.opacity(0.04)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )

                        VStack(spacing: 0) {
                            ForEach(0..<3, id: \.self) { _ in
                                Rectangle()
                                    .fill(Color.white.opacity(0.08))
                                    .frame(height: 1)
                                Spacer()
                            }
                        }
                        .padding(.vertical, 10)

                        if let secondaryPoints {
                            LineChartPath(
                                points: secondaryPoints.map(\.value),
                                minValue: minValue,
                                maxValue: maxValue
                            )
                            .stroke(Color.white.opacity(0.42), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                        }

                        LineChartPath(
                            points: points.map(\.value),
                            minValue: minValue,
                            maxValue: maxValue
                        )
                        .stroke(Color.white.opacity(0.94), style: StrokeStyle(lineWidth: 2.1, lineCap: .round, lineJoin: .round))

                        if points.count > 1 {
                            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                                let x = rect.minX + rect.width * CGFloat(index) / CGFloat(points.count - 1)
                                let y = yPosition(for: point.value, in: rect, minValue: minValue, maxValue: maxValue)
                                let baseY = rect.maxY - 10
                                let isHighlighted = highlightedIndex == index
                                let markerColor = pointColor(for: point.value)
                                let capsuleHeight = max(16, baseY - y)

                                Capsule()
                                    .fill(markerColor.opacity(isHighlighted ? 0.55 : 0.30))
                                    .frame(width: isHighlighted ? 8 : 6, height: capsuleHeight)
                                    .position(x: x, y: y + capsuleHeight / 2)

                                Circle()
                                    .fill(markerColor)
                                    .frame(width: isHighlighted ? 12 : 8, height: isHighlighted ? 12 : 8)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.88), lineWidth: isHighlighted ? 2 : 1)
                                    )
                                    .shadow(color: markerColor.opacity(isHighlighted ? 0.50 : 0.22), radius: isHighlighted ? 5 : 2)
                                    .position(x: x, y: y)
                            }
                        } else if let point = points.first {
                            Circle()
                                .fill(pointColor(for: point.value))
                                .frame(width: 12, height: 12)
                                .overlay(Circle().stroke(Color.white.opacity(0.88), lineWidth: 2))
                                .position(x: rect.midX, y: yPosition(for: point.value, in: rect, minValue: minValue, maxValue: maxValue))
                        }
                    }
                    .frame(width: plotWidth, height: chartHeight)
                }

                HStack {
                    ForEach(points) { point in
                        Text(weekdayLetter(point.date))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.68))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func minimumValue() -> Double {
        let primary = points.map(\.value)
        let secondary = secondaryPoints?.map(\.value) ?? []
        return min(primary.min() ?? 0, secondary.min() ?? primary.min() ?? 0)
    }

    private func maximumValue() -> Double {
        let primary = points.map(\.value)
        let secondary = secondaryPoints?.map(\.value) ?? []
        return max(primary.max() ?? 1, secondary.max() ?? primary.max() ?? 1)
    }

    private func pointColor(for value: Double) -> Color {
        guard let idealRange else { return accent }

        switch band(for: value, idealRange: idealRange) {
        case .low:
            return .cyan
        case .optimal:
            return accent
        case .high:
            return .orange
        }
    }

    private func yPosition(for value: Double, in rect: CGRect, minValue: Double, maxValue: Double) -> CGFloat {
        let inset: CGFloat = 10
        guard maxValue > minValue else { return rect.midY }
        let ratio = (value - minValue) / (maxValue - minValue)
        return rect.maxY - inset - (rect.height - inset * 2) * CGFloat(ratio)
    }
}

private struct TrendSummaryCard: View {
    let value: String
    let trend: MetricTrendDirection
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)

            Image(systemName: trend.symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(trend.color)
                .padding(7)
                .background(trend.color.opacity(0.18))
                .clipShape(Circle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.07, green: 0.16, blue: 0.28).opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

private struct BottomInfoStrip: View {
    let text: String
    let symbol: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.82))

            Text(text)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct WeeklyBarChart: View {
    let points: [MetricPoint]
    let accent: Color
    let highlightedIndex: Int?

    var body: some View {
        GeometryReader { proxy in
            let maxValue = max(points.map(\.value).max() ?? 1, 1)
            let averageValue = points.isEmpty ? 0 : points.map(\.value).reduce(0, +) / Double(points.count)
            let showsMaxGuide = shouldShowMaxGuide(maxValue: maxValue, averageValue: averageValue)
            let yLabelWidth: CGFloat = 18
            let xLabelHeight: CGFloat = 16
            let chartHeight = max(proxy.size.height - xLabelHeight - 4, 26)
            let plotWidth = max(proxy.size.width - yLabelWidth - 4, 40)
            let barWidth = min(14, max(6, (plotWidth - CGFloat(max(points.count - 1, 0)) * 4) / CGFloat(max(points.count, 1))))

            VStack(spacing: 4) {
                HStack(alignment: .bottom, spacing: 4) {
                    yAxisLabels(
                        maxValue: maxValue,
                        averageValue: averageValue,
                        chartHeight: chartHeight,
                        highlightColor: accent,
                        showsMaxGuide: showsMaxGuide
                    )
                    .frame(width: yLabelWidth, height: chartHeight)

                    ZStack(alignment: .bottomLeading) {
                        referenceLine(
                            value: averageValue,
                            maxValue: maxValue,
                            chartHeight: chartHeight,
                            plotWidth: plotWidth,
                            color: accent.opacity(0.75)
                        )

                        if showsMaxGuide {
                            referenceLine(
                                value: maxValue,
                                maxValue: maxValue,
                                chartHeight: chartHeight,
                                plotWidth: plotWidth,
                                color: accent
                            )
                        }

                        Rectangle()
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 1, height: chartHeight)

                        Rectangle()
                            .fill(Color.white.opacity(0.18))
                            .frame(height: 1)

                        HStack(alignment: .bottom, spacing: 4) {
                            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                                let isHighlighted = highlightedIndex == index
                                let ratio = point.value / maxValue

                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(isHighlighted ? accent : accent.opacity(0.72))
                                    .frame(width: barWidth, height: max(10, (chartHeight - 2) * CGFloat(ratio.clamped(to: 0...1))))
                            }
                        }
                        .padding(.leading, 4)
                    }
                    .frame(width: plotWidth, height: chartHeight, alignment: .bottomLeading)
                }

                HStack(spacing: 4) {
                    Spacer()
                        .frame(width: yLabelWidth)

                    HStack(spacing: 4) {
                        ForEach(points) { point in
                            Text(weekdayLetter(point.date))
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.white.opacity(0.62))
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    @ViewBuilder
    private func yAxisLabels(maxValue: Double, averageValue: Double, chartHeight: CGFloat, highlightColor: Color, showsMaxGuide: Bool) -> some View {
        let averageY = yPosition(for: averageValue, maxValue: maxValue, chartHeight: chartHeight)

        ZStack(alignment: .topTrailing) {
            if showsMaxGuide {
                Text(shortMetricLabel(maxValue))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(highlightColor)
                    .offset(y: -4)
            }

            Text(shortMetricLabel(averageValue))
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(highlightColor.opacity(0.82))
                .offset(y: averageY - 6)

            Text("0")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
                .frame(maxHeight: .infinity, alignment: .bottomTrailing)
                .offset(y: 4)
        }
    }

    @ViewBuilder
    private func referenceLine(value: Double, maxValue: Double, chartHeight: CGFloat, plotWidth: CGFloat, color: Color) -> some View {
        let ratio = maxValue > 0 ? value / maxValue : 0
        let y = chartHeight - (chartHeight - 2) * CGFloat(ratio.clamped(to: 0...1))

        Rectangle()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .foregroundStyle(color)
            .frame(width: plotWidth, height: 1)
            .position(x: plotWidth / 2, y: y)
    }

    private func yPosition(for value: Double, maxValue: Double, chartHeight: CGFloat) -> CGFloat {
        let ratio = maxValue > 0 ? value / maxValue : 0
        return chartHeight - (chartHeight - 2) * CGFloat(ratio.clamped(to: 0...1))
    }

    private func shouldShowMaxGuide(maxValue: Double, averageValue: Double) -> Bool {
        maxValue > 0 && ((maxValue - averageValue) / maxValue) >= 0.14
    }
}

private struct WeeklyDualBarChart: View {
    let primaryPoints: [MetricPoint]
    let primaryColor: Color
    let secondaryPoints: [MetricPoint]
    let secondaryColor: Color

    var body: some View {
        GeometryReader { proxy in
            let maxValue = max(
                primaryPoints.map(\.value).max() ?? 1,
                secondaryPoints.map(\.value).max() ?? 1,
                1
            )
            let combinedValues = primaryPoints.map(\.value) + secondaryPoints.map(\.value)
            let averageValue = combinedValues.isEmpty ? 0 : combinedValues.reduce(0, +) / Double(combinedValues.count)
            let showsMaxGuide = shouldShowMaxGuide(maxValue: maxValue, averageValue: averageValue)
            let yLabelWidth: CGFloat = 18
            let xLabelHeight: CGFloat = 16
            let chartHeight = max(proxy.size.height - xLabelHeight - 4, 26)
            let plotWidth = max(proxy.size.width - yLabelWidth - 4, 40)
            let dayWidth = min(18, max(10, (plotWidth - CGFloat(max(primaryPoints.count - 1, 0)) * 4) / CGFloat(max(primaryPoints.count, 1))))
            let barWidth = max(4, (dayWidth - 3) / 2)

            VStack(spacing: 4) {
                HStack(alignment: .bottom, spacing: 4) {
                    yAxisLabels(
                        maxValue: maxValue,
                        averageValue: averageValue,
                        chartHeight: chartHeight,
                        showsMaxGuide: showsMaxGuide
                    )
                    .frame(width: yLabelWidth, height: chartHeight)

                    ZStack(alignment: .bottomLeading) {
                        referenceLine(
                            value: averageValue,
                            maxValue: maxValue,
                            chartHeight: chartHeight,
                            plotWidth: plotWidth,
                            color: primaryColor.opacity(0.82)
                        )

                        if showsMaxGuide {
                            referenceLine(
                                value: maxValue,
                                maxValue: maxValue,
                                chartHeight: chartHeight,
                                plotWidth: plotWidth,
                                color: secondaryColor
                            )
                        }

                        Rectangle()
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 1, height: chartHeight)

                        Rectangle()
                            .fill(Color.white.opacity(0.18))
                            .frame(height: 1)

                        HStack(alignment: .bottom, spacing: 4) {
                            ForEach(primaryPoints.indices, id: \.self) { index in
                                let primaryRatio = primaryPoints[index].value / maxValue
                                let secondaryValue = secondaryPoints[safe: index]?.value ?? 0
                                let secondaryRatio = secondaryValue / maxValue

                                HStack(alignment: .bottom, spacing: 3) {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(primaryColor)
                                        .frame(width: barWidth, height: max(10, (chartHeight - 2) * CGFloat(primaryRatio.clamped(to: 0...1))))

                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(secondaryColor)
                                        .frame(width: barWidth, height: max(10, (chartHeight - 2) * CGFloat(secondaryRatio.clamped(to: 0...1))))
                                }
                                .frame(width: dayWidth, alignment: .center)
                            }
                        }
                        .padding(.leading, 4)
                    }
                    .frame(width: plotWidth, height: chartHeight, alignment: .bottomLeading)
                }

                HStack(spacing: 4) {
                    Spacer()
                        .frame(width: yLabelWidth)

                    HStack(spacing: 4) {
                        ForEach(primaryPoints) { point in
                            Text(weekdayLetter(point.date))
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.white.opacity(0.62))
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    @ViewBuilder
    private func yAxisLabels(maxValue: Double, averageValue: Double, chartHeight: CGFloat, showsMaxGuide: Bool) -> some View {
        let averageY = yPosition(for: averageValue, maxValue: maxValue, chartHeight: chartHeight)

        ZStack(alignment: .topTrailing) {
            if showsMaxGuide {
                Text(shortMetricLabel(maxValue))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(secondaryColor)
                    .offset(y: -4)
            }

            Text(shortMetricLabel(averageValue))
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(primaryColor.opacity(0.82))
                .offset(y: averageY - 6)

            Text("0")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
                .frame(maxHeight: .infinity, alignment: .bottomTrailing)
                .offset(y: 4)
        }
    }

    @ViewBuilder
    private func referenceLine(value: Double, maxValue: Double, chartHeight: CGFloat, plotWidth: CGFloat, color: Color) -> some View {
        let ratio = maxValue > 0 ? value / maxValue : 0
        let y = chartHeight - (chartHeight - 2) * CGFloat(ratio.clamped(to: 0...1))

        Rectangle()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .foregroundStyle(color)
            .frame(width: plotWidth, height: 1)
            .position(x: plotWidth / 2, y: y)
    }

    private func yPosition(for value: Double, maxValue: Double, chartHeight: CGFloat) -> CGFloat {
        let ratio = maxValue > 0 ? value / maxValue : 0
        return chartHeight - (chartHeight - 2) * CGFloat(ratio.clamped(to: 0...1))
    }

    private func shouldShowMaxGuide(maxValue: Double, averageValue: Double) -> Bool {
        maxValue > 0 && ((maxValue - averageValue) / maxValue) >= 0.14
    }
}

private struct MindfulnessRing: View {
    let score: Double

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height) * 1.16
            let lineWidth = max(13, size * 0.125)

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: lineWidth)

                Circle()
                    .trim(from: 0, to: score.clamped(to: 0...100) / 100)
                    .stroke(
                        AngularGradient(
                            colors: [.mint, .teal, .blue, .pink],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Text(String(format: "%.0f", score))
                    .font(.system(size: max(26, size * 0.22), weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct SectionCard<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))

            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct WatchDashboardBackground: View {
    let style: WatchDashboardBackgroundStyle

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [style.topColor, .black],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [style.glowColor, .clear],
                center: .top,
                startRadius: 10,
                endRadius: 180
            )
            .blendMode(.screen)
        }
    }
}

private struct MetricLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
        }
    }
}

private struct WorkoutRowCard: View {
    let workout: WorkoutSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.title)
                        .font(.caption.weight(.semibold))
                    Text(workout.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.72))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.45))
            }

            HStack(spacing: 8) {
                WorkoutTag(text: shortTime(workout.startDate), symbol: "clock.fill")
                WorkoutTag(text: "\(workout.durationMinutes)m", symbol: "timer")
                WorkoutTag(text: "\(workout.calories)", symbol: "flame.fill")
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct WorkoutTag: View {
    let text: String
    let symbol: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
            Text(text)
                .font(.system(size: 9, weight: .semibold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
    }
}

private struct SleepManagerView: View {
    @ObservedObject var store: WatchDashboardStore

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                SectionCard(title: "Tonight") {
                    MetricLine(label: "Recommended", value: hoursString(store.recommendedSleepHours))
                    MetricLine(label: "Sleep debt", value: hoursString(store.sleepDebtHours))
                    MetricLine(label: "Schedule", value: store.sleepScheduleText)
                }

                SectionCard(title: "Wake-Up Timer") {
                    DatePicker("Wake Time", selection: $store.wakeUpTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Text(store.wakeScheduler.statusText)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.68))
                }

                SectionCard(title: "Suggestion") {
                    Text(store.wakeSuggestionText)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.78))
                }
            }
            .padding(10)
        }
        .navigationTitle("Sleep Manager")
        .task {
            await store.wakeScheduler.scheduleWakeNotification(for: store.wakeUpTime)
        }
        .onChange(of: store.wakeUpTime) { _, newValue in
            Task {
                await store.wakeScheduler.scheduleWakeNotification(for: newValue)
            }
        }
    }
}

private struct WorkoutLauncherView: View {
    @ObservedObject var store: WatchDashboardStore
    @State private var customizationActivity: HKWorkoutActivityType = .running

    private func draftBinding<Value>(_ keyPath: WritableKeyPath<WatchCustomWorkoutDraft, Value>) -> Binding<Value> {
        Binding {
            store.workoutManager.customDraft[keyPath: keyPath]
        } set: { newValue in
            var updatedDraft = store.workoutManager.customDraft
            updatedDraft[keyPath: keyPath] = newValue
            store.workoutManager.customDraft = updatedDraft
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if store.workoutManager.postWorkoutDestination == .nextWorkoutPicker {
                    SectionCard(title: "Next Workout") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your last workout was saved. Pick the next one to keep going.")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.78))

                            Button("Return to App") {
                                store.workoutManager.dismissPostWorkoutFlow()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                if store.workoutManager.isSessionActive {
                    SectionCard(title: store.workoutManager.activeTitle ?? "Live Workout") {
                        VStack(alignment: .leading, spacing: 8) {
                            if let subtitle = store.workoutManager.activeSubtitle {
                                Text(subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.68))
                            }

                            HStack {
                                Text(elapsedWorkoutString(store.workoutManager.elapsedTime))
                                    .font(.headline.monospacedDigit())
                                Spacer()
                                Text(store.workoutManager.displayState.rawValue.capitalized)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(store.workoutManager.displayState == .paused ? Color.yellow : Color.green)
                            }

                            ForEach(store.workoutManager.metrics) { metric in
                                HStack {
                                    Label(metric.title, systemImage: metric.symbol)
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.72))
                                    Spacer()
                                    Text(metric.valueText)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(metric.tint)
                                }
                            }

                            HStack(spacing: 8) {
                                if store.workoutManager.displayState == .running {
                                    Button("Pause") {
                                        store.workoutManager.pause()
                                    }
                                    .buttonStyle(.bordered)
                                } else if store.workoutManager.displayState == .paused {
                                    Button("Resume") {
                                        store.workoutManager.resume()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.green)
                                }

                                Button("End") {
                                    store.workoutManager.end()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                            }
                        }
                    }
                }

                SectionCard(title: "Quick Start") {
                    VStack(spacing: 8) {
                        ForEach(store.workoutTemplates) { workout in
                            Button {
                                store.queuedWorkout = workout.title
                                store.workoutManager.start(template: workout)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Label(workout.title, systemImage: workout.symbol)
                                            .font(.caption.weight(.semibold))
                                        Text(workout.subtitle)
                                            .font(.caption2)
                                            .foregroundStyle(.white.opacity(0.68))
                                    }
                                    Spacer()
                                    Image(systemName: "play.fill")
                                        .font(.caption.weight(.bold))
                                }
                                .padding(10)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                SectionCard(title: "Tab Layout") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Workout", selection: $customizationActivity) {
                            ForEach(store.workoutTemplates) { workout in
                                Text(workout.title).tag(workout.activity)
                            }
                        }
                        .labelsHidden()

                        ForEach(WatchWorkoutPageKind.allCases) { page in
                            HStack(spacing: 6) {
                                Toggle(
                                    page.title,
                                    isOn: Binding(
                                        get: {
                                            store.workoutManager.isPageEnabled(page, for: customizationActivity)
                                        },
                                        set: { isEnabled in
                                            store.workoutManager.setPageEnabled(isEnabled, page: page, for: customizationActivity)
                                        }
                                    )
                                )
                                .font(.caption2)

                                Button {
                                    store.workoutManager.movePage(page, direction: -1, for: customizationActivity)
                                } label: {
                                    Image(systemName: "arrow.up")
                                }
                                .buttonStyle(.bordered)

                                Button {
                                    store.workoutManager.movePage(page, direction: 1, for: customizationActivity)
                                } label: {
                                    Image(systemName: "arrow.down")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                SectionCard(title: "Custom Workout") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Name", text: draftBinding(\.displayName))
                            .padding(8)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        Picker("Activity", selection: draftBinding(\.activity)) {
                            ForEach(store.workoutTemplates) { workout in
                                Text(workout.title).tag(workout.activity)
                            }
                        }
                        .labelsHidden()

                        Picker("Location", selection: draftBinding(\.location)) {
                            ForEach(WatchWorkoutLocationChoice.allCases) { choice in
                                Text(choice.rawValue.capitalized).tag(choice)
                            }
                        }
                        .labelsHidden()

                        Picker("Goal", selection: draftBinding(\.goalMode)) {
                            ForEach(WatchWorkoutGoalMode.allCases) { mode in
                                Text(mode.rawValue.capitalized).tag(mode)
                            }
                        }
                        .labelsHidden()

                        if store.workoutManager.customDraft.goalMode != .open {
                            Stepper(value: draftBinding(\.goalValue), in: 1...240, step: store.workoutManager.customDraft.goalMode == .distance ? 0.5 : 5) {
                                Text(customGoalLabel(for: store.workoutManager.customDraft))
                                    .font(.caption2)
                            }
                        }

                        Stepper(value: draftBinding(\.warmupMinutes), in: 0...20, step: 1) {
                            Text("Warm-up \(Int(store.workoutManager.customDraft.warmupMinutes)) min")
                                .font(.caption2)
                        }
                        Stepper(value: draftBinding(\.workMinutes), in: 1...20, step: 1) {
                            Text("Work \(Int(store.workoutManager.customDraft.workMinutes)) min")
                                .font(.caption2)
                        }
                        Stepper(value: draftBinding(\.recoveryMinutes), in: 1...10, step: 1) {
                            Text("Recovery \(Int(store.workoutManager.customDraft.recoveryMinutes)) min")
                                .font(.caption2)
                        }
                        Stepper(value: draftBinding(\.repeats), in: 1...12, step: 1) {
                            Text("Repeats \(store.workoutManager.customDraft.repeats)")
                                .font(.caption2)
                        }
                        Stepper(value: draftBinding(\.cooldownMinutes), in: 0...20, step: 1) {
                            Text("Cooldown \(Int(store.workoutManager.customDraft.cooldownMinutes)) min")
                                .font(.caption2)
                        }

                        HStack(spacing: 8) {
                            Button("Start") {
                                store.queuedWorkout = store.workoutManager.customDraft.displayName
                                store.workoutManager.startCustomWorkout()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)

                            Button("Schedule") {
                                store.workoutManager.scheduleCustomWorkoutForTomorrow()
                            }
                            .buttonStyle(.bordered)
                        }

                        Text("Start launches a live custom session here. Schedule sends the structured interval workout to WorkoutKit for Apple Watch.")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.68))
                    }
                }

                if !store.workoutManager.statusMessage.isEmpty {
                    SectionCard(title: "Status") {
                        Text(store.workoutManager.statusMessage)
                            .font(.caption2)
                    }
                }

                if #available(watchOS 10.0, *), !store.workoutManager.scheduledPlans.isEmpty {
                    SectionCard(title: "Scheduled") {
                        VStack(alignment: .leading, spacing: 6) {
                            if store.workoutManager.scheduledPlans.indices.contains(0) {
                                Text(scheduledWorkoutText(store.workoutManager.scheduledPlans[0].date))
                                    .font(.caption2)
                            }
                            if store.workoutManager.scheduledPlans.indices.contains(1) {
                                Text(scheduledWorkoutText(store.workoutManager.scheduledPlans[1].date))
                                    .font(.caption2)
                            }
                            if store.workoutManager.scheduledPlans.indices.contains(2) {
                                Text(scheduledWorkoutText(store.workoutManager.scheduledPlans[2].date))
                                    .font(.caption2)
                            }
                        }
                    }
                }
            }
            .padding(10)
        }
        .navigationTitle("Workout")
        .task {
            store.workoutManager.activate()
        }
    }
}

private struct WorkoutEffortPromptView: View {
    @ObservedObject var manager: WatchWorkoutManager
    @State private var selectedEffort: Double = 5

    private let effortLabels: [Int: String] = [
        1: "Very Easy",
        2: "Easy",
        3: "Steady",
        4: "Moderate",
        5: "Working",
        6: "Challenging",
        7: "Hard",
        8: "Very Hard",
        9: "Max",
        10: "All Out"
    ]

    private var roundedEffort: Int {
        Int(selectedEffort.rounded()).clamped(to: 1...10)
    }

    private var effortProgress: Double {
        (Double(roundedEffort) - 1) / 9
    }

    private func commitEffort() {
        manager.submitEffortScore(roundedEffort)
    }

    var body: some View {
        GeometryReader { proxy in
            let progressWidth = max(proxy.size.width - 36, 80)
            let compact = proxy.size.height < 205

            VStack(alignment: .leading, spacing: compact ? 8 : 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(manager.lastCompletedWorkoutTitle ?? "Workout Complete")
                            .font(compact ? .subheadline.weight(.semibold) : .headline)
                        if let subtitle = manager.lastCompletedWorkoutSubtitle {
                            Text(subtitle)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.68))
                        }
                    }

                    Spacer(minLength: 8)

                    Button {
                        commitEffort()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(.black)
                            .frame(width: 30, height: 30)
                            .background(Color.green, in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Intensity")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.78))

                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text("\(roundedEffort)")
                            .font(.system(size: compact ? 27 : 32, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                        Text("/10")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.65))
                    }

                    Text(effortLabels[roundedEffort] ?? "")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.green.opacity(0.9))
                }

                VStack(alignment: .leading, spacing: 8) {
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: progressWidth, height: compact ? 12 : 14)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.green, Color.yellow, Color.orange, Color.red],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(compact ? 16 : 18, progressWidth * effortProgress), height: compact ? 12 : 14)

                        Circle()
                            .fill(Color.white)
                            .frame(width: compact ? 16 : 18, height: compact ? 16 : 18)
                            .offset(x: max(0, progressWidth * effortProgress - (compact ? 8 : 9)))
                    }

                    HStack {
                        Text("1")
                        Spacer()
                        Text("10")
                    }
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: progressWidth)
                }

                if compact {
                    Text("Crown adjusts effort. Double tap or check saves.")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                } else {
                    SectionCard(title: "Commit") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Rotate the Digital Crown to set effort.")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.78))
                            Text("Double tap anywhere or press the check button to save.")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.62))
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
        .background(Color.black.ignoresSafeArea())
        .contentShape(Rectangle())
        .focusable(true)
        .digitalCrownRotation(
            $selectedEffort,
            from: 1,
            through: 10,
            by: 1,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onAppear {
            selectedEffort = Double(manager.lastEffortScore ?? 5)
        }
        .onTapGesture(count: 2) {
            commitEffort()
        }
    }
}

private struct JournalComposerView: View {
    @ObservedObject var store: WatchDashboardStore
    let title: String
    @State private var draft = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                SectionCard(title: "New Entry") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Add a short note", text: $draft)
                            .padding(8)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        Button("Save") {
                            store.addJournalSnippet(draft)
                            draft = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.pink)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                if !store.journalSnippets.isEmpty {
                    SectionCard(title: "Recent") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(store.journalSnippets.prefix(4)) { snippet in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(snippet.text)
                                        .font(.caption2)
                                    Text(relativeDate(snippet.date))
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.55))
                                }
                            }
                        }
                    }
                }
            }
            .padding(10)
        }
        .navigationTitle(title)
    }
}

private struct HRZonesView: View {
    @ObservedObject var store: WatchDashboardStore
    @State private var selectedWorkoutID: UUID?

    var body: some View {
        let zoneMinutes = store.zoneMinutes(for: selectedWorkoutID)
        let maxValue = zoneMinutes.max() ?? 1

        ScrollView {
            VStack(spacing: 10) {
                SectionCard(title: "Time in Zone") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(selectedWorkoutID == nil ? "All workouts today" : "Specific workout")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.72))
                            Spacer()
                            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.pink)
                        }

                        Picker("Workout Filter", selection: $selectedWorkoutID) {
                            Text("All workouts today")
                                .tag(UUID?.none)
                            ForEach(store.todayWorkouts) { workout in
                                Text(workout.title)
                                    .tag(UUID?.some(workout.id))
                            }
                        }
                        .labelsHidden()

                        ForEach(zoneMinutes.indices, id: \.self) { index in
                            ZoneBarRow(
                                label: "Zone \(index + 1)",
                                minutes: zoneMinutes[index],
                                maxValue: maxValue,
                                color: zoneColor(index)
                            )
                        }
                    }
                }
            }
            .padding(10)
        }
        .navigationTitle("HR Zones")
    }
}

private struct ZoneBarRow: View {
    let label: String
    let minutes: Double
    let maxValue: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(Int(minutes.rounded())) min")
                    .font(.caption2)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(color)
                        .frame(width: proxy.size.width * CGFloat(minutes / max(maxValue, 1)))
                }
            }
            .frame(height: 8)
        }
    }
}

private struct TrainingLoadView: View {
    @ObservedObject var store: WatchDashboardStore

    var body: some View {
        CrownControlledMetricView(
            title: "Load",
            subtitle: "",
            points: store.trainingLoadWeek,
            unit: "TL",
            accent: .orange,
            idealRange: 70...90
        )
    }
}

private struct StatsSnapshotView: View {
    @ObservedObject var store: WatchDashboardStore

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(store.stats, id: \.title) { stat in
                    SectionCard(title: stat.title) {
                        HStack {
                            Image(systemName: stat.symbol)
                                .foregroundStyle(stat.tint)
                            Text(stat.value)
                                .font(.headline.weight(.semibold))
                        }
                    }
                }
            }
            .padding(10)
        }
        .navigationTitle("Stats")
    }
}

private struct CoachSummaryView: View {
    @ObservedObject var store: WatchDashboardStore
    @State private var selectedWindow: CoachWindow = .day

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                SectionCard(title: "Report Window") {
                    Picker("Window", selection: $selectedWindow) {
                        ForEach(CoachWindow.allCases) { window in
                            Text(window.rawValue)
                                .tag(window)
                        }
                    }
                    .labelsHidden()
                }

                SectionCard(title: "Coach Summary") {
                    Text(store.coachSummary(for: selectedWindow))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.82))
                }
            }
            .padding(10)
        }
        .navigationTitle("Coach")
    }
}

private struct VitalsDetailView: View {
    @ObservedObject var store: WatchDashboardStore

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(store.vitals) { vital in
                    SectionCard(title: vital.title) {
                        VitalGaugeRow(gauge: vital)
                    }
                }
            }
            .padding(10)
        }
        .navigationTitle("Vitals")
    }
}

private struct VitalGaugeRow: View {
    let gauge: VitalGauge

    var body: some View {
        let span = max(gauge.maximum - gauge.minimum, 0.01)
        let lowRatio = (gauge.normalRange.lowerBound - gauge.minimum) / span
        let normalRatio = (gauge.normalRange.upperBound - gauge.normalRange.lowerBound) / span
        let valueRatio = (gauge.value - gauge.minimum) / span
        let currentBand = band(for: gauge.value, idealRange: gauge.normalRange)

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(gauge.displayValue)
                    .font(.headline.weight(.semibold))
                Spacer()
                StatusPill(band: currentBand)
            }

            GeometryReader { proxy in
                let fullWidth = proxy.size.width
                let lowWidth = fullWidth * CGFloat(lowRatio.clamped(to: 0...1))
                let normalWidth = fullWidth * CGFloat(normalRatio.clamped(to: 0...1))
                let highWidth = max(fullWidth - lowWidth - normalWidth, 0)
                let markerX = fullWidth * CGFloat(valueRatio.clamped(to: 0...1))

                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.blue.opacity(0.55))
                            .frame(width: lowWidth)
                        Rectangle()
                            .fill(Color.green.opacity(0.75))
                            .frame(width: normalWidth)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.orange.opacity(0.55))
                            .frame(width: highWidth)
                    }

                    Circle()
                        .fill(.white)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(currentBand.color, lineWidth: 2))
                        .offset(x: markerX - 5)
                }
            }
            .frame(height: 12)
        }
    }
}

private struct TrendMetricDetailView: View {
    let title: String
    let subtitle: String
    let points: [MetricPoint]
    let unit: String
    let accent: Color
    let idealRange: ClosedRange<Double>

    var body: some View {
        CrownControlledMetricView(
            title: title,
            subtitle: subtitle,
            points: points,
            unit: unit,
            accent: accent,
            idealRange: idealRange
        )
    }
}

private struct CrownControlledMetricView: View {
    let title: String
    let subtitle: String
    let points: [MetricPoint]
    let unit: String
    let accent: Color
    let idealRange: ClosedRange<Double>

    @State private var crownSelection: Double = 0

    private var selectedIndex: Int {
        guard !points.isEmpty else { return 0 }
        return Int(crownSelection.rounded()).clamped(to: 0...(points.count - 1))
    }

    var body: some View {
        GeometryReader { proxy in
            let compactHeight = proxy.size.height < 220
            let chartHeight = min(max(proxy.size.height * 0.38, 96), 128)
            let point = points[safe: selectedIndex]
            let selectedValue = point?.value ?? 0
            let trend = metricTrendDirection(points: points, index: selectedIndex)

            VStack(spacing: compactHeight ? 8 : 10) {
                MiniTrendChart(
                    points: points,
                    accent: accent,
                    secondaryPoints: nil,
                    highlightedIndex: selectedIndex,
                    idealRange: idealRange
                )
                .frame(height: chartHeight)

                TrendSummaryCard(
                    value: formattedMetricValue(selectedValue, unit: unit),
                    trend: trend,
                    accent: accent
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 8)
            .padding(.vertical, compactHeight ? 8 : 10)
        }
        .navigationTitle(title)
        .focusable(true)
        .digitalCrownRotation(
            $crownSelection,
            from: 0,
            through: Double(max(points.count - 1, 0)),
            by: 1,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onAppear {
            crownSelection = Double(max(points.count - 1, 0))
        }
    }
}

private struct MoodLoggerView: View {
    @ObservedObject var store: WatchDashboardStore

    private let moods: [(label: String, symbol: String)] = [
        ("Low", "cloud.drizzle.fill"),
        ("Flat", "cloud.fill"),
        ("Good", "sun.haze.fill"),
        ("Great", "sun.max.fill"),
        ("Peak", "sparkles")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                SectionCard(title: "Today") {
                    HStack(spacing: 6) {
                        ForEach(moods.indices, id: \.self) { index in
                            Button {
                                store.latestMoodIndex = index
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: moods[index].symbol)
                                        .font(.caption.weight(.bold))
                                    Text("\(index + 1)")
                                        .font(.system(size: 9, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(index == store.latestMoodIndex ? Color.yellow.opacity(0.28) : Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                SectionCard(title: "Current Mood") {
                    Text(moods[store.latestMoodIndex].label)
                        .font(.headline.weight(.semibold))
                    Text(store.moodNote)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .padding(10)
        }
        .navigationTitle("Mood Logger")
    }
}

private struct StressTrendView: View {
    @ObservedObject var store: WatchDashboardStore
    @State private var crownSelection: Double = 0

    private var selectedIndex: Int {
        guard !store.stressWeek.isEmpty else { return 0 }
        return Int(crownSelection.rounded()).clamped(to: 0...(store.stressWeek.count - 1))
    }

    var body: some View {
        GeometryReader { proxy in
            let compactHeight = proxy.size.height < 220
            let chartHeight = min(max(proxy.size.height * 0.38, 96), 128)
            let point = store.stressWeek[safe: selectedIndex]
            let stressPoints = store.stressWeek.map { MetricPoint(date: $0.date, value: $0.stress) }
            let selectedStress = point?.stress ?? 0
            let trend = metricTrendDirection(points: stressPoints, index: selectedIndex)

            VStack(spacing: compactHeight ? 8 : 10) {
                MiniTrendChart(
                    points: stressPoints,
                    accent: .red,
                    secondaryPoints: nil,
                    highlightedIndex: selectedIndex,
                    idealRange: 35...55
                )
                .frame(height: chartHeight)

                if point != nil {
                    TrendSummaryCard(
                        value: "\(Int(selectedStress.rounded())) pts",
                        trend: trend,
                        accent: .red
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 8)
            .padding(.vertical, compactHeight ? 8 : 10)
        }
        .navigationTitle("Stress")
        .focusable(true)
        .digitalCrownRotation(
            $crownSelection,
            from: 0,
            through: Double(max(store.stressWeek.count - 1, 0)),
            by: 1,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onAppear {
            crownSelection = Double(max(store.stressWeek.count - 1, 0))
        }
    }
}

private struct SleepSnapshotView: View {
    @ObservedObject var store: WatchDashboardStore

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                SectionCard(title: "Sleep Snapshot") {
                    MetricLine(label: "Hours", value: String(format: "%.1f h", store.sleepHours))
                    MetricLine(label: "Consistency", value: "\(Int(store.sleepConsistency.rounded()))%")
                }

                SectionCard(title: "Stages") {
                    VStack(spacing: 10) {
                        ForEach(store.sleepStages, id: \.name) { stage in
                            StageBarRow(name: stage.name, hours: stage.hours, total: store.sleepHours, color: stage.color)
                        }
                    }
                }
            }
            .padding(10)
        }
        .navigationTitle("Sleep")
    }
}

private struct StageBarRow: View {
    let name: String
    let hours: Double
    let total: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(String(format: "%.1f h", hours))
                    .font(.caption2)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(color)
                        .frame(width: proxy.size.width * CGFloat((hours / max(total, 0.1)).clamped(to: 0...1)))
                }
            }
            .frame(height: 8)
        }
    }
}

private struct WorkoutDetailView: View {
    let workout: WorkoutSession

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                SectionCard(title: workout.title) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(workout.subtitle)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.72))
                        MetricLine(label: "Start", value: shortTime(workout.startDate))
                        MetricLine(label: "Duration", value: "\(workout.durationMinutes) min")
                        MetricLine(label: "Calories", value: "\(workout.calories) kcal")
                        if let distance = workout.distanceKilometers {
                            MetricLine(label: "Distance", value: String(format: "%.1f km", distance))
                        }
                    }
                }

                SectionCard(title: "Performance") {
                    if workout.averageHeartRate > 0 {
                        MetricLine(label: "Avg HR", value: "\(workout.averageHeartRate) bpm")
                    }
                    if workout.maxHeartRate > 0 {
                        MetricLine(label: "Max HR", value: "\(workout.maxHeartRate) bpm")
                    }
                    if workout.strain > 0 {
                        MetricLine(label: "Strain", value: String(format: "%.1f / 21", workout.strain))
                    }
                    if workout.load > 0 {
                        MetricLine(label: "Load", value: String(format: "%.0f", workout.load))
                    }
                    if workout.averageHeartRate <= 0 && workout.maxHeartRate <= 0 && workout.strain <= 0 && workout.load <= 0 {
                        Text("Detailed performance analytics are syncing from your iPhone.")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }

                if workout.zoneMinutes.contains(where: { $0 > 0 }) {
                    SectionCard(title: "HR Zones") {
                        let maxValue = workout.zoneMinutes.max() ?? 1
                        VStack(spacing: 10) {
                            ForEach(workout.zoneMinutes.indices, id: \.self) { index in
                                ZoneBarRow(
                                    label: "Zone \(index + 1)",
                                    minutes: workout.zoneMinutes[index],
                                    maxValue: maxValue,
                                    color: zoneColor(index)
                                )
                            }
                        }
                    }
                }

                SectionCard(title: "Coach Note") {
                    Text(workout.note)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.82))
                }
            }
            .padding(10)
        }
        .navigationTitle("Workout Details")
    }
}

private struct MissingWorkoutView: View {
    var body: some View {
        Text("Workout details are unavailable.")
            .font(.caption)
            .padding()
            .navigationTitle("Workout")
    }
}

private struct LineChartPath: Shape {
    let points: [Double]
    let minValue: Double
    let maxValue: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }

        let inset: CGFloat = 10
        let height = rect.height - inset * 2
        let width = rect.width
        let span = max(maxValue - minValue, 0.0001)

        for index in points.indices {
            let x = width * CGFloat(index) / CGFloat(points.count - 1)
            let ratio = (points[index] - minValue) / span
            let y = rect.height - inset - height * CGFloat(ratio)

            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        return path
    }
}

private func band(for value: Double, idealRange: ClosedRange<Double>) -> MetricBand {
    if value < idealRange.lowerBound {
        return .low
    }

    if value > idealRange.upperBound {
        return .high
    }

    return .optimal
}

private func zoneColor(_ index: Int) -> Color {
    switch index {
    case 0:
        return .blue
    case 1:
        return .cyan
    case 2:
        return .green
    case 3:
        return .orange
    default:
        return .red
    }
}

private func detailMessage(for value: Double, title: String, band: MetricBand) -> String {
    switch band {
    case .low:
        return "\(title) is below its current target range. Keep recovery habits tight and avoid forcing intensity."
    case .optimal:
        return "\(title) is sitting in its target range. This is a good point to preserve the current rhythm."
    case .high:
        return "\(title) is above its current target range. Great trend, but make sure it is supported by recovery."
    }
}

private func metricTrendDirection(points: [MetricPoint], index: Int) -> MetricTrendDirection {
    guard points.indices.contains(index) else { return .steady }
    guard index > 0 else { return .steady }

    let current = points[index].value
    let previous = points[index - 1].value
    let delta = current - previous
    let threshold = max(abs(previous) * 0.035, 0.6)

    if delta > threshold {
        return .up
    }

    if delta < -threshold {
        return .down
    }

    return .steady
}

private func stressDetailMessage(for point: StressPoint) -> String {
    if point.stress <= 40 && point.regulation >= 70 {
        return "Stress stayed controlled while regulation remained strong."
    }

    if point.stress >= 60 {
        return "Stress ran elevated, so give recovery habits more weight."
    }

    return "Stress looks manageable with balanced energy and regulation."
}

private func formattedMetricValue(_ value: Double, unit: String) -> String {
    if unit == "TL" {
        return String(format: "%.0f %@", value, unit)
    }

    return String(format: "%.1f %@", value, unit)
}

private func shortDay(_ date: Date) -> String {
    date.formatted(.dateTime.weekday(.abbreviated).day())
}

private func weekdayLetter(_ date: Date) -> String {
    String(date.formatted(.dateTime.weekday(.narrow)))
}

private func shortTime(_ date: Date) -> String {
    date.formatted(.dateTime.hour().minute())
}

private func todayLabel() -> String {
    Date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
}

private func relativeDate(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: Date())
}

private func elapsedWorkoutString(_ elapsed: TimeInterval) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = elapsed >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
    formatter.zeroFormattingBehavior = [.pad]
    return formatter.string(from: elapsed) ?? "00:00"
}

private func customGoalLabel(for draft: WatchCustomWorkoutDraft) -> String {
    switch draft.goalMode {
    case .open:
        return "Open goal"
    case .time:
        return "Goal \(Int(draft.goalValue)) min"
    case .distance:
        return String(format: "Goal %.1f km", draft.goalValue)
    case .energy:
        return "Goal \(Int(draft.goalValue)) kcal"
    }
}

private func scheduledWorkoutText(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

private func scheduledWorkoutText(_ components: DateComponents) -> String {
    guard let date = Calendar.current.date(from: components) else {
        return "Scheduled workout"
    }

    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

private func shortMetricLabel(_ value: Double) -> String {
    if value >= 100 {
        return String(format: "%.0f", value)
    }

    return String(format: "%.1f", value)
}

private func watchStrainClassificationTitle(for score: Double) -> String {
    switch score {
    case ..<6:
        return "Low"
    case ..<11:
        return "Building"
    case ..<15:
        return "Productive"
    default:
        return "High"
    }
}

private func watchStrainClassificationColor(for score: Double) -> Color {
    switch score {
    case ..<6:
        return .blue
    case ..<11:
        return .green
    case ..<15:
        return .orange
    default:
        return .red
    }
}

private func watchRecoveryClassificationTitle(for score: Double) -> String {
    switch score {
    case 90...100:
        return "Full Send"
    case 70..<90:
        return "Perform"
    case 40..<70:
        return "Adapt"
    default:
        return "Recover"
    }
}

private func watchRecoveryClassificationColor(for score: Double) -> Color {
    switch score {
    case 90...100:
        return .green
    case 70..<90:
        return .green
    case 40..<70:
        return .orange
    default:
        return .red
    }
}

private func hoursString(_ hours: Double) -> String {
    let wholeHours = Int(hours)
    let minutes = Int(((hours - Double(wholeHours)) * 60).rounded())
    return "\(wholeHours)h \(minutes)m"
}

private struct WorkoutPrimaryLine: Identifiable {
    let id: String
    let value: String
    let label: String
}

private func metricLines(for manager: WatchWorkoutManager, variant: WorkoutMetricsVariant) -> [WorkoutPrimaryLine] {
    switch variant {
    case .primary:
        return primaryWorkoutLines(for: manager)
    case .secondary:
        return secondaryWorkoutLines(for: manager)
    }
}

private func primaryWorkoutLines(for manager: WatchWorkoutManager) -> [WorkoutPrimaryLine] {
    let distanceMiles = manager.totalDistanceMeters / 1609.344
    let distanceKilometers = manager.totalDistanceMeters / 1000
    let elapsedHours = max(manager.elapsedTime / 3600, 0.0001)
    let averageSpeedMPH = distanceMiles / elapsedHours
    let averageSpeedKPH = distanceKilometers / elapsedHours
    let averagePaceSecondsPerMile = distanceMiles > 0 ? manager.elapsedTime / distanceMiles : 0
    let rollingPaceSecondsPerMile = (manager.currentSpeedMetersPerSecond ?? 0) > 0
        ? 1609.344 / max(manager.currentSpeedMetersPerSecond ?? 0, 0.01)
        : 0

    switch manager.activeActivity {
    case .some(.running), .some(.walking):
        return [
            WorkoutPrimaryLine(id: "rolling-mile", value: paceString(secondsPerMile: rollingPaceSecondsPerMile), label: "ROLLING MILE"),
            WorkoutPrimaryLine(id: "avg-pace", value: paceString(secondsPerMile: averagePaceSecondsPerMile), label: "AVERAGE PACE"),
            WorkoutPrimaryLine(id: "distance", value: distanceString(miles: distanceMiles), label: "")
        ]
    case .some(.cycling):
        return [
            WorkoutPrimaryLine(id: "avg-speed", value: speedString(mph: averageSpeedMPH), label: "AVERAGE SPEED"),
            WorkoutPrimaryLine(id: "power", value: manager.currentPowerWatts.map { "\(Int($0.rounded()))W" } ?? "--", label: "POWER"),
            WorkoutPrimaryLine(id: "distance", value: distanceString(miles: distanceMiles), label: "")
        ]
    case .some(.swimming):
        return [
            WorkoutPrimaryLine(id: "distance", value: distanceString(kilometers: distanceKilometers), label: "DISTANCE"),
            WorkoutPrimaryLine(id: "strokes", value: manager.strokeCount.map { "\(Int($0.rounded()))" } ?? "--", label: "STROKES"),
            WorkoutPrimaryLine(id: "avg-hr", value: manager.averageHeartRate.map { "\(Int($0.rounded()))" } ?? "--", label: "AVERAGE HR")
        ]
    case .some(.hiking):
        return [
            WorkoutPrimaryLine(id: "avg-speed", value: speedString(kph: averageSpeedKPH), label: "AVERAGE SPEED"),
            WorkoutPrimaryLine(id: "climb", value: manager.flightsClimbed.map { "\(Int($0.rounded())) FL" } ?? "--", label: "ELEVATION"),
            WorkoutPrimaryLine(id: "distance", value: distanceString(miles: distanceMiles), label: "")
        ]
    default:
        return [
            WorkoutPrimaryLine(id: "energy", value: manager.metrics.first(where: { $0.id == "energy" })?.valueText ?? "--", label: "ENERGY"),
            WorkoutPrimaryLine(id: "avg-hr", value: manager.averageHeartRate.map { "\(Int($0.rounded())) BPM" } ?? "--", label: "AVERAGE HR"),
            WorkoutPrimaryLine(id: "time", value: preciseWorkoutElapsedString(manager.elapsedTime), label: "ELAPSED")
        ]
    }
}

private func secondaryWorkoutLines(for manager: WatchWorkoutManager) -> [WorkoutPrimaryLine] {
    switch manager.activeActivity {
    case .some(.running), .some(.walking), .some(.hiking):
        return [
            WorkoutPrimaryLine(id: "cadence", value: manager.currentCadence.map { "\(Int($0.rounded()))" } ?? "--", label: "CADENCE"),
            WorkoutPrimaryLine(id: "stride", value: manager.strideMeters.map { String(format: "%.2fm", $0) } ?? "--", label: "STRIDE"),
            WorkoutPrimaryLine(id: "gct", value: manager.groundContactTimeMilliseconds.map { "\(Int($0.rounded()))ms" } ?? "--", label: "GROUND CONTACT")
        ]
    case .some(.cycling):
        return [
            WorkoutPrimaryLine(id: "cadence", value: manager.currentCadence.map { "\(Int($0.rounded()))RPM" } ?? "--", label: "CADENCE"),
            WorkoutPrimaryLine(id: "power-avg", value: manager.averagePowerWatts.map { "\(Int($0.rounded()))W" } ?? "--", label: "AVG POWER"),
            WorkoutPrimaryLine(id: "elev", value: "\(Int(manager.elevationGainFeet.rounded()))FT", label: "ELEVATION")
        ]
    default:
        return Array(specificMetricCards(from: manager.metrics, activity: manager.activeActivity).prefix(3)).map {
            WorkoutPrimaryLine(id: $0.id, value: $0.valueText.replacingOccurrences(of: " ", with: ""), label: $0.title.uppercased())
        }
    }
}

private func summaryMetricCards(from metrics: [WatchLiveMetric]) -> [WatchLiveMetric] {
    let preferredIDs = ["hr-current", "distance", "energy", "speed-current", "hr-avg", "power-current"]
    let filtered = metrics.filter { preferredIDs.contains($0.id) }
    return filtered.isEmpty ? Array(metrics.prefix(6)) : filtered
}

private func specificMetricCards(
    from metrics: [WatchLiveMetric],
    activity: HKWorkoutActivityType?
) -> [WatchLiveMetric] {
    let preferredIDs: [String]

    switch activity {
    case .running:
        preferredIDs = ["speed-current", "stride", "gct", "vo", "power-current", "hr-avg"]
    case .cycling:
        preferredIDs = ["power-current", "power-avg", "cadence", "speed-current", "distance", "hr-avg"]
    case .swimming:
        preferredIDs = ["distance", "strokes", "energy", "hr-avg"]
    case .walking, .hiking:
        preferredIDs = ["speed-current", "distance", "flights", "energy", "hr-avg"]
    default:
        preferredIDs = ["power-current", "cadence", "stride", "gct", "vo", "flights", "strokes", "hr-avg"]
    }

    let filtered = metrics.filter { preferredIDs.contains($0.id) }
    return filtered.isEmpty ? metrics : filtered
}

private func shortElapsedString(_ elapsed: TimeInterval) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = elapsed >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
    formatter.zeroFormattingBehavior = [.pad]
    return formatter.string(from: elapsed) ?? "00:00"
}

private func workoutElapsedDisplayString(_ elapsed: TimeInterval, reducedLuminance: Bool) -> String {
    if reducedLuminance {
        return shortElapsedString(elapsed.rounded(.down))
    }
    return preciseWorkoutElapsedString(elapsed)
}

private func preciseWorkoutElapsedString(_ elapsed: TimeInterval) -> String {
    let totalCentiseconds = Int((elapsed * 100).rounded())
    let centiseconds = totalCentiseconds % 100
    let totalSeconds = totalCentiseconds / 100
    let seconds = totalSeconds % 60
    let totalMinutes = totalSeconds / 60
    let minutes = totalMinutes % 60
    let hours = totalMinutes / 60

    if hours > 0 {
        return String(format: "%02d:%02d:%02d.%02d", hours, minutes, seconds, centiseconds)
    }
    if minutes > 0 {
        return String(format: "%02d:%02d.%02d", minutes, seconds, centiseconds)
    }
    return String(format: "%02d.%02d", seconds, centiseconds)
}

private func paceString(secondsPerMile: Double) -> String {
    guard secondsPerMile.isFinite, secondsPerMile > 0 else { return "--" }
    let minutes = Int(secondsPerMile) / 60
    let seconds = Int(secondsPerMile) % 60
    return String(format: "%d'%02d''", minutes, seconds)
}

private func speedString(mph: Double) -> String {
    guard mph.isFinite, mph > 0 else { return "--" }
    return String(format: "%.1fMPH", mph)
}

private func speedString(kph: Double) -> String {
    guard kph.isFinite, kph > 0 else { return "--" }
    return String(format: "%.1fKM/H", kph)
}

private func distanceString(miles: Double) -> String {
    guard miles.isFinite, miles > 0 else { return "0.00MI" }
    return String(format: "%.2fMI", miles)
}

private func distanceString(kilometers: Double) -> String {
    guard kilometers.isFinite, kilometers > 0 else { return "0.00KM" }
    return String(format: "%.2fKM", kilometers)
}

private func segmentGraphPoints(for manager: WatchWorkoutManager) -> [WatchWorkoutSeriesPoint] {
    switch manager.activeActivity {
    case .some(.cycling):
        return manager.powerHistory
    case .some(.swimming):
        return manager.paceHistory
    default:
        return manager.paceHistory
    }
}

private func segmentPrimaryValue(for manager: WatchWorkoutManager) -> String {
    switch manager.activeActivity {
    case .some(.cycling):
        return manager.currentPowerWatts.map { "\(Int($0.rounded()))W" } ?? "--"
    default:
        let currentPace = (manager.currentSpeedMetersPerSecond ?? 0) > 0 ? 1609.344 / max(manager.currentSpeedMetersPerSecond ?? 0, 0.01) : 0
        return paceString(secondsPerMile: currentPace)
    }
}

private func segmentPrimaryLabel(for manager: WatchWorkoutManager) -> String {
    manager.activeActivity == .cycling ? "CURRENT POWER" : "CURRENT PACE"
}

private func segmentSecondaryValue(for manager: WatchWorkoutManager) -> String {
    if let latest = manager.splits.last {
        return shortElapsedString(latest.splitDuration)
    }
    return shortElapsedString(manager.elapsedTime)
}

private func segmentSecondaryLabel(for manager: WatchWorkoutManager) -> String {
    manager.splits.isEmpty ? "ELAPSED" : "LAST SEGMENT"
}

private func metricPrimaryValue(_ metric: WorkoutGraphMetric, manager: WatchWorkoutManager) -> String {
    switch metric {
    case .elevation:
        return "\(Int(manager.elevationGainFeet.rounded()))FT"
    case .power:
        return manager.currentPowerWatts.map { "\(Int($0.rounded()))W" } ?? "--"
    }
}

private func metricPrimaryLabel(_ metric: WorkoutGraphMetric) -> String {
    switch metric {
    case .elevation:
        return "ELEV GAIN"
    case .power:
        return "CURRENT POWER"
    }
}

private func metricSecondaryValue(_ metric: WorkoutGraphMetric, manager: WatchWorkoutManager) -> String {
    switch metric {
    case .elevation:
        return "\(Int(manager.currentElevationFeet.rounded()))FT"
    case .power:
        return manager.currentCadence.map { "\(Int($0.rounded()))RPM" } ?? "--"
    }
}

private func metricSecondaryLabel(_ metric: WorkoutGraphMetric, manager: WatchWorkoutManager) -> String {
    switch metric {
    case .elevation:
        return "ELEV"
    case .power:
        return "CADENCE"
    }
}

private func splitSpeedValue(for manager: WatchWorkoutManager, splitDistanceMeters: Double, splitDuration: TimeInterval) -> String {
    switch manager.activeActivity {
    case .some(.cycling):
        return speedString(mph: (splitDistanceMeters / max(splitDuration, 1)) * 2.23694)
    case .some(.swimming):
        return pacePer100mString(distanceMeters: splitDistanceMeters, duration: splitDuration)
    default:
        let pace = splitDistanceMeters > 0 ? splitDuration / (splitDistanceMeters / 1609.344) : 0
        return paceString(secondsPerMile: pace)
    }
}

private func splitSpeedLabel(for manager: WatchWorkoutManager) -> String {
    switch manager.activeActivity {
    case .some(.cycling):
        return "SPLIT SPEED"
    case .some(.swimming):
        return "SPLIT PACE"
    default:
        return "SPLIT PACE"
    }
}

private func splitDistanceValue(for manager: WatchWorkoutManager, splitDistanceMeters: Double) -> String {
    switch manager.activeActivity {
    case .some(.swimming):
        return "\(Int(splitDistanceMeters.rounded()))M"
    default:
        return distanceString(miles: splitDistanceMeters / 1609.344)
    }
}

private func pacerCurrentValue(for manager: WatchWorkoutManager) -> String {
    guard let target = manager.pacerTarget else { return "--" }
    switch target.unitLabel {
    case "PACE", "/100M":
        let pace = target.unitLabel == "/100M"
            ? pacePer100mValue(speedMetersPerSecond: manager.currentSpeedMetersPerSecond)
            : paceString(secondsPerMile: currentPaceSecondsPerMile(manager))
        return pace
    default:
        return speedString(mph: (manager.currentSpeedMetersPerSecond ?? 0) * 2.23694)
    }
}

private func pacerAverageValue(for manager: WatchWorkoutManager) -> String {
    let distanceMiles = manager.totalDistanceMeters / 1609.344
    let avgPace = distanceMiles > 0 ? manager.elapsedTime / distanceMiles : 0
    guard let target = manager.pacerTarget else { return "--" }
    switch target.unitLabel {
    case "PACE":
        return paceString(secondsPerMile: avgPace)
    case "/100M":
        return pacePer100mString(distanceMeters: manager.totalDistanceMeters, duration: manager.elapsedTime)
    default:
        let avgSpeed = manager.totalDistanceMeters / max(manager.elapsedTime, 1)
        return speedString(mph: avgSpeed * 2.23694)
    }
}

private func pacerProgress(for manager: WatchWorkoutManager, target: WatchPacerTarget) -> Double {
    let currentValue: Double
    switch target.unitLabel {
    case "PACE":
        currentValue = currentPaceSecondsPerMile(manager)
    case "/100M":
        currentValue = currentPacePer100Meters(manager)
    default:
        currentValue = (manager.currentSpeedMetersPerSecond ?? 0) * 2.23694
    }
    let span = max(target.upperBound - target.lowerBound, 0.001)
    return (currentValue - (target.lowerBound - span)) / (span * 3)
}

private func pacerInRange(for manager: WatchWorkoutManager, target: WatchPacerTarget) -> Bool {
    let currentValue: Double
    switch target.unitLabel {
    case "PACE":
        currentValue = currentPaceSecondsPerMile(manager)
    case "/100M":
        currentValue = currentPacePer100Meters(manager)
    default:
        currentValue = (manager.currentSpeedMetersPerSecond ?? 0) * 2.23694
    }
    return currentValue >= target.lowerBound && currentValue <= target.upperBound
}

private func distanceSummaryValue(for manager: WatchWorkoutManager) -> String {
    switch manager.activeActivity {
    case .some(.swimming):
        return "\(Int(manager.totalDistanceMeters.rounded()))M"
    default:
        return distanceString(miles: manager.totalDistanceMeters / 1609.344)
    }
}

private func currentPaceSecondsPerMile(_ manager: WatchWorkoutManager) -> Double {
    guard let speed = manager.currentSpeedMetersPerSecond, speed > 0 else { return 0 }
    return 1609.344 / speed
}

private func currentPacePer100Meters(_ manager: WatchWorkoutManager) -> Double {
    guard let speed = manager.currentSpeedMetersPerSecond, speed > 0 else { return 0 }
    return 100 / speed
}

private func pacePer100mValue(speedMetersPerSecond: Double?) -> String {
    guard let speedMetersPerSecond, speedMetersPerSecond > 0 else { return "--" }
    let seconds = 100 / speedMetersPerSecond
    let minutes = Int(seconds) / 60
    let remainder = Int(seconds) % 60
    return String(format: "%d:%02d", minutes, remainder)
}

private func pacePer100mString(distanceMeters: Double, duration: TimeInterval) -> String {
    guard distanceMeters > 0, duration > 0 else { return "--" }
    let seconds = duration / (distanceMeters / 100)
    let minutes = Int(seconds) / 60
    let remainder = Int(seconds) % 60
    return String(format: "%d:%02d", minutes, remainder)
}

private func shortMetricAxisLabel(_ value: Double) -> String {
    if value >= 100 {
        return "\(Int(value.rounded()))"
    }
    if value >= 10 {
        return String(format: "%.0f", value)
    }
    return String(format: "%.1f", value)
}

private func denseGraphSamples(from points: [WatchWorkoutSeriesPoint], count: Int) -> [Double] {
    guard count > 0 else { return [] }
    guard !points.isEmpty else { return Array(repeating: 0, count: count) }
    guard points.count > 1 else { return Array(repeating: points[0].value, count: count) }

    let sorted = points.sorted { $0.elapsedTime < $1.elapsedTime }
    let start = sorted.first?.elapsedTime ?? 0
    let end = max(sorted.last?.elapsedTime ?? start, start + 1)
    let span = end - start

    return (0..<count).map { index in
        let progress = Double(index) / Double(max(count - 1, 1))
        let targetTime = start + span * progress
        let upperIndex = sorted.firstIndex { $0.elapsedTime >= targetTime } ?? (sorted.count - 1)
        let lowerIndex = max(upperIndex - 1, 0)
        let lower = sorted[lowerIndex]
        let upper = sorted[upperIndex]

        if upper.elapsedTime == lower.elapsedTime {
            return upper.value
        }

        let localProgress = (targetTime - lower.elapsedTime) / (upper.elapsedTime - lower.elapsedTime)
        return lower.value + (upper.value - lower.value) * localProgress
    }
}

private func powerZoneColor(_ index: Int) -> Color {
    switch index {
    case 0:
        return Color(red: 0.13, green: 0.31, blue: 0.55)
    case 1:
        return Color(red: 0.12, green: 0.43, blue: 0.39)
    case 2:
        return Color(red: 0.39, green: 0.54, blue: 0.05)
    case 3:
        return Color(red: 0.63, green: 0.35, blue: 0.05)
    default:
        return Color(red: 0.49, green: 0.03, blue: 0.24)
    }
}

private func powerZoneIndex(_ power: Double) -> Int {
    let referencePower = 240.0
    let ratio = power / max(referencePower, 1)
    switch ratio {
    case ..<0.60:
        return 0
    case ..<0.75:
        return 1
    case ..<0.90:
        return 2
    case ..<1.05:
        return 3
    default:
        return 4
    }
}

private func watchWorkoutSymbol(_ activityType: HKWorkoutActivityType?) -> String {
    switch activityType {
    case .some(.running):
        return "figure.run"
    case .some(.walking):
        return "figure.walk"
    case .some(.cycling):
        return "bicycle"
    case .some(.swimming):
        return "figure.pool.swim"
    case .some(.hiking):
        return "figure.hiking"
    case .some(.traditionalStrengthTraining), .some(.functionalStrengthTraining):
        return "dumbbell.fill"
    case .some(.highIntensityIntervalTraining):
        return "flame.fill"
    case .some(.yoga):
        return "figure.mind.and.body"
    default:
        return "figure.run"
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
