import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(JournalingSuggestions) && !targetEnvironment(macCatalyst)
import JournalingSuggestions
#endif
import HealthKit
import CoreLocation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct JournalStatCard: Identifiable, Codable, Hashable, Equatable {
    let id: UUID
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    let size: CardSize
    let accentHue: Double

    enum CardSize: String, Codable, Hashable {
        case small, medium, large
    }

    init(icon: String, title: String, value: String, subtitle: String = "", size: CardSize = .medium, accentHue: Double = 30) {
        self.id = UUID()
        self.icon = icon
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.size = size
        self.accentHue = accentHue
    }
}

struct JournalEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var content: String
    var inspiration: String
    var date: Date
    var imageData: [Data] = []
    var kind: String
    var reportMetrics: [WorkoutReportMetric]
    var statCards: [JournalStatCard]
    /// Lowercased person name → role label (e.g. friend, teacher) from “Who is this?” picks.
    var personRelationshipHints: [String: String] = [:]
    /// User overrides for detected correlation life-areas (correlation UUID → NutrivanceAssociation rawValue).
    var correlationAssociationOverrides: [UUID: String] = [:]
    /// Stable keys for follow-up MC clarifiers → selected choice index.
    var journalClarifierAnswers: [String: Int] = [:]
    /// Nudges the user saved as used inspiration.
    var savedNudges: [JournalSavedNudge] = []
    
    init(title: String = "", content: String = "") {
        self.id = UUID()
        self.title = title
        self.content = content
        self.inspiration = ""
        self.date = Date()
        self.imageData = []
        self.kind = "standard"
        self.reportMetrics = []
        self.statCards = []
    }
    
    enum CodingKeys: String, CodingKey {
        case id, title, content, inspiration, date, imageData, kind, reportMetrics, statCards
        case personRelationshipHints, correlationAssociationOverrides, journalClarifierAnswers, savedNudges
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        inspiration = try container.decodeIfPresent(String.self, forKey: .inspiration) ?? ""
        date = try container.decode(Date.self, forKey: .date)
        imageData = try container.decodeIfPresent([Data].self, forKey: .imageData) ?? []
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "standard"
        reportMetrics = try container.decodeIfPresent([WorkoutReportMetric].self, forKey: .reportMetrics) ?? []
        statCards = try container.decodeIfPresent([JournalStatCard].self, forKey: .statCards) ?? []
        personRelationshipHints = try container.decodeIfPresent([String: String].self, forKey: .personRelationshipHints) ?? [:]
        correlationAssociationOverrides = try container.decodeIfPresent([UUID: String].self, forKey: .correlationAssociationOverrides) ?? [:]
        journalClarifierAnswers = try container.decodeIfPresent([String: Int].self, forKey: .journalClarifierAnswers) ?? [:]
        savedNudges = try container.decodeIfPresent([JournalSavedNudge].self, forKey: .savedNudges) ?? []
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(content, forKey: .content)
        try container.encode(inspiration, forKey: .inspiration)
        try container.encode(date, forKey: .date)
        try container.encode(imageData, forKey: .imageData)
        try container.encode(kind, forKey: .kind)
        try container.encode(reportMetrics, forKey: .reportMetrics)
        try container.encode(statCards, forKey: .statCards)
        try container.encode(personRelationshipHints, forKey: .personRelationshipHints)
        try container.encode(correlationAssociationOverrides, forKey: .correlationAssociationOverrides)
        try container.encode(journalClarifierAnswers, forKey: .journalClarifierAnswers)
        try container.encode(savedNudges, forKey: .savedNudges)
    }
}

private func isFitnessReportEntry(_ entry: JournalEntry) -> Bool {
    entry.kind == "workout_report" || !entry.reportMetrics.isEmpty || !entry.statCards.isEmpty
}

/// Strips HealthKit debug dumps and non-user icon tokens from journal text for display and persistence.
enum JournalDisplaySanitizer {
    static func endUserText(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        let kept = lines.filter { !shouldStripLine($0) }
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func metricSFSymbolName(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty { return "chart.bar.fill" }
        if t.range(of: #"^[0-9a-f]{6,}$"#, options: .regularExpression) != nil { return "figure.run" }
        if t.contains("rawvalue") || t.contains("hkworkout") { return "figure.run" }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.")
        guard t.unicodeScalars.allSatisfy({ allowed.contains($0) }), t.contains(where: { $0.isLetter }) else {
            return "chart.bar.fill"
        }
        return t
    }

    private static func shouldStripLine(_ line: String) -> Bool {
        let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return false }
        let lower = s.lowercased()
        if lower.contains("hkworkoutactivitytype(rawvalue:") { return true }
        if lower.hasPrefix("activitytype:"), lower.contains("hkworkout") { return true }
        if lower.hasPrefix("icon:") {
            let afterColon = s.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard afterColon.count > 1 else { return false }
            let rest = String(afterColon[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            if rest.range(of: #"^[0-9A-Fa-f\-]+$"#, options: .regularExpression) != nil, rest.count >= 6 {
                return true
            }
        }
        return false
    }
}

enum JournalPersistence {
    static let cloudStorageKey = "journal_entries_cache_v1"

    static var journalFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("journal_entries.json")
    }

    static func loadEntries() -> [JournalEntry] {
        let localEntries = loadLocalEntries()
        let cloudEntries = loadCloudEntries()
        let merged = merge(localEntries: localEntries, cloudEntries: cloudEntries)

        if merged != localEntries {
            persistLocalEntries(merged)
        }
        if merged != cloudEntries {
            persistCloudEntries(merged)
        }

        return merged
    }

    static func persistEntries(_ entries: [JournalEntry]) {
        let normalized = deduplicate(entries)
        persistLocalEntries(normalized)
        persistCloudEntries(normalized)
    }

    private static func loadLocalEntries() -> [JournalEntry] {
        do {
            let data = try Data(contentsOf: journalFileURL)
            return try JSONDecoder().decode([JournalEntry].self, from: data)
        } catch {
            return []
        }
    }

    private static func loadCloudEntries() -> [JournalEntry] {
        let cloudStore = NSUbiquitousKeyValueStore.default
        guard let data = cloudStore.data(forKey: cloudStorageKey),
              let entries = try? JSONDecoder().decode([JournalEntry].self, from: data) else {
            return []
        }
        return entries
    }

    private static func persistLocalEntries(_ entries: [JournalEntry]) {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: journalFileURL, options: [.atomic])
        } catch {
            print("Failed to save journal entries locally:", error)
        }
    }

    private static func persistCloudEntries(_ entries: [JournalEntry]) {
        do {
            let data = try JSONEncoder().encode(entries)
            let cloudStore = NSUbiquitousKeyValueStore.default
            cloudStore.set(data, forKey: cloudStorageKey)
        } catch {
            print("Failed to save journal entries to iCloud:", error)
        }
    }

    private static func merge(localEntries: [JournalEntry], cloudEntries: [JournalEntry]) -> [JournalEntry] {
        var mergedByID: [UUID: JournalEntry] = [:]

        for entry in localEntries {
            mergedByID[entry.id] = entry
        }

        for entry in cloudEntries {
            if let existing = mergedByID[entry.id] {
                mergedByID[entry.id] = preferredEntry(existing, entry)
            } else {
                mergedByID[entry.id] = entry
            }
        }

        return mergedByID.values.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.id.uuidString > rhs.id.uuidString
            }
            return lhs.date > rhs.date
        }
    }

    private static func deduplicate(_ entries: [JournalEntry]) -> [JournalEntry] {
        merge(localEntries: entries, cloudEntries: [])
    }

    private static func preferredEntry(_ lhs: JournalEntry, _ rhs: JournalEntry) -> JournalEntry {
        if rhs.date != lhs.date {
            return rhs.date > lhs.date ? rhs : lhs
        }
        let lhsSignal = lhs.content.count + lhs.inspiration.count + lhs.imageData.count * 100 + lhs.reportMetrics.count * 10 + lhs.statCards.count * 15
        let rhsSignal = rhs.content.count + rhs.inspiration.count + rhs.imageData.count * 100 + rhs.reportMetrics.count * 10 + rhs.statCards.count * 15
        return rhsSignal >= lhsSignal ? rhs : lhs
    }

    static func appendWorkoutReport(title: String, content: String, date: Date = Date()) {
        var entries = loadEntries()
        let cleaned = JournalDisplaySanitizer.endUserText(content)
        var entry = JournalEntry(title: title, content: cleaned)
        entry.date = date
        entry.kind = "workout_report"
        entry.reportMetrics = WorkoutReportNLPParser.parseMetrics(from: cleaned)
        entries.insert(entry, at: 0)
        persistEntries(entries)
    }
}

private struct WorkoutReportMetricsWall: View {
    let metrics: [WorkoutReportMetric]

    var body: some View {
        if !metrics.isEmpty {
            let columns = [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ]

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(metrics) { metric in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            Image(systemName: JournalDisplaySanitizer.metricSFSymbolName(metric.icon))
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.orange)
                                .frame(width: 46, height: 46)
                                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            Spacer()
                        }

                        Text(metric.value)
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(.primary)

                        Text(metric.title.uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.orange.opacity(0.14), lineWidth: 1)
                    )
                }
            }
        }
    }
}

private struct SuggestionImport {
    let text: String
    let imageData: [Data]
}

private struct InspirationCardContent: Identifiable {
    let id = UUID()
    let title: String
    let lines: [String]
}

private func inspirationCards(from inspiration: String) -> [InspirationCardContent] {
    JournalDisplaySanitizer.endUserText(inspiration)
        .components(separatedBy: "\n\n")
        .compactMap { block in
            let lines = block
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            
            guard let title = lines.first else { return nil }
            return InspirationCardContent(title: title, lines: Array(lines.dropFirst()))
        }
}

private struct InspirationImageStrip: View {
    let imageData: [Data]
    var thumbnailSize: CGFloat = 100
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(imageData.enumerated()), id: \.offset) { _, data in
                    if let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: thumbnailSize, height: thumbnailSize)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    }
                }
            }
        }
    }
}

private struct InspirationCardView: View {
    let card: InspirationCardContent

    private var accent: Color {
        switch card.title.lowercased() {
        case "workout", "workout group":
            return .orange
        case "motion activity":
            return .cyan
        case "location", "location group":
            return .blue
        case "state of mind", "reflection":
            return .pink
        case "podcast", "song", "media":
            return .indigo
        case "photo", "live photo", "video", "event":
            return .teal
        case "contact":
            return .mint
        default:
            return .secondary
        }
    }
    
    private var accentIcon: String {
        switch card.title.lowercased() {
        case "workout", "workout group":
            return "figure.run"
        case "motion activity":
            return "figure.walk"
        case "location", "location group":
            return "location.fill"
        case "state of mind", "reflection":
            return "brain.head.profile"
        case "podcast":
            return "waveform"
        case "song":
            return "music.note"
        case "media":
            return "play.rectangle.fill"
        case "photo":
            return "photo.fill"
        case "live photo":
            return "livephoto"
        case "video":
            return "video.fill"
        case "event":
            return "calendar"
        case "contact":
            return "person.fill"
        default:
            return "sparkles"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: accentIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                
                Text(card.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
                    .textCase(.uppercase)
                
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(card.lines, id: \.self) { line in
                    if line.hasSuffix(":") {
                        Text(line.dropLast())
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                    } else if let separatorIndex = line.firstIndex(of: ":") {
                        let label = String(line[..<separatorIndex])
                        let valueStart = line.index(after: separatorIndex)
                        let value = String(line[valueStart...]).trimmingCharacters(in: .whitespaces)
                        
                        HStack(alignment: .top, spacing: 8) {
                            Text(label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 90, alignment: .leading)
                            
                            Text(value)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Text(line)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [accent.opacity(0.35), accent.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

private struct InspirationSectionView: View {
    let inspiration: String
    let imageData: [Data]
    var compact: Bool = false
    
    private var cards: [InspirationCardContent] {
        inspirationCards(from: inspiration)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !imageData.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(Array(imageData.enumerated()), id: \.offset) { _, data in
                            if let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: compact ? 168 : 208, height: compact ? 124 : 164)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                                    )
                            }
                        }
                    }
                }
                .frame(height: compact ? 132 : 172)
            }
            
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(cards) { card in
                    InspirationCardView(card: card)
                }
            }
        }
    }
}

/// Mesh hue phase from wall-clock time — avoids `withAnimation(.repeatForever)` so toolbar and
/// text fields are not continuously re-animated with the background.
private struct JournalMeshPhaseBackground: View {
    enum Style {
        case spirit
        case burning
    }

    let style: Style

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let phase = Self.phase(for: context.date)
            Group {
                switch style {
                case .spirit:
                    GradientBackgrounds().spiritGradient(animationPhase: .constant(phase))
                case .burning:
                    ZStack {
                        GradientBackgrounds().burningGradient(animationPhase: .constant(phase))
                        Color.black.opacity(0.22)
                    }
                }
            }
        }
    }

    private static func phase(for date: Date) -> Double {
        let elapsed = date.timeIntervalSinceReferenceDate
        let period = 8.0
        let s = sin((elapsed / period) * (2 * Double.pi))
        return (s + 1) * 0.5 * 20.0
    }
}

struct JournalView: View {
    @State private var entries: [JournalEntry] = []
    @State private var showingEditor = false
    @State private var currentEntry = JournalEntry()
    @State private var filter: JournalFeedFilter = .all
    @State private var searchText = ""

    private var filteredEntries: [JournalEntry] {
        entries
            .filter { filter.matches($0) }
            .filter { matchesSearch($0) }
            .sorted { lhs, rhs in
                if lhs.date == rhs.date {
                    return lhs.id.uuidString > rhs.id.uuidString
                }
                return lhs.date > rhs.date
            }
    }

    private var groupedEntries: [JournalTimelineGroup] {
        let grouped = Dictionary(grouping: filteredEntries) { entry in
            Calendar.current.startOfDay(for: entry.date)
        }

        return grouped.keys.sorted(by: >).map { date in
            JournalTimelineGroup(
                date: date,
                entries: grouped[date]?.sorted(by: { $0.date > $1.date }) ?? []
            )
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundView

                if filteredEntries.isEmpty {
                    JournalEmptyState(filter: filter, searchText: searchText)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            JournalSearchBar(searchText: $searchText)
                                .padding(.top, 8)

                            JournalFilterBar(filter: $filter)
                                .padding(.top, 8)

                            ForEach(groupedEntries) { group in
                                JournalTimelineSection(
                                    group: group,
                                    onTap: { entry in
                                        currentEntry = entry
                                        showingEditor = true
                                    },
                                    onDelete: { entry in
                                        deleteEntry(entry)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("Journal")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        currentEntry = JournalEntry()
                        showingEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .onAppear {
                loadEntries()
            }
            .fullScreenCover(isPresented: $showingEditor) {
                JournalEditorView(
                    entry: $currentEntry,
                    onSave: { entry in
                        saveEntry(entry)
                    }
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .saveWorkoutReportToJournal)) { notification in
                guard let payload = notification.object as? SavedWorkoutReportPayload else { return }
                JournalPersistence.appendWorkoutReport(
                    title: payload.title,
                    content: payload.content,
                    date: payload.date
                )
                loadEntries()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceViewControlNewJournalEntry)) { _ in
                currentEntry = JournalEntry()
                showingEditor = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)) { _ in
                loadEntries()
            }
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        JournalMeshPhaseBackground(style: filter == .reports ? .burning : .spirit)
            .ignoresSafeArea()
    }
    
    func saveEntry(_ entry: JournalEntry) {
        var normalized = entry
        normalized.content = JournalDisplaySanitizer.endUserText(normalized.content)
        normalized.inspiration = JournalDisplaySanitizer.endUserText(normalized.inspiration)
        if let index = entries.firstIndex(where: { $0.id == normalized.id }) {
            entries[index] = normalized
        } else {
            entries.insert(normalized, at: 0)
        }

        persistEntries()
    }
    
    func deleteEntry(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        persistEntries()
    }

    func deleteEntry(_ entry: JournalEntry) {
        entries.removeAll { $0.id == entry.id }
        persistEntries()
    }

    func deleteEntries(from source: [JournalEntry], at offsets: IndexSet) {
        let idsToDelete = offsets.map { source[$0].id }
        entries.removeAll { idsToDelete.contains($0.id) }
        persistEntries()
    }
    
    func persistEntries() {
        JournalPersistence.persistEntries(entries)
    }
    
    func loadEntries() {
        entries = JournalPersistence.loadEntries()
    }

    private func matchesSearch(_ entry: JournalEntry) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }

        let metricText = entry.reportMetrics
            .map { "\($0.title) \($0.value)" }
            .joined(separator: " ")

        let statCardText = entry.statCards
            .map { "\($0.title) \($0.value) \($0.subtitle)" }
            .joined(separator: " ")

        let imageHintText = entry.imageData.isEmpty ? "" : "photo image inspiration memory picture"
        let haystack = [
            entry.title,
            entry.content,
            entry.inspiration,
            entry.kind,
            metricText,
            statCardText,
            imageHintText
        ]
        .joined(separator: "\n")

        return haystack.localizedCaseInsensitiveContains(query)
    }
}

private enum JournalFeedFilter: String, CaseIterable, Identifiable {
    case all
    case entries
    case reports

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .entries: return "Entries"
        case .reports: return "Fitness Reports"
        }
    }

    func matches(_ entry: JournalEntry) -> Bool {
        switch self {
        case .all: return true
        case .entries: return !isFitnessReportEntry(entry)
        case .reports: return isFitnessReportEntry(entry)
        }
    }
}

private struct JournalTimelineGroup: Identifiable {
    let date: Date
    let entries: [JournalEntry]

    var id: Date { date }
}

private struct JournalFilterBar: View {
    @Binding var filter: JournalFeedFilter

