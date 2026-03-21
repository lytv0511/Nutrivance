import Foundation
import SwiftUI
#if canImport(JournalingSuggestions)
import JournalingSuggestions
#endif
import HealthKit
import CoreLocation

struct JournalEntry: Identifiable, Codable {
    let id: UUID
    var title: String
    var content: String
    var inspiration: String
    var date: Date
    var imageData: [Data] = []
    
    init(title: String = "", content: String = "") {
        self.id = UUID()
        self.title = title
        self.content = content
        self.inspiration = ""
        self.date = Date()
        self.imageData = []
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case content
        case inspiration
        case date
        case imageData
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        inspiration = try container.decodeIfPresent(String.self, forKey: .inspiration) ?? ""
        date = try container.decode(Date.self, forKey: .date)
        imageData = try container.decodeIfPresent([Data].self, forKey: .imageData) ?? []
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(content, forKey: .content)
        try container.encode(inspiration, forKey: .inspiration)
        try container.encode(date, forKey: .date)
        try container.encode(imageData, forKey: .imageData)
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
            return .mint
        case "location", "location group":
            return .blue
        case "state of mind", "reflection":
            return .pink
        case "podcast", "song", "generic media":
            return .purple
        case "photo", "live photo", "video", "event poster":
            return .teal
        case "contact":
            return .indigo
        default:
            return .green
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent.gradient)
                    .frame(width: 10, height: 10)
                Text(card.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            
            ForEach(card.lines, id: \.self) { line in
                if line.hasSuffix(":") {
                    Text(line)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.top, 2)
                } else if let separatorIndex = line.firstIndex(of: ":") {
                    let label = String(line[..<separatorIndex])
                    let valueStart = line.index(after: separatorIndex)
                    let value = String(line[valueStart...]).trimmingCharacters(in: .whitespaces)
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(
                    LinearGradient(
                        colors: [
                            accent.opacity(0.18),
                            Color(uiColor: .secondarySystemBackground)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(accent.opacity(0.18), lineWidth: 1)
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
                InspirationImageStrip(
                    imageData: imageData,
                    thumbnailSize: compact ? 72 : 100
                )
                .frame(height: compact ? 78 : 110)
            }
            
            if compact {
                ForEach(cards) { card in
                    InspirationCardView(card: card)
                }
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(cards) { card in
                        InspirationCardView(card: card)
                    }
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
    

    private var journalFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("journal_entries.json")
    }
    
    var body: some View {
        NavigationStack {
            
            ZStack {
                
                GradientBackgrounds().spiritGradient(animationPhase: $animationPhase)
                    .ignoresSafeArea()
                    .onAppear {
                        loadEntries()
                        withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                            animationPhase = 20
                        }
                    }
                
                if entries.isEmpty {
                    
                    VStack(spacing: 12) {
                        Image(systemName: "book.closed")
                            .font(.largeTitle)
                        Text("No Journal Entries Yet")
                            .font(.headline)
                        Text("Tap + to start writing")
                            .foregroundColor(.secondary)
                    }
                    
                } else {
                    
                    List {
                        ForEach(entries) { entry in
                            Button {
                                currentEntry = entry
                                showingEditor = true
                            } label: {
                                VStack(alignment: .leading) {
                                    
                                    Text(entry.title.isEmpty ? "Untitled Entry" : entry.title)
                                        .font(.headline)
                                    
                                    Text(entry.date, style: .date)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    if !entry.content.isEmpty {
                                        Text(entry.content)
                                            .lineLimit(10)
                                            .foregroundColor(.secondary)
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
                                        .padding(.top, 6)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .onDelete(perform: deleteEntry)
                    }
                    .scrollContentBackground(.hidden)
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
            
            .sheet(isPresented: $showingEditor) {
                JournalEditorView(
                    entry: $currentEntry,
                    onSave: { entry in
                        saveEntry(entry)
                    }
                )
            }
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
    
    func persistEntries() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: journalFileURL, options: [.atomic])
        } catch {
            print("Failed to save journal entries:", error)
        }
    }
    
    func loadEntries() {
        do {
            let data = try Data(contentsOf: journalFileURL)
            let decoded = try JSONDecoder().decode([JournalEntry].self, from: data)
            entries = decoded
        } catch {
            entries = []
        }
    }
}

struct JournalEditorView: View {
    
    @Environment(\.dismiss) var dismiss
    
    @Binding var entry: JournalEntry
    
    var onSave: (JournalEntry) -> Void
    
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
        var lines: [String?] = [
            detailLine("Steps", value: "\(motionActivity.steps)"),
            detailLine("Date", value: motionActivity.date.map(format(dateInterval:))),
            detailLine("Icon", value: motionActivity.icon?.lastPathComponent)
        ]
        
        if #available(iOS 18.0, *) {
            lines.append(detailLine("Movement Type", value: motionActivity.movementType.map { String(describing: $0) }))
        }
        
        return section(title: "Motion Activity", lines: lines)
    }
    
    private func format(podcast: JournalingSuggestion.Podcast) -> String {
        section(title: "Podcast", lines: [
            detailLine("Episode", value: podcast.episode),
            detailLine("Show", value: podcast.show),
            detailLine("Date", value: podcast.date.map(format(date:))),
            detailLine("Artwork", value: podcast.artwork?.lastPathComponent)
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
            detailLine("Date", value: song.date.map(format(date:))),
            detailLine("Artwork", value: song.artwork?.lastPathComponent)
        ])
    }
    
    private func format(workout: JournalingSuggestion.Workout) -> String {
        let route = workout.route ?? []
        return section(title: "Workout", lines: [
            detailLine("Activity Type", value: String(describing: workout.details?.activityType ?? .other)),
            detailLine("Localized Name", value: workout.details?.localizedName),
            detailLine("Date", value: workout.details?.date.map(format(dateInterval:))),
            detailLine("Active Energy", value: format(energy: workout.details?.activeEnergyBurned)),
            detailLine("Distance", value: format(distance: workout.details?.distance)),
            detailLine("Average Heart Rate", value: format(heartRate: workout.details?.averageHeartRate)),
            detailLine("Icon", value: workout.icon?.lastPathComponent),
            detailLine("Route Points", value: route.isEmpty ? nil : "\(route.count)"),
            detailLine("Route Distance", value: route.isEmpty ? nil : format(distanceMeters: routeDistance(route))),
            detailLine("Route Start", value: route.first.flatMap { format(coordinate: $0.coordinate) }),
            detailLine("Route End", value: route.last.flatMap { format(coordinate: $0.coordinate) })
        ])
    }
    
    private func format(workoutGroup: JournalingSuggestion.WorkoutGroup) -> String {
        let workoutSummaries = workoutGroup.workouts.enumerated().map { index, workout in
            let title = workout.details?.localizedName ?? String(describing: workout.details?.activityType ?? .other)
            let date = workout.details?.date.map(format(dateInterval:)) ?? "Unknown date"
            return "\(index + 1). \(title) | \(date)"
        }
        
        return section(title: "Workout Group", lines: [
            detailLine("Workout Count", value: "\(workoutGroup.workouts.count)"),
            detailLine("Duration", value: workoutGroup.duration.flatMap(format(duration:))),
            detailLine("Active Energy", value: format(energy: workoutGroup.activeEnergyBurned)),
            detailLine("Average Heart Rate", value: format(heartRate: workoutGroup.averageHeartRate)),
            detailLine("Icon", value: workoutGroup.icon?.lastPathComponent),
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
            detailLine("Valence Classification", value: String(describing: state.valenceClassification)),
            detailLine("Labels", value: state.labels.isEmpty ? nil : state.labels.map { String(describing: $0) }.joined(separator: ", ")),
            detailLine("Associations", value: state.associations.isEmpty ? nil : state.associations.map { String(describing: $0) }.joined(separator: ", ")),
            detailLine("Icon", value: stateOfMind.icon?.lastPathComponent),
            detailLine("Light Background", value: stateOfMind.lightBackground.map { String(describing: $0) }),
            detailLine("Dark Background", value: stateOfMind.darkBackground.map { String(describing: $0) })
        ])
    }
    
    @available(iOS 18.0, *)
    private func format(genericMedia: JournalingSuggestion.GenericMedia) -> String {
        section(title: "Generic Media", lines: [
            detailLine("Title", value: genericMedia.title),
            detailLine("Artist", value: genericMedia.artist),
            detailLine("Album", value: genericMedia.album),
            detailLine("Date", value: genericMedia.date.map(format(date:))),
            detailLine("App Icon", value: genericMedia.appIcon?.lastPathComponent)
        ])
    }
    
    @available(iOS 26.0, *)
    private func format(eventPoster: JournalingSuggestion.EventPoster) -> String {
        section(title: "Event Poster", lines: [
            detailLine("Title", value: String(eventPoster.title.characters)),
            detailLine("Place", value: eventPoster.placeName),
            detailLine("Event Start", value: eventPoster.eventStart.map(format(date:))),
            detailLine("Event End", value: eventPoster.eventEnd.map(format(date:))),
            detailLine("Is Host", value: eventPoster.isHost.map(boolLabel)),
            detailLine("Image", value: eventPoster.image?.lastPathComponent)
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
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    TextField("Title", text: $entry.title)
                        .font(.title2.bold())
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Entry")
                            .font(.headline)
                        TextEditor(text: $entry.content)
                            .frame(minHeight: 220)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color(uiColor: .secondarySystemBackground))
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Inspiration")
                                .font(.headline)
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
                            .frame(minHeight: 220)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color(uiColor: .secondarySystemBackground))
                            )
                        
                        Text("You can edit imported inspiration text here, but new inspiration is added only through Journaling Suggestions.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            
            .navigationTitle("Entry")
            
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
                        entry.content += generateHealthSnapshot()
                    } label: {
                        Label("Health Snapshot", systemImage: "heart.text.square")
                    }

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
}
