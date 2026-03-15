# Dynamic Heart Rate Zone System

## Overview

Nutrivance now features a sophisticated, adaptive heart rate zone system that personalizes zone calculations based on user physiology and training context. The system offers multiple zone schemas, sport-specific profiles, and dynamic adaptation capabilities.

## Architecture

### Core Components

#### 1. **Zone Schemas**
The system supports four distinct HR zone calculation methods:

- **Maximum Heart Rate Percentage (MHR%)**
  - Simplest model using percentage of max HR
  - `50-60-70-80-90-100%` of MHR
  - Best for: Casual users, general fitness, group classes
  - No resting HR requirement

- **Karvonen / Heart Rate Reserve (HRR)**
  - Uses resting HR for personalization
  - Formula: `Target HR = (HRR × intensity) + RHR`
  - More accurate for individuals with varied resting HR
  - Best for: Runners, cyclists doing structured training

- **Lactate Threshold (LTHR)**
  - Based on user's sustainable threshold HR
  - Zones: 85-89%, 90-94%, 95-99%, 100%+ of LTHR
  - Most sport-specific and accurate
  - Best for: Competitive athletes, threshold-based training

- **Polarized 3-Zone**
  - Simpler 3-zone model: Easy, Moderate, Hard
  - Based on LT1 and LT2 thresholds
  - Best for: Endurance athletes, 80/20 training philosophy

### 2. **Anchor Metrics**

The system collects key physiological data to personalize calculations:

```swift
struct HRZoneAnchorMetrics {
    var age: Double?                    // From HealthKit dateOfBirth
    var restingHR: Double?              // Latest sample
    var maxHR: Double?                  // Tested or measured
    var peakHRLast90Days: Double?       // From recent workouts
    var lactateThresholdHR: Double?     // Inferred from patterns
    var vo2Max: Double?                 // From HealthKit
    var hrvTrendDays7: Double?          // 7-day HRV trend
    var sleepQualityWeekly: Double?     // 1-5 scale
    var recoveryScore: Double?          // 0-100
}
```

### 3. **Zone Profile**

Each sport has its own zone profile containing:
- Selected schema (auto-detected or user-chosen)
- Max HR, resting HR, lactate threshold estimates
- Generated zone boundaries
- Adaptive multiplier for readiness adjustments
- Cache timestamp for refresh logic (7-day validity)

```swift
struct HRZoneProfile: Codable {
    var sport: HKWorkoutActivityType.RawValue
    var schema: HRZoneSchema                    // Calculation method
    var maxHR: Double?
    var restingHR: Double?
    var lactateThresholdHR: Double?
    var zones: [HeartRateZone]                  // 3-5 zones
    var lastUpdated: Date
    var adaptive: Bool = true
    var adjustmentFactor: Double = 1.0          // For HRV adaptation
}
```

## Usage

### Automatic Zone Detection (Default)

When a workout is analyzed, the system automatically:

1. **Detects the sport** from `workout.workoutActivityType`
2. **Selects the optimal schema:**
   - Running/Hiking/Walking → **Karvonen (HRR)**
   - Cycling/Rowing → **Lactate Threshold**
   - Swimming → **MHR Percentage**
   - Other → **MHR Percentage**
3. **Fetches anchor metrics** from HealthKit
4. **Generates zones** using the selected formula
5. **Caches the profile** for 7 days (per sport)
6. **Calculates time in each zone** during workout

### Viewing Zone Information

In the WorkoutDetailView, users see:

- **HR Zone Profile Card** showing:
  - Active schema (e.g., "Karvonen HRR")
  - Estimated Max HR
  - Resting HR
  - Explanation of methodology

- **Zone Breakdown** section showing:
  - Time spent in each zone (color-coded)
  - Zone names with HR ranges
  - Interactive zone thresholds on HR chart

### Example: Running Workout