    var body: some View {
        HStack(spacing: 10) {
            ForEach(JournalFeedFilter.allCases) { option in
                Button {
                    filter = option
                } label: {
                    Text(option.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(filter == option ? Color.primary : Color.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background((filter == option ? Color.white.opacity(0.2) : Color.white.opacity(0.08)), in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(filter == option ? 0.18 : 0.08), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(8)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

private struct JournalEmptyState: View {
    let filter: JournalFeedFilter
    let searchText: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.largeTitle)
            Text(emptyTitle)
                .font(.headline)
            Text(emptyMessage)
                .foregroundColor(.secondary)
        }
        .padding(28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var emptyTitle: String {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No Matching Entries"
        }
        return filter == .all ? "No Journal Entries Yet" : "Nothing In This Filter"
    }

    private var emptyMessage: String {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Try another word, title, metric, or inspiration detail."
        }
        return filter == .all ? "Tap + to start writing" : "Try another filter or add a new entry."
    }
}

private struct JournalSearchBar: View {
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search titles, keywords, inspiration, reports, images...", text: $searchText)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled(false)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct JournalTimelineSection: View {
    let group: JournalTimelineGroup
    let onTap: (JournalEntry) -> Void
    let onDelete: (JournalEntry) -> Void

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE, MMM d")
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(Self.dayFormatter.string(from: group.date))
                    .font(.title3.weight(.bold))
                Spacer()
                Text("\(group.entries.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08), in: Capsule())
            }

            LazyVStack(spacing: 16) {
                ForEach(group.entries) { entry in
                    JournalEntryRow(entry: entry) {
                        onTap(entry)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            onDelete(entry)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }
}

private struct JournalEntryRow: View {
    let entry: JournalEntry
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.title.isEmpty ? "Untitled Entry" : entry.title)
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(.primary)

                        HStack(spacing: 8) {
                            Text(entry.date.formatted(.dateTime.hour().minute()))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Text(isFitnessReportEntry(entry) ? "Fitness Report" : "Entry")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(isFitnessReportEntry(entry) ? Color.orange : Color.white.opacity(0.8))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    (isFitnessReportEntry(entry) ? Color.orange.opacity(0.16) : Color.white.opacity(0.08)),
                                    in: Capsule()
                                )
                        }
                    }

                    Spacer()

                    Image(systemName: isFitnessReportEntry(entry) ? "figure.run" : "book.pages")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(isFitnessReportEntry(entry) ? Color.orange : Color.white.opacity(0.82))
                        .frame(width: 50, height: 50)
                        .background(
                            (isFitnessReportEntry(entry) ? Color.orange.opacity(0.14) : Color.white.opacity(0.08)),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                }

                if !entry.content.isEmpty {
                    Text(JournalDisplaySanitizer.endUserText(entry.content))
                        .lineLimit(8)
                        .foregroundStyle(.secondary)
                }

                if isFitnessReportEntry(entry) {
                    WorkoutReportMetricsWall(metrics: entry.reportMetrics)
                }

                if !entry.statCards.isEmpty {
                    JournalStatCardsGrid(
                        cards: entry.statCards,
                        onResize: { _, _ in },
                        onDelete: { _ in }
                    )
                    .allowsHitTesting(false)
                }

                if !entry.inspiration.isEmpty || !entry.imageData.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Inspiration")
                            .font(.subheadline.weight(.semibold))

                        InspirationSectionView(
                            inspiration: entry.inspiration,
                            imageData: entry.imageData,
                            compact: true
                        )
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(cardBorderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var cardBackground: LinearGradient {
        if isFitnessReportEntry(entry) {
            return LinearGradient(
                colors: [
                    Color.orange.opacity(0.18),
                    Color.red.opacity(0.08),
                    Color.black.opacity(0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [
                Color.white.opacity(0.1),
                Color.teal.opacity(0.05),
                Color.indigo.opacity(0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardBorderColor: Color {
        isFitnessReportEntry(entry) ? Color.orange.opacity(0.16) : Color.white.opacity(0.08)
    }
}

// MARK: - Journal selectable editor (cursor-aware inline suggestions)

#if canImport(UIKit)
struct JournalSelectableTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    var onEdit: (String, NSRange) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.font = UIFont.preferredFont(forTextStyle: .body)
        tv.textColor = UIColor.label
        tv.backgroundColor = .clear
        tv.textContainer.lineFragmentPadding = 0
        tv.textContainerInset = .zero
        tv.adjustsFontForContentSizeCategory = true
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        let ns = text as NSString
        let maxLen = ns.length
        let loc = min(max(0, selection.location), maxLen)
        let len = min(max(0, selection.length), maxLen - loc)
        let desired = NSRange(location: loc, length: len)

        if uiView.text != text {
            context.coordinator.isProgrammaticUpdate = true
            uiView.text = text
            uiView.selectedRange = desired
            context.coordinator.isProgrammaticUpdate = false
        } else if uiView.selectedRange.location != desired.location || uiView.selectedRange.length != desired.length {
            context.coordinator.isProgrammaticUpdate = true
            uiView.selectedRange = desired
            context.coordinator.isProgrammaticUpdate = false
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: JournalSelectableTextEditor
        var isProgrammaticUpdate = false

        init(_ parent: JournalSelectableTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isProgrammaticUpdate else { return }
            let t = textView.text ?? ""
            parent.text = t
            parent.selection = textView.selectedRange
            parent.onEdit(t, textView.selectedRange)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isProgrammaticUpdate else { return }
            parent.selection = textView.selectedRange
            parent.onEdit(textView.text ?? "", textView.selectedRange)
        }
    }
}
#endif

// MARK: - Inline Suggestion Engine

/// Distinguishes predictive inline text, rewrites, metrics, and labeled nudges in the UI.
enum InlineSuggestionChipRole: Hashable {
    /// Health / keyword metric tails at the caret.
    case caretContinuation
    /// AI-predicted continuation of the user’s thought at the caret (not a question).
    case predictedContinuation
    /// Replaces the clause from sentence start through caret with a clearer full sentence.
    case clauseRewrite
    /// Reflective question or prompt—shown under the “Nudges” row, not as inline prediction.
    case nudge
}

struct InlineSuggestion: Identifiable, Hashable {
    let id = UUID()
    /// Shown on the suggestion chip
    let preview: String
    let confidence: Double
    let mode: InlineSuggestionApplyMode
    var chipRole: InlineSuggestionChipRole = .caretContinuation

    init(preview: String, confidence: Double, mode: InlineSuggestionApplyMode, chipRole: InlineSuggestionChipRole = .caretContinuation) {
        self.preview = preview
        self.confidence = confidence
        self.mode = mode
        self.chipRole = chipRole
    }
}

/// How a suggestion is merged into the entry when tapped.
enum InlineSuggestionApplyMode: Hashable {
    /// Insert at the caret (or replace the current selection) without removing text before the caret.
    case completion(insertUTF16: String)
    /// Replace a utf-16 range (e.g. rewrite the whole clause or sentence prefix).
    case replacement(location: Int, length: Int, replacementUTF16: String)

    fileprivate var isReplacement: Bool {
        if case .replacement = self { return true }
        return false
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable(description: "Whether journal paragraphs share one narrative thread.")
struct JournalParagraphRelationOutput {
    var sameThread: Bool
}

@available(iOS 26.0, *)
@Generable(description: "Short, grounded continuations at the caret, light clause polish, and warm reflective nudges.")
struct JournalAIInlineSuggestionPack {
    /// Brief continuations (about 4-12 words) inserted at the caret. Stay close to what the user already wrote—same voice and facts; extend the thought without inventing new scenes. Never a question.
    var inlineCompletions: [String]
    /// Full sentences replacing the clause from sentence start through caret. Same topic and entities as the original; clearer or slightly reframed—not a new story. Preserve normal spacing after sentence-ending punctuation when relevant.
    var clauseRewrites: [String]
    /// Warm reflective questions shown as Nudge cards. Each references a specific person, activity, or detail from the cursor section. Never generic.
    var nudges: [String]
}

@available(iOS 26.0, *)
@Generable(description: "A concise title for a journal entry.")
struct JournalAITitleOutput {
    var suggestedTitle: String
}

@available(iOS 26.0, *)
@Generable(description: "A labeled section from the backbone of a journal entry.")
struct JournalBackboneSection {
    var label: String
    var themes: [String]
}

@available(iOS 26.0, *)
@Generable(description: "A structural outline of a journal entry, broken into labeled sections by topic.")
struct JournalBackboneOutput {
    var sections: [JournalBackboneSection]
}
#endif

// MARK: - Backbone Outline

struct JournalOutlineSection: Identifiable, Equatable {
    let id = UUID()
    var label: String
    var themes: [String]
    /// Approximate UTF-16 range in the full text this section covers.
    var textRange: NSRange
}

// MARK: - Saved Nudge

struct JournalSavedNudge: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var text: String
    var savedDate: Date

    init(id: UUID = UUID(), text: String, savedDate: Date = Date()) {
        self.id = id
        self.text = text
        self.savedDate = savedDate
    }
}

@MainActor
final class JournalInlineSuggestionEngine: ObservableObject {
    @Published var suggestions: [InlineSuggestion] = []
    /// Reflective questions—separate row in the editor, not treated as inline prediction.
    @Published var nudgeSuggestions: [InlineSuggestion] = []
    /// Backbone outline of the entry: labeled semantic sections for cursor-aware context.
    @Published var backboneOutline: [JournalOutlineSection] = []
    /// The pinned nudge (pauses new nudge generation while pinned).
    @Published var pinnedNudge: InlineSuggestion? = nil
    private var debounceTask: Task<Void, Never>?
    private var backboneTask: Task<Void, Never>?
    private var cachedMoodStates: [HKStateOfMind] = []
    private var moodCacheDate: Date?
    private var paragraphRelationCache: (signature: UInt64, unrelated: Bool)?
    private var backboneCache: (textHash: UInt64, sections: [JournalOutlineSection])?

    private struct SuggestionFocusContext {
        let fullText: String
        let fullTextLower: String
        let activeParagraph: String
        let activeParagraphLower: String
        /// When true, keyword triggers only match inside the paragraph that contains the caret.
        let restrictTriggersToActiveParagraph: Bool
        let typingFragment: String
        let typingLower: String
        let cursorUTF16: Int
        let clauseStartUTF16: Int
        /// The backbone section where the cursor lives (nil if backbone not generated yet).
        var cursorSectionLabel: String?
        var cursorSectionThemes: [String]?
    }

    func prepare(referenceDate: Date) {
        Task {
            let cal = Calendar.current
            let start = cal.startOfDay(for: referenceDate)
            let end = cal.date(byAdding: .day, value: 1, to: start) ?? referenceDate
            let hkm = HealthKitManager()
            cachedMoodStates = await hkm.fetchStateOfMindSamples(from: start, to: end)
            moodCacheDate = referenceDate
        }
    }

    func textDidChange(_ text: String, selection: NSRange, referenceDate: Date, isFitnessReport: Bool, inspirationContext: String) {
        debounceTask?.cancel()
        refreshBackbone(text: text)
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }

            let unrelated = await paragraphsUnrelatedToCursorParagraph(text: text, selection: selection)
            var ctx = Self.makeFocusContext(text: text, selection: selection, paragraphsUnrelated: unrelated)
            ctx = enrichWithBackbone(ctx)

            var newSuggestions = buildSuggestions(ctx: ctx, referenceDate: referenceDate, isFitnessReport: isFitnessReport)

            let inspirationTrimmed = inspirationContext.trimmingCharacters(in: .whitespacesAndNewlines)
            let prioritizeImportedInspiration = !inspirationTrimmed.isEmpty

            var newNudges: [InlineSuggestion] = []
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                let shouldRunAI = newSuggestions.count < 3 || prioritizeImportedInspiration
                if shouldRunAI, let parts = await aiSuggestions(
                    ctx: ctx,
                    referenceDate: referenceDate,
                    inspirationLayer: inspirationTrimmed
                ) {
                    newSuggestions.append(contentsOf: parts.inline)
                    if pinnedNudge == nil {
                        newNudges = parts.nudges
                    }
                }
            }
            #endif

            guard !Task.isCancelled else { return }

            if prioritizeImportedInspiration {
                newSuggestions.sort { $0.confidence > $1.confidence }
            }

            let deduped = deduplicateSuggestions(newSuggestions, existingText: text)
            withAnimation(.easeOut(duration: 0.15)) {
                suggestions = Array(deduped.prefix(6))
                if pinnedNudge == nil {
                    let dedupedNudges = deduplicateSuggestions(newNudges, existingText: text).sorted { $0.confidence > $1.confidence }
                    nudgeSuggestions = Array(dedupedNudges.prefix(4))
                }
            }
        }
    }

    func pinNudge(_ nudge: InlineSuggestion) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            pinnedNudge = nudge
            nudgeSuggestions = []
        }
    }

    func unpinNudge() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            pinnedNudge = nil
        }
    }

    // MARK: - Backbone

    func refreshBackbone(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 60 else {
            if !backboneOutline.isEmpty { withAnimation { backboneOutline = [] } }
            return
        }
        var hasher = Hasher()
        hasher.combine(trimmed)
        let hash = UInt64(bitPattern: Int64(hasher.finalize()))
        if let cache = backboneCache, cache.textHash == hash { return }

        backboneTask?.cancel()
        backboneTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }

            #if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                if let sections = await generateBackbone(text: trimmed) {
                    guard !Task.isCancelled else { return }
                    backboneCache = (hash, sections)
                    withAnimation(.easeOut(duration: 0.2)) {
                        backboneOutline = sections
                    }
                    return
                }
            }
            #endif

            let sections = heuristicBackbone(text: trimmed)
            guard !Task.isCancelled else { return }
            backboneCache = (hash, sections)
            withAnimation(.easeOut(duration: 0.2)) {
                backboneOutline = sections
            }
        }
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func generateBackbone(text: String) async -> [JournalOutlineSection]? {
        let model = SystemLanguageModel(useCase: .general)
        guard model.isAvailable else { return nil }
        do {
            let session = LanguageModelSession(
                model: model,
                instructions: """
                Break the journal entry into its distinct topical sections in order. Each section gets a short label (3–8 words) and 1–3 keyword themes. A section may be one sentence or several. Do not merge unrelated topics. If a topic has clear sub-parts, split them. Keep the order as written.
                """
            )
            let response = try await session.respond(to: String(text.prefix(3000)), generating: JournalBackboneOutput.self)
            let ns = text as NSString
            return mapBackboneSectionsToRanges(aiSections: response.content.sections, fullText: ns)
        } catch {
            return nil
        }
    }
    #endif

    private func heuristicBackbone(text: String) -> [JournalOutlineSection] {
        let ns = text as NSString
        let paragraphs = text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard paragraphs.count >= 1 else { return [] }

        var offset = 0
        return paragraphs.enumerated().map { idx, para in
            let range = ns.range(of: para, options: [], range: NSRange(location: offset, length: ns.length - offset))
            let actualRange = range.location != NSNotFound ? range : NSRange(location: offset, length: (para as NSString).length)
            offset = actualRange.location + actualRange.length
            let words = para.split { $0.isWhitespace || $0.isNewline }.prefix(6).map(String.init)
            let label = words.joined(separator: " ") + (para.count > 40 ? "…" : "")
            return JournalOutlineSection(label: label, themes: [], textRange: actualRange)
        }
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func mapBackboneSectionsToRanges(aiSections: [JournalBackboneSection], fullText: NSString) -> [JournalOutlineSection] {
        let fullLen = fullText.length
        var offset = 0
        return aiSections.enumerated().map { idx, sec in
            let keyword = sec.themes.first ?? sec.label
            let searchStart = min(max(0, offset), fullLen)
            let searchLen = max(0, fullLen - searchStart)
            var range = NSRange(location: NSNotFound, length: 0)
            if searchLen > 0, !keyword.isEmpty {
                range = fullText.range(of: keyword, options: .caseInsensitive, range: NSRange(location: searchStart, length: searchLen))
            }
            if range.location == NSNotFound, searchLen > 0 {
                let fallback = sec.label.components(separatedBy: " ").prefix(3).joined(separator: " ")
                if !fallback.isEmpty {
                    range = fullText.range(of: fallback, options: .caseInsensitive, range: NSRange(location: searchStart, length: searchLen))
                }
            }
            let rawStart = range.location != NSNotFound ? range.location : offset
            let sectionStart = min(max(0, rawStart), fullLen)

            let nextStart: Int
            if idx + 1 < aiSections.count {
                let nextKw = aiSections[idx + 1].themes.first ?? aiSections[idx + 1].label
                let nextSearchLoc = sectionStart + 1
                if nextSearchLoc < fullLen, !nextKw.isEmpty {
                    let nextLen = fullLen - nextSearchLoc
                    let nextRange = fullText.range(of: nextKw, options: .caseInsensitive, range: NSRange(location: nextSearchLoc, length: nextLen))
                    nextStart = nextRange.location != NSNotFound ? nextRange.location : fullLen
                } else {
                    nextStart = fullLen
                }
            } else {
                nextStart = fullLen
            }

            let end = min(max(sectionStart, nextStart), fullLen)
            let sectionRange = NSRange(location: sectionStart, length: max(0, end - sectionStart))
            offset = end
            return JournalOutlineSection(label: sec.label, themes: sec.themes, textRange: sectionRange)
        }
    }
    #endif

    private func enrichWithBackbone(_ ctx: SuggestionFocusContext) -> SuggestionFocusContext {
        guard !backboneOutline.isEmpty else { return ctx }
        var enriched = ctx
        for section in backboneOutline {
            let start = section.textRange.location
            let end = start + section.textRange.length
            if ctx.cursorUTF16 >= start && ctx.cursorUTF16 <= end {
                enriched.cursorSectionLabel = section.label
                enriched.cursorSectionThemes = section.themes
                break
            }
        }
        return enriched
    }

    func apply(_ suggestion: InlineSuggestion, to text: String, selection: NSRange) -> (String, NSRange) {
        let ns = text as NSString
        let maxLen = ns.length
        let safeLoc = min(max(0, selection.location), maxLen)
        let safeLen = min(max(0, selection.length), maxLen - safeLoc)

        switch suggestion.mode {
        case .completion(let insert):
            let r = NSRange(location: safeLoc, length: safeLen)
            let newText = ns.replacingCharacters(in: r, with: insert)
            let newPos = r.location + (insert as NSString).length
            return (newText, NSRange(location: newPos, length: 0))

        case .replacement(let loc, let len, let repl):
            let rLoc = min(max(0, loc), maxLen)
            let rLen = min(max(0, len), maxLen - rLoc)
            var finalRepl = repl.trimmingCharacters(in: .whitespacesAndNewlines)
            if rLoc > 0, !finalRepl.isEmpty,
               Self.needsLeadingSpaceAfterSentenceEnd(ns: ns, replaceLocation: rLoc),
               finalRepl.first?.isWhitespace != true {
                finalRepl = " " + finalRepl
            }
            let r = NSRange(location: rLoc, length: rLen)
            let newText = ns.replacingCharacters(in: r, with: finalRepl)
            let newPos = r.location + (finalRepl as NSString).length
            return (newText, NSRange(location: newPos, length: 0))
        }
    }

    func clear() {
        suggestions = []
        if pinnedNudge == nil {
            nudgeSuggestions = []
        }
    }

    // MARK: - Focus / paragraphs

    private static func makeFocusContext(text: String, selection: NSRange, paragraphsUnrelated: Bool) -> SuggestionFocusContext {
        let ns = text as NSString
        let maxLen = ns.length
        let cursor = min(max(0, selection.location), maxLen)
        let paraRange = activeParagraphUTF16Range(in: ns, cursorUTF16: cursor)
        let active = ns.substring(with: paraRange).trimmingCharacters(in: .whitespacesAndNewlines)
        let clauseStart = clauseStartUTF16(full: ns, cursorUTF16: cursor)
        let frag = ns.substring(with: NSRange(location: clauseStart, length: cursor - clauseStart))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fullLower = text.lowercased()
        return SuggestionFocusContext(
            fullText: text,
            fullTextLower: fullLower,
            activeParagraph: active,
            activeParagraphLower: active.lowercased(),
            restrictTriggersToActiveParagraph: paragraphsUnrelated,
            typingFragment: frag,
            typingLower: frag.lowercased(),
            cursorUTF16: cursor,
            clauseStartUTF16: clauseStart
        )
    }

    private static func activeParagraphUTF16Range(in ns: NSString, cursorUTF16: Int) -> NSRange {
        let len = ns.length
        let c = min(max(0, cursorUTF16), len)
        var start = 0
        var i = 0
        while i <= len {
            let r = ns.range(of: "\n\n", options: [], range: NSRange(location: i, length: len - i))
            if r.location == NSNotFound {
                return NSRange(location: start, length: len - start)
            }
            if c >= start && c < r.location {
                return NSRange(location: start, length: r.location - start)
            }
            start = r.location + r.length
            i = start
        }
        return NSRange(location: 0, length: len)
    }

    private static func clauseStartUTF16(full: NSString, cursorUTF16: Int) -> Int {
        let c = min(max(0, cursorUTF16), full.length)
        if c == 0 { return 0 }
        let charset = CharacterSet(charactersIn: ".!?\n")
        let search = full.rangeOfCharacter(from: charset, options: [.backwards], range: NSRange(location: 0, length: c))
        if search.location == NSNotFound { return 0 }
        return search.location + search.length
    }

    private static func logicalParagraphs(_ text: String) -> [String] {
        let n = text.replacingOccurrences(of: "\r\n", with: "\n")
        return n.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func paragraphsUnrelatedToCursorParagraph(text: String, selection: NSRange) async -> Bool {
        let paras = Self.logicalParagraphs(text)
        guard paras.count >= 2 else {
            paragraphRelationCache = nil
            return false
        }

        var hasher = Hasher()
        for p in paras { hasher.combine(p) }
        let sig = UInt64(bitPattern: Int64(hasher.finalize()))

        if let cache = paragraphRelationCache, cache.signature == sig {
            return cache.unrelated
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel(useCase: .general)
            if model.isAvailable {
                let joined = paras.enumerated().map { "P\($0.offset + 1): \($0.element)" }.joined(separator: "\n")
                let prompt = """
                The user wrote these paragraphs in one journal entry (possibly same day or different topics).
                Do they describe one continuous story/theme, or mostly separate unrelated events/thoughts?
                Answer unrelated=true if the paragraphs are separate topics (e.g. morning workout vs evening argument) with no single narrative thread.
                unrelated=false if they clearly continue the same story, reflection, or theme.
                Paragraphs:
                \(String(joined.prefix(2500)))
                """
                do {
                    let session = LanguageModelSession(model: model, instructions: "Reply only with structured output. Be conservative: unrelated=true only when paragraphs are clearly different topics.")
                    let response = try await session.respond(to: prompt, generating: JournalParagraphRelationOutput.self)
                    let unrelated = !response.content.sameThread
                    paragraphRelationCache = (sig, unrelated)
                    return unrelated
                } catch {}
            }
        }
        #endif

        let unrelated = heuristicParagraphsUnrelated(paras)
        paragraphRelationCache = (sig, unrelated)
        return unrelated
    }

    private func heuristicParagraphsUnrelated(_ paragraphs: [String]) -> Bool {
        guard paragraphs.count >= 2 else { return false }
        let words0 = Set(paragraphs[0].lowercased().split { !$0.isLetter && !$0.isNumber }.filter { $0.count > 2 })
        guard !words0.isEmpty else { return false }
        for p in paragraphs.dropFirst() {
            let w1 = Set(p.lowercased().split { !$0.isLetter && !$0.isNumber }.filter { $0.count > 2 })
            let uni = words0.union(w1)
            guard !uni.isEmpty else { continue }
            let j = Double(words0.intersection(w1).count) / Double(uni.count)
            if j < 0.05 { return true }
        }
        return false
    }

    // MARK: - Deduplication

    private func deduplicateSuggestions(_ suggestions: [InlineSuggestion], existingText: String) -> [InlineSuggestion] {
        let lowerText = existingText.lowercased()
        var seen: Set<String> = []
        return suggestions.filter { s in
            let normalized = s.preview.trimmingCharacters(in: .whitespaces).lowercased()
            guard !normalized.isEmpty else { return false }
            if lowerText.contains(normalized) { return false }
            guard !seen.contains(normalized) else { return false }
            seen.insert(normalized)
            return true
        }
    }

    private func completionChip(_ tail: String, after fragment: String, confidence: Double) -> InlineSuggestion {
        let t = grammarAdjust(tail, after: fragment)
        let preview = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return InlineSuggestion(preview: preview.isEmpty ? tail : preview, confidence: confidence, mode: .completion(insertUTF16: t), chipRole: .caretContinuation)
    }

    /// Inserts standalone ideas/prompts as a new block, not glued to the clause at the caret.
    private static func newlinePrefixForStandaloneInsert(fullText: String, cursorUTF16: Int) -> String {
        let ns = fullText as NSString
        let c = min(max(0, cursorUTF16), ns.length)
        guard c > 0 else { return "" }
        if ns.character(at: c - 1) == 10 { return "" }
        return "\n\n"
    }

    // MARK: - Pattern Matching

    private func buildSuggestions(ctx: SuggestionFocusContext, referenceDate: Date, isFitnessReport: Bool) -> [InlineSuggestion] {
        let trimmed = ctx.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return [] }

        var results: [InlineSuggestion] = []

        results.append(contentsOf: workoutMetricSuggestions(ctx: ctx, referenceDate: referenceDate))
        results.append(contentsOf: moodSuggestions(ctx: ctx))
        results.append(contentsOf: sleepSuggestions(ctx: ctx))
        results.append(contentsOf: recoverySuggestions(ctx: ctx))
        results.append(contentsOf: vitalsSuggestions(ctx: ctx))

        if isFitnessReport {
            results.sort { $0.confidence > $1.confidence }
        }

        return results
    }

    /// True when the replaced range begins after sentence-ending punctuation, possibly with spaces between.
    private static func needsLeadingSpaceAfterSentenceEnd(ns: NSString, replaceLocation: Int) -> Bool {
        guard replaceLocation > 0 else { return false }
        var i = replaceLocation - 1
        while i >= 0 {
            let u = ns.character(at: i)
            if u == 0x0020 || u == 0x0009 || u == 0x00A0 { i -= 1; continue }
            return u == 0x002E || u == 0x0021 || u == 0x003F
        }
        return false
    }

    /// Keeps completions short and on-topic in the UI and at insert time.
    private static func clampInlineContinuation(_ text: String, maxWords: Int, maxChars: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var clipped = words.prefix(maxWords).joined(separator: " ")
        if clipped.count > maxChars {
            clipped = String(clipped.prefix(maxChars))
            if let lastSpace = clipped.lastIndex(of: " ") {
                clipped = String(clipped[..<lastSpace])
            }
        }
        return clipped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func clampClauseRewrite(_ text: String, maxWords: Int, maxChars: Int) -> String {
        clampInlineContinuation(text, maxWords: maxWords, maxChars: maxChars)
    }

    // MARK: - Grammar Adjustment

    private func grammarAdjust(_ suggestion: String, after trailing: String) -> String {
        let trimTrail = trailing.trimmingCharacters(in: .whitespaces)
        let lastToken = trimTrail.split(whereSeparator: { $0.isWhitespace }).last.map(String.init) ?? ""
        let lastWord = lastToken.trimmingCharacters(in: .punctuationCharacters).lowercased()
        guard !lastWord.isEmpty else { return Self.joinCompletionFragment(suggestion) }
        var trimSug = suggestion.trimmingCharacters(in: .whitespaces)

        let prepositions: Set<String> = [
            "for", "in", "at", "on", "with", "about", "to", "from", "during", "after", "before",
            "around", "near", "above", "below", "under", "over", "like", "into", "onto", "by",
            "between", "through", "than", "toward", "towards", "within", "across", "upon",
        ]
        let copulas: Set<String> = ["is", "was", "were", "are", "been", "being", "felt", "feels", "seemed", "seem", "looks", "looked"]
        let articles: Set<String> = ["a", "an", "the"]

        if prepositions.contains(lastWord) {
            trimSug = Self.rephraseCompletionAfterPreposition(trimSug, lastFragmentWord: lastWord)
            if trimSug.hasPrefix("a ") || trimSug.hasPrefix("an ") {
                return " " + trimSug
            }
            return Self.joinCompletionFragment(trimSug)
        }

        if copulas.contains(lastWord) {
            return Self.joinCompletionFragment(trimSug)
        }

        if articles.contains(lastWord) {
            var cleaned = trimSug
            if cleaned.lowercased().hasPrefix("a ") { cleaned = String(cleaned.dropFirst(2)) }
            if cleaned.lowercased().hasPrefix("an ") { cleaned = String(cleaned.dropFirst(3)) }
            return Self.joinCompletionFragment(cleaned)
        }

        return Self.joinCompletionFragment(trimSug)
    }

    private static func joinCompletionFragment(_ suggestion: String) -> String {
        let trimSug = suggestion.trimmingCharacters(in: .whitespaces)
        return trimSug.hasPrefix(" ") ? trimSug : " " + trimSug
    }

    /// After trailing prepositions ("at", "around", …), completions must be noun phrases, not new clauses ("is averaging…").
    private static func rephraseCompletionAfterPreposition(_ raw: String, lastFragmentWord: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespaces)
        var low = s.lowercased()

        for prefix in ["is ", "was ", "were ", "are "] {
            guard low.hasPrefix(prefix) else { continue }
            s = String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            low = s.lowercased()
            break
        }

        if low.hasPrefix("averaging ") {
            s = String(s.dropFirst("averaging ".count)).trimmingCharacters(in: .whitespaces)
            return s
        }

        if low.hasPrefix("heart rate was ") {
            let rest = String(s.dropFirst("heart rate was ".count)).trimmingCharacters(in: .whitespaces)
            return "a heart rate that was \(rest)"
        }

        if low.hasPrefix("score is ") {
            let rest = String(s.dropFirst("score is ".count)).trimmingCharacters(in: .whitespaces)
            return "a score of \(rest)"
        }

        let qualRewrites: [(String, String)] = [
            ("significantly higher than usual", "a reading significantly higher than my usual"),
            ("slightly above my average", "a level slightly above my average"),
            ("noticeably lower than usual", "a reading noticeably lower than my usual"),
            ("a bit below my average", "a level a bit below my average"),
            ("right around my usual level", "my usual level"),
            ("pretty intense", "a pretty intense effort"),
            ("pretty gruelling", "a pretty gruelling effort"),
            ("challenging", "a challenging effort"),
            ("a great light session", "a great light session"),
            ("a relaxed session", "a relaxed session"),
        ]
        for (needle, replacement) in qualRewrites where low == needle || low.hasPrefix(needle) {
            if low == needle { return replacement }
            let suffix = s.dropFirst(needle.count).trimmingCharacters(in: .whitespaces)
            return suffix.isEmpty ? replacement : "\(replacement) \(suffix)"
        }

        if lastFragmentWord == "around", low.contains("around my") || low.hasPrefix("right around") {
            var t = s
            t = t.replacingOccurrences(of: "right around ", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespaces)
            return t
        }

        return s
    }

    // MARK: - AI-Powered Suggestions

    /// Builds prompt text from Apple Journaling Suggestions import (Inspiration section): venue, city, coords, dates → meal hints.
    private static func journalingInspirationPromptBlock(_ layer: String) -> String {
        let trimmed = layer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        var lines: [String] = []
        lines.append("IMPORTED JOURNALING SUGGESTIONS LAYER (authoritative for proper nouns, place names, spelling, area/neighborhood, and timing). Prefer these facts over guessing.")
        lines.append(String(trimmed.prefix(4500)))

        var place = ""
        var city = ""
        for raw in trimmed.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let low = line.lowercased()
            if low.hasPrefix("place:") {
                place = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if low.hasPrefix("city:") {
                city = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            }
        }

        if !place.isEmpty || !city.isEmpty {
            lines.append("PARSED VENUE LINE: \(place)\(place.isEmpty || city.isEmpty ? "" : ", ")\(city)")
        }

        for raw in trimmed.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.lowercased().hasPrefix("title:") {
                let t = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { lines.append("SUGGESTION TITLE: \(t)") }
            }
        }

        if let mealHint = mealHintsFromInspirationDates(in: trimmed) {
            lines.append("TIME / MEAL CONTEXT (from Date fields in the layer): \(mealHint)")
        }

        lines.append("""
        When the user's clause is about dining, a restaurant, going out, travel, or an event, use EXACT venue and area names from the layer (e.g. \"Kushi\", \"Reston Town Center\", \"Reston\"). Combine neighborhood + city when it reads naturally. If times suggest evening, prefer \"dinner\"; midday → \"lunch\"; morning → \"breakfast\".
        """)

        return lines.joined(separator: "\n\n")
    }

    private static func mealHintsFromInspirationDates(in text: String) -> String? {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        df.locale = Locale.current

        var hints: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.lowercased().hasPrefix("date:") else { continue }
            let value = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            for segment in value.components(separatedBy: " - ").map({ $0.trimmingCharacters(in: .whitespaces) }) where !segment.isEmpty {
                if let d = df.date(from: segment) {
                    hints.append(mealLabel(for: d))
                }
            }
        }
        let unique = Array(Set(hints))
        return unique.isEmpty ? nil : unique.joined(separator: "; ")
    }

    private static func mealLabel(for date: Date) -> String {
        let h = Calendar.current.component(.hour, from: date)
        switch h {
        case 5..<11: return "morning (~breakfast)"
        case 11..<14: return "midday (~lunch)"
        case 14..<17: return "afternoon (~snack or early dinner)"
        case 17..<22: return "evening (~dinner)"
        default: return "late night"
        }
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func aiSuggestions(ctx: SuggestionFocusContext, referenceDate: Date, inspirationLayer: String) async -> (inline: [InlineSuggestion], nudges: [InlineSuggestion])? {
        let model = SystemLanguageModel(useCase: .general)
        guard model.isAvailable else { return nil }

        let inspirationTrimmed = inspirationLayer.trimmingCharacters(in: .whitespacesAndNewlines)
        let focusBody = ctx.restrictTriggersToActiveParagraph ? ctx.activeParagraph : ctx.fullText
        let focusTrimmed = focusBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard focusTrimmed.count >= 14 || ctx.typingFragment.count >= 2 || inspirationTrimmed.count >= 24 else { return nil }
        let hasInspiration = !inspirationTrimmed.isEmpty
        let inspirationBlock = Self.journalingInspirationPromptBlock(inspirationTrimmed)

        let completionConfidence: Double = hasInspiration ? 0.94 : 0.78
        let rewriteConfidence: Double = hasInspiration ? 0.87 : 0.72
        let nudgeConfidence: Double = hasInspiration ? 0.86 : 0.70

        let engine = HealthStateEngine.shared
        var contextFacts: [String] = []
        if let sleep = engine.sleepHours { contextFacts.append("Sleep: \(String(format: "%.1f", sleep))h") }
        if let hrv = engine.latestHRV { contextFacts.append("HRV: \(Int(hrv))ms") }
        if let rhr = engine.restingHeartRate { contextFacts.append("RHR: \(Int(rhr))bpm") }
        let recoveryScore = Int(engine.recoveryScore)
        if recoveryScore > 0 { contextFacts.append("Recovery: \(recoveryScore)") }

        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: referenceDate)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? referenceDate
        let todayWorkouts = engine.workoutAnalytics.filter { $0.workout.startDate >= dayStart && $0.workout.startDate < dayEnd }
        for w in todayWorkouts.prefix(3) {
            let dur = Int(w.workout.duration / 60)
            let name = w.workout.workoutActivityType.name
            contextFacts.append("\(name): \(dur)min")
            if let dist = w.workout.totalDistance?.doubleValue(for: .meter()), dist > 0 {
                contextFacts.append("\(name) distance: \(String(format: "%.1f", dist / 1000))km")
            }
        }

        let clauseLen = max(0, ctx.cursorUTF16 - ctx.clauseStartUTF16)
        let clausePrefix = (ctx.fullText as NSString).substring(with: NSRange(location: ctx.clauseStartUTF16, length: clauseLen))

        // Build backbone context for the AI
        var backboneBlock = ""
        if !backboneOutline.isEmpty {
            let outlineLines = backboneOutline.enumerated().map { idx, sec in
                let themes = sec.themes.isEmpty ? "" : " [\(sec.themes.joined(separator: ", "))]"
                let marker = (ctx.cursorSectionLabel == sec.label) ? " ← CURSOR IS HERE" : ""
                return "  \(idx + 1). \(sec.label)\(themes)\(marker)"
            }
            backboneBlock = "ENTRY BACKBONE (structural outline):\n" + outlineLines.joined(separator: "\n")
        }

        var cursorSectionBlock = ""
        if let sectionLabel = ctx.cursorSectionLabel {
            let themes = ctx.cursorSectionThemes?.joined(separator: ", ") ?? ""
            cursorSectionBlock = """
            CURSOR SECTION: "\(sectionLabel)" (themes: \(themes))
            Focus ALL completions and rewrites on this section's topics. The user is currently writing about THIS part of their entry, not other sections.
            """
        }

        var prompt = """
        Journal entry. Reference date: \(referenceDate.formatted(date: .abbreviated, time: .omitted)).
        Health hints: \(contextFacts.joined(separator: ", "))
        """

        if !backboneBlock.isEmpty {
            prompt += "\n\n\(backboneBlock)"
        }
        if !cursorSectionBlock.isEmpty {
            prompt += "\n\n\(cursorSectionBlock)"
        }
        if !inspirationBlock.isEmpty {
            prompt += "\n\n\(inspirationBlock)"
        }

        prompt += """

        FULL ENTRY (for broad context):
        \(String(ctx.fullText.prefix(2400)))

        ACTIVE PARAGRAPH (cursor is here):
        \(String(ctx.activeParagraph.prefix(800)))

        CLAUSE from sentence start through caret (continue FROM the caret, do not repeat it):
        "\(clausePrefix)"

        === EXAMPLES ===
        Bad inlineCompletion for "I am inspired by his passion in...": "things" or "a whole new chapter of discovery and wonder across continents"
        Bad inlineCompletion when clause ends with "...high at around": "is averaging 170 bpm" or "heart rate was elevated" (new clause after a preposition)
        Good inlineCompletion for "...high at around": "170 bpm" or "a level a bit above my usual average"
        Good inlineCompletion: "architecture and how cities take shape"
        Good inlineCompletion: "the way he talks about design"
        Bad clauseRewrite: "Suddenly we were astronauts on Mars" (off-topic fantasy)
        Good clauseRewrite: "I'm inspired by his passion for architecture and urban design."
        === END EXAMPLES ===

        inlineCompletions: 2-4 items. Each 4-12 words only. Stay literal: finish the same thought using words already implied nearby (people, places, activities). Same voice, tense, POV. No new plot twists. No questions.
        If the clause ends with a preposition or "around"/"at"/"near" (e.g. "pretty high at around"), each completion must be a noun phrase or number that fits directly after it—e.g. "170 bpm" or "a level above my usual"—never a new clause starting with "is", "was", "were", or "heart rate was".
        clauseRewrites: 1-2 items. One clear sentence replacing the clause—same facts and topic, slightly clearer or smoother. If the previous character before the clause is . ! or ?, the rewritten sentence must read correctly with a normal space after that punctuation (do not run words together).
        nudges: 1-3 items. Warm QUESTIONS referencing specific people/activities/details from THIS section. Never generic.
        """

        do {
            var sessionInstructions = """
            You are a restrained journaling assistant. Suggest SHORT, grounded phrases—not mini essays.

            CRITICAL RULES:
            1. Backbone / cursor section = current topic only. Do not introduce unrelated themes.
            2. inlineCompletions: 4-12 words each. Extend what they already started; prefer concrete nouns from the paragraph over flowery language. No metaphors unless the user already uses that tone.
            3. After prepositions ("in", "about", "for", "at", "around", "near"), supply a noun phrase or number that completes the grammar—not a fresh predicate. Never start the completion with "is", "was", "were", "heart rate was", or "averaging" when the user already ended on a preposition.
            4. clauseRewrites: one sentence, same meaning and entities as the original clause; clearer wording only. Do not invent new events.
            5. nudges: reflective QUESTIONS naming specific people or details from the cursor section.
            6. No numbering, bullets, or generic filler.
            """
            if hasInspiration {
                sessionInstructions += "\n\nIMPORTED JOURNALING SUGGESTIONS LAYER is highest-priority ground truth for proper nouns and timing."
            }

            let session = LanguageModelSession(model: model, instructions: sessionInstructions)
            let response = try await session.respond(to: prompt, generating: JournalAIInlineSuggestionPack.self)
            let pack = response.content
            var outInline: [InlineSuggestion] = []
            var outNudges: [InlineSuggestion] = []

            let blockPrefix = Self.newlinePrefixForStandaloneInsert(fullText: ctx.fullText, cursorUTF16: ctx.cursorUTF16)

            let completionCap = hasInspiration ? 4 : 3
            for line in pack.inlineCompletions.prefix(completionCap) {
                let trimmed = Self.clampInlineContinuation(line, maxWords: 12, maxChars: 90)
                let wordCount = trimmed.split(whereSeparator: { $0.isWhitespace }).count
                guard !trimmed.isEmpty, trimmed.count < 160, !trimmed.contains("?"), wordCount >= 3 else { continue }
                let insert = grammarAdjust(" \(trimmed)", after: ctx.typingFragment)
                let preview = insert.trimmingCharacters(in: .whitespacesAndNewlines)
                outInline.append(InlineSuggestion(
                    preview: preview,
                    confidence: completionConfidence,
                    mode: .completion(insertUTF16: insert),
                    chipRole: .predictedContinuation
                ))
            }

            let replaceLen = max(0, ctx.cursorUTF16 - ctx.clauseStartUTF16)
            for line in pack.clauseRewrites.prefix(2) {
                let trimmed = Self.clampClauseRewrite(line, maxWords: 22, maxChars: 140)
                let rewriteWords = trimmed.split(whereSeparator: { $0.isWhitespace }).count
                guard !trimmed.isEmpty, trimmed.count < 220, rewriteWords >= 5 else { continue }
                let shortPreview = trimmed.count > 56 ? String(trimmed.prefix(53)) + "…" : trimmed
                outInline.append(InlineSuggestion(
                    preview: "↺ \(shortPreview)",
                    confidence: rewriteConfidence,
                    mode: .replacement(location: ctx.clauseStartUTF16, length: replaceLen, replacementUTF16: trimmed),
                    chipRole: .clauseRewrite
                ))
            }

            let nudgeCap = hasInspiration ? 3 : 2
            for line in pack.nudges.prefix(nudgeCap) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, trimmed.count < 220 else { continue }
                let insert = blockPrefix + trimmed
                let shortPreview = trimmed.count > 60 ? String(trimmed.prefix(57)) + "…" : trimmed
                outNudges.append(InlineSuggestion(
                    preview: shortPreview,
                    confidence: nudgeConfidence,
                    mode: .completion(insertUTF16: insert),
                    chipRole: .nudge
                ))
            }

            if outInline.isEmpty && outNudges.isEmpty { return nil }
            return (outInline, outNudges)
        } catch {
            return nil
        }
    }
    #endif

