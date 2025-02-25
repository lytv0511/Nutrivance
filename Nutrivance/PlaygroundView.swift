import SwiftUI

struct PlaygroundView: View {
    @StateObject private var presetManager = PresetManager()
    @State private var isEditing = false
    @State private var selectedWidget: ResizableWidget?
    @State private var showToolPicker = false
    @State private var selectedTool: WidgetType?
    
    var body: some View {
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
            }
            
            VStack {
                Spacer()
                
                if isEditing {
                    ToolPicker(
                        isPresented: $showToolPicker,
                        selectedTool: $selectedTool,
                        isEditing: $isEditing
                    )
                    .transition(.move(edge: .bottom))
                    .padding()
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
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(tools, id: \.0) { tool, name, icon in
                    Button {
                        selectedTool = tool
                    } label: {
                        VStack {
                            Image(systemName: icon)
                                .font(.title2)
                            Text(name)
                                .font(.caption)
                        }
                        .frame(width: 60, height: 60)
                        .background(selectedTool == tool ? .blue.opacity(0.2) : .clear)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}

// Wiggle animation modifier
struct WiggleModifier: ViewModifier {
    let isEnabled: Bool
    @State private var rotation: Double = 0
    
    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(isEnabled ? rotation : 0))
            .onAppear {
                guard isEnabled else { return }
                withAnimation(.easeInOut(duration: 0.15).repeatForever(autoreverses: true)) {
                    rotation = [-2, 2][Int.random(in: 0...1)]
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
    @State private var offset = CGSize.zero
    @State private var dragOffset = CGSize.zero
    @State private var previousDragOffset = CGSize.zero

    var smoothedOffset: CGSize {
        let dampening: CGFloat = 0.7
        let smoothedY = dragOffset.height * dampening + previousDragOffset.height * (1 - dampening)
        return CGSize(width: 0, height: smoothedY)
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer()
                
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Spacer()
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(.secondary)
                            .frame(width: 36, height: 5)
                            .gesture(
                                DragGesture()
                                    .onChanged { gesture in
                                        previousDragOffset = dragOffset
                                        dragOffset = gesture.translation
                                    }
                                    .onEnded { gesture in
                                        if gesture.translation.height > 100 {
                                            withAnimation(.spring()) {
                                                isPresented = false
                                                isEditing = false
                                            }
                                        } else {
                                            withAnimation(.spring(
                                                response: 0.4,
                                                dampingFraction: 0.7,
                                                blendDuration: 0.3
                                            )) {
                                                dragOffset = .zero
                                                previousDragOffset = .zero
                                            }
                                        }
                                    }
                            )
                        Spacer()
                    }
                    .padding(.top, 12)
                    
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
                    }
                    .padding()
                    
                    toolGrid
                }
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .frame(height: geometry.size.height * 0.7)
                .offset(y: smoothedOffset.height)
            }
        }
    }
    
    private var dismissBackground: some View {
        Color.black.opacity(0.3)
            .edgesIgnoringSafeArea(.all)
            .onTapGesture {
                withAnimation(.spring()) {
                    isPresented = false
                }
            }
    }
    
    private func toolPickerContent(geometry: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            pickerHeader
            toolGrid
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .frame(height: geometry.size.height * 0.7)
        .edgesIgnoringSafeArea(.bottom)
    }
    
    private var pickerHeader: some View {
        HStack {
            Text("Add Widget")
                .font(.title2)
                .bold()
            Spacer()
            Button("Done") {
                withAnimation(.spring()) {
                    isPresented = false
                }
            }
        }
        .padding()
    }
    
    private var toolGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 180), spacing: 16)], spacing: 16) {
                ForEach(WidgetType.allCases, id: \.self) { tool in
                    ToolPreview(type: tool)
                        .onTapGesture {
                            selectedTool = tool
                            isPresented = false
                        }
                }
            }
            .padding()
        }
    }
}

struct ToolPreview: View {
    let type: WidgetType
    
    var body: some View {
        VStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay {
                    previewContent
                }
                .frame(height: 120)
            
            Text(type.displayName)
                .font(.callout)
                .foregroundStyle(.primary)
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