```
Workout: 5K run
Sport: Running
Selected Schema: Karvonen (HRR)
Metrics:
  Age: 32
  Max HR: 188 bpm (from Tanaka: 208 - 0.7×32)
  Resting HR: 52 bpm
  HRR: 136 bpm

Zones Generated:
  Zone 1: 118-144 bpm (50-60% HRR + RHR) → Easy
  Zone 2: 144-163 bpm (60-70% HRR + RHR) → Base
  Zone 3: 163-181 bpm (70-80% HRR + RHR) → Tempo
  Zone 4: 181-199 bpm (80-90% HRR + RHR) → Threshold
  Zone 5: 199+ bpm (90%+ HRR + RHR) → Max

Time in Zones:
  Zone 1: 5 min 23 sec
  Zone 2: 18 min 42 sec
  Zone 3: 8 min 14 sec
  Zone 4: 2 min 09 sec
  Zone 5: 0 sec
```

## Data Calculation Methods

### Maximum Heart Rate Estimation

**Tanaka Formula (primary):**
```
MHR = 208 - 0.7 × age
```

**Refinement Logic:**
1. Start with Tanaka estimate
2. Monitor peak HR from workouts (90 days)
3. If measured peak > Tanaka × 1.05, use peak × 1.05 as new max
4. User can override with tested max

### Heart Rate Reserve (Karvonen)

```
HRR = MaxHR - RestingHR

Zone n = (HRR × intensity_percentage) + RestingHR
```

**Advantages:**
- Accounts for individual resting HR variation
- More personalized than % of max
- More conservative for unfit individuals

### Lactate Threshold Detection

The system infers LTHR by:
1. Analyzing all workouts in last 30 days
2. Identifying high-intensity efforts (≥80% estimated MaxHR)
3. Taking 95th percentile of HRs in those efforts
4. Using this as estimated LTHR

**Fallback:** LTHR = MaxHR × 0.88 if insufficient data

### Zone Time Calculation

For each HR sample in the workout:
1. Get sample HR and timestamp
2. Calculate time until next sample
3. Find which zone contains this HR
4. Add time duration to that zone's total
5. Repeat for entire workout data

## Adaptive Zone Adjustment

### How Adaptation Works

Zones can be dynamically adjusted using an `adjustmentFactor`:

```swift
func adaptZoneProfile(_ profile: inout HRZoneProfile, adjustmentFactor: Double) {
    profile.adjustmentFactor = adjustmentFactor
    profile.zones = profile.zones.map { zone in
        let adjustedLower = zone.range.lowerBound * adjustmentFactor
        let adjustedUpper = zone.range.upperBound * adjustmentFactor
        // Return adjusted zone
    }
}
```

### Adaptation Triggers (Future Enhancement)

```
- HRV Suppressed (-1 sigma)        → adjustmentFactor = 0.95 (lower zones)
- Sleep Quality Low                → adjustmentFactor = 0.93
- Elevated Resting HR (+5 bpm)    → adjustmentFactor = 0.97
- Recovery Score Low (<50)         → adjustmentFactor = 0.90
- High Training Load              → adjustmentFactor = 0.92
```

**Result:** On stressful days, the system temporarily lowers zone thresholds to reflect reduced capacity.

## Persistence & Sync

### Local Storage
Zone profiles are cached in `UserDefaults`:
```
Key: "hr_zone_profile_\(sport.rawValue)"
Format: Codable JSON
Validity: 7 days
```

### CloudKit Sync (Framework Ready)
The system is designed to sync to iCloud via CloudKit:
- Updates propagate across all user devices
- Manual zone customizations persist
- Schema preferences remembered per sport

**Implementation:** Can be enabled in settings to sync `HRZoneProfile` records to a CloudKit container.

## Customization

### User Overrides

Users can customize zones in settings (future UI):

```swift
// Manual max HR override
profile.maxHR = 195  // Tested value

// Manual theme HR override  
profile.lactateThresholdHR = 175  // From threshold test

// Change schema
profile.schema = .polarized  // Override auto-selection

// Disable adaptive adjustment
profile.adaptive = false

// Save changes
saveZoneProfile(profile)
```

### Per-Sport Customization