    // MARK: - Workout Metric Suggestions

    private func workoutMetricSuggestions(ctx: SuggestionFocusContext, referenceDate: Date) -> [InlineSuggestion] {
        let triggerSpace = ctx.restrictTriggersToActiveParagraph ? ctx.activeParagraphLower : ctx.fullTextLower
        let lowerTyping = ctx.typingLower
        let sportPatterns: [(pattern: String, sports: [HKWorkoutActivityType])] = [
            ("cycl", [.cycling]),
            ("bike", [.cycling]),
            ("ride", [.cycling]),
            ("run", [.running]),
            ("jog", [.running]),
            ("swim", [.swimming]),
            ("walk", [.walking]),
            ("hik", [.hiking]),
            ("yoga", [.yoga]),
            ("row", [.rowing]),
            ("elliptical", [.elliptical]),
            ("strength", [.traditionalStrengthTraining, .functionalStrengthTraining]),
            ("lift", [.traditionalStrengthTraining]),
            ("weight", [.traditionalStrengthTraining]),
        ]

        let metricPatterns: [(pattern: String, extract: (WorkoutAnalytics, HKWorkout) -> String?)] = [
            ("power", { a, _ in
                let vals = a.powerSeries.map(\.1)
                guard !vals.isEmpty else { return nil }
                let avg = Int(vals.reduce(0, +) / Double(vals.count))
                let peak = Int(vals.max() ?? 0)
                return "averaging \(avg)W (peak \(peak)W)"
            }),
            ("heart rate", { a, _ in
                let hrs = a.heartRates.map(\.1)
                guard !hrs.isEmpty else { return nil }
                let avg = Int(hrs.reduce(0, +) / Double(hrs.count))
                return "averaging \(avg) bpm"
            }),
            ("hr", { a, _ in
                let hrs = a.heartRates.map(\.1)
                guard !hrs.isEmpty else { return nil }
                let avg = Int(hrs.reduce(0, +) / Double(hrs.count))
                return "averaging \(avg) bpm"
            }),
            ("cadence", { a, _ in
                let vals = a.cadenceSeries.map(\.1)
                guard !vals.isEmpty else { return nil }
                return "averaging \(Int(vals.reduce(0, +) / Double(vals.count))) rpm"
            }),
            ("pace", { a, _ in
                let speeds = a.speedSeries.map(\.1).filter { $0 > 0 }
                guard !speeds.isEmpty else { return nil }
                let avgSpeed = speeds.reduce(0, +) / Double(speeds.count)
                let paceSecsPerKm = Int(1000.0 / avgSpeed)
                return "\(paceSecsPerKm / 60):\(String(format: "%02d", paceSecsPerKm % 60)) /km"
            }),
            ("speed", { a, _ in
                let vals = a.speedSeries.map(\.1)
                guard !vals.isEmpty else { return nil }
                let avg = vals.reduce(0, +) / Double(vals.count) * 3.6
                return String(format: "averaging %.1f km/h", avg)
            }),
            ("calorie", { _, w in
                guard let kcal = w.totalEnergyBurned?.doubleValue(for: .kilocalorie()) else { return nil }
                return "\(Int(kcal)) kcal burned"
            }),
            ("distance", { _, w in
                guard let d = w.totalDistance?.doubleValue(for: .meter()) else { return nil }
                return d >= 1000 ? String(format: "%.2f km", d / 1000) : "\(Int(d)) m"
            }),
        ]

        let engine = HealthStateEngine.shared
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: referenceDate)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? referenceDate

