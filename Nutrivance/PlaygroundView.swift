import SwiftUI

enum DragState: Equatable {
    case inactive
    case dragging(type: WidgetType, location: CGPoint)
    
    static func == (lhs: DragState, rhs: DragState) -> Bool {
        switch (lhs, rhs) {
        case (.inactive, .inactive):
            return true
        case let (.dragging(type1, location1), .dragging(type2, location2)):
            return type1 == type2 && location1 == location2
        default:
            return false
        }
    }
}

struct PlaygroundView: View {
    @StateObject private var presetManager = PresetManager()
    @State private var isEditing = false
    @State private var selectedWidget: ResizableWidget?
    @State private var showToolPicker = false
    @State private var selectedTool: WidgetType?
    @State private var toolPickerOffset: CGFloat = 0
    @State private var dragState: DragState = .inactive
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onLongPressGesture {
                        withAnimation(.spring()) {
                            isEditing = true
                            showToolPicker = true
                        }
                    }
                
                ForEach($presetManager.elements) { $widget in
                    ResizableWidgetView(
                        widget: $widget,
                        isSelected: selectedWidget?.id == widget.id,
                        onSelect: { selectedWidget = widget }
                    )
                    .wiggle(isEnabled: isEditing)
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                withAnimation(.spring()) {
                                    toolPickerOffset = 300
                                }
                                widget.position = gesture.location
                            }
                            .onEnded { _ in
                                withAnimation(.spring()) {
                                    toolPickerOffset = 0
                                }
                            }
                    )
                }
                
                // Floating preview for dragged widget
                if case let .dragging(type, location) = dragState {
                    createWidgetView(for: type)
                        .frame(width: 200, height: 200)
                        .position(location)
                }
                
                VStack {
                    Spacer()
                    
                    if isEditing {
                        ToolPicker(
                            isPresented: $showToolPicker,
                            selectedTool: $selectedTool,
                            isEditing: $isEditing,
                            presetManager: presetManager
                        )
                        .offset(y: toolPickerOffset)
                        .transition(.move(edge: .bottom))
                        .padding()
                    }
                    
                    HStack {
                        if !isEditing {
                            Spacer()
                        }
                    }
                    HStack {
                        if !isEditing {
                            Spacer()
                        }
                        PlaygroundPresetPicker(
                            presets: $presetManager.presets,
                            selectedPreset: $presetManager.selectedPreset,
                            isExpanded: isEditing
                        )
                        .padding()
                    }
                }
            }
            .navigationTitle("Playground")
        }
    }


    private func addWidget(type: WidgetType) {
        let widget = ResizableWidget(
            type: type,
            position: CGPoint(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY),
            size: CGSize(width: 200, height: 200),
            view: createWidgetView(for: type)
        )
        presetManager.elements.append(widget)
    }

    private func createWidgetView(for type: WidgetType) -> AnyView {
        switch type {
        case .view:
            return AnyView(RoundedRectangle(cornerRadius: 8).fill(.blue.opacity(0.3)))
        case .tool:
            return AnyView(Circle().fill(.green.opacity(0.3)))
        case .container:
            return AnyView(RoundedRectangle(cornerRadius: 12).stroke(.purple, lineWidth: 2))
        case .equation:
            return AnyView(Text("f(x)").font(.system(.title, design: .monospaced)))
        case .chart:
            return AnyView(Image(systemName: "chart.bar.fill"))
        case .input:
            return AnyView(Image(systemName: "arrow.right.circle.fill"))
        case .output:
            return AnyView(Image(systemName: "arrow.left.circle.fill"))
        }
    }

}

struct PlaygroundPresetPicker: View {
    @Binding var presets: [PlaygroundPreset]
    @Binding var selectedPreset: Int
    @State private var isButtonsShown = false
    let isExpanded: Bool
    
    private var centeringOffset: CGFloat {
        isExpanded && isButtonsShown ? -90 : 0
    }
    
    private var rotationAngle: Double {
        if isExpanded {
            if isButtonsShown {
                // Rotation when tapped in tool picker mode
                return 180.0 // One full rotation plus 90 degrees for x mark
            }
            // Rotation when moving to center
            return 720.0
        } else if isButtonsShown {
            // Rotation when showing additional buttons
            return -270.0
        }
        return 0
    }
    
