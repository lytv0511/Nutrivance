import SwiftUI

struct PlaygroundView: View {
    @StateObject private var presetManager = PresetManager()
    @State private var isEditing = false
    @State private var selectedWidget: ResizableWidget?
    @State private var connections: [Connection] = []
    @State private var selectedTool: WidgetType?
    
    var body: some View {
        ZStack {
            GeometryReader { geometry in
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedWidget = nil
                    }
                
                ForEach($presetManager.elements) { $widget in
                    ResizableWidgetView(
                        widget: $widget,
                        isSelected: selectedWidget?.id == widget.id,
                        onSelect: { selectedWidget = widget }
                    )
                }
                
                ConnectionsView(connections: connections)
            }
            
            if isEditing {
                VStack {
                    ToolPalette(selectedTool: $selectedTool)
                    Spacer()
                }
            }
            
            HStack {
                ForEach(0..<3) { index in
                    PresetButton(
                        index: index,
                        isSelected: presetManager.selectedPreset == index,
                        action: { presetManager.selectPreset(index) }
                    )
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(isEditing ? "Done" : "Edit") {
                    isEditing.toggle()
                }
            }
        }
    }
}

class PresetManager: ObservableObject {
    @Published var elements: [ResizableWidget] = []
    @Published var selectedPreset: Int = 0
    @Published var connections: [Connection] = []

    private let presetKey = "playground_presets"
    private var presets: [PlaygroundPreset] = []
    
    init() {
        loadPresetsFromDisk()
        if presets.isEmpty {
            presets = [
                PlaygroundPreset(elements: [], connections: [], equations: []),
                PlaygroundPreset(elements: [], connections: [], equations: []),
                PlaygroundPreset(elements: [], connections: [], equations: [])
            ]
        }
        loadPreset(0)
    }
    
    func selectPreset(_ index: Int) {
        saveCurrentPreset()
        selectedPreset = index
        loadPreset(index)
    }
    
    func removeConnection(_ connection: Connection) {
        connections.removeAll { $0.id == connection.id }
        saveCurrentPreset()
    }
    
    private func saveCurrentPreset() {
        presets[selectedPreset] = PlaygroundPreset(
            elements: elements,
            connections: connections,  // This will now match the type
            equations: []
        )
        savePresetsToDisk()
    }
    
    private func loadPreset(_ index: Int) {
        let preset = presets[index]
        elements = preset.elements
        connections = preset.connections  // This will now match the type
    }
    
    private func savePresetsToDisk() {
        if let encoded = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(encoded, forKey: presetKey)
        }
    }
    
    private func loadPresetsFromDisk() {
        if let data = UserDefaults.standard.data(forKey: presetKey),
           let decoded = try? JSONDecoder().decode([PlaygroundPreset].self, from: data) {
            presets = decoded
        }
    }
}


struct ToolPalette: View {
    let categories = ["Views", "Tools", "Containers", "Equations"]
    @Binding var selectedTool: WidgetType?
    
    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(categories, id: \.self) { category in
                    Menu(category) {
                        // Tool items based on category
                    }
                }
            }
        }
    }
}