        var results: [InlineSuggestion] = []

        for sp in sportPatterns where triggerSpace.contains(sp.pattern) || lowerTyping.contains(sp.pattern) {
            let workoutsForSport = engine.workoutAnalytics.filter { pair in
                pair.workout.startDate >= dayStart && pair.workout.startDate < dayEnd
                    && sp.sports.contains(pair.workout.workoutActivityType)
            }
            guard let pair = workoutsForSport.first else { continue }

            let hasSpecificMetric = metricPatterns.contains { lowerTyping.contains($0.pattern) }

            if hasSpecificMetric {
                for mp in metricPatterns where lowerTyping.contains(mp.pattern) {
                    if let desc = mp.extract(pair.analytics, pair.workout) {
                        results.append(completionChip(" is \(desc)", after: ctx.typingFragment, confidence: 0.9))

                        if let b = baselineString(pair: pair, metricExtract: mp.extract, days: 7, before: referenceDate, engine: engine) {
                            results.append(completionChip(" is \(b)", after: ctx.typingFragment, confidence: 0.8))
                        }

                        if let qual = qualitativeMetricPhrase(pair: pair, metricExtract: mp.extract, days: 7, before: referenceDate, engine: engine) {
                            results.append(completionChip(qual, after: ctx.typingFragment, confidence: 0.75))
                        }
                    }
                }
            }

            let openEndedPatterns = ["for", "and it", "which", "that was", "it was"]
            let isOpenEnded = !hasSpecificMetric || openEndedPatterns.contains(where: { lowerTyping.hasSuffix($0) || lowerTyping.contains("\($0) ") })

            if isOpenEnded || results.isEmpty {
                let dur = Int(pair.workout.duration / 60)
                let trailing = ctx.typingFragment

                if !ctx.fullTextLower.contains("\(dur) min") {
                    results.append(completionChip(" \(dur) minutes", after: trailing, confidence: 0.7))
                }

                if let d = pair.workout.totalDistance?.doubleValue(for: .meter()), d > 0 {
                    let distStr = d >= 1000 ? String(format: "%.1f km", d / 1000) : "\(Int(d)) m"
                    if !ctx.fullTextLower.contains("km") && !ctx.fullTextLower.contains("meter") {
                        results.append(completionChip(" \(distStr)", after: trailing, confidence: 0.68))
                    }
                }

                if let durationQual = qualitativeDurationPhrase(workout: pair.workout, days: 7, before: referenceDate, engine: engine) {
                    results.append(completionChip(durationQual, after: trailing, confidence: 0.65))
                }

                if let overallQual = qualitativeWorkoutPhrase(pair: pair, sportCount: workoutsForSport.count, days: 7, before: referenceDate, engine: engine) {
                    results.append(completionChip(overallQual, after: trailing, confidence: 0.6))
                }
            }
        }