    var body: some View {
        ZStack {
            ForEach(0..<3) { i in
                Circle()
                    .fill(.blue.opacity(0.8))
                    .frame(width: 50, height: 50)
                    .offset(x: isExpanded ?
                           CGFloat(i + 1) * 60 : 0,
                           y: isExpanded ? 0 : CGFloat(i + 1) * -60)
                    .opacity(isButtonsShown ? 1 : 0)
                    .scaleEffect(isButtonsShown ? 1 : 0.5)
            }
            
            Button {
                withAnimation(.spring(
                    response: 0.6,
                    dampingFraction: 0.8,
                    blendDuration: 0.3
                )) {
                    isButtonsShown.toggle()
                }
            } label: {
                Image(systemName: isButtonsShown ? "xmark" : "plus")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(Color.blue)
                    .clipShape(Circle())
                    .rotationEffect(.degrees(rotationAngle))
            }
        }
        .offset(x: centeringOffset)
    }
}


class PresetManager: ObservableObject {
    @Published var elements: [ResizableWidget] = []
    @Published var selectedPreset: Int = 0
    @Published var connections: [Connection] = []
    @Published var presets: [PlaygroundPreset] = []

    private let presetKey = "playground_presets"
    
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
    @Binding var selectedTool: WidgetType?
    
    let tools: [(WidgetType, String, String)] = [
        (.view, "View", "square.fill"),
        (.container, "Container", "square.dashed"),
        (.tool, "Tool", "gear"),
        (.equation, "Equation", "function"),
        (.chart, "Chart", "chart.bar"),
        (.input, "Input", "arrow.right.circle"),
        (.output, "Output", "arrow.left.circle")
    ]
    
    var body: some View {
        List {
            ForEach(tools, id: \.0) { tool, name, icon in
                HStack {
                    Image(systemName: icon)
                        .imageScale(.large)
                        .frame(width: 24, height: 24)
                    Text(name)
                        .font(.body)
                    Spacer()
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .listRowBackground(selectedTool == tool ? Color.blue.opacity(0.2) : Color.clear)
                .onTapGesture {
                    selectedTool = tool
                }
            }
        }
        .listStyle(.sidebar)
        .background(.ultraThinMaterial)
    }
}

// Wiggle animation modifier
struct WiggleModifier: ViewModifier {
    let isEnabled: Bool
    @State private var rotation: Double = 0
    
    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(isEnabled ? rotation : 0))
            .onChange(of: isEnabled) { _, newValue in
                if newValue {
                    withAnimation(.easeInOut(duration: 0.15).repeatForever(autoreverses: true)) {
                        rotation = [-2, 2][Int.random(in: 0...1)]
                    }
                }
            }
    }
}

extension View {
    func wiggle(isEnabled: Bool) -> some View {
        modifier(WiggleModifier(isEnabled: isEnabled))
    }
}

// PresetOption view
struct PresetOption: View {
    let preset: PlaygroundPreset
    let index: Int
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            Text("Preset \(index + 1)")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 70, height: 70)
                .background(Color.blue.opacity(0.8))
                .clipShape(Circle())
                .shadow(radius: 3)
        }
    }
}

struct ToolPicker: View {
    @Binding var isPresented: Bool
    @Binding var selectedTool: WidgetType?
    @Binding var isEditing: Bool
    let presetManager: PresetManager
    @Environment(\.horizontalSizeClass) var sizeClass
    @GestureState private var translation = CGFloat.zero
    @State private var offset = CGFloat.zero
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer()
                
