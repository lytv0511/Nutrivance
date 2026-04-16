# Program Builder - Apple Workout App Integration

## Overview

The **Workout App** option in ProgramBuilderView allows users to send custom workouts directly to Apple's first-party Workout app. Workouts are built using WorkoutKit and scheduled via `WorkoutScheduler`.

**Location in UI:** ProgramBuilderView → workoutLaunchSection → "Workout App" button (iPhone only)

## Architecture

### Data Flow

```
ProgramBuilderView
    └── buildPlanPhases() → [ProgramWorkoutPlanPhase]
            └── sendWorkoutToAppleWorkoutAppOnWatch()
                    └── buildWorkoutPlansFromPhases()
                            ├── buildTriathlonWorkout() (if applicable)
                            └── buildCustomWorkoutFromPhases()
                                    ├── buildWorkoutStep()
                                    │       └── buildWorkoutAlert()
                                    ├── buildIntervalStepFromStage()
                                    └── IntervalBlock(iterations:)

WorkoutScheduler.shared.schedule(WorkoutPlan, at: dateComponents)
```

### Key Components

| Component | Description |
|-----------|-------------|
| `ProgramWorkoutPlanPhase` | Contains activity type, location, duration, and stages |
| `ProgramCustomWorkoutMicroStage` | Individual workout segment with role, goal, and target |
| `ProgramWorkoutCircuitGroup` | Groups stages that repeat together |
| `CustomWorkout` | WorkoutKit workout with warmup, blocks, cooldown |
| `IntervalBlock` | Contains steps and iteration count |
| `WorkoutStep` | Individual interval with goal and optional alert |
| `WorkoutPlan` | Wrapper for scheduling via WorkoutScheduler |

## Stage Structure

### ProgramMicroStageRole

Workout stages are categorized by their purpose:

| Role | WorkoutKit Purpose | Description |
|------|-------------------|-------------|
| `warmup` | `.work` | Preparation phase, typically 5-15 min |
| `steady` | `.work` | Sustained effort at target intensity |
| `work` | `.work` | High-intensity interval work |
| `recovery` | `.recovery` | Low-intensity recovery between efforts |
| `cooldown` | `.work` | Post-workout recovery phase |

### ProgramMicroStageGoal

The goal defines what metric drives the stage:

| Goal | WorkoutKit Goal | Alert Support |
|------|----------------|---------------|
| `time` | `.time(minutes, .minutes)` | None |
| `distance` | `.distance(km, .kilometers)` | None |
| `energy` | `.energy(kcal, .kilocalories)` | None |
| `pace` | `.distance(...)` (calculated) | `.speed()` alert |
| `speed` | `.distance(...)` (calculated) | `.speed()` alert |
| `power` | `.energy(...)` (calculated) | `.power()` alert |
| `cadence` | `.time(...)` (fallback) | `.cadence()` alert |
| `heartRateZone` | `.energy(...)` (estimated) | `.heartRate(zone:)` alert |
| `open` | `.time(...)` (1 min fallback) | None |

### ProgramStageTargetBehavior

Defines how the target is enforced:

| Behavior | Description |
|----------|-------------|
| `range` | Maintain within target range |
| `aboveThreshold` | Match or exceed target |
| `belowThreshold` | Stay below target |
| `completionGoal` | No threshold enforcement |

## Translation to Apple WorkoutKit

### Stage → WorkoutStep

Each `ProgramCustomWorkoutMicroStage` translates to a `WorkoutKit.WorkoutStep`:

```swift
WorkoutStep(
    goal: workoutGoalFromStage(stage),
    alert: buildWorkoutAlert(for: stage),
    displayName: stage.title
)
```

### Role → IntervalStep.Purpose

```swift
switch stage.role {
case .recovery: purpose = .recovery
default: purpose = .work
}
```

### Goal → WorkoutGoal

| Goal | Conversion |
|------|-----------|
| `time` | `.time(minutes, .minutes)` |
| `distance` | `.distance(value, .kilometers)` |
| `energy` | `.energy(value, .kilocalories)` |
| `pace` | Parses "7:10-7:30 /mi" → calculates distance for duration |
| `speed` | Parses "18-20 mph" → calculates distance for duration |
| `power` | Converts to energy based on avg power × duration |
| `cadence` | Falls back to time goal |
| `heartRateZone` | Estimates kcal burn based on zone |

### Workout Alerts

Alerts are attached to steps for real-time guidance:

#### Heart Rate Zone
```swift
func buildHeartRateAlert(for stage) -> WorkoutAlert?
// "Zone 5" → .heartRate(zone: 5)
// "Zone 2-3" → .heartRate(zone: 3) // uses upper bound
```

#### Power
```swift
func buildPowerAlert(label:, behavior:) -> WorkoutAlert?
// "250-300 W" → .power(250...300, unit: .watts)
// "belowthreshold" + "250 W" → .power(0...250, unit: .watts)
```

#### Cadence
```swift
func buildCadenceAlert(label:, behavior:) -> WorkoutAlert?
// "90-110 rpm" → .cadence(90...110)
// "belowthreshold" + "100 rpm" → .cadence(0...100)
```

#### Speed
```swift
func buildSpeedAlert(label:, behavior:) -> WorkoutAlert?
// "18-20 mph" → .speed(28.97...32.19, unit: .kilometersPerHour)
// "10-12 kph" → .speed(10...12, unit: .kilometersPerHour)
```

#### Pace (converted to speed)
```swift
func buildPaceAlert(label:, behavior:) -> WorkoutAlert?
// "7:10-7:30 /mi" → .speed(...) in kph
// "5:00-5:30 /km" → .speed(...) in kph
```

