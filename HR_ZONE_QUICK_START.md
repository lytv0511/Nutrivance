# Dynamic HR Zone System - Developer Quick Start

## One-Minute Overview

The dynamic heart rate zone system automatically personalizes zone calculations per sport:
- **Automatic detection** of best schema (Karvonen for runners, LTHR for cyclists)
- **Adaptive zones** that adjust based on recovery state (optional)
- **Sport-specific profiles** cached for 7 days
- **Fallback strategies** when HealthKit data unavailable

## Integration

### 1. Automatic (Already Built In!)

Zones are **automatically integrated** into `WorkoutAnalytics`:

```swift
let analytics = await healthKitManager.computeWorkoutAnalytics(for: workout)

// Access zone data:
if let profile = analytics.hrZoneProfile {
    print("Schema: \(profile.schema.rawValue)")
    print("Max HR: \(profile.maxHR ?? 0)")
    print("Zones: \(profile.zones.count)")
}

// Access zone breakdown:
for (zone, timeInZone) in analytics.hrZoneBreakdown {
    print("\(zone.name): \(Int(timeInZone)) seconds")
}
```

### 2. Manual Zone Profile Creation

For custom applications:

```swift
// Get auto-selected profile for a sport
let profile = await healthKitManager.getOrCreateZoneProfile(for: .running)

// Or create with custom parameters
let customProfile = await healthKitManager.createHRZoneProfile(
    for: .cycling,
    schema: .lactatThreshold,
    customMaxHR: 195,
    customRestingHR: 50,
    customLTHR: 175
)

// Check what was generated
customProfile.zones.forEach { zone in
    print("\(zone.name): \(Int(zone.range.lowerBound)) - \(Int(zone.range.upperBound)) bpm")
}
```

### 3. Calculate Zone Time

Compute time spent in each zone:

```swift
let hrSamples: [(Date, Double)] = // ... from workout
let profile = await healthKitManager.getOrCreateZoneProfile(for: .running)

let breakdown = healthKitManager.calculateZoneBreakdown(
    heartRates: hrSamples,
    zoneProfile: profile
)

breakdown.forEach { zone, timeInZone in
    let minutes = timeInZone / 60
    print("\(zone.name): \(String(format: "%.1f", minutes)) min")
}
```

## Customization Recipes

### Recipe 1: Override with Tested Max HR

```swift
var profile = await healthKitManager.getOrCreateZoneProfile(for: .cycling)
profile.maxHR = 192  // From maximal VO2 test
profile.lastUpdated = Date()  // Mark as fresh
healthKitManager.saveZoneProfile(profile)
```

### Recipe 2: Force Schema Change

```swift
var profile = await healthKitManager.getOrCreateZoneProfile(for: .running)
profile.schema = .polarized  // Force 3-zone model
profile.zones = healthKitManager.generatePolarizedZones(
    lthr: profile.lactateThresholdHR ?? 170
)
healthKitManager.saveZoneProfile(profile)
```

### Recipe 3: Adapt for Fatigue

```swift
var profile = await healthKitManager.getOrCreateZoneProfile(for: .cycling)

// If HRV is low or sleep was poor:
let adjustmentFactor = 0.93  // 7% lower zones
healthKitManager.adaptZoneProfile(&profile, adjustmentFactor: adjustmentFactor)

// Zones temporarily lowered based on readiness
```

### Recipe 4: Create Sport-Specific Bundle

```swift
// Multi-sport athlete customization
let runningProfile = await healthKitManager.createHRZoneProfile(
    for: .running,
    schema: .karvonen
)

let cyclingProfile = await healthKitManager.createHRZoneProfile(
    for: .cycling,
    schema: .lactatThreshold,
    customLTHR: 178
)

let swimmingProfile = await healthKitManager.createHRZoneProfile(
    for: .swimming,
    schema: .mhrPercentage
)

// Each sport maintains independent settings
healthKitManager.saveZoneProfile(runningProfile)
healthKitManager.saveZoneProfile(cyclingProfile)
healthKitManager.saveZoneProfile(swimmingProfile)
```

## Schema Comparison Quick Reference

```
┌─────────────────┬──────────────────┬─────────────────┬──────────────────┐
│ Schema          │ Formula          │ Complexity      │ Best For         │
├─────────────────┼──────────────────┼─────────────────┼──────────────────┤
│ MHR %           │ % of max HR      │ ★☆☆             │ Casual, swimming │
│ Karvonen (HRR)  │ %HRR + RHR       │ ★★☆             │ Runners, cyclists│
│ LTHR            │ % of threshold   │ ★★★             │ Competitive      │
│ Polarized       │ 3-zone easy/mod  │ ★★☆             │ Endurance        │
└─────────────────┴──────────────────┴─────────────────┴──────────────────┘
```

## Debugging

### Check What Schema Was Selected

```swift
let profile = await healthKitManager.getOrCreateZoneProfile(for: .running)
print("Selected: \(profile.schema.rawValue)")
// Output: "karvonen_hrr" ✓
```

### View All Zone Boundaries

