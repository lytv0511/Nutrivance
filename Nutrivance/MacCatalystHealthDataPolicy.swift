import Foundation

/// Mac Catalyst has no HealthKit reads; the app relies on **cached metrics** (local + iCloud KVS / sync) from the iPhone build.
enum MacCatalystHealthDataPolicy {
    static var isActive: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return false
        #endif
    }

    /// Matches the practical window for data the phone can sync; keeps pickers aligned with what cache can contain.
    static var minimumAllowedDate: Date {
        let calendar = Calendar.current
        let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        return calendar.startOfDay(for: oneMonthAgo)
    }

    static let historyNotice = "On Mac, HealthKit isn’t available. Open Sleep on iPhone/iPad after waking so it can upload sleep segments, per-stage HR/RR, heart-rate dip, bedtime consistency, and overnight vitals to iCloud (CloudKit); then refresh here."

    static let stressHistoryNotice = "On Mac, HealthKit isn’t available. Stress uses HRV samples synced from your iPhone (iCloud / app sync). Pull to refresh after your phone updates."
}
