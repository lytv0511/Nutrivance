import Foundation
import SwiftUI
import JournalingSuggestions
import HealthKit

struct JournalEntry: Identifiable, Codable {
    let id: UUID
    var title: String
    var content: String
    var date: Date
    
    init(title: String = "", content: String = "") {
        self.id = UUID()
        self.title = title
        self.content = content
        self.date = Date()
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
    
    var body: some View {
        
        NavigationStack {
            
            VStack(spacing: 0) {
                
                TextField("Title", text: $entry.title)
                    .font(.title2.bold())
                    .padding()
                
                Divider()
                
                TextEditor(text: $entry.content)
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
                JournalingSuggestionsPicker("Write about your day") { suggestion in
                    entry.content += "\n\n\(suggestion.title)"
                }
            }
        }
    }
}
