import Foundation

enum MacCatalystHealthDataPolicy {
    static var isActive: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return false
        #endif
    }

    static var minimumAllowedDate: Date {
        let calendar = Calendar.current
        let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        return calendar.startOfDay(for: oneMonthAgo)
    }

    static let historyNotice = "Mac health data is only available up to 1 month."
}