                VStack(alignment: .leading, spacing: 16) {
                    // Existing handle
                    HStack {
                        Spacer()
                        Capsule()
                            .fill(Color.clear)
                            .frame(width: 50, height: 16)
                            .overlay {
                                RoundedRectangle(cornerRadius: 2.5)
                                    .fill(.secondary)
                                    .frame(width: 40, height: 6)
                            }
                            .contentShape(Capsule())
                            .hoverEffect(.automatic)
                        Spacer()
                    }
                    .padding(.top, 12)
                    
                    // Existing header
                    HStack {
                        Text("Add Widget")
                            .font(.title2)
                            .bold()
                        Spacer()
                        Button("Done") {
                            withAnimation(.spring()) {
                                isPresented = false
                                isEditing = false
                            }
                        }
                        .padding(8)
                        .hoverEffect(.automatic)
                    }
                    .padding()
                    
                    // New adaptive content
                    if sizeClass == .compact {
                        iPhoneLayout
                    } else {
                        iPadLayout
                    }
                }
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .frame(height: geometry.size.height * 0.7)
                .offset(y: offset + translation)
                .gesture(
                    DragGesture()
                        .updating($translation) { value, state, _ in
                            state = value.translation.height
                        }
                        .onEnded { gesture in
                            let translation = gesture.translation.height
                            let velocity = gesture.predictedEndLocation.y - gesture.location.y
                            
                            offset += translation
                            withAnimation(.interpolatingSpring(stiffness: 300, damping: 30)) {
                                offset = (translation > 200 || velocity > 300) ? 400 : 0
                            }
                        }
                )
            }
        }
    }
    
    private var iPhoneLayout: some View {
        VStack {
            List(WidgetType.allCases, id: \.self) { tool in
                HStack {
                    Image(systemName: tool.iconName)
                        .font(.title2)
                    Text(tool.displayName)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.blue.opacity(selectedTool == tool ? 0.2 : 0))
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedTool = tool
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(.clear)

            if let selectedTool {
                VStack {
                    createWidgetView(for: selectedTool)
                        .frame(width: 200, height: 200)
                        .padding()
                    
                    Button(action: addWidget) {
                        Label("Add Widget", systemImage: "plus")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(.blue)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                    .padding()
                }
                .background(.ultraThinMaterial)
            }
        }
    }
    
    private var iPadLayout: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(WidgetType.allCases, id: \.self) { tool in
                        Button(action: {
                            selectedTool = tool
                        }) {
                            HStack {
                                Image(systemName: tool.iconName)
                                    .font(.title2)
                                Text(tool.displayName)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedTool == tool ? .blue.opacity(0.2) : .clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .frame(width: 250, height: 350)
            .padding(.bottom)
            .padding(.horizontal)
            
            if let selectedTool {
                VStack {
                    Spacer()
                    createWidgetView(for: selectedTool)
                        .frame(width: 250, height: 250)
                    Spacer()
                    
                    Button(action: addWidget) {
                        Label("Add Widget", systemImage: "plus")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(.blue)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                    .padding()
                }
                .frame(maxWidth: .infinity)
                .background(.clear)
            }
        }
    }
    
    private func createWidgetView(for type: WidgetType) -> AnyView {
        switch type {
        case .view:
            return AnyView(RoundedRectangle(cornerRadius: 8).fill(.blue.opacity(0.3)))
        case .tool:
            return AnyView(Circle().fill(.green.opacity(0.3)))
        case .container:
            return AnyView(RoundedRectangle(cornerRadius: 12).stroke(.purple, lineWidth: 2))
        case .equation:
            return AnyView(Text("f(x)").font(.system(.title, design: .monospaced)))
        case .chart:
            return AnyView(Image(systemName: "chart.bar.fill"))
        case .input:
            return AnyView(Image(systemName: "arrow.right.circle.fill"))
        case .output:
            return AnyView(Image(systemName: "arrow.left.circle.fill"))
        }
    }
    
    private func addWidget() {
        if let type = selectedTool {
            let widget = ResizableWidget(
                type: type,
                position: CGPoint(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY),
                size: CGSize(width: 200, height: 200),
                view: createWidgetView(for: type)
            )
            presetManager.elements.append(widget)
        }
        
        withAnimation(.interpolatingSpring(stiffness: 300, damping: 30)) {
            offset = 400
            isPresented = false
        }
    }
}

struct ToolPreview: View {
    let type: WidgetType
    @Binding var dragState: DragState
    @GestureState private var isDetectingLongPress = false
    @State private var isDragging = false
    
    var body: some View {
        VStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay {
                    previewContent
                }
                .frame(height: 120)
                .scaleEffect(isDetectingLongPress || isDragging ? 1.05 : 1.0)
                .opacity(isDragging ? 0 : 1)
                .gesture(
                    LongPressGesture(minimumDuration: 0.3)
                        .sequenced(before: DragGesture(coordinateSpace: .global))
                        .updating($isDetectingLongPress) { value, state, _ in
                            switch value {
                            case .first(true):
                                state = true
                            default:
                                break
                            }
                        }
                        .onChanged { value in
                            switch value {
                            case .second(true, let drag):
                                isDragging = true
                                if let location = drag?.location {
                                    dragState = .dragging(type: type, location: location)
                                }
                            default:
                                break
                            }
                        }
                        .onEnded { _ in
                            isDragging = false
                            dragState = .inactive
                        }
                )
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        switch type {
        case .view:
            Image(systemName: "square.grid.2x2")
                .font(.title)
        case .tool:
            Image(systemName: "hammer")
                .font(.title)
        case .container:
            Image(systemName: "square.dashed")
                .font(.title)
        case .equation:
            Text("f(x)")
                .font(.title.monospaced())
        case .chart:
            Image(systemName: "chart.bar")
                .font(.title)
        case .input:
            Image(systemName: "arrow.right.circle")
                .font(.title)
        case .output:
            Image(systemName: "arrow.left.circle")
                .font(.title)
        }
    }
}

import UniformTypeIdentifiers

extension WidgetType: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .widget)
    }
}

extension UTType {
    static var widget: UTType {
        UTType(exportedAs: "com.nutrivance.widget")
    }
}
