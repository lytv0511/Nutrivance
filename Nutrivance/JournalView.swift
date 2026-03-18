import Foundation
import SwiftUI
import JournalingSuggestions
import HealthKit

struct JournalEntry: Identifiable, Codable {
    let id: UUID
    var title: String
    var content: String
    var date: Date
    var imageData: [Data] = []  // Store images as Data
    
    init(title: String = "", content: String = "") {
        self.id = UUID()
        self.title = title
        self.content = content
        self.date = Date()
        self.imageData = []
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
                                    
                                    Text(entry.content)
                                        .lineLimit(2)
                                        .foregroundColor(.secondary)
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
    
    @State private var showingSuggestions = false
    
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
    
    var body: some View {
        
        NavigationStack {
            
            VStack(spacing: 0) {
                
                TextField("Title", text: $entry.title)
                    .font(.title2.bold())
                    .padding()
                
                Divider()
                
                TextEditor(text: $entry.content)
                    .padding()
                
                // Image gallery if images exist
                if !entry.imageData.isEmpty {
                    Divider()
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(entry.imageData.enumerated()), id: \.offset) { index, imageData in
                                ZStack(alignment: .topTrailing) {
                                    if let uiImage = UIImage(data: imageData) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 100, height: 100)
                                            .clipped()
                                            .cornerRadius(8)
                                    }
                                    Button(action: {
                                        entry.imageData.remove(at: index)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.title3)
                                            .foregroundColor(.red)
                                            .padding(4)
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                    .frame(height: 120)
                }
                
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

                    Button {
                        showingSuggestions = true
                    } label: {
                        Label("Suggestions", systemImage: "sparkles")
                    }

                    Spacer()

                    Button {
                        entry.content += generateHealthSnapshot()
                    } label: {
                        Label("Health Snapshot", systemImage: "heart.text.square")
                    }

                }
            }
            
            .sheet(isPresented: $showingSuggestions) {
                JournalingSuggestionsPicker("What's on your mind?") { suggestion in
                    // Use suggestion title as entry title, or add to existing content
                    if entry.title.isEmpty {
                        entry.title = suggestion.title
                    } else {
                        entry.content = suggestion.title + "\n\n" + entry.content
                    }
                    
                    // Extract and store suggestion images if available
                    Task {
                        let downloadedImages = await downloadImagesFromSuggestion(suggestion)
                        await MainActor.run {
                            entry.imageData.append(contentsOf: downloadedImages)
                        }
                    }
                    
                    // Close suggestions and keep editor open
                    showingSuggestions = false
                }
            }
        }
    }
}
