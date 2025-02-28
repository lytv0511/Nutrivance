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
