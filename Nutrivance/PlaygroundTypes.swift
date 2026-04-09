import SwiftUI

struct Connection: Codable, Identifiable {
    let id: UUID
    let sourceWidget: UUID
    let targetWidget: UUID
    let sourcePoint: CGPoint
    let targetPoint: CGPoint
    
    enum CodingKeys: String, CodingKey {
        case id, sourceWidget, targetWidget, sourcePoint, targetPoint
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sourceWidget, forKey: .sourceWidget)
        try container.encode(targetWidget, forKey: .targetWidget)
        try container.encode([sourcePoint.x, sourcePoint.y], forKey: .sourcePoint)
        try container.encode([targetPoint.x, targetPoint.y], forKey: .targetPoint)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sourceWidget = try container.decode(UUID.self, forKey: .sourceWidget)
        targetWidget = try container.decode(UUID.self, forKey: .targetWidget)
        let sourcePointArray = try container.decode([CGFloat].self, forKey: .sourcePoint)
        let targetPointArray = try container.decode([CGFloat].self, forKey: .targetPoint)
        sourcePoint = CGPoint(x: sourcePointArray[0], y: sourcePointArray[1])
        targetPoint = CGPoint(x: targetPointArray[0], y: targetPointArray[1])
    }
}

struct EquationBox: Codable, Identifiable {
    let id: UUID
    var equation: String
    var inputs: [UUID]
    var output: Double
    
    enum CodingKeys: String, CodingKey {
        case id, equation, inputs, output
    }
}

struct ResizableWidget: Identifiable, Codable {
    let id: UUID
    var type: WidgetType
    var position: CGPoint
    var size: CGSize
    var view: AnyView
    
    enum CodingKeys: String, CodingKey {
        case id, type, position, size
    }
    
    init(type: WidgetType, position: CGPoint, size: CGSize, view: AnyView) {
        self.id = UUID()
        self.type = type
        self.position = position
        self.size = size
        self.view = view
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(WidgetType.self, forKey: .type)
        position = try container.decode(CGPoint.self, forKey: .position)
        size = try container.decode(CGSize.self, forKey: .size)
        view = AnyView(EmptyView()) // Default view, will be set after decoding
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(position, forKey: .position)
        try container.encode(size, forKey: .size)
    }
}

struct PlaygroundPreset: Codable {
    var elements: [ResizableWidget]
    var connections: [Connection]
    var equations: [EquationBox]
}