        return results
    }

    // MARK: - Qualitative Suggestions

    private func qualitativeMetricPhrase(pair: (workout: HKWorkout, analytics: WorkoutAnalytics), metricExtract: (WorkoutAnalytics, HKWorkout) -> String?, days: Int, before: Date, engine: HealthStateEngine) -> String? {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: before))!
        let end = cal.startOfDay(for: before)
        let prior = engine.workoutAnalytics.filter { p in
            p.workout.startDate >= start && p.workout.startDate < end
                && p.workout.workoutActivityType == pair.workout.workoutActivityType
        }
        guard !prior.isEmpty else { return nil }
        guard let currentStr = metricExtract(pair.analytics, pair.workout),
              let currentNum = extractLeadingNumber(from: currentStr) else { return nil }
        let priorNums = prior.compactMap { p in metricExtract(p.analytics, p.workout).flatMap { extractLeadingNumber(from: $0) } }
        guard !priorNums.isEmpty else { return nil }
        let avg = priorNums.reduce(0, +) / Double(priorNums.count)
        guard avg > 0 else { return nil }
        let pct = ((currentNum - avg) / avg) * 100

        if pct > 20 { return " significantly higher than usual" }
        if pct > 5 { return " slightly above my average" }
        if pct < -20 { return " noticeably lower than usual" }
        if pct < -5 { return " a bit below my average" }
        return " right around my usual level"
    }

    private func qualitativeDurationPhrase(workout: HKWorkout, days: Int, before: Date, engine: HealthStateEngine) -> String? {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: before))!
        let end = cal.startOfDay(for: before)
        let prior = engine.workoutAnalytics.filter { p in
            p.workout.startDate >= start && p.workout.startDate < end
                && p.workout.workoutActivityType == workout.workoutActivityType
        }
        guard !prior.isEmpty else { return nil }
        let avgDur = prior.map { $0.workout.duration }.reduce(0, +) / Double(prior.count)
        guard avgDur > 0 else { return nil }
        let pct = ((workout.duration - avgDur) / avgDur) * 100

        if pct > 30 { return " an extended session" }
        if pct > 10 { return " a slightly longer session" }
        if pct < -30 { return " a quick session" }
        if pct < -10 { return " a shorter session than usual" }

        let isFrequent = prior.count >= 3
        if isFrequent { return " another solid session" }
        return " a typical session"
    }

    private func qualitativeWorkoutPhrase(pair: (workout: HKWorkout, analytics: WorkoutAnalytics), sportCount: Int, days: Int, before: Date, engine: HealthStateEngine) -> String? {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: before))!
        let end = cal.startOfDay(for: before)
        let prior = engine.workoutAnalytics.filter { p in
            p.workout.startDate >= start && p.workout.startDate < end
                && p.workout.workoutActivityType == pair.workout.workoutActivityType
        }

        let avgHR = pair.analytics.heartRates.map(\.1).reduce(0, +) / max(1, Double(pair.analytics.heartRates.count))
        if prior.isEmpty {
            if avgHR > 150 { return " pretty intense" }
            if avgHR > 120 { return " a moderate effort" }
            return " a light effort"
        }

        let priorAvgHRs = prior.compactMap { p -> Double? in
            let hrs = p.analytics.heartRates.map(\.1)
            guard !hrs.isEmpty else { return nil }
            return hrs.reduce(0, +) / Double(hrs.count)
        }
        guard !priorAvgHRs.isEmpty else { return nil }
        let baselineHR = priorAvgHRs.reduce(0, +) / Double(priorAvgHRs.count)
        guard baselineHR > 0 else { return nil }

        let hrPct = ((avgHR - baselineHR) / baselineHR) * 100
        if hrPct > 15 { return " pretty gruelling" }
        if hrPct > 5 { return " challenging" }
        if hrPct < -15 { return " a great light session" }
        if hrPct < -5 { return " a relaxed session" }
        return nil
    }

    private func baselineString(pair: (workout: HKWorkout, analytics: WorkoutAnalytics), metricExtract: (WorkoutAnalytics, HKWorkout) -> String?, days: Int, before: Date, engine: HealthStateEngine) -> String? {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: before))!
        let end = cal.startOfDay(for: before)
        let prior = engine.workoutAnalytics.filter { p in
            p.workout.startDate >= start && p.workout.startDate < end
                && p.workout.workoutActivityType == pair.workout.workoutActivityType
        }
        guard !prior.isEmpty else { return nil }

        guard let currentStr = metricExtract(pair.analytics, pair.workout),
              let currentNum = extractLeadingNumber(from: currentStr) else { return nil }

        let priorNums = prior.compactMap { p in
            metricExtract(p.analytics, p.workout).flatMap { extractLeadingNumber(from: $0) }
        }
        guard !priorNums.isEmpty else { return nil }
        let avg = priorNums.reduce(0, +) / Double(priorNums.count)
        guard avg > 0 else { return nil }
        let pct = ((currentNum - avg) / avg) * 100
        let direction = pct >= 0 ? "above" : "below"
        return String(format: "%+.0f%% %@ %dd baseline", pct, direction, days)
    }

    private func extractLeadingNumber(from s: String) -> Double? {
        let scanner = Scanner(string: s.replacingOccurrences(of: "averaging ", with: ""))
        return scanner.scanDouble()
    }

    // MARK: - Mood Suggestions

    private func moodSuggestions(ctx: SuggestionFocusContext) -> [InlineSuggestion] {
        let lowerTyping = ctx.typingLower
        let triggers = ["today is", "i feel", "feeling", "my mood", "i'm", "my day", "this day"]
        guard triggers.contains(where: { lowerTyping.contains($0) }) else { return [] }

        let trailing = ctx.typingFragment
        var results: [InlineSuggestion] = []

        if !cachedMoodStates.isEmpty {
            for state in cachedMoodStates.prefix(3) {
                let phrase = moodPhrase(from: state)
                results.append(completionChip(" \(phrase)", after: trailing, confidence: 0.85))
            }
        }

        let engine = HealthStateEngine.shared
        if engine.moodScore > 70 {
            results.append(completionChip(" a great day", after: trailing, confidence: 0.5))
        } else if engine.moodScore > 50 {
            results.append(completionChip(" a good day", after: trailing, confidence: 0.5))
        } else if engine.moodScore > 30 {
            results.append(completionChip(" an okay day", after: trailing, confidence: 0.5))
        } else {
            results.append(completionChip(" a tough day", after: trailing, confidence: 0.5))
        }

        return results
    }

    private func moodPhrase(from state: HKStateOfMind) -> String {
        let valence = state.valence
        let labels = state.labels
        let associations = state.associations

        let emotionWord: String
        if labels.contains(.happy) || labels.contains(.joyful) { emotionWord = "wonderful" }
        else if labels.contains(.content) || labels.contains(.satisfied) { emotionWord = "content" }
        else if labels.contains(.calm) || labels.contains(.peaceful) { emotionWord = "peaceful" }
        else if labels.contains(.excited) || labels.contains(.passionate) { emotionWord = "exciting" }
        else if labels.contains(.grateful) { emotionWord = "grateful" }
        else if labels.contains(.hopeful) || labels.contains(.brave) { emotionWord = "hopeful" }
        else if labels.contains(.proud) || labels.contains(.confident) { emotionWord = "proud" }
        else if labels.contains(.relieved) { emotionWord = "relieving" }
        else if labels.contains(.amazed) { emotionWord = "amazing" }
        else if labels.contains(.amused) { emotionWord = "fun" }
        else if labels.contains(.sad) || labels.contains(.lonely) { emotionWord = "melancholy" }
        else if labels.contains(.anxious) || labels.contains(.worried) { emotionWord = "anxious" }
        else if labels.contains(.stressed) || labels.contains(.overwhelmed) { emotionWord = "stressful" }
        else if labels.contains(.frustrated) || labels.contains(.angry) { emotionWord = "frustrating" }
        else if labels.contains(.drained) || labels.contains(.discouraged) { emotionWord = "draining" }
        else if labels.contains(.indifferent) { emotionWord = "neutral" }
        else if valence > 0.5 { emotionWord = "wonderful" }
        else if valence > 0 { emotionWord = "decent" }
        else if valence > -0.5 { emotionWord = "difficult" }
        else { emotionWord = "tough" }

        let contextWord: String?
        if associations.contains(.friends) { contextWord = "with friends" }
        else if associations.contains(.family) { contextWord = "with family" }
        else if associations.contains(.partner) { contextWord = "with my partner" }
        else if associations.contains(.work) { contextWord = "at work" }
        else if associations.contains(.fitness) { contextWord = "through fitness" }
        else if associations.contains(.health) { contextWord = "for my health" }
        else if associations.contains(.selfCare) { contextWord = "focused on self-care" }
        else if associations.contains(.hobbies) { contextWord = "enjoying hobbies" }
        else if associations.contains(.travel) { contextWord = "while traveling" }
        else if associations.contains(.education) { contextWord = "through learning" }
        else if associations.contains(.community) { contextWord = "in community" }
        else if associations.contains(.spirituality) { contextWord = "in reflection" }
        else if associations.contains(.dating) { contextWord = "on a date" }
        else if associations.contains(.weather) { contextWord = "with the weather" }
        else if associations.contains(.money) { contextWord = "regarding finances" }
        else if associations.contains(.currentEvents) { contextWord = "following the news" }
        else if associations.contains(.identity) { contextWord = "exploring identity" }
        else if associations.contains(.tasks) { contextWord = "getting things done" }
        else { contextWord = nil }

        if let ctx = contextWord {
            return "a \(emotionWord) day \(ctx)"
        }
        return "a \(emotionWord) day"
    }

    // MARK: - Sleep Suggestions

    private func sleepSuggestions(ctx: SuggestionFocusContext) -> [InlineSuggestion] {
        let lowerTyping = ctx.typingLower
        let triggers = ["my sleep", "i slept", "sleep was", "sleep is", "last night", "slept for", "hours of sleep"]
        guard triggers.contains(where: { lowerTyping.contains($0) }) else { return [] }

        let engine = HealthStateEngine.shared
        let trailing = ctx.typingFragment
        var results: [InlineSuggestion] = []

        if let hours = engine.sleepHours {
            results.append(completionChip(" \(String(format: "%.1f", hours)) hours", after: trailing, confidence: 0.85))
            if let baseline = engine.sleepBaseline7Day, baseline > 0 {
                let diff = hours - baseline
                let direction = diff >= 0 ? "above" : "below"
                results.append(completionChip(String(format: " %.1f hours (%+.1f %@ average)", hours, abs(diff), direction), after: trailing, confidence: 0.8))

                let pct = ((hours - baseline) / baseline) * 100
                if pct > 15 {
                    results.append(completionChip(" really well, more than usual", after: trailing, confidence: 0.65))
                } else if pct > 5 {
                    results.append(completionChip(" well, slightly above average", after: trailing, confidence: 0.65))
                } else if pct < -15 {
                    results.append(completionChip(" less than I needed", after: trailing, confidence: 0.65))
                } else if pct < -5 {
                    results.append(completionChip(" a bit less than usual", after: trailing, confidence: 0.65))
                } else {
                    results.append(completionChip(" about the right amount", after: trailing, confidence: 0.6))
                }
            }
        }

        return results
    }

    // MARK: - Recovery / HRV Suggestions

    private func recoverySuggestions(ctx: SuggestionFocusContext) -> [InlineSuggestion] {
        let lowerTyping = ctx.typingLower
        let triggers = ["my hrv", "recovery", "readiness", "how i feel", "my recovery", "body feels", "feeling recovered"]
        guard triggers.contains(where: { lowerTyping.contains($0) }) else { return [] }

        let engine = HealthStateEngine.shared
        let trailing = ctx.typingFragment
        var results: [InlineSuggestion] = []

        if lowerTyping.contains("hrv"), let hrv = engine.latestHRV {
            results.append(completionChip(" \(Int(hrv)) ms", after: trailing, confidence: 0.85))
            if let baseline = engine.hrvBaseline7Day, baseline > 0 {
                let pct = ((hrv - baseline) / baseline) * 100
                results.append(completionChip(String(format: " %d ms (%+.0f%% vs 7d)", Int(hrv), pct), after: trailing, confidence: 0.8))
            }
        }

        if lowerTyping.contains("recovery") {
            let score = Int(engine.recoveryScore)
            let label = score >= 70 ? "strong" : score >= 40 ? "moderate" : "low"
            results.append(completionChip(" score is \(score) (\(label))", after: trailing, confidence: 0.8))

            if score >= 70 {
                results.append(completionChip(" well-recovered and ready to push", after: trailing, confidence: 0.6))
            } else if score < 40 {
                results.append(completionChip(" still recovering, taking it easy", after: trailing, confidence: 0.6))
            }
        }

        if lowerTyping.contains("readiness") {
            let score = Int(engine.readinessScore)
            results.append(completionChip(" score is \(score)", after: trailing, confidence: 0.8))
        }

        return results
    }

    // MARK: - Vitals Suggestions

    private func vitalsSuggestions(ctx: SuggestionFocusContext) -> [InlineSuggestion] {
        let lowerTyping = ctx.typingLower
        let engine = HealthStateEngine.shared
        let trailing = ctx.typingFragment
        var results: [InlineSuggestion] = []

        if lowerTyping.contains("resting heart rate") || lowerTyping.contains("rhr") {
            if let rhr = engine.restingHeartRate {
                results.append(completionChip(" \(Int(rhr)) bpm", after: trailing, confidence: 0.85))
                if let baseline = engine.rhrBaseline7Day, baseline > 0 {
                    let diff = rhr - baseline
                    results.append(completionChip(String(format: " %d bpm (%+.0f vs 7d avg)", Int(rhr), diff), after: trailing, confidence: 0.8))
                }
            }
        }

        let vitalsTriggers: [(trigger: String, key: String, unit: String)] = [
            ("respiratory rate", "RespiratoryRate", "br/min"),
            ("spo2", "SpO2", "%"),
            ("oxygen", "SpO2", "%"),
            ("temperature", "WristTemp", "°C"),
            ("wrist temp", "WristTemp", "°C"),
        ]

        for vt in vitalsTriggers where lowerTyping.contains(vt.trigger) {
            if let summary = engine.vitalsSummary[vt.key], let current = summary.current {
                results.append(completionChip(" \(String(format: "%.1f", current)) \(vt.unit)", after: trailing, confidence: 0.8))
            }
        }

        return results
    }
}

// MARK: - Journal Stat Resolver

private enum JournalStatMetricKey: String, CaseIterable, Identifiable {
    case duration, heartRate, calories, hrr, power, cadence, speed, pace, elevationGain
    case verticalOscillation, groundContactTime, strideLength, strokeCount
    case zone1, zone2, zone3, zone4, zone5

    var id: String { rawValue }

    var title: String {
        switch self {
        case .duration: return "Duration"
        case .heartRate: return "Heart Rate"
        case .calories: return "Calories"
        case .hrr: return "HRR"
        case .power: return "Power"
        case .cadence: return "Cadence"
        case .speed: return "Speed"
        case .pace: return "Pace"
        case .elevationGain: return "Elevation Gain"
        case .verticalOscillation: return "Vertical Oscillation"
        case .groundContactTime: return "Ground Contact"
        case .strideLength: return "Stride Length"
        case .strokeCount: return "Stroke Count"
        case .zone1: return "Zone 1"
        case .zone2: return "Zone 2"
        case .zone3: return "Zone 3"
        case .zone4: return "Zone 4"
        case .zone5: return "Zone 5"
        }
    }

    var icon: String {
        switch self {
        case .duration: return "clock.fill"
        case .heartRate: return "heart.fill"
        case .calories: return "flame.fill"
        case .hrr: return "heart.text.square.fill"
        case .power: return "bolt.fill"
        case .cadence: return "gauge.with.dots.needle.bottom.50percent"
        case .speed: return "speedometer"
        case .pace: return "figure.run"
        case .elevationGain: return "mountain.2.fill"
        case .verticalOscillation: return "arrow.up.arrow.down"
        case .groundContactTime: return "shoe.fill"
        case .strideLength: return "ruler.fill"
        case .strokeCount: return "figure.pool.swim"
        case .zone1: return "heart.fill"
        case .zone2: return "heart.fill"
        case .zone3: return "heart.fill"
        case .zone4: return "waveform.path.ecg"
        case .zone5: return "flame.fill"
        }
    }

    var accentHue: Double {
        switch self {
        case .heartRate, .hrr, .zone4, .zone5: return 0
        case .power, .calories: return 30
        case .cadence, .speed, .pace: return 200
        case .duration: return 270
        case .elevationGain: return 120
        case .verticalOscillation, .groundContactTime, .strideLength: return 180
        case .strokeCount: return 210
        case .zone1: return 210
        case .zone2: return 140
        case .zone3: return 50
        }
    }
}

private enum JournalStatVariant: String, CaseIterable, Identifiable {
    case average, peak, total, pctFrom7d, pctFrom28d, quests

    var id: String { rawValue }

    var title: String {
        switch self {
        case .average: return "Average"
        case .peak: return "Peak"
        case .total: return "Total"
        case .pctFrom7d: return "% from 7d"
        case .pctFrom28d: return "% from 28d"
        case .quests: return "Quests"
        }
    }
}

private enum JournalStatResolver {
    static func availableMetrics(for activityType: HKWorkoutActivityType, analytics: WorkoutAnalytics) -> [JournalStatMetricKey] {
        var keys: [JournalStatMetricKey] = [.duration, .heartRate, .calories]
        if analytics.hrr1 != nil || analytics.hrr2 != nil { keys.append(.hrr) }
        if !analytics.powerSeries.isEmpty { keys.append(.power) }
        if !analytics.cadenceSeries.isEmpty { keys.append(.cadence) }
        if !analytics.speedSeries.isEmpty { keys.append(.speed) }
        if activityType == .running || activityType == .walking {
            if !analytics.speedSeries.isEmpty { keys.append(.pace) }
        }
        if analytics.elevationGain != nil { keys.append(.elevationGain) }
        if analytics.verticalOscillation != nil { keys.append(.verticalOscillation) }
        if analytics.groundContactTime != nil { keys.append(.groundContactTime) }
        if analytics.strideLength != nil { keys.append(.strideLength) }
        if !analytics.strokeCountSeries.isEmpty { keys.append(.strokeCount) }
        if !analytics.hrZoneBreakdown.isEmpty {
            for i in 1...min(5, analytics.hrZoneBreakdown.count) {
                if analytics.hrZoneBreakdown[i - 1].timeInZone > 0 {
                    switch i {
                    case 1: keys.append(.zone1)
                    case 2: keys.append(.zone2)
                    case 3: keys.append(.zone3)
                    case 4: keys.append(.zone4)
                    case 5: keys.append(.zone5)
                    default: break
                    }
                }
            }
        }
        return keys
    }

    static func availableVariants(for metric: JournalStatMetricKey) -> [JournalStatVariant] {
        switch metric {
        case .duration:
            return [.total, .pctFrom7d, .pctFrom28d]
        case .heartRate:
            return [.average, .peak, .pctFrom7d, .pctFrom28d]
        case .calories:
            return [.total, .pctFrom7d, .pctFrom28d]
        case .hrr:
            return [.average, .pctFrom7d, .pctFrom28d]
        case .power:
            return [.average, .peak, .pctFrom7d, .pctFrom28d, .quests]
        case .cadence:
            return [.average, .pctFrom7d, .pctFrom28d, .quests]
        case .speed:
            return [.average, .peak, .pctFrom7d, .pctFrom28d]
        case .pace:
            return [.average, .peak, .pctFrom7d, .pctFrom28d, .quests]
        case .elevationGain:
            return [.total, .pctFrom7d, .pctFrom28d]
        case .verticalOscillation, .groundContactTime, .strideLength:
            return [.average, .pctFrom7d, .pctFrom28d]
        case .strokeCount:
            return [.total, .average]
        case .zone1, .zone2, .zone3, .zone4, .zone5:
            return [.total, .pctFrom7d, .pctFrom28d, .quests]
        }
    }

    @MainActor
    static func resolve(
        metric: JournalStatMetricKey,
        variant: JournalStatVariant,
        workout: HKWorkout,
        analytics: WorkoutAnalytics,
        referenceDate: Date
    ) -> (value: String, subtitle: String) {
        let raw = rawValue(metric: metric, variant: variant, workout: workout, analytics: analytics, referenceDate: referenceDate)
        let sub = subtitle(metric: metric, variant: variant, workout: workout, analytics: analytics, referenceDate: referenceDate)
        return (raw, sub)
    }

    @MainActor
    private static func rawValue(metric: JournalStatMetricKey, variant: JournalStatVariant, workout: HKWorkout, analytics: WorkoutAnalytics, referenceDate: Date) -> String {
        if variant == .quests {
            return questValue(metric: metric, workout: workout, referenceDate: referenceDate)
        }

        let primary = primaryNumericValue(metric: metric, variant: variant, workout: workout, analytics: analytics)

        if variant == .pctFrom7d || variant == .pctFrom28d {
            let days = variant == .pctFrom7d ? 7 : 28
            let baseline = baselineAverage(metric: metric, sport: workout.workoutActivityType, days: days, before: referenceDate)
            guard let p = primary, let b = baseline, b > 0 else { return "—" }
            let pct = ((p - b) / b) * 100
            let sign = pct >= 0 ? "+" : ""
            return "\(sign)\(String(format: "%.0f", pct))%"
        }

        guard let p = primary else { return "—" }
        return formatNumeric(p, metric: metric)
    }

    @MainActor
    private static func subtitle(metric: JournalStatMetricKey, variant: JournalStatVariant, workout: HKWorkout, analytics: WorkoutAnalytics, referenceDate: Date) -> String {
        switch variant {
        case .pctFrom7d: return "vs 7-day baseline"
        case .pctFrom28d: return "vs 28-day baseline"
        case .quests: return questSubtitle(metric: metric, workout: workout, referenceDate: referenceDate)
        default:
            let days7 = baselineAverage(metric: metric, sport: workout.workoutActivityType, days: 7, before: referenceDate)
            if let b = days7 {
                return "7d avg: \(formatNumeric(b, metric: metric))"
            }
            return ""
        }
    }

