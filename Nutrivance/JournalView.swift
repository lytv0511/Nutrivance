import Foundation
import SwiftUI
#if canImport(JournalingSuggestions)
import JournalingSuggestions
#endif
import HealthKit
import CoreLocation

struct JournalEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var content: String
    var inspiration: String
    var date: Date
    var imageData: [Data] = []
    var kind: String
    var reportMetrics: [WorkoutReportMetric]
    
    init(title: String = "", content: String = "") {
        self.id = UUID()
        self.title = title
        self.content = content
        self.inspiration = ""
        self.date = Date()
        self.imageData = []
        self.kind = "standard"
        self.reportMetrics = []
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case content
        case inspiration
        case date
        case imageData
        case kind
        case reportMetrics
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
    }
}

private func isFitnessReportEntry(_ entry: JournalEntry) -> Bool {
    entry.kind == "workout_report" || !entry.reportMetrics.isEmpty
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
        let lhsSignal = lhs.content.count + lhs.inspiration.count + lhs.imageData.count * 100 + lhs.reportMetrics.count * 10
        let rhsSignal = rhs.content.count + rhs.inspiration.count + rhs.imageData.count * 100 + rhs.reportMetrics.count * 10
        return rhsSignal >= lhsSignal ? rhs : lhs
    }

    static func appendWorkoutReport(title: String, content: String, date: Date = Date()) {
        var entries = loadEntries()
        var entry = JournalEntry(title: title, content: content)
        entry.date = date
        entry.kind = "workout_report"
        entry.reportMetrics = WorkoutReportNLPParser.parseMetrics(from: content)
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
                            Image(systemName: metric.icon)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.orange)
                                .frame(width: 34, height: 34)
                                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
    inspiration
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
                                    .frame(width: compact ? 148 : 188, height: compact ? 108 : 148)
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
                .frame(height: compact ? 112 : 152)
            }
            
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(cards) { card in
                    InspirationCardView(card: card)
                }
            }
        }
    }
}

struct JournalView: View {
    @State private var animationPhase: Double = 0
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
                withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                    animationPhase = 20
                }
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
        if filter == .reports {
            ZStack {
                GradientBackgrounds().burningGradient(animationPhase: $animationPhase)
                Color.black.opacity(0.22)
            }
            .ignoresSafeArea()
        } else {
            GradientBackgrounds().spiritGradient(animationPhase: $animationPhase)
                .ignoresSafeArea()
        }
    }
    
    func saveEntry(_ entry: JournalEntry) {
        if let index = entries.firstIndex(where: {$0.id == entry.id}) {
            entries[index] = entry
        } else {
            entries.insert(entry, at: 0)
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

        let imageHintText = entry.imageData.isEmpty ? "" : "photo image inspiration memory picture"
        let haystack = [
            entry.title,
            entry.content,
            entry.inspiration,
            entry.kind,
            metricText,
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
                        .font(.headline.weight(.bold))
                        .foregroundStyle(isFitnessReportEntry(entry) ? Color.orange : Color.white.opacity(0.82))
                        .frame(width: 42, height: 42)
                        .background(
                            (isFitnessReportEntry(entry) ? Color.orange.opacity(0.14) : Color.white.opacity(0.08)),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                }

                if !entry.content.isEmpty {
                    Text(entry.content)
                        .lineLimit(8)
                        .foregroundStyle(.secondary)
                }

                if isFitnessReportEntry(entry) {
                    WorkoutReportMetricsWall(metrics: entry.reportMetrics)
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

struct JournalEditorView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var entry: JournalEntry
    var onSave: (JournalEntry) -> Void
    @State private var editorAnimationPhase: Double = 0

    #if canImport(JournalingSuggestions)
    @State private var showingSuggestions = false
    #endif
    
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
    
    private func generateHealthSnapshot() -> String {
        // Placeholder snapshot (can later connect to HealthStateEngine)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        
        return """
        
        --- Health Snapshot ---
        Date: \(formatter.string(from: Date()))
        Feel‑Good Score: —
        HRV: —
        Sleep: —
        Mood: —
        -----------------------
        
        """
    }
    
    #if canImport(JournalingSuggestions)
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
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackgrounds().spiritGradient(animationPhase: $editorAnimationPhase)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("Untitled entry", text: $entry.title)
                                .font(.system(.largeTitle, design: .serif, weight: .bold))
                                .foregroundStyle(.primary)

                            Text(entry.date.formatted(.dateTime.weekday(.wide).month().day().hour().minute()))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        journalEditorSection(
                            title: "Reflection",
                            subtitle: "Write like you're speaking to yourself, not filling out a form."
                        ) {
                            TextEditor(text: $entry.content)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 260)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 6)
                        }

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

                            TextEditor(text: $entry.inspiration)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 220)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 6)

                            Text("You can refine imported inspiration here. New inspiration is still added through Journaling Suggestions.")
                                .font(.caption)
                                .foregroundColor(.secondary)
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
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        entry.date = Date()
                        onSave(entry)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }

                ToolbarItemGroup(placement: .bottomBar) {
                    #if canImport(JournalingSuggestions)
                    Button {
                        showingSuggestions = true
                    } label: {
                        Label("Suggestions", systemImage: "sparkles")
                    }
                    #endif

                    Spacer()

                    Button {
                        if entry.content.isEmpty {
                            entry.content = generateHealthSnapshot()
                        } else {
                            entry.content += "\n" + generateHealthSnapshot()
                        }
                    } label: {
                        Label("Health Snapshot", systemImage: "heart.text.square")
                    }
                }
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                    editorAnimationPhase = 20
                }
            }
            #if canImport(JournalingSuggestions)
            .sheet(isPresented: $showingSuggestions) {
                JournalingSuggestionsPicker("What's on your mind?") { suggestion in
                    Task {
                        let importedSuggestion = await importSuggestion(suggestion)

                        await MainActor.run {
                            if entry.title.isEmpty {
                                entry.title = suggestion.title
                            }

                            entry.inspiration = mergeInspiration(
                                existing: entry.inspiration,
                                imported: importedSuggestion.text
                            )

                            for image in importedSuggestion.imageData where !entry.imageData.contains(image) {
                                entry.imageData.append(image)
                            }

                            showingSuggestions = false
                        }
                    }
                }
            }
            #endif
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
