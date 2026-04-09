//
//  WorkoutLiveActivityControlIntents.swift
//  WaterWidget
//
//  Interactive Live Activity controls (lock screen, Dynamic Island, StandBy).
//  Intents run in the widget extension; commands are queued in the app group and
//  drained by the iPhone app (see iOSWorkoutSyncManager.flushPendingLiveActivityWorkoutControl).
//

import ActivityKit
import AppIntents
import Foundation

private enum LiveActivityWorkoutControlStorage {
    static let suiteName = "group.com.nutrivance.workouts"
    static let pendingKey = "liveActivityPendingWorkoutControl"

    static func enqueue(_ command: String) {
        UserDefaults(suiteName: suiteName)?.set(command.lowercased(), forKey: pendingKey)
    }
}

// MARK: - Live Activity intents

struct PauseWorkoutLiveActivityIntent: LiveActivityIntent {
    typealias ActivityAttributesType = WorkoutLiveActivityAttributes

    static var title: LocalizedStringResource { "Pause" }
    static var description: IntentDescription {
        IntentDescription("Pause the workout on Apple Watch.")
    }

    init() {}

    func perform() async throws -> some IntentResult {
        LiveActivityWorkoutControlStorage.enqueue("pause")
        return .result()
    }
}

struct ResumeWorkoutLiveActivityIntent: LiveActivityIntent {
    typealias ActivityAttributesType = WorkoutLiveActivityAttributes

    static var title: LocalizedStringResource { "Resume" }
    static var description: IntentDescription {
        IntentDescription("Resume the workout on Apple Watch.")
    }

    init() {}

    func perform() async throws -> some IntentResult {
        LiveActivityWorkoutControlStorage.enqueue("resume")
        return .result()
    }
}

struct EndWorkoutLiveActivityIntent: LiveActivityIntent {
    typealias ActivityAttributesType = WorkoutLiveActivityAttributes

    static var title: LocalizedStringResource { "End" }
    static var description: IntentDescription {
        IntentDescription("End the workout on Apple Watch.")
    }

    init() {}

    func perform() async throws -> some IntentResult {
        LiveActivityWorkoutControlStorage.enqueue("stop")
        return .result()
    }
}