    private static func primaryNumericValue(metric: JournalStatMetricKey, variant: JournalStatVariant, workout: HKWorkout, analytics: WorkoutAnalytics) -> Double? {
        switch metric {
        case .duration:
            return workout.duration / 60.0
        case .heartRate:
            let hrs = analytics.heartRates.map(\.1)
            guard !hrs.isEmpty else { return nil }
            return variant == .peak ? hrs.max() : hrs.reduce(0, +) / Double(hrs.count)
        case .calories:
            return workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
        case .hrr:
            return analytics.hrr2 ?? analytics.hrr1
        case .power:
            let vals = analytics.powerSeries.map(\.1)
            guard !vals.isEmpty else { return nil }
            return variant == .peak ? vals.max() : vals.reduce(0, +) / Double(vals.count)
        case .cadence:
            let vals = analytics.cadenceSeries.map(\.1)
            guard !vals.isEmpty else { return nil }
            return vals.reduce(0, +) / Double(vals.count)
        case .speed:
            let vals = analytics.speedSeries.map(\.1)
            guard !vals.isEmpty else { return nil }
            let v = variant == .peak ? vals.max()! : vals.reduce(0, +) / Double(vals.count)
            return v * 3.6
        case .pace:
            let vals = analytics.speedSeries.map(\.1).filter { $0 > 0 }
            guard !vals.isEmpty else { return nil }
            let avgSpeed = variant == .peak ? vals.max()! : vals.reduce(0, +) / Double(vals.count)
            guard avgSpeed > 0 else { return nil }
            return 1000.0 / avgSpeed / 60.0
        case .elevationGain:
            return analytics.elevationGain
        case .verticalOscillation:
            return analytics.verticalOscillation
        case .groundContactTime:
            return analytics.groundContactTime
        case .strideLength:
            return analytics.strideLength
        case .strokeCount:
            let vals = analytics.strokeCountSeries.map(\.1)
            guard !vals.isEmpty else { return nil }
            return variant == .total ? vals.last : vals.reduce(0, +) / Double(vals.count)
        case .zone1, .zone2, .zone3, .zone4, .zone5:
            let idx: Int
            switch metric {
            case .zone1: idx = 0; case .zone2: idx = 1; case .zone3: idx = 2
            case .zone4: idx = 3; case .zone5: idx = 4; default: return nil
            }
            guard idx < analytics.hrZoneBreakdown.count else { return nil }
            return analytics.hrZoneBreakdown[idx].timeInZone / 60.0
        }
    }

    @MainActor
    private static func baselineAverage(metric: JournalStatMetricKey, sport: HKWorkoutActivityType, days: Int, before date: Date) -> Double? {
        let engine = HealthStateEngine.shared
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: date))!
        let end = cal.startOfDay(for: date)
        let matching = engine.workoutAnalytics.filter { pair in
            pair.workout.startDate >= start && pair.workout.startDate < end
                && pair.workout.workoutActivityType == sport
        }
        guard !matching.isEmpty else { return nil }
        let vals: [Double] = matching.compactMap { pair in
            primaryNumericValue(metric: metric, variant: .average, workout: pair.workout, analytics: pair.analytics)
        }
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }

    @MainActor
    private static func questValue(metric: JournalStatMetricKey, workout: HKWorkout, referenceDate: Date) -> String {
        let quests = relevantQuests(metric: metric, workout: workout, referenceDate: referenceDate)
        guard !quests.isEmpty else { return "None" }
        return "\(quests.count) completed"
    }

    @MainActor
    private static func questSubtitle(metric: JournalStatMetricKey, workout: HKWorkout, referenceDate: Date) -> String {
        let quests = relevantQuests(metric: metric, workout: workout, referenceDate: referenceDate)
        guard !quests.isEmpty else { return "No matching quests" }
        let grouped = Dictionary(grouping: quests, by: { "\($0.role.rawValue) \($0.goal.rawValue)" })
        var parts: [String] = []
        for (_, recs) in grouped.sorted(by: { $0.value.count > $1.value.count }).prefix(3) {
            guard let first = recs.first else { continue }
            let roleName = first.role.rawValue
            let goalName = first.goal.rawValue
            let totalMin = recs.reduce(0) { $0 + $1.minutes }
            let repeats = recs.reduce(0) { $0 + $1.repeats }
            if repeats > 1 {
                parts.append("\(recs.count) sets of \(roleName) \(goalName) (\(repeats) x \(totalMin / max(repeats, 1)) min)")
            } else {
                parts.append("\(recs.count)x \(roleName) \(goalName) for \(totalMin) min")
            }
        }
        return parts.joined(separator: ", ")
    }

    @MainActor
    private static func relevantQuests(metric: JournalStatMetricKey, workout: HKWorkout, referenceDate: Date) -> [StageQuestRecord] {
        let store = StageQuestStore.shared
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: referenceDate)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
        let sportName = workout.workoutActivityType.name.lowercased().replacingOccurrences(of: " ", with: "-")
        let all = store.quests(forSport: sportName, from: dayStart, to: dayEnd)
        let goalKey: String
        switch metric {
        case .power: goalKey = "power"
        case .cadence: goalKey = "cadence"
        case .pace: goalKey = "pace"
        case .zone1, .zone2, .zone3, .zone4, .zone5: goalKey = "heartRateZone"
        default: return all
        }
        return all.filter { $0.goalRawValue == goalKey }
    }

    private static func formatNumeric(_ value: Double, metric: JournalStatMetricKey) -> String {
        switch metric {
        case .duration:
            let h = Int(value) / 60
            let m = Int(value) % 60
            return h > 0 ? "\(h)h \(m)m" : "\(m) min"
        case .heartRate, .hrr:
            return "\(Int(value)) bpm"
        case .calories:
            return "\(Int(value)) kcal"
        case .power:
            return "\(Int(value)) W"
        case .cadence:
            return "\(Int(value)) rpm"
        case .speed:
            return String(format: "%.1f km/h", value)
        case .pace:
            let totalSecs = Int(value * 60)
            return "\(totalSecs / 60):\(String(format: "%02d", totalSecs % 60)) /km"
        case .elevationGain:
            return "\(Int(value)) m"
        case .verticalOscillation:
            return String(format: "%.1f cm", value)
        case .groundContactTime:
            return "\(Int(value)) ms"
        case .strideLength:
            return String(format: "%.2f m", value)
        case .strokeCount:
            return "\(Int(value))"
        case .zone1, .zone2, .zone3, .zone4, .zone5:
            return "\(Int(value)) min"
        }
    }
}

// MARK: - Achievement Card Views

private struct JournalStatCardView: View {
    let card: JournalStatCard
    let onResize: (JournalStatCard.CardSize) -> Void
    let onDelete: () -> Void

    private var accent: Color { Color(hue: card.accentHue / 360.0, saturation: 0.7, brightness: 0.9) }

    var body: some View {
        Group {
            switch card.size {
            case .small:
                smallCard
            case .medium:
                mediumCard
            case .large:
                largeCard
            }
        }
        .contextMenu {
            Menu("Resize") {
                Button("Small") { onResize(.small) }
                Button("Medium") { onResize(.medium) }
                Button("Large") { onResize(.large) }
            }
            Button(role: .destructive) { onDelete() } label: { Label("Remove", systemImage: "trash") }
        }
    }

    private var smallCard: some View {
        VStack(spacing: 4) {
            Image(systemName: card.icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(accent)
            Text(card.value)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(card.title.uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(accent.opacity(0.2), lineWidth: 1))
    }

    private var mediumCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: card.icon)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(accent)
                    .frame(width: 32, height: 32)
                    .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Spacer()
            }
            Text(card.value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
            Text(card.title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            if !card.subtitle.isEmpty {
                Text(card.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(accent.opacity(0.16), lineWidth: 1))
    }

    private var largeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: card.icon)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(accent)
                    .frame(width: 40, height: 40)
                    .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(card.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Spacer()
                Text(card.value)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(accent)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(accent.opacity(0.16), lineWidth: 1))
    }
}

private struct JournalStatCardsGrid: View {
    let cards: [JournalStatCard]
    let onResize: (UUID, JournalStatCard.CardSize) -> Void
    let onDelete: (UUID) -> Void

    var body: some View {
        if !cards.isEmpty {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(cards) { card in
                    JournalStatCardView(
                        card: card,
                        onResize: { newSize in onResize(card.id, newSize) },
                        onDelete: { onDelete(card.id) }
                    )
                    .gridCellColumns(card.size == .large ? 2 : 1)
                }
            }
        }
    }
}

// MARK: - Editor