## Circuit Groups

Stages can be grouped into **circuits** that repeat together:

```swift
struct ProgramWorkoutCircuitGroup {
    let id: UUID
    var title: String       // e.g., "Main Set", "Supersets"
    var repeats: Int         // Number of times to repeat
}

// Stage references its group
struct ProgramCustomWorkoutMicroStage {
    var circuitGroupID: UUID?
    var repeatSetLabel: String  // Alternative label-based grouping
}
```

### Translation to IntervalBlock

```swift
// Group stages by circuit key (ID or label)
while stageIndex < workStages.count {
    let stage = workStages[stageIndex]
    let circuitKey = stage.circuitGroupID?.uuidString ?? stage.repeatSetLabel
    
    var groupedStages = [stage]
    // Collect all stages with same circuit key and repeats
    
    let steps = groupedStages.map { buildIntervalStepFromStage($0) }
    
    // IntervalBlock.iterations handles the repeat count
    blocks.append(
        IntervalBlock(steps: steps, iterations: max(stage.repeats, 1))
    )
}
```

## Workout Structure

### CustomWorkout

```swift
CustomWorkout(
    activity: HKWorkoutActivityType,  // e.g., .running, .cycling
    location: HKWorkoutSessionLocationType,  // .outdoor, .indoor
    displayName: String,
    warmup: WorkoutStep?,  // First .warmup stage
    blocks: [IntervalBlock],
    cooldown: WorkoutStep?  // Last .cooldown stage
)
```

### WorkoutPlan

```swift
WorkoutPlan(.custom(customWorkout))
```

## Triathlon Support

When phases include swimming + cycling + running (any 2+), a `SwimBikeRunWorkout` is created:

```swift
// buildTriathlonWorkout() detects:
// - "swimming" → .swimming(pool/openWater)
// - "cycling" → .cycling(outdoor/indoor)
// - "running" → .running(outdoor/indoor)

// Ordered and wrapped
return SwimBikeRunWorkout(activities: workoutActivities, displayName: title)
return WorkoutPlan(.swimBikeRun(triathlonWorkout))
```

## Supported Activity Types

All `HKWorkoutActivityType` values from the program are supported:

| ProgramWorkoutType | HKWorkoutActivityType |
|-------------------|----------------------|
| running | `.running` |
| walking | `.walking` |
| hiking | `.hiking` |
| cycling | `.cycling` |
| swimming | `.swimming` |
| rowing | `.rowing` |
| elliptical | `.elliptical` |
| stairStepper | `.stairClimbing` |
| ... | All others supported |

## Scheduling

Workouts are scheduled via `WorkoutScheduler`:

```swift
// Schedule for 1 minute in the future
let now = Date()
var dateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: now)
dateComponents.minute = (dateComponents.minute ?? 0) + 1

for plan in workoutPlans {
    try await WorkoutScheduler.shared.schedule(plan, at: dateComponents)
}
```

**Requirements:**
- iOS 17+ (`WorkoutScheduler.isSupported`)
- Authorization from `WorkoutScheduler.shared.requestAuthorization()`

## Error Handling

| Error | Cause | User Message |
|-------|-------|--------------|
| `noValidPhases` | No activity selected | "No valid workout phases found." |
| `invalidActivity` | Unknown HKWorkoutActivityType | "Invalid workout activity type." |
| `triathlonNotSupported` | Missing triathlon activities | (caught internally) |
| `customWorkoutFailed` | Translation failed | "Failed to create custom workout." |
| Not authorized | WorkoutScheduler permission denied | "Permission denied to schedule workouts." |

## Stage Manager Integration

The **Stage Manager** feature generates workout stage suggestions that integrate with the Workout App:

1. User selects activity and optional intent (e.g., "improve FTP")
2. System generates 3 suggestions based on:
   - Activity type
   - User's intensity profile (strain, recovery, readiness scores)
   - Banned roles/goals from user's preferences
3. Suggestions include pre-configured:
   - Role (warmup, steady, work, recovery, cooldown)
   - Goal (time, power, HR zone, cadence, etc.)
   - Target values (port from Past Quests recommendations)
   - Default duration and repeat counts
4. User adds stages to workout → translated to Apple WorkoutKit

## Target Value Formatting

Target values are parsed from text using regex:

| Format | Example | Parsed As |
|--------|---------|-----------|
| Pace range | "7:10-7:30 /mi" | (430, 450) seconds/mile |
| Speed range | "18-20 mph" | (18, 20) miles/hour |
| Power range | "250-300 W" | (250, 300) watts |
| Cadence range | "90-110 rpm" | (90, 110) steps/minute |
| HR Zone | "Zone 2-3" | zone 3 (upper) |
| Distance | "10 km" | 10 kilometers |
| Energy | "300 kcal" | 300 kilocalories |

## Implementation Files

| File | Responsibility |
|------|---------------|
| `ProgramBuilderView.swift` | UI, buildPlanPhases() |
| `ContentView.swift` | sendWorkoutToAppleWorkoutAppOnWatch(), buildWorkoutPlansFromPhases(), buildCustomWorkoutFromPhases(), workoutGoalFromStage(), buildWorkoutAlert() |
| `WatchWorkoutSupport.swift` | Watch-side implementation (mirrors iPhone logic) |

## Future Enhancements

- [ ] Power zone alerts with FTP-based targets
- [ ] Cadence drill patterns with step cues
- [ ] HRV-guided workout selection
- [ ] VO2max-based intensity suggestions
- [ ] Workout sharing via link
