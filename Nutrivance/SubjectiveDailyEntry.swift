import Foundation

/// Optional daily subjective data: soreness, stress, sleep quality ratings.
/// Persisted to UserDefaults/Realm, used to augment pro-athlete recovery calculation.
struct SubjectiveDailyEntry: Codable, Identifiable {
    let id: UUID
    let date: Date  // Normalized to start of day
    var sorenessRating: Int?  // 1-10
    var stressRating: Int?  // 1-10
    var sleepQualityRating: Int?  // 1-10 (independent of duration)
    var notes: String?
    let createdAt: Date
    var updatedAt: Date
    
    init(
        date: Date,
        sorenessRating: Int? = nil,
        stressRating: Int? = nil,
        sleepQualityRating: Int? = nil,
        notes: String? = nil
    ) {
        self.id = UUID()
        self.date = Calendar.current.startOfDay(for: date)
        self.sorenessRating = sorenessRating
        self.stressRating = stressRating
        self.sleepQualityRating = sleepQualityRating
        self.notes = notes
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Persistence Manager

@MainActor
final class SubjectiveDailyEntryManager {
    static let shared = SubjectiveDailyEntryManager()
    
    private static let storageKey = "SubjectiveDailyEntries"
    private var entries: [SubjectiveDailyEntry] = []
    
    private init() {
        loadFromDisk()
    }
    
    // MARK: - CRUD Operations
    
    func getEntry(for date: Date) -> SubjectiveDailyEntry? {
        let normalizedDate = Calendar.current.startOfDay(for: date)
        return entries.first { Calendar.current.isDate($0.date, inSameDayAs: normalizedDate) }
    }
    
    func saveEntry(_ entry: SubjectiveDailyEntry) {
        let normalizedDate = Calendar.current.startOfDay(for: entry.date)
        
        if let index = entries.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: normalizedDate) }) {
            var updated = entries[index]
            updated.sorenessRating = entry.sorenessRating
            updated.stressRating = entry.stressRating
            updated.sleepQualityRating = entry.sleepQualityRating
            updated.notes = entry.notes
            updated.updatedAt = Date()
            entries[index] = updated
        } else {
            var newEntry = entry
            newEntry.updatedAt = Date()
            entries.append(newEntry)
        }
        
        entries.sort { $0.date > $1.date }
        saveToDisk()
    }
    
    func deleteEntry(for date: Date) {
        let normalizedDate = Calendar.current.startOfDay(for: date)
        entries.removeAll { Calendar.current.isDate($0.date, inSameDayAs: normalizedDate) }
        saveToDisk()
    }
    
    func getEntries(from startDate: Date, to endDate: Date) -> [SubjectiveDailyEntry] {
        let normalizedStart = Calendar.current.startOfDay(for: startDate)
        let normalizedEnd = Calendar.current.startOfDay(for: endDate)
        
        return entries.filter { entry in
            entry.date >= normalizedStart && entry.date <= normalizedEnd
        }.sorted { $0.date > $1.date }
    }
    
    func getAllEntries() -> [SubjectiveDailyEntry] {
        entries.sorted { $0.date > $1.date }
    }
    
    func clearOldEntries(olderThan days: Int = 90) {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        entries.removeAll { $0.date < cutoffDate }
        saveToDisk()
    }
    
    // MARK: - Persistence
    
    private func saveToDisk() {
        if let encoded = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(encoded, forKey: Self.storageKey)
        }
    }
    
    private func loadFromDisk() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([SubjectiveDailyEntry].self, from: data) {
            self.entries = decoded.sorted { $0.date > $1.date }
        }
    }
    
    // MARK: - Analysis Helpers
    
    /// Average soreness over date range (1-10 scale)
    func averageSoreness(from startDate: Date, to endDate: Date) -> Double? {
        let entries = getEntries(from: startDate, to: endDate)
        let soreness = entries.compactMap { $0.sorenessRating }.map { Double($0) }
        guard !soreness.isEmpty else { return nil }
        return soreness.reduce(0, +) / Double(soreness.count)
    }
    
    /// Average stress over date range (1-10 scale)
    func averageStress(from startDate: Date, to endDate: Date) -> Double? {
        let entries = getEntries(from: startDate, to: endDate)
        let stress = entries.compactMap { $0.stressRating }.map { Double($0) }
        guard !stress.isEmpty else { return nil }
        return stress.reduce(0, +) / Double(stress.count)
    }
    
    /// Average subjective sleep quality over date range (1-10 scale)
    func averageSleepQuality(from startDate: Date, to endDate: Date) -> Double? {
        let entries = getEntries(from: startDate, to: endDate)
        let quality = entries.compactMap { $0.sleepQualityRating }.map { Double($0) }
        guard !quality.isEmpty else { return nil }
        return quality.reduce(0, +) / Double(quality.count)
    }
    
    /// Compute subjective recovery boost (-5 to +5 points) based on stress and soreness
    /// High stress and soreness reduce the boost; low values increase it
    func subjectiveRecoveryBoost() -> Double? {
        guard let lastEntry = getEntry(for: Date()) else { return nil }
        
        var boost = 0.0
        
        // Stress: 1-3 = +3, 4-7 = 0, 8-10 = -3
        if let stress = lastEntry.stressRating {
            if stress <= 3 {
                boost += 3.0
            } else if stress >= 8 {
                boost -= 3.0
            }
        }
        
        // Soreness: 1-3 = +2, 4-7 = 0, 8-10 = -2
        if let soreness = lastEntry.sorenessRating {
            if soreness <= 3 {
                boost += 2.0
            } else if soreness >= 8 {
                boost -= 2.0
            }
        }
        
        return max(-5, min(5, boost))
    }
}