struct JournalEditorView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var entry: JournalEntry
    var onSave: (JournalEntry) -> Void
    @State private var referenceDate: Date = Date()

    // Stats picker state
    @State private var selectedWorkoutIndex: Int? = nil
    @State private var selectedMetric: JournalStatMetricKey? = nil
    @State private var selectedVariant: JournalStatVariant? = nil
    @State private var selectedCardSize: JournalStatCard.CardSize = .medium
    @State private var showStatPicker = false

    // Inline suggestion engine
    @StateObject private var suggestionEngine = JournalInlineSuggestionEngine()
    @State private var activeSuggestionField: SuggestionField = .content
    @State private var contentSelection = NSRange(location: 0, length: 0)
    @State private var inspirationSelection = NSRange(location: 0, length: 0)
    @State private var journalInlineAssistantExpanded = true
    @State private var journalNudgesAssistantExpanded = true
    @State private var isGeneratingAITitle = false
    /// Start of this editor presentation; used to log Mindful Minutes on dismiss.
    @State private var journalMindfulSessionStart: Date?
    private enum SuggestionField { case content, inspiration }

    private var trimmedReflection: String {
        entry.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Enough body text to infer a meaningful title.
    private var hasSufficientContentForTitleSuggestion: Bool {
        let t = trimmedReflection
        guard t.count >= 48 else { return false }
        let words = t.split { $0.isWhitespace || $0.isNewline }.filter { !$0.isEmpty }
        return words.count >= 10
    }

    // Correlation detection
    @StateObject private var correlationEngine = JournalCorrelationEngine()
    @State private var editingCorrelationInJournal: EmotionCorrelation? = nil
    @State private var showAddCorrelationInJournal = false

    #if canImport(JournalingSuggestions) && !targetEnvironment(macCatalyst)
    @State private var showingSuggestions = false
    #endif

    private var supportsJournalingSuggestions: Bool {
        #if canImport(JournalingSuggestions) && !targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }

    private var isFitnessReport: Bool { entry.kind == "workout_report" }

    /// Collapsible assistant rows save vertical space on iPhone.
    private var journalAssistantSectionsCollapsible: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    @MainActor
    private var todaysWorkouts: [(workout: HKWorkout, analytics: WorkoutAnalytics)] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: referenceDate)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? referenceDate
        return HealthStateEngine.shared.workoutAnalytics.filter { pair in
            pair.workout.startDate >= dayStart && pair.workout.startDate < dayEnd
        }.sorted { $0.workout.startDate < $1.workout.startDate }
    }
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    private let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private static let timeOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
    
    private func generateHealthSnapshot() -> String {
        let engine = HealthStateEngine.shared
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        var lines: [String] = ["--- Health Snapshot ---", "Date: \(formatter.string(from: Date()))"]
        if let hrv = engine.latestHRV { lines.append("HRV: \(Int(hrv)) ms") }
        if let rhr = engine.restingHeartRate { lines.append("RHR: \(Int(rhr)) bpm") }
        if let sleep = engine.sleepHours { lines.append("Sleep: \(String(format: "%.1f", sleep)) hrs") }
        lines.append("Recovery: \(Int(engine.recoveryScore))")
        lines.append("Readiness: \(Int(engine.readinessScore))")
        lines.append("-----------------------")
        return "\n" + lines.joined(separator: "\n") + "\n"
    }

    private func fallbackTitleFromReflection(_ content: String) -> String {
        let firstSentence = content.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? content
        let words = firstSentence.split { $0.isWhitespace || $0.isNewline }.prefix(10)
        let joined = words.joined(separator: " ")
        if joined.count <= 80 { return joined }
        return String(joined.prefix(77)).trimmingCharacters(in: .whitespaces) + "…"
    }

    @MainActor
    private func generateSuggestedTitle() async {
        let raw = trimmedReflection
        guard raw.count >= 48 else { return }

        isGeneratingAITitle = true
        defer { isGeneratingAITitle = false }

        let inspirationSnippet = entry.inspiration.trimmingCharacters(in: .whitespacesAndNewlines)

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel(useCase: .general)
            if model.isAvailable {
                do {
                    let session = LanguageModelSession(
                        model: model,
                        instructions: """
                        Propose a short diary title: 2–10 words, natural language, no quotation marks, no emoji, no trailing period unless part of a name.
                        Capture the main theme or moment. Use proper nouns from the text when important.
                        """
                    )
                    let body = String(raw.prefix(3500))
                    let prompt: String
                    if inspirationSnippet.isEmpty {
                        prompt = "Reflection text:\n\(body)"
                    } else {
                        prompt = """
                        Reflection text:
                        \(body)

                        Imported inspiration / context (for names, places, events):
                        \(String(inspirationSnippet.prefix(2000)))
                        """
                    }
                    let response = try await session.respond(to: prompt, generating: JournalAITitleOutput.self)
                    let t = response.content.suggestedTitle
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: #"^[\"']|[\"']$"#, with: "", options: .regularExpression)
                    if !t.isEmpty, t.count <= 120 {
                        entry.title = t
                        return
                    }
                } catch {}
            }
        }
        #endif

        let fallback = fallbackTitleFromReflection(raw)
        if !fallback.isEmpty { entry.title = fallback }
    }

    #if canImport(JournalingSuggestions) && !targetEnvironment(macCatalyst)
    private func downloadImagesFromSuggestion(_ suggestion: JournalingSuggestion) async -> [Data] {
        let imageURLs = await imageURLs(from: suggestion)
        var downloadedImages: [Data] = []
        
        for url in imageURLs {
            guard let data = try? Data(contentsOf: url),
                  UIImage(data: data) != nil else {
                continue
            }
            
            downloadedImages.append(data)
        }
        
        return downloadedImages
    }
    
    private func importSuggestion(_ suggestion: JournalingSuggestion) async -> SuggestionImport {
        async let inspirationText = inspirationText(from: suggestion)
        async let images = downloadImagesFromSuggestion(suggestion)
        
        return await SuggestionImport(
            text: inspirationText,
            imageData: images
        )
    }
    
    private func imageURLs(from suggestion: JournalingSuggestion) async -> [URL] {
        var urls: [URL] = []
        
        let photos = await suggestion.content(forType: JournalingSuggestion.Photo.self)
        urls.append(contentsOf: photos.map(\.photo))
        
        let livePhotos = await suggestion.content(forType: JournalingSuggestion.LivePhoto.self)
        urls.append(contentsOf: livePhotos.map(\.image))
        
        let motionActivities = await suggestion.content(forType: JournalingSuggestion.MotionActivity.self)
        urls.append(contentsOf: motionActivities.compactMap(\.icon))
        
        let workouts = await suggestion.content(forType: JournalingSuggestion.Workout.self)
        urls.append(contentsOf: workouts.compactMap(\.icon))
        
        let workoutGroups = await suggestion.content(forType: JournalingSuggestion.WorkoutGroup.self)
        urls.append(contentsOf: workoutGroups.compactMap(\.icon))
        
        let contacts = await suggestion.content(forType: JournalingSuggestion.Contact.self)
        urls.append(contentsOf: contacts.compactMap(\.photo))
        
        let songs = await suggestion.content(forType: JournalingSuggestion.Song.self)
        urls.append(contentsOf: songs.compactMap(\.artwork))
        
        let podcasts = await suggestion.content(forType: JournalingSuggestion.Podcast.self)
        urls.append(contentsOf: podcasts.compactMap(\.artwork))
        
        if #available(iOS 18.0, *) {
            let statesOfMind = await suggestion.content(forType: JournalingSuggestion.StateOfMind.self)
            urls.append(contentsOf: statesOfMind.compactMap(\.icon))
            
            let media = await suggestion.content(forType: JournalingSuggestion.GenericMedia.self)
            urls.append(contentsOf: media.compactMap(\.appIcon))
        }
        
        if #available(iOS 26.0, *) {
            let eventPosters = await suggestion.content(forType: JournalingSuggestion.EventPoster.self)
            urls.append(contentsOf: eventPosters.compactMap(\.image))
        }
        
        return Array(Set(urls))
    }
    
    private func inspirationText(from suggestion: JournalingSuggestion) async -> String {
        var sections: [String] = []
        
        sections.append(section(
            title: "Suggestion",
            lines: [
                "Title: \(suggestion.title)",
                detailLine("Date", value: suggestion.date.map(format(dateInterval:)))
            ]
        ))
        
        let contacts = await suggestion.content(forType: JournalingSuggestion.Contact.self)
        sections.append(contentsOf: contacts.map(format(contact:)))
        
        let photos = await suggestion.content(forType: JournalingSuggestion.Photo.self)
        sections.append(contentsOf: photos.map(format(photo:)))
        
        let livePhotos = await suggestion.content(forType: JournalingSuggestion.LivePhoto.self)
        sections.append(contentsOf: livePhotos.map(format(livePhoto:)))
        
        let videos = await suggestion.content(forType: JournalingSuggestion.Video.self)
        sections.append(contentsOf: videos.map(format(video:)))
        
        let locations = await suggestion.content(forType: JournalingSuggestion.Location.self)
        sections.append(contentsOf: locations.map(format(location:)))
        
        let locationGroups = await suggestion.content(forType: JournalingSuggestion.LocationGroup.self)
        sections.append(contentsOf: locationGroups.map(format(locationGroup:)))
        
        let motionActivities = await suggestion.content(forType: JournalingSuggestion.MotionActivity.self)
        sections.append(contentsOf: motionActivities.map(format(motionActivity:)))
        
        let podcasts = await suggestion.content(forType: JournalingSuggestion.Podcast.self)
        sections.append(contentsOf: podcasts.map(format(podcast:)))
        
        let reflections = await suggestion.content(forType: JournalingSuggestion.Reflection.self)
        sections.append(contentsOf: reflections.map(format(reflection:)))
        
        let songs = await suggestion.content(forType: JournalingSuggestion.Song.self)
        sections.append(contentsOf: songs.map(format(song:)))
        
        let workouts = await suggestion.content(forType: JournalingSuggestion.Workout.self)
        sections.append(contentsOf: workouts.map(format(workout:)))
        
        let workoutGroups = await suggestion.content(forType: JournalingSuggestion.WorkoutGroup.self)
        sections.append(contentsOf: workoutGroups.map(format(workoutGroup:)))
        
        if #available(iOS 18.0, *) {
            let statesOfMind = await suggestion.content(forType: JournalingSuggestion.StateOfMind.self)
            sections.append(contentsOf: statesOfMind.map(format(stateOfMind:)))
            
            let genericMedia = await suggestion.content(forType: JournalingSuggestion.GenericMedia.self)
            sections.append(contentsOf: genericMedia.map(format(genericMedia:)))
        }
        
        if #available(iOS 26.0, *) {
            let eventPosters = await suggestion.content(forType: JournalingSuggestion.EventPoster.self)
            sections.append(contentsOf: eventPosters.map(format(eventPoster:)))
        }
        
        return sections
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
    
    private func section(title: String, lines: [String?]) -> String {
        let body = lines.compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        
        guard !body.isEmpty else { return "" }
        return ([title] + body).joined(separator: "\n")
    }
    
    private func detailLine(_ label: String, value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return "\(label): \(value)"
    }
    
    private func mergeInspiration(existing: String, imported: String) -> String {
        [existing.trimmingCharacters(in: .whitespacesAndNewlines),
         imported.trimmingCharacters(in: .whitespacesAndNewlines)]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
    
    private func format(photo: JournalingSuggestion.Photo) -> String {
        section(title: "Photo", lines: [
            detailLine("Date", value: photo.date.map(format(date:))),
            detailLine("Asset", value: photo.photo.lastPathComponent)
        ])
    }
    
    private func format(video: JournalingSuggestion.Video) -> String {
        section(title: "Video", lines: [
            detailLine("Date", value: video.date.map(format(date:))),
            detailLine("Video", value: video.url.lastPathComponent)
        ])
    }
    
    private func format(livePhoto: JournalingSuggestion.LivePhoto) -> String {
        section(title: "Live Photo", lines: [
            detailLine("Date", value: livePhoto.date.map(format(date:))),
            detailLine("Image", value: livePhoto.image.lastPathComponent),
            detailLine("Video", value: livePhoto.video.lastPathComponent)
        ])
    }
    
    private func format(contact: JournalingSuggestion.Contact) -> String {
        section(title: "Contact", lines: [
            detailLine("Name", value: contact.name),
            detailLine("Photo", value: contact.photo?.lastPathComponent)
        ])
    }
    
    private func format(location: JournalingSuggestion.Location) -> String {
        var lines: [String?] = [
            detailLine("Place", value: location.place),
            detailLine("City", value: location.city),
            detailLine("Coordinates", value: format(coordinate: location.location?.coordinate)),
            detailLine("Date", value: location.date.map(format(date:)))
        ]
        
        if #available(iOS 26.0, *) {
            lines.append(detailLine("Map Item Identifier", value: location.mapKitItemIdentifier.map { String(describing: $0) }))
            lines.append(detailLine("Is Work Location", value: location.isWorkLocation.map(boolLabel)))
        }
        
        return section(title: "Location", lines: lines)
    }
    
    private func format(locationGroup: JournalingSuggestion.LocationGroup) -> String {
        let locations = locationGroup.locations.enumerated().map { index, location in
            let summaryParts = [
                location.place,
                location.city,
                format(coordinate: location.location?.coordinate)
            ].compactMap { $0 }
            
            return "\(index + 1). \(summaryParts.joined(separator: " | "))"
        }
        
        return section(title: "Location Group", lines: [
            detailLine("Count", value: "\(locationGroup.locations.count)"),
            locations.isEmpty ? nil : "Locations:",
            locations.isEmpty ? nil : locations.joined(separator: "\n")
        ])
    }
    
    private func format(motionActivity: JournalingSuggestion.MotionActivity) -> String {
        return section(title: "Motion Activity", lines: [
            detailLine("Steps", value: "\(motionActivity.steps)"),
            detailLine("Date", value: motionActivity.date.map(format(dateInterval:)))
        ])
    }
    
    private func format(podcast: JournalingSuggestion.Podcast) -> String {
        section(title: "Podcast", lines: [
            detailLine("Episode", value: podcast.episode),
            detailLine("Show", value: podcast.show),
            detailLine("Date", value: podcast.date.map(format(date:)))
        ])
    }
    
    private func format(reflection: JournalingSuggestion.Reflection) -> String {
        section(title: "Reflection", lines: [
            detailLine("Prompt", value: reflection.prompt),
            detailLine("Color", value: reflection.color.map { String(describing: $0) })
        ])
    }
    
    private func format(song: JournalingSuggestion.Song) -> String {
        section(title: "Song", lines: [
            detailLine("Song", value: song.song),
            detailLine("Artist", value: song.artist),
            detailLine("Album", value: song.album),
            detailLine("Date", value: song.date.map(format(date:)))
        ])
    }
    
    private func format(workout: JournalingSuggestion.Workout) -> String {
        let route = workout.route ?? []
        return section(title: "Workout", lines: [
            detailLine("Name", value: workout.details?.localizedName),
            detailLine("Date", value: workout.details?.date.map(format(dateInterval:))),
            detailLine("Calories", value: format(energy: workout.details?.activeEnergyBurned)),
            detailLine("Distance", value: format(distance: workout.details?.distance)),
            detailLine("Avg Heart Rate", value: format(heartRate: workout.details?.averageHeartRate)),
            detailLine("Route Points", value: route.isEmpty ? nil : "\(route.count)"),
            detailLine("Route Distance", value: route.isEmpty ? nil : format(distanceMeters: routeDistance(route))),
            detailLine("Route Start", value: route.first.flatMap { format(coordinate: $0.coordinate) }),
            detailLine("Route End", value: route.last.flatMap { format(coordinate: $0.coordinate) })
        ])
    }
    
    private func format(workoutGroup: JournalingSuggestion.WorkoutGroup) -> String {
        let workoutSummaries = workoutGroup.workouts.enumerated().map { index, workout in
            let title = workout.details?.localizedName ?? "Workout"
            let date = workout.details?.date.map(format(dateInterval:)) ?? "Unknown date"
            return "\(index + 1). \(title) | \(date)"
        }
        
        return section(title: "Workout Group", lines: [
            detailLine("Sessions", value: "\(workoutGroup.workouts.count)"),
            detailLine("Duration", value: workoutGroup.duration.flatMap(format(duration:))),
            detailLine("Calories", value: format(energy: workoutGroup.activeEnergyBurned)),
            detailLine("Avg Heart Rate", value: format(heartRate: workoutGroup.averageHeartRate)),
            workoutSummaries.isEmpty ? nil : "Workouts:",
            workoutSummaries.isEmpty ? nil : workoutSummaries.joined(separator: "\n")
        ])
    }
    
    @available(iOS 18.0, *)
    private func format(stateOfMind: JournalingSuggestion.StateOfMind) -> String {
        let state = stateOfMind.state
        return section(title: "State of Mind", lines: [
            detailLine("Date", value: format(date: state.startDate)),
            detailLine("Kind", value: String(describing: state.kind)),
            detailLine("Valence", value: String(format: "%.2f", state.valence)),
            detailLine("Classification", value: String(describing: state.valenceClassification)),
            detailLine("Labels", value: state.labels.isEmpty ? nil : state.labels.map { String(describing: $0) }.joined(separator: ", ")),
            detailLine("Associations", value: state.associations.isEmpty ? nil : state.associations.map { String(describing: $0) }.joined(separator: ", "))
        ])
    }
    
    @available(iOS 18.0, *)
    private func format(genericMedia: JournalingSuggestion.GenericMedia) -> String {
        section(title: "Media", lines: [
            detailLine("Title", value: genericMedia.title),
            detailLine("Artist", value: genericMedia.artist),
            detailLine("Album", value: genericMedia.album),
            detailLine("Date", value: genericMedia.date.map(format(date:)))
        ])
    }
    
    @available(iOS 26.0, *)
    private func format(eventPoster: JournalingSuggestion.EventPoster) -> String {
        section(title: "Event", lines: [
            detailLine("Title", value: String(eventPoster.title.characters)),
            detailLine("Place", value: eventPoster.placeName),
            detailLine("Start", value: eventPoster.eventStart.map(format(date:))),
            detailLine("End", value: eventPoster.eventEnd.map(format(date:))),
            detailLine("Host", value: eventPoster.isHost.map(boolLabel))
        ])
    }
    
    private func format(date: Date) -> String {
        dateFormatter.string(from: date)
    }
    
    private func format(dateInterval: DateInterval) -> String {
        "\(format(date: dateInterval.start)) - \(format(date: dateInterval.end))"
    }
    
    private func format(duration: TimeInterval) -> String? {
        durationFormatter.string(from: duration)
    }
    
    private func format(energy: HKQuantity?) -> String? {
        guard let energy else { return nil }
        return "\(Int(energy.doubleValue(for: .kilocalorie()))) kcal"
    }
    
    private func format(distance: HKQuantity?) -> String? {
        guard let distance else { return nil }
        return format(distanceMeters: distance.doubleValue(for: .meter()))
    }
    
    private func format(distanceMeters: Double) -> String {
        if distanceMeters >= 1000 {
            return String(format: "%.2f km", distanceMeters / 1000)
        }
        
        return String(format: "%.0f m", distanceMeters)
    }
    
    private func format(heartRate: HKQuantity?) -> String? {
        guard let heartRate else { return nil }
        let unit = HKUnit.count().unitDivided(by: .minute())
        return String(format: "%.0f bpm", heartRate.doubleValue(for: unit))
    }
    
    private func format(coordinate: CLLocationCoordinate2D?) -> String? {
        guard let coordinate else { return nil }
        return String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
    }
    
    private func routeDistance(_ route: [CLLocation]) -> Double {
        guard route.count > 1 else { return 0 }
        
        return zip(route, route.dropFirst()).reduce(0) { partialResult, points in
            partialResult + points.0.distance(from: points.1)
        }
    }
    
    private func boolLabel(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }
    #endif

    private func flushJournalEditorMindfulSession() {
        guard let start = journalMindfulSessionStart else { return }
        journalMindfulSessionStart = nil
        let end = Date()
        HealthKitManager().saveMindfulSession(start: start, end: end, completion: nil)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                editorBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        // Title + Date + Kind Toggle
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                TextField("Untitled entry", text: $entry.title)
                                    .font(.system(.largeTitle, design: .serif, weight: .bold))
                                    .foregroundStyle(.primary)

                                if hasSufficientContentForTitleSuggestion {
                                    Button {
                                        Task { await generateSuggestedTitle() }
                                    } label: {
                                        Group {
                                            if isGeneratingAITitle {
                                                ProgressView()
                                                    .controlSize(.small)
                                            } else {
                                                Image(systemName: "wand.and.stars")
                                                    .font(.title3.weight(.semibold))
                                            }
                                        }
                                        .frame(width: 36, height: 36)
                                        .background(Color.orange.opacity(0.18), in: Circle())
                                        .overlay(Circle().stroke(Color.orange.opacity(0.35), lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(isGeneratingAITitle)
                                    .accessibilityLabel("Suggest title from reflection")
                                    .help("Suggest a title from your reflection")
                                }
                            }

                            HStack(spacing: 12) {
                                Text(entry.date.formatted(.dateTime.weekday(.wide).month().day().hour().minute()))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                Spacer()

                                Menu {
                                    Button { withAnimation { entry.kind = "standard" } } label: {
                                        Label("Entry", systemImage: "book.pages")
                                    }
                                    Button { withAnimation { entry.kind = "workout_report" } } label: {
                                        Label("Fitness Report", systemImage: "figure.run")
                                    }
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: isFitnessReport ? "figure.run" : "book.pages")
                                        Text(isFitnessReport ? "Fitness Report" : "Entry")
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.system(size: 8, weight: .bold))
                                    }
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(isFitnessReport ? Color.orange : Color.primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        (isFitnessReport ? Color.orange.opacity(0.16) : Color.white.opacity(0.1)),
                                        in: Capsule()
                                    )
                                    .overlay(Capsule().stroke(
                                        isFitnessReport ? Color.orange.opacity(0.25) : Color.white.opacity(0.12),
                                        lineWidth: 1
                                    ))
                                }
                            }
                        }

                        // Reflection
                        journalEditorSection(
                            title: "Reflection",
                            subtitle: "Write like you're speaking to yourself, not filling out a form."
                        ) {
                            VStack(alignment: .leading, spacing: 10) {
                                #if canImport(UIKit)
                                JournalSelectableTextEditor(text: $entry.content, selection: $contentSelection) { text, range in
                                    activeSuggestionField = .content
                                    suggestionEngine.textDidChange(
                                        text,
                                        selection: range,
                                        referenceDate: referenceDate,
                                        isFitnessReport: isFitnessReport,
                                        inspirationContext: entry.inspiration
                                    )
                                    let combined = text + " " + entry.inspiration
                                    correlationEngine.analyzeText(combined, journalEntryID: entry.id, referenceDate: referenceDate)
                                }
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 260)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 6)
                                #else
                                TextEditor(text: $entry.content)
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 260)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 6)
                                    .onChange(of: entry.content) { _, newValue in
                                        activeSuggestionField = .content
                                        let r = NSRange(location: (newValue as NSString).length, length: 0)
                                        suggestionEngine.textDidChange(
                                            newValue,
                                            selection: r,
                                            referenceDate: referenceDate,
                                            isFitnessReport: isFitnessReport,
                                            inspirationContext: entry.inspiration
                                        )
                                        let combined = newValue + " " + entry.inspiration
                                        correlationEngine.analyzeText(combined, journalEntryID: entry.id, referenceDate: referenceDate)
                                    }
                                #endif

                                if activeSuggestionField == .content && hasJournalAssistantChips {
                                    Divider().opacity(0.35)
                                    journalAssistantBars { selected in
                                        let (newText, newSel) = suggestionEngine.apply(selected, to: entry.content, selection: contentSelection)
                                        entry.content = newText
                                        contentSelection = newSel
                                    }
                                }
                            }
                        }

                        // Stats (Fitness Report only)
                        if isFitnessReport {
                            statsSection
                        }

                        // Inspiration
                        journalEditorSection(
                            title: "Inspiration",
                            subtitle: "Imported prompts, places, workouts, and memories live here."
                        ) {
                            HStack {
                                Text("Suggestions layer")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("Imported from Suggestions")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if !entry.inspiration.isEmpty || !entry.imageData.isEmpty {
                                InspirationSectionView(
                                    inspiration: entry.inspiration,
                                    imageData: entry.imageData
                                )
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                #if canImport(UIKit)
                                JournalSelectableTextEditor(text: $entry.inspiration, selection: $inspirationSelection) { text, range in
                                    activeSuggestionField = .inspiration
                                    suggestionEngine.textDidChange(
                                        text,
                                        selection: range,
                                        referenceDate: referenceDate,
                                        isFitnessReport: isFitnessReport,
                                        inspirationContext: entry.inspiration
                                    )
                                }
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 220)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 6)
                                #else
                                TextEditor(text: $entry.inspiration)
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 220)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 6)
                                    .onChange(of: entry.inspiration) { _, newValue in
                                        activeSuggestionField = .inspiration
                                        let r = NSRange(location: (newValue as NSString).length, length: 0)
                                        suggestionEngine.textDidChange(
                                            newValue,
                                            selection: r,
                                            referenceDate: referenceDate,
                                            isFitnessReport: isFitnessReport,
                                            inspirationContext: entry.inspiration
                                        )
                                    }
                                #endif

                                if activeSuggestionField == .inspiration && hasJournalAssistantChips {
                                    Divider().opacity(0.35)
                                    journalAssistantBars { selected in
                                        let (newText, newSel) = suggestionEngine.apply(selected, to: entry.inspiration, selection: inspirationSelection)
                                        entry.inspiration = newText
                                        inspirationSelection = newSel
                                    }
                                }
                            }

                            Text("You can refine imported inspiration here. New inspiration is still added through Journaling Suggestions.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // Detected Correlations
                        if !correlationEngine.detectedCorrelations.isEmpty
                            || !CorrelationStore.shared.correlations(forJournal: entry.id).isEmpty
                            || !correlationEngine.suggestedPeople.isEmpty
                            || !correlationEngine.correlationClarifiers.isEmpty {
                            journalEditorSection(
                                title: "Detected Correlations",
                                subtitle: "Emotions, people, and quick checks to sharpen what we spotted."
                            ) {
                                VStack(alignment: .leading, spacing: 14) {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            let displayed = correlationEngine.detectedCorrelations.isEmpty
                                                ? CorrelationStore.shared.correlations(forJournal: entry.id)
                                                : correlationEngine.detectedCorrelations

                                            ForEach(displayed) { corr in
                                                correlationBubble(corr)
                                            }

                                            Button {
                                                showAddCorrelationInJournal = true
                                            } label: {
                                                Image(systemName: "plus")
                                                    .font(.caption.weight(.bold))
                                                    .foregroundStyle(.secondary)
                                                    .frame(width: 32, height: 32)
                                                    .background(.ultraThinMaterial, in: Circle())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(.vertical, 4)
                                    }

                                    if !correlationEngine.suggestedPeople.isEmpty {
                                        journalPersonDisambiguationBlock
                                    }
                                    if !correlationEngine.correlationClarifiers.isEmpty {
                                        journalClarifierFollowUpsBlock
                                    }
                                }
                            }
                        }

                        // Stat cards for non-editor display (they also show in the editor below stats section)
                        if !entry.statCards.isEmpty && !isFitnessReport {
                            JournalStatCardsGrid(
                                cards: entry.statCards,
                                onResize: { id, size in resizeCard(id: id, to: size) },
                                onDelete: { id in deleteCard(id: id) }
                            )
                        }

                        // Saved Nudges
                        if !entry.savedNudges.isEmpty {
                            journalEditorSection(
                                title: "Saved Nudges",
                                subtitle: "Nudges you used as inspiration for this entry."
                            ) {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(entry.savedNudges) { nudge in
                                        HStack(spacing: 10) {
                                            Image(systemName: "bookmark.fill")
                                                .font(.caption2)
                                                .foregroundStyle(.blue)
                                            Text(nudge.text)
                                                .font(.caption.weight(.medium))
                                                .foregroundStyle(.primary)
                                            Spacer()
                                            Button {
                                                withAnimation { entry.savedNudges.removeAll { $0.id == nudge.id } }
                                            } label: {
                                                Image(systemName: "xmark")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                        }

                        // Backbone Outline
                        if !suggestionEngine.backboneOutline.isEmpty {
                            journalEditorSection(
                                title: "Entry Outline",
                                subtitle: "AI-detected structure of your entry. Helps the assistant know where you are."
                            ) {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(Array(suggestionEngine.backboneOutline.enumerated()), id: \.element.id) { idx, section in
                                        HStack(alignment: .top, spacing: 8) {
                                            Text("\(idx + 1)")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.orange)
                                                .frame(width: 20, alignment: .trailing)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(section.label)
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(.primary)
                                                if !section.themes.isEmpty {
                                                    Text(section.themes.joined(separator: " · "))
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 18)
                    .padding(.bottom, 120)
                }
            }
            .navigationTitle("Journal Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        entry.date = Date()
                        onSave(entry)

                        // Persist detected correlations (merge user association overrides)
                        let correlationsToSave = correlationEngine.detectedCorrelations.map { corr in
                            var mutable = corr
                            mutable.journalEntryID = entry.id
                            if let raw = entry.correlationAssociationOverrides[corr.id],
                               let assoc = NutrivanceAssociation(rawValue: raw) {
                                mutable.association = assoc
                            }
                            return mutable
                        }
                        CorrelationStore.shared.appendBatch(correlationsToSave)

                        dismiss()
                    }
                    .fontWeight(.semibold)
                }

                ToolbarItemGroup(placement: .bottomBar) {
                    #if canImport(JournalingSuggestions) && !targetEnvironment(macCatalyst)
                    if supportsJournalingSuggestions {
                        Button {
                            showingSuggestions = true
                        } label: {
                            Label("Suggestions", systemImage: "sparkles")
                        }
                    }
                    #endif

                    Spacer()

                    Button {
                        if entry.content.isEmpty {
                            entry.content = generateHealthSnapshot()
                        } else {
                            entry.content += "\n" + generateHealthSnapshot()
                        }
                        contentSelection = NSRange(location: (entry.content as NSString).length, length: 0)
                    } label: {
                        Label("Health Snapshot", systemImage: "heart.text.square")
                    }
                }
            }
            .onAppear {
                if journalMindfulSessionStart == nil {
                    journalMindfulSessionStart = Date()
                }
                suggestionEngine.prepare(referenceDate: referenceDate)
                let cLen = (entry.content as NSString).length
                contentSelection = NSRange(location: cLen, length: 0)
                let iLen = (entry.inspiration as NSString).length
                inspirationSelection = NSRange(location: iLen, length: 0)
            }
            .onChange(of: suggestionEngine.pinnedNudge?.id) { _, newID in
                if newID != nil { journalNudgesAssistantExpanded = true }
            }
            .onDisappear {
                flushJournalEditorMindfulSession()
            }
            #if canImport(JournalingSuggestions) && !targetEnvironment(macCatalyst)
            .sheet(isPresented: $showingSuggestions) {
                if supportsJournalingSuggestions {
                    JournalingSuggestionsPicker("What's on your mind?") { suggestion in
                        Task {
                            let importedSuggestion = await importSuggestion(suggestion)

                            await MainActor.run {
                                if entry.title.isEmpty {
                                    entry.title = suggestion.title
                                }

                                if let dateInterval = suggestion.date {
                                    referenceDate = dateInterval.end
                                }

                                entry.inspiration = mergeInspiration(
                                    existing: entry.inspiration,
                                    imported: importedSuggestion.text
                                )

                                for image in importedSuggestion.imageData where !entry.imageData.contains(image) {
                                    entry.imageData.append(image)
                                }

                                activeSuggestionField = .content
                                suggestionEngine.textDidChange(
                                    entry.content,
                                    selection: contentSelection,
                                    referenceDate: referenceDate,
                                    isFitnessReport: isFitnessReport,
                                    inspirationContext: entry.inspiration
                                )

                                showingSuggestions = false
                            }
                        }
                    }
                } else {
                    Text("Journaling Suggestions are unavailable on Mac Catalyst.")
                        .padding()
                }
            }
            #endif
            .sheet(isPresented: $showAddCorrelationInJournal) {
                AddCorrelationSheet { correlation in
                    var c = correlation
                    c.journalEntryID = entry.id
                    correlationEngine.detectedCorrelations.append(c)
                }
            }
            .sheet(item: $editingCorrelationInJournal) { correlation in
                EditCorrelationSheet(correlation: correlation) { updated in
                    if let idx = correlationEngine.detectedCorrelations.firstIndex(where: { $0.id == updated.id }) {
                        correlationEngine.detectedCorrelations[idx] = updated
                    }
                }
            }
        }
    }

    // MARK: - Correlation Bubble

    @ViewBuilder
    private func correlationBubble(_ corr: EmotionCorrelation) -> some View {
        let color = corr.valenceCategory.color
        HStack(spacing: 6) {
            Image(systemName: emotionIcon(for: corr.emotionLabel))
                .font(.caption2)
                .foregroundStyle(color)
            Text(corr.emotionLabel.capitalized)
                .font(.caption2.weight(.semibold))
            Text(corr.association.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(color.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 1))
        .contextMenu {
            Button {
                editingCorrelationInJournal = corr
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                correlationEngine.detectedCorrelations.removeAll { $0.id == corr.id }
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    // MARK: - Person Disambiguation

    @ViewBuilder
    private var journalPersonDisambiguationBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("People Mentioned")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            ForEach(correlationEngine.suggestedPeople) { person in
                HStack(spacing: 10) {
                    Image(systemName: "person.fill.questionmark")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.name)
                            .font(.caption.weight(.semibold))
                        if !person.mentionContext.isEmpty {
                            Text(person.mentionContext)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    if let existing = entry.personRelationshipHints[person.name.lowercased()] {
                        Text(existing.capitalized)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.12), in: Capsule())
                    }
                    Menu {
                        ForEach(["Friend", "Family", "Teacher", "Classmate", "Coworker", "Partner", "Mentor", "Other"], id: \.self) { role in
                            Button {
                                withAnimation {
                                    entry.personRelationshipHints[person.name.lowercased()] = role.lowercased()
                                }
                            } label: {
                                Text(role)
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.down.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Follow-Up Clarifiers

    @ViewBuilder
    private var journalClarifierFollowUpsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Checks")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            ForEach(correlationEngine.correlationClarifiers) { clarifier in
                VStack(alignment: .leading, spacing: 8) {
                    Text(clarifier.question)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    
                    let stableKey = "\(clarifier.question.prefix(40))_\(clarifier.choices.count)"
                    let selectedIdx = entry.journalClarifierAnswers[stableKey]

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(clarifier.choices.enumerated()), id: \.offset) { idx, choice in
                                let isSelected = selectedIdx == idx
                                Button {
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        entry.journalClarifierAnswers[stableKey] = idx
                                        applyClarifierAnswer(clarifier, choiceIndex: idx)
                                    }
                                } label: {
                                    Text(choice)
                                        .font(.caption2.weight(isSelected ? .bold : .medium))
                                        .foregroundStyle(isSelected ? .white : .primary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            isSelected ? Color.blue : Color.clear,
                                            in: Capsule()
                                        )
                                        .background(.ultraThinMaterial, in: Capsule())
                                        .overlay(Capsule().stroke(Color.blue.opacity(isSelected ? 0 : 0.3), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
            }
        }
    }

    private func applyClarifierAnswer(_ clarifier: JournalCorrelationClarifier, choiceIndex: Int) {
        guard choiceIndex < clarifier.associationKeys.count else { return }
        let key = clarifier.associationKeys[choiceIndex]
        guard key != "skip", let assoc = NutrivanceAssociation(rawValue: key) else { return }

        for corrID in clarifier.targetCorrelationIDs {
            if let idx = correlationEngine.detectedCorrelations.firstIndex(where: { $0.id == corrID }) {
                correlationEngine.detectedCorrelations[idx].association = assoc
            }
            entry.correlationAssociationOverrides[corrID] = key
        }

        if let person = clarifier.linkedPersonName?.lowercased(), !person.isEmpty {
            let roleMap: [String: String] = ["friends": "friend", "family": "family", "partner": "partner", "work": "coworker", "education": "teacher"]
            if let role = roleMap[key] {
                entry.personRelationshipHints[person] = role
            }
        }
    }

    // MARK: - Editor Background

    @ViewBuilder
    private var editorBackground: some View {
        JournalMeshPhaseBackground(style: isFitnessReport ? .burning : .spirit)
    }

    // MARK: - Stats Section

    @ViewBuilder
    private var statsSection: some View {
        journalEditorSection(
            title: "Stats",
            subtitle: "Add workout metrics as achievement cards."
        ) {
            // Workout picker
            if todaysWorkouts.isEmpty {
                Text("No workouts found for this day.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(todaysWorkouts.enumerated()), id: \.offset) { idx, pair in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedWorkoutIndex = (selectedWorkoutIndex == idx) ? nil : idx
                                    selectedMetric = nil
                                    selectedVariant = nil
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: workoutIcon(pair.workout.workoutActivityType))
                                        .font(.caption2.weight(.bold))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(pair.workout.workoutActivityType.name)
                                            .font(.caption.weight(.semibold))
                                        Text("\(Self.timeOnlyFormatter.string(from: pair.workout.startDate))–\(Self.timeOnlyFormatter.string(from: pair.workout.endDate))")
                                            .font(.system(size: 9))
                                    }
                                }
                                .foregroundStyle(selectedWorkoutIndex == idx ? Color.white : Color.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    selectedWorkoutIndex == idx ? Color.orange : Color.white.opacity(0.08),
                                    in: Capsule()
                                )
                                .overlay(Capsule().stroke(Color.orange.opacity(selectedWorkoutIndex == idx ? 0.5 : 0.15), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Metric picker (after workout selection)
            if let wIdx = selectedWorkoutIndex, wIdx < todaysWorkouts.count {
                let pair = todaysWorkouts[wIdx]
                let metrics = JournalStatResolver.availableMetrics(for: pair.workout.workoutActivityType, analytics: pair.analytics)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Metric")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(metrics) { m in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        selectedMetric = (selectedMetric == m) ? nil : m
                                        selectedVariant = nil
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: m.icon)
                                            .font(.system(size: 10, weight: .bold))
                                        Text(m.title)
                                            .font(.caption2.weight(.semibold))
                                    }
                                    .foregroundStyle(selectedMetric == m ? Color.white : Color.primary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(selectedMetric == m ? Color.orange : Color.white.opacity(0.06), in: Capsule())
                                    .overlay(Capsule().stroke(Color.orange.opacity(selectedMetric == m ? 0.4 : 0.12), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // Variant + Size picker
                if let metric = selectedMetric {
                    let variants = JournalStatResolver.availableVariants(for: metric)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Value")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(variants) { v in
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            selectedVariant = (selectedVariant == v) ? nil : v
                                        }
                                    } label: {
                                        Text(v.title)
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(selectedVariant == v ? Color.white : Color.primary)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 7)
                                            .background(selectedVariant == v ? Color.orange : Color.white.opacity(0.06), in: Capsule())
                                            .overlay(Capsule().stroke(Color.orange.opacity(selectedVariant == v ? 0.4 : 0.12), lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    if selectedVariant != nil {
                        HStack(spacing: 10) {
                            Text("Size")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Picker("", selection: $selectedCardSize) {
                                Text("S").tag(JournalStatCard.CardSize.small)
                                Text("M").tag(JournalStatCard.CardSize.medium)
                                Text("L").tag(JournalStatCard.CardSize.large)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 140)

                            Spacer()

                            Button {
                                addStatCard()
                            } label: {
                                Label("Add", systemImage: "plus.circle.fill")
                                    .font(.caption.weight(.bold))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                        }
                    }
                }
            }

            // Achievement cards grid
            if !entry.statCards.isEmpty {
                JournalStatCardsGrid(
                    cards: entry.statCards,
                    onResize: { id, size in resizeCard(id: id, to: size) },
                    onDelete: { id in deleteCard(id: id) }
                )
            }
        }
    }

    // MARK: - Inline Suggestions

    private func inlineSuggestionIcon(_ suggestion: InlineSuggestion) -> String {
        if suggestion.mode.isReplacement || suggestion.chipRole == .clauseRewrite {
            return "arrow.triangle.2.circlepath"
        }
        switch suggestion.chipRole {
        case .predictedContinuation: return "brain.head.profile"
        case .nudge: return "questionmark.bubble"
        case .caretContinuation: return "text.cursor"
        case .clauseRewrite: return "text.cursor"
        }
    }

    private func inlineSuggestionIconTint(_ suggestion: InlineSuggestion) -> Color {
        if suggestion.mode.isReplacement || suggestion.chipRole == .clauseRewrite {
            return .purple
        }
        switch suggestion.chipRole {
        case .predictedContinuation: return .orange
        case .nudge: return .blue
        case .caretContinuation, .clauseRewrite: return .orange
        }
    }

    private var hasJournalAssistantChips: Bool {
        !suggestionEngine.suggestions.isEmpty || !suggestionEngine.nudgeSuggestions.isEmpty || suggestionEngine.pinnedNudge != nil
    }

    @ViewBuilder
    private func suggestionChipScroll(
        suggestions: [InlineSuggestion],
        stroke: Color,
        onSelect: @escaping (InlineSuggestion) -> Void
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions) { suggestion in
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            onSelect(suggestion)
                            suggestionEngine.clear()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: inlineSuggestionIcon(suggestion))
                                .font(.caption2)
                                .foregroundStyle(inlineSuggestionIconTint(suggestion))
                            Text(suggestion.preview)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(stroke.opacity(0.35), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder
    private func journalAssistantCollapsibleHeader(title: String, expanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { expanded.wrappedValue.toggle() }
        } label: {
            HStack {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: expanded.wrappedValue ? "chevron.up" : "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(expanded.wrappedValue ? "expanded" : "collapsed")")
    }

    @ViewBuilder
    private func journalAssistantBars(onSelect: @escaping (InlineSuggestion) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !suggestionEngine.suggestions.isEmpty {
                if journalAssistantSectionsCollapsible {
                    journalAssistantCollapsibleHeader(title: "Inline suggestions", expanded: $journalInlineAssistantExpanded)
                    if journalInlineAssistantExpanded {
                        suggestionChipScroll(suggestions: suggestionEngine.suggestions, stroke: .orange, onSelect: onSelect)
                    }
                } else {
                    suggestionChipScroll(suggestions: suggestionEngine.suggestions, stroke: .orange, onSelect: onSelect)
                }
            }

            if let pinned = suggestionEngine.pinnedNudge {
                if journalAssistantSectionsCollapsible {
                    journalAssistantCollapsibleHeader(title: "Nudges", expanded: $journalNudgesAssistantExpanded)
                    if journalNudgesAssistantExpanded {
                        pinnedNudgeCard(pinned, onSelect: onSelect)
                    }
                } else {
                    pinnedNudgeCard(pinned, onSelect: onSelect)
                }
            } else if !suggestionEngine.nudgeSuggestions.isEmpty {
                if journalAssistantSectionsCollapsible {
                    journalAssistantCollapsibleHeader(title: "Nudges", expanded: $journalNudgesAssistantExpanded)
                    if journalNudgesAssistantExpanded {
                        nudgeCardsRow(showSectionTitle: false)
                    }
                } else {
                    nudgeCardsRow(showSectionTitle: true)
                }
            }
        }
    }

    @ViewBuilder
    private func nudgeCardsRow(showSectionTitle: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if showSectionTitle {
                Text("Nudges")
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 10)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(suggestionEngine.nudgeSuggestions) { nudge in
                        nudgeCard(nudge, onTap: {
                            suggestionEngine.pinNudge(nudge)
                        })
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private enum JournalNudgeCardMetrics {
        static let width: CGFloat = 200
        static let minHeight: CGFloat = 128
    }

    @ViewBuilder
    private func nudgeCard(_ nudge: InlineSuggestion, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "questionmark.bubble")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                Text(nudge.preview)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(
                minWidth: JournalNudgeCardMetrics.width,
                maxWidth: JournalNudgeCardMetrics.width,
                minHeight: JournalNudgeCardMetrics.minHeight,
                alignment: .topLeading
            )
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.blue.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func pinnedNudgeCard(_ nudge: InlineSuggestion, onSelect: @escaping (InlineSuggestion) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "pin.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.blue)
                Text("Pinned Nudge")
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    suggestionEngine.unpinNudge()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text(nudge.preview)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button {
                    entry.savedNudges.append(JournalSavedNudge(text: nudge.preview))
                    suggestionEngine.unpinNudge()
                } label: {
                    Label("Save", systemImage: "bookmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)

                Button {
                    onSelect(nudge)
                    suggestionEngine.unpinNudge()
                } label: {
                    Label("Insert", systemImage: "text.insert")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.blue.opacity(0.35), lineWidth: 1.5)
        )
        .padding(.horizontal, 6)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    // MARK: - Helpers

    @MainActor
    private func addStatCard() {
        guard let wIdx = selectedWorkoutIndex, wIdx < todaysWorkouts.count,
              let metric = selectedMetric, let variant = selectedVariant else { return }
        let pair = todaysWorkouts[wIdx]
        let resolved = JournalStatResolver.resolve(
            metric: metric, variant: variant,
            workout: pair.workout, analytics: pair.analytics,
            referenceDate: referenceDate
        )
        let variantLabel = variant == .average || variant == .peak || variant == .total ? "\(variant.title) " : ""
        let card = JournalStatCard(
            icon: metric.icon,
            title: "\(variantLabel)\(metric.title)",
            value: resolved.value,
            subtitle: resolved.subtitle,
            size: selectedCardSize,
            accentHue: metric.accentHue
        )
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            entry.statCards.append(card)
        }
        selectedMetric = nil
        selectedVariant = nil
    }

    private func resizeCard(id: UUID, to size: JournalStatCard.CardSize) {
        guard let idx = entry.statCards.firstIndex(where: { $0.id == id }) else { return }
        let old = entry.statCards[idx]
        let resized = JournalStatCard(icon: old.icon, title: old.title, value: old.value, subtitle: old.subtitle, size: size, accentHue: old.accentHue)
        withAnimation { entry.statCards[idx] = resized }
    }

    private func deleteCard(id: UUID) {
        withAnimation { entry.statCards.removeAll { $0.id == id } }
    }

    private func workoutIcon(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .cycling: return "bicycle"
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .swimming: return "figure.pool.swim"
        case .hiking: return "figure.hiking"
        default: return "figure.mixed.cardio"
        }
    }

    @ViewBuilder
    private func journalEditorSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            content()
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
