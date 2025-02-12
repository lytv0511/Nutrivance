#!/bin/bash
cd Nutrivance

views=(
    "Dashboard" "TodaysPlan" "WorkoutHistory" "TrainingCalendar"
    "FormCoach" "MovementAnalysis" "ExerciseLibrary" "ProgramBuilder" "WorkoutGenerator"
    "RecoveryScore" "SleepAnalysis" "MobilityTest" "ReadinessCheck" "StrainRecovery"
    "ActivityRings" "HeartZones" "StepCount" "Distance" "CaloriesBurned" "PersonalRecords"
    "PreWorkoutTiming" "PostWorkoutWindow" "PerformanceFoods" "HydrationStatus" "MacroBalance"
    "LiveChallenges" "FriendActivity" "Achievements" "ShareWorkouts" "Leaderboards"
)

for view in "${views[@]}"; do
    cat > "${view}View.swift" << EOF
import SwiftUI

struct ${view}View: View {
    var body: some View {
        ComingSoonView(
            feature: "$view",
            description: "Experience the future of fitness tracking with $view"
        )
    }
}
EOF
done