```swift
profile.zones.forEach { zone in
    let lower = Int(zone.range.lowerBound)
    let upper = Int(zone.range.upperBound)
    print("\(zone.name): \(lower)-\(upper) | Color: \(zone.color)")
}

// Output:
// Zone 1: Easy: 120-144 | Color: 0099FF
// Zone 2: Base: 144-163 | Color: 00CC00
// Zone 3: Tempo: 163-181 | Color: FFCC00
// Zone 4: Threshold: 181-199 | Color: FF6600
// Zone 5: Max: 199-199+ | Color: FF0000
```

### Verify Time-in-Zone Calculation

```swift
let total = analytics.hrZoneBreakdown.reduce(0) { $0 +  $1.1 }
let workoutDuration = workout.duration

print("Total time in zones: \(Int(total))s")
print("Workout duration: \(Int(workoutDuration))s")
print("Coverage: \(String(format: "%.1f", total / workoutDuration * 100))%")
```

## API Cheat Sheet

```swift
// Fetch metrics
let metrics = await healthKitManager.fetchAnchorMetrics()
let lthr = await healthKitManager.inferLactateThresholdHR()
let peakHR = await healthKitManager.fetchPeakHRLast90Days()

// Calculate
let mhr = healthKitManager.estimateMaxHRTanaka(age: 32)     // 185.6
let hrr = healthKitManager.calculateHeartRateReserve(maxHR: 190, restingHR: 50)

// Generate
let zones1 = healthKitManager.generateMHRPercentageZones(maxHR: 190)
let zones2 = healthKitManager.generateKarvonenZones(maxHR: 190, restingHR: 50)
let zones3 = healthKitManager.generateLTHRZones(lthr: 175)
let zones4 = healthKitManager.generatePolarizedZones(lthr: 175)

// Profiling
let profile = await healthKitManager.getOrCreateZoneProfile(for: .running)
let breakdown = healthKitManager.calculateZoneBreakdown(hrs, zoneProfile: profile)

// Persistence
healthKitManager.saveZoneProfile(profile)
let cached = healthKitManager.loadZoneProfile(for: .cycling)

// Adaptation
healthKitManager.adaptZoneProfile(&profile, adjustmentFactor: 0.95)
```

## Common Patterns

### Pattern 1: Workflow for New Workout

```swift
func processNewWorkout(_ workout: HKWorkout) async {
    // 1. Compute analytics (zones included)
    let analytics = await healthKitManager.computeWorkoutAnalytics(for: workout)
    
    // 2. Extract zone data
    let profile = analytics.hrZoneProfile!
    let breakdown = analytics.hrZoneBreakdown
    
    // 3. Display or store
    updateUI(with: profile, breakdown: breakdown)
}
```

### Pattern 2: Update Zones When Metrics Change

```swift
func handleNewMaxHRTest(_ testMaxHR: Double) {
    // Force regenerate profile with new anchor
    Task {
        let profile = await healthKitManager.createHRZoneProfile(
            for: .cycling,
            customMaxHR: testMaxHR
        )
        healthKitManager.saveZoneProfile(profile)
        await MainActor.run {
            analytics.hrZoneProfile = profile
        }
    }
}
```

### Pattern 3: Compare Schemas

```swift
func compareSchemas() async {
    let sport: HKWorkoutActivityType = .running
    
    let mhrProfile = await healthKitManager.createHRZoneProfile(
        for: sport,
        schema: .mhrPercentage
    )
    
    let karvonenProfile = await healthKitManager.createHRZoneProfile(
        for: sport,
        schema: .karvonen
    )
    
    print("MHR Zone 2 ceiling: \(mhrProfile.zones[1].range.upperBound)")
    print("Karvonen Zone 2 ceiling: \(karvonenProfile.zones[1].range.upperBound)")
}
```

## Performance Tips

1. **Cache is your friend**: Profiles cached for 7 days per sport - use `getOrCreateZoneProfile` (not `createHRZoneProfile` every time)

2. **Batch zone calculations**: Process multiple hrSamples in one `calculateZoneBreakdown` call

3. **Check `hrZoneBreakdown` first**: Before calculating manually - it's already computed in `WorkoutAnalytics`

4. **Save after customization**: Call `saveZoneProfile` after any manual changes

## Next Steps

1. **Review** `HR_ZONE_SYSTEM.md` for complete documentation
2. **Test** with a recent workout: zones should appear in WorkoutDetailView
3. **Customize** per-sport profiles in settings (TODO: future UI)
4. **Integrate** CloudKit sync for multi-device support (TODO: future)

---

## Troubleshooting

**Q: Zones seem flat/limited?**
A: Likely cause - insufficient HealthKit HR samples. Ensure workout has continuous HR recording.

**Q: Max HR seems too high/low?**
A: Check Tanaka formula: `208 - 0.7 × age`. Override with `customMaxHR` in profile creation.

**Q: How do I see current schema?**
A: `profile.schema.rawValue` → e.g., "karvonen_hrr"

**Q: When do profiles update?**
A: Automatic: Every 7 days or when `forceRefresh: true` passed

---

Built with ❤️ for endurance athletes
