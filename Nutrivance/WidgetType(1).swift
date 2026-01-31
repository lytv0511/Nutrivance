//
//  WidgetType.swift
//  Nutrivance
//
//  Created by Vincent Leong on 2/25/25.
//

import Foundation
import SwiftUI

enum WidgetType: String, Codable, CaseIterable {
    case view
    case tool
    case container
    case equation
    case chart
    case input
    case output
    
    var iconName: String {
        switch self {
        case .view: return "square.grid.2x2"
        case .tool: return "hammer"
        case .container: return "square.dashed"
        case .equation: return "function"
        case .chart: return "chart.bar"
        case .input: return "arrow.right.circle"
        case .output: return "arrow.left.circle"
        }
    }
    
    var displayName: String {
        switch self {
        case .view: return "View"
        case .tool: return "Tool"
        case .container: return "Container"
        case .equation: return "Equation"
        case .chart: return "Chart"
        case .input: return "Input"
        case .output: return "Output"
        }
    }
}