Each sport maintains independent settings:
- Running: Karvonen (can switch to LTHR)
- Cycling: LTHR (can switch to MHR%)
- Swimming: MHR% (can switch to Karvonen)
- etc.

## API Reference

### Primary Methods

#### Fetch Anchor Metrics
```swift
let metrics = await healthKitManager.fetchAnchorMetrics()
// Returns: HRZoneAnchorMetrics with all physiological data
```

#### Get or Create Zone Profile
```swift
let profile = await healthKitManager.getOrCreateZoneProfile(
    for: .running,
    forceRefresh: false
)
// Auto-selects schema, generates zones, caches for 7 days
```

#### Create Custom Profile
```swift
let profile = await healthKitManager.createHRZoneProfile(
    for: .cycling,
    schema: .lactatThreshold,
    customMaxHR: 195,
    customRestingHR: 48,
    customLTHR: 175
)
```

#### Calculate Zone Breakdown
```swift
let breakdown = healthKitManager.calculateZoneBreakdown(
    heartRates: [(Date, Double)],
    zoneProfile: profile
)
// Returns: [(zone: HeartRateZone, timeInZone: TimeInterval)]
```

#### Apply Adaptive Adjustment
```swift
var profile = /* existing profile */
healthKitManager.adaptZoneProfile(&profile, adjustmentFactor: 0.95)
// Lowers all zone thresholds by 5%
```

## Display Integration

### WorkoutDetailView Shows:

1. **Zone Profile Card**
   - Active schema name
   - Estimated max HR
   - Resting HR
   - Methodology explanation

2. **Zone Time Breakdown**
   - Color-coded zone names
   - Time in each zone
   - Percentage bar charts
   - Zone HR ranges

3. **HR Chart with Zones**
   - Zone boundary lines (dashed)
   - HR samples color-coded by zone
   - Interactive point selection
   - Zone legend with time totals

## Performance Considerations

- **Caching:** Zone profiles cached for 7 days per sport (minimal HealthKit queries)
- **Lazy Loading:** Profiles generated on-demand, not precomputed
- **Efficient Calculations:** O(n) zone breakdown using linear scan
- **Memory:** One profile stored per sport, minimal overhead

## Accuracy & Limitations

### High Accuracy For:
- Trained athletes with multiple workouts (LTHR inference)
- Users who enter tested max HR
- Consistent resting HR measurements

### Lower Accuracy For:
- Single workout (insufficient LTHR inference data)
- New users (Tanaka estimate only)
- Sports without HealthKit HR support
- Users who don't grant HealthKit access

### Fallback Strategy:
- Max HR: Tanaka → Measured Peak + 5% → 190 bpm default
- Resting HR: Latest HealthKit → 60 bpm default
- LTHR: 30-day inference → MaxHR × 0.88 default

## Future Enhancements

1. **Sport-Specific HR Response Models**
   - Running HR 5% higher than cycling at same effort
   - Swimming HR suppressed 10-15% due to hydrostatic pressure

2. **Multi-Modal Training**
   - Cross-sport threshold zone sharing (e.g., triathlon)
   - Modality-adjusted zones

3. **AI-Powered Readiness**
   - HRV + Sleep + Recovery + Training Load → adjustmentFactor
   - Automatic threshold detection from power/pace data

4. **User Preferences UI**
   - Settings screen for zone customization
   - Manual threshold entry workflow
   - Schema selection per sport

5. **Historical Analysis**
   - Zone drift over season
   - Fitness improvements (max HR changes)
   - Recovery trends

---

## Quick Reference

| Sport | Auto Schema | Best For |
|-------|-----------|----------|
| Running | Karvonen | Threshold-based training |
| Cycling | LTHR | Power + HR analysis |
| Walking | Karvonen | General fitness |
| Hiking | Karvonen | Elevation-aware training |
| Swimming | MHR% | Data-sparse training |
| Generic | MHR% | Casual workouts |

---

## Questions?

Refer to HealthKitManager zone extension or contact the development team for advanced customization.
