import SwiftUI

enum WidgetType: String, Codable {
    case view
    case tool
    case container
    case equation
    case chart
    case input
    case output
}

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

struct ResizableWidget: Codable, Identifiable {
    let id: UUID
    var type: WidgetType
    var position: CGPoint
    var size: CGSize
    var connections: Set<UUID>
    var value: Double?
    var view: AnyView
    
    private enum CodingKeys: String, CodingKey {
        case id, type, position, size, connections, value
    }
    
    init(type: WidgetType, position: CGPoint, size: CGSize, view: AnyView) {
        self.id = UUID()
        self.type = type
        self.position = position
        self.size = size
        self.connections = []
        self.value = nil
        self.view = view
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try WidgetType(rawValue: container.decode(String.self, forKey: .type))!
        let positionArray = try container.decode([CGFloat].self, forKey: .position)
        let sizeArray = try container.decode([CGFloat].self, forKey: .size)
        position = CGPoint(x: positionArray[0], y: positionArray[1])
        size = CGSize(width: sizeArray[0], height: sizeArray[1])
        connections = try container.decode(Set<UUID>.self, forKey: .connections)
        value = try container.decodeIfPresent(Double.self, forKey: .value)
        view = AnyView(EmptyView()) // Default view that will be set after decoding
    }
}

struct PlaygroundPreset: Codable {
    var elements: [ResizableWidget]
    var connections: [Connection]
    var equations: [EquationBox]
}
